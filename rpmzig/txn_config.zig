//! Minimal native macro/config resolution for the transaction engine.
//!
//! This intentionally models only the small librpm surface that tdnf's
//! native transaction work needs today:
//! - `%{_dbpath}` for rpmdb open/init/rebuild/verify
//! - `%{_tmppath}` for temporary transaction/script files
//! - `%{_install_script_path}` for the PATH exported to scriptlets
//! - `%{_topdir}`, `%{_specdir}`, and `%{_sourcedir}` for source RPMs
//!
//! Upstream librpm defaults the script interpreter itself to `/bin/sh`
//! when an RPM header does not carry an explicit `*PROG` tag. That is
//! a hard-coded runtime default, not a macro, so it is exposed here as
//! a constant for downstream consumers.

const std = @import("std");
const c = @cImport({
    @cInclude("glob.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

pub const DEFAULT_INSTALL_ROOT = "/";
pub const DEFAULT_DBPATH = "/var/lib/rpm";
pub const DEFAULT_RPMDB_BASENAME = "rpmdb.sqlite";
pub const DEFAULT_TMPPATH = "/var/tmp";
pub const DEFAULT_INSTALL_SCRIPT_PATH = "/sbin:/bin:/usr/sbin:/usr/bin:/usr/X11R6/bin";
pub const DEFAULT_TOPDIR = "%{getenv:HOME}/rpmbuild";
pub const DEFAULT_SPECDIR = "%{_topdir}/SPECS";
pub const DEFAULT_SOURCEDIR = "%{_topdir}/SOURCES";
pub const DEFAULT_SYSCONFDIR = "/etc";
pub const DEFAULT_SCRIPT_INTERPRETER = "/bin/sh";
const MAX_EXPANSION_DEPTH = 32;
const mode_type_mask: u16 = 0o170000;
const mode_directory: u16 = 0o040000;
const mode_regular: u16 = 0o100000;
const open_directory: u64 = 0x10000;
const open_cloexec: u64 = 0x80000;
const resolve_no_magiclinks: u64 = 0x02;
const resolve_in_root: u64 = 0x10;

const OpenHow = extern struct {
    flags: u64,
    mode: u64 = 0,
    resolve: u64,
};

pub const Macro = enum {
    dbpath,
    tmppath,
    install_script_path,
    topdir,
    specdir,
    sourcedir,

    /// Returns the rpm macro name this enum member represents.
    pub fn name(self: Macro) []const u8 {
        return switch (self) {
            .dbpath => "_dbpath",
            .tmppath => "_tmppath",
            .install_script_path => "_install_script_path",
            .topdir => "_topdir",
            .specdir => "_specdir",
            .sourcedir => "_sourcedir",
        };
    }

    /// Returns the default librpm value for this macro.
    pub fn defaultValue(self: Macro) []const u8 {
        return switch (self) {
            .dbpath => DEFAULT_DBPATH,
            .tmppath => DEFAULT_TMPPATH,
            .install_script_path => DEFAULT_INSTALL_SCRIPT_PATH,
            .topdir => DEFAULT_TOPDIR,
            .specdir => DEFAULT_SPECDIR,
            .sourcedir => DEFAULT_SOURCEDIR,
        };
    }

    /// Returns true when the macro resolves to an install-root-relative path.
    pub fn isInstallRootRelative(self: Macro) bool {
        return switch (self) {
            .dbpath, .tmppath, .topdir, .specdir, .sourcedir => true,
            .install_script_path => false,
        };
    }
};

pub const ParsedRpmDefine = struct {
    macro: ?Macro,
    name: []const u8,
    value: []const u8,
};

pub const ParseDefineError = error{
    InvalidDefine,
};

pub const SetMacroError = error{
    InvalidMacroValue,
    InvalidMacroName,
    OutOfMemory,
};

pub const ExpandError = error{
    ExpansionCycle,
    ExpansionTooDeep,
    InvalidMacroExpression,
    UnknownMacro,
    OutOfMemory,
};

pub const ResolvePathError = ExpandError || error{
    NotPathMacro,
    PathTooLong,
};

pub const InitError = error{
    InvalidInstallRoot,
    InstallRootPinFailed,
    OutOfMemory,
    RpmDbPinFailed,
};

pub const TargetPathError = error{
    InvalidTargetPath,
    NotFound,
    SyscallFailed,
    UnsafeTargetPath,
};

pub const LoadMacrosError = SetMacroError || error{
    GlobFailed,
    MacroFileOpenFailed,
    MacroFileReadFailed,
};

/// Returns the known macro represented by `name`, or null for a valid
/// but currently irrelevant macro.
pub fn macroFromName(name: []const u8) ?Macro {
    if (std.mem.eql(u8, name, "_dbpath")) return .dbpath;
    if (std.mem.eql(u8, name, "_tmppath")) return .tmppath;
    if (std.mem.eql(u8, name, "_install_script_path")) return .install_script_path;
    if (std.mem.eql(u8, name, "_topdir")) return .topdir;
    if (std.mem.eql(u8, name, "_specdir")) return .specdir;
    if (std.mem.eql(u8, name, "_sourcedir")) return .sourcedir;
    return null;
}

/// Parses a raw rpmdefine payload from either `--rpmdefine` or
/// `--setopt=rpmdefine=...`.
///
/// Accepted forms are:
/// - `_dbpath /usr/lib/sysimage/rpm`
/// - `_dbpath=/usr/lib/sysimage/rpm`
/// - `%{_dbpath}=/usr/lib/sysimage/rpm`
///
/// The returned slices alias the caller-owned `text`.
pub fn parseRpmDefine(text: []const u8) ParseDefineError!ParsedRpmDefine {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidDefine;

    const split_index = std.mem.indexOfAny(u8, trimmed, "=\t ") orelse {
        return error.InvalidDefine;
    };

    var name = std.mem.trim(u8, trimmed[0..split_index], " \t\r\n");
    var value = std.mem.trimStart(u8, trimmed[split_index..], "=\t ");
    value = std.mem.trim(u8, value, " \t\r\n");
    if (name.len == 0 or value.len == 0) return error.InvalidDefine;

    if (name[0] == '%') {
        if (name.len >= 4 and name[1] == '{' and name[name.len - 1] == '}') {
            name = name[2 .. name.len - 1];
        } else {
            name = name[1..];
        }
    }
    if (name.len == 0) return error.InvalidDefine;

    return .{
        .macro = macroFromName(name),
        .name = name,
        .value = value,
    };
}

const MacroEntry = struct {
    name: []u8,
    value: []u8,
};

const FsIdentity = struct {
    dev_major: u32,
    dev_minor: u32,
    ino: u64,

    fn eql(left: FsIdentity, right: FsIdentity) bool {
        return left.dev_major == right.dev_major and
            left.dev_minor == right.dev_minor and
            left.ino == right.ino;
    }
};

const FsStat = struct {
    identity: FsIdentity,
    mode: u16,
    nlink: u32,
};

fn fdStat(fd: c_int) ?FsStat {
    var st = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        std.os.linux.STATX.BASIC_STATS,
        &st,
    ) != 0) return null;
    return .{
        .identity = .{
            .dev_major = st.dev_major,
            .dev_minor = st.dev_minor,
            .ino = st.ino,
        },
        .mode = st.mode,
        .nlink = st.nlink,
    };
}

fn duplicateFdCloexec(fd: c_int) c_int {
    return std.c.fcntl(
        fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
}

fn openDirectoryInRoot(
    root_fd: c_int,
    path: []const u8,
) TargetPathError!?c_int {
    if (path.len > std.fs.max_path_bytes) return error.InvalidTargetPath;
    var path_buffer: [std.fs.max_path_bytes + 1]u8 = undefined;
    @memcpy(path_buffer[0..path.len], path);
    path_buffer[path.len] = 0;
    const how = OpenHow{
        .flags = open_directory | open_cloexec,
        .resolve = resolve_in_root | resolve_no_magiclinks,
    };
    const rc = std.os.linux.syscall4(
        .openat2,
        @intCast(root_fd),
        @intFromPtr(&path_buffer),
        @intFromPtr(&how),
        @sizeOf(OpenHow),
    );
    return switch (std.os.linux.errno(rc)) {
        .SUCCESS => @intCast(rc),
        .NOSYS => null,
        .NOENT => error.NotFound,
        .LOOP, .NOTDIR, .XDEV => error.UnsafeTargetPath,
        .INVAL, .NAMETOOLONG => error.InvalidTargetPath,
        else => error.SyscallFailed,
    };
}

pub const PinnedFdReleaseFn = *const fn (?*anyopaque) void;

/// Transaction-engine config store backed by explicit defaults plus arbitrary
/// command-line definitions. Values are expanded lazily so later definitions
/// affect macros that reference them, matching librpm's macro behavior.
pub const TxnConfig = struct {
    allocator: std.mem.Allocator,
    install_root: []u8,
    pinned_install_root_fd: ?c_int = null,
    pinned_rpmdb_dir_fd: ?c_int = null,
    pinned_rpmdb_main_fd: ?c_int = null,
    pinned_cache_dir_fd: ?c_int = null,
    pinned_rpmdb_main_release: ?PinnedFdReleaseFn = null,
    pinned_rpmdb_main_release_context: ?*anyopaque = null,
    rpmdb_pin_finalized: bool = false,
    target_lock_held: bool = false,
    literal_dbpath: ?[]u8 = null,
    pinned_repo_dir: ?[]u8 = null,
    pinned_cache_dir: ?[]u8 = null,
    pinned_plugin_conf_dir: ?[]u8 = null,
    macros: std.ArrayList(MacroEntry),

    /// Initializes a config store rooted at `install_root`. Empty input
    /// is treated as `/`.
    pub fn init(allocator: std.mem.Allocator, install_root: []const u8) InitError!TxnConfig {
        const root = try normalizeInstallRootOwned(allocator, install_root);
        var config = TxnConfig{
            .allocator = allocator,
            .install_root = root,
            .pinned_install_root_fd = null,
            .pinned_rpmdb_dir_fd = null,
            .pinned_rpmdb_main_fd = null,
            .pinned_cache_dir_fd = null,
            .pinned_rpmdb_main_release = null,
            .pinned_rpmdb_main_release_context = null,
            .rpmdb_pin_finalized = false,
            .target_lock_held = false,
            .literal_dbpath = null,
            .pinned_repo_dir = null,
            .pinned_cache_dir = null,
            .pinned_plugin_conf_dir = null,
            .macros = .empty,
        };
        errdefer config.deinit();

        inline for (std.meta.fields(Macro)) |field| {
            const macro_name: Macro = @enumFromInt(field.value);
            config.setMacroByName(macro_name.name(), macro_name.defaultValue()) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidMacroName, error.InvalidMacroValue => unreachable,
                };
            };
        }
        config.setMacroByName("_sysconfdir", DEFAULT_SYSCONFDIR) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidMacroName, error.InvalidMacroValue => unreachable,
            };
        };

        return config;
    }

    pub fn deinit(self: *TxnConfig) void {
        if (self.pinned_install_root_fd) |fd| {
            _ = std.c.close(fd);
            self.pinned_install_root_fd = null;
        }
        if (self.pinned_rpmdb_main_fd) |fd| {
            if (self.pinned_rpmdb_main_release) |release|
                release(self.pinned_rpmdb_main_release_context)
            else
                _ = std.c.close(fd);
            self.pinned_rpmdb_main_fd = null;
            self.pinned_rpmdb_main_release = null;
            self.pinned_rpmdb_main_release_context = null;
        }
        if (self.pinned_rpmdb_dir_fd) |fd| {
            _ = std.c.close(fd);
            self.pinned_rpmdb_dir_fd = null;
        }
        if (self.pinned_cache_dir_fd) |fd| {
            _ = std.c.close(fd);
            self.pinned_cache_dir_fd = null;
        }
        if (self.literal_dbpath) |literal| {
            self.allocator.free(literal);
            self.literal_dbpath = null;
        }
        if (self.pinned_repo_dir) |path| self.allocator.free(path);
        if (self.pinned_cache_dir) |path| self.allocator.free(path);
        if (self.pinned_plugin_conf_dir) |path| self.allocator.free(path);
        self.pinned_repo_dir = null;
        self.pinned_cache_dir = null;
        self.pinned_plugin_conf_dir = null;
        self.allocator.free(self.install_root);
        for (self.macros.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.value);
        }
        self.macros.deinit(self.allocator);
    }

    pub fn clone(self: *const TxnConfig, allocator: std.mem.Allocator) InitError!TxnConfig {
        return self.cloneWithRoot(
            allocator,
            self.install_root,
            self.pinned_install_root_fd,
            self.rpmdb_pin_finalized,
        );
    }

    /// Clone the macro state while pinning all native filesystem access to
    /// `root_fd`. `install_root` is the resolved display path for that fd.
    pub fn cloneWithPinnedInstallRoot(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        install_root: []const u8,
        root_fd: c_int,
    ) InitError!TxnConfig {
        return self.cloneWithRoot(allocator, install_root, root_fd, true);
    }

    pub fn cloneWithPinnedInstallRootDeferredRpmDb(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        install_root: []const u8,
        root_fd: c_int,
    ) InitError!TxnConfig {
        return self.cloneWithRoot(allocator, install_root, root_fd, false);
    }

    pub fn pinnedInstallRootFd(self: *const TxnConfig) ?c_int {
        return self.pinned_install_root_fd;
    }

    pub fn pinnedRpmDbDirFd(self: *const TxnConfig) ?c_int {
        return self.pinned_rpmdb_dir_fd;
    }

    pub fn pinnedRpmDbMainFd(self: *const TxnConfig) ?c_int {
        return self.pinned_rpmdb_main_fd;
    }

    pub fn pinnedCacheDirFd(self: *const TxnConfig) ?c_int {
        return self.pinned_cache_dir_fd;
    }

    pub fn targetLockHeld(self: *const TxnConfig) bool {
        return self.target_lock_held;
    }

    pub fn markTargetLockHeld(self: *TxnConfig) void {
        self.target_lock_held = true;
    }

    pub fn finalizeRpmDbPin(self: *TxnConfig) InitError!void {
        if (self.rpmdb_pin_finalized) return;
        if (self.pinned_install_root_fd == null)
            return error.InstallRootPinFailed;
        try self.pinRpmDb();
        self.rpmdb_pin_finalized = true;
    }

    pub fn adoptPinnedRpmDbDirFd(
        self: *TxnConfig,
        fd: c_int,
    ) InitError!void {
        const st = fdStat(fd) orelse return error.RpmDbPinFailed;
        if ((st.mode & mode_type_mask) != mode_directory)
            return error.RpmDbPinFailed;
        if (self.pinned_rpmdb_dir_fd) |current| {
            const current_st = fdStat(current) orelse
                return error.RpmDbPinFailed;
            if (!current_st.identity.eql(st.identity))
                return error.RpmDbPinFailed;
            return;
        }
        const duplicate = duplicateFdCloexec(fd);
        if (duplicate < 0) return error.RpmDbPinFailed;
        self.pinned_rpmdb_dir_fd = duplicate;
    }

    pub fn adoptPinnedCacheDirFd(
        self: *TxnConfig,
        fd: c_int,
    ) InitError!void {
        const st = fdStat(fd) orelse return error.InstallRootPinFailed;
        if ((st.mode & mode_type_mask) != mode_directory)
            return error.InstallRootPinFailed;
        if (self.pinned_cache_dir_fd) |current| {
            const current_st = fdStat(current) orelse
                return error.InstallRootPinFailed;
            if (!current_st.identity.eql(st.identity))
                return error.InstallRootPinFailed;
            return;
        }
        const duplicate = duplicateFdCloexec(fd);
        if (duplicate < 0) return error.InstallRootPinFailed;
        self.pinned_cache_dir_fd = duplicate;
    }

    pub fn adoptPinnedRpmDbMainFd(
        self: *TxnConfig,
        fd: c_int,
    ) InitError!void {
        const st = fdStat(fd) orelse return error.RpmDbPinFailed;
        if ((st.mode & mode_type_mask) != mode_regular or st.nlink != 1) {
            return error.RpmDbPinFailed;
        }
        if (self.pinned_rpmdb_main_fd) |current| {
            const current_st = fdStat(current) orelse
                return error.RpmDbPinFailed;
            if (!current_st.identity.eql(st.identity))
                return error.RpmDbPinFailed;
            return;
        }
        const duplicate = duplicateFdCloexec(fd);
        if (duplicate < 0) return error.RpmDbPinFailed;
        self.pinned_rpmdb_main_fd = duplicate;
        self.pinned_rpmdb_main_release = null;
        self.pinned_rpmdb_main_release_context = null;
    }

    pub fn adoptPinnedRpmDbMainLease(
        self: *TxnConfig,
        fd: c_int,
        context: ?*anyopaque,
        release: PinnedFdReleaseFn,
    ) InitError!void {
        const st = fdStat(fd) orelse return error.RpmDbPinFailed;
        if ((st.mode & mode_type_mask) != mode_regular or st.nlink != 1 or
            self.pinned_rpmdb_main_fd != null or context == null)
        {
            return error.RpmDbPinFailed;
        }
        self.pinned_rpmdb_main_fd = fd;
        self.pinned_rpmdb_main_release = release;
        self.pinned_rpmdb_main_release_context = context;
    }

    fn cloneWithRoot(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        install_root: []const u8,
        pinned_root_fd: ?c_int,
        finalize_rpmdb: bool,
    ) InitError!TxnConfig {
        const root = try normalizeInstallRootOwned(allocator, install_root);
        const duplicated_fd = if (pinned_root_fd) |fd| blk: {
            const duplicate = duplicateFdCloexec(fd);
            if (duplicate < 0) {
                allocator.free(root);
                return error.InstallRootPinFailed;
            }
            break :blk @as(?c_int, duplicate);
        } else null;
        var copy = TxnConfig{
            .allocator = allocator,
            .install_root = root,
            .pinned_install_root_fd = duplicated_fd,
            .pinned_rpmdb_dir_fd = null,
            .pinned_rpmdb_main_fd = null,
            .pinned_cache_dir_fd = null,
            .pinned_rpmdb_main_release = null,
            .pinned_rpmdb_main_release_context = null,
            .rpmdb_pin_finalized = false,
            .target_lock_held = false,
            .literal_dbpath = null,
            .pinned_repo_dir = null,
            .pinned_cache_dir = null,
            .pinned_plugin_conf_dir = null,
            .macros = .empty,
        };
        errdefer copy.deinit();

        for (self.macros.items) |entry| {
            copy.setMacroByName(entry.name, entry.value) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidMacroName, error.InvalidMacroValue => unreachable,
                };
            };
        }
        if (self.literal_dbpath) |literal| {
            copy.setLiteralRpmDbPath(literal) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidMacroName, error.InvalidMacroValue => unreachable,
            };
        }
        if (self.pinned_repo_dir) |path|
            try copy.setPinnedRepoDir(path);
        if (self.pinned_cache_dir) |path| {
            try copy.setPinnedCacheDir(path);
            if (duplicated_fd != null) {
                const cache_fd = copy.openPinnedDirectory(
                    path,
                    false,
                ) catch return error.InstallRootPinFailed;
                defer _ = std.c.close(cache_fd);
                try copy.adoptPinnedCacheDirFd(cache_fd);
            }
        }
        if (self.pinned_plugin_conf_dir) |path|
            try copy.setPinnedPluginConfDir(path);
        if (duplicated_fd != null and finalize_rpmdb)
            try copy.finalizeRpmDbPin();
        return copy;
    }

    fn pinRpmDb(self: *TxnConfig) InitError!void {
        const root_fd = self.pinned_install_root_fd orelse return;
        const expanded = self.expandMacroAlloc(
            self.allocator,
            .dbpath,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.RpmDbPinFailed,
        };
        defer self.allocator.free(expanded);
        if (std.mem.indexOfScalar(u8, expanded, 0) != null or
            !std.mem.eql(
                u8,
                expanded,
                std.mem.trim(u8, expanded, " \t\r\n"),
            ))
        {
            return error.RpmDbPinFailed;
        }
        const relative = std.mem.trim(u8, expanded, "/");
        if (relative.len != 0) {
            var components = std.mem.splitScalar(u8, relative, '/');
            while (components.next()) |component| {
                if (component.len == 0 or
                    std.mem.eql(u8, component, ".") or
                    std.mem.eql(u8, component, ".."))
                {
                    return error.RpmDbPinFailed;
                }
            }
        }
        _ = root_fd;
        const normalized = if (expanded.len != 0 and expanded[0] == '/')
            expanded
        else
            std.fmt.allocPrint(
                self.allocator,
                "/{s}",
                .{expanded},
            ) catch return error.OutOfMemory;
        defer if (normalized.ptr != expanded.ptr)
            self.allocator.free(normalized);
        const dir_fd = self.openPinnedDirectory(
            normalized,
            false,
        ) catch |err| return switch (err) {
            error.NotFound => return,
            else => error.RpmDbPinFailed,
        };
        errdefer _ = std.c.close(dir_fd);

        const main_fd = std.c.openat(
            dir_fd,
            DEFAULT_RPMDB_BASENAME,
            .{
                .ACCMODE = .RDONLY,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            },
        );
        if (main_fd < 0) {
            if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT)) {
                self.pinned_rpmdb_dir_fd = dir_fd;
                return;
            }
            return error.RpmDbPinFailed;
        }
        errdefer _ = std.c.close(main_fd);
        try self.adoptPinnedRpmDbMainFd(main_fd);
        _ = std.c.close(main_fd);
        self.pinned_rpmdb_dir_fd = dir_fd;
    }

    /// Loads the conventional system and per-user declarative macro files.
    /// Missing glob patterns are expected and ignored.
    pub fn loadConventionalMacroFiles(self: *TxnConfig) LoadMacrosError!void {
        const patterns = [_][]const u8{
            "/usr/lib/rpm/macros",
            "/usr/lib/rpm/macros.d/macros.*",
            "/usr/lib/rpm/macros.d/*.macros",
            "/etc/rpm/macros.*",
            "/etc/rpm/*.macros",
            "/etc/rpm/macros",
        };
        for (patterns) |pattern| {
            try self.loadMacroGlob(pattern);
        }

        if (c.getenv("HOME")) |home_ptr| {
            const user_path = std.fmt.allocPrint(
                self.allocator,
                "{s}/.rpmmacros",
                .{std.mem.span(home_ptr)},
            ) catch return error.OutOfMemory;
            defer self.allocator.free(user_path);
            try self.loadMacroGlob(user_path);
        }
    }

    pub fn installRoot(self: *const TxnConfig) []const u8 {
        return self.install_root;
    }

    pub fn setPinnedRepoDir(
        self: *TxnConfig,
        path: []const u8,
    ) std.mem.Allocator.Error!void {
        try self.replacePinnedPath(&self.pinned_repo_dir, path);
    }

    pub fn setPinnedCacheDir(
        self: *TxnConfig,
        path: []const u8,
    ) std.mem.Allocator.Error!void {
        try self.replacePinnedPath(&self.pinned_cache_dir, path);
    }

    pub fn setPinnedPluginConfDir(
        self: *TxnConfig,
        path: []const u8,
    ) std.mem.Allocator.Error!void {
        try self.replacePinnedPath(&self.pinned_plugin_conf_dir, path);
    }

    pub fn repoDirUsesPinnedRoot(
        self: *const TxnConfig,
        path: []const u8,
    ) bool {
        return pinnedPathMatches(self.pinned_repo_dir, path);
    }

    pub fn cacheDirUsesPinnedRoot(
        self: *const TxnConfig,
        path: []const u8,
    ) bool {
        _ = path;
        return self.pinned_cache_dir_fd != null;
    }

    pub fn pluginConfDirUsesPinnedRoot(
        self: *const TxnConfig,
        path: []const u8,
    ) bool {
        return pinnedPathMatches(self.pinned_plugin_conf_dir, path);
    }

    fn replacePinnedPath(
        self: *TxnConfig,
        slot: *?[]u8,
        path: []const u8,
    ) std.mem.Allocator.Error!void {
        const replacement = try self.allocator.dupe(u8, path);
        if (slot.*) |old| self.allocator.free(old);
        slot.* = replacement;
    }

    fn pinnedPathMatches(stored: ?[]const u8, path: []const u8) bool {
        return if (stored) |expected|
            std.mem.eql(u8, expected, path)
        else
            false;
    }

    pub fn openPinnedDirectory(
        self: *const TxnConfig,
        raw_path: []const u8,
        create: bool,
    ) TargetPathError!c_int {
        const root_fd = self.pinned_install_root_fd orelse
            return error.InvalidTargetPath;
        if (raw_path.len == 0 or raw_path[0] != '/' or
            std.mem.indexOfScalar(u8, raw_path, 0) != null)
        {
            return error.InvalidTargetPath;
        }
        const confined = openDirectoryInRoot(
            root_fd,
            raw_path,
        ) catch |err| switch (err) {
            error.NotFound => null,
            else => return err,
        };
        if (confined) |fd| return fd;
        var current = duplicateFdCloexec(root_fd);
        if (current < 0) return error.SyscallFailed;
        errdefer _ = std.c.close(current);
        const relative = std.mem.trim(u8, raw_path, "/");
        if (relative.len == 0) return current;

        var components = std.mem.splitScalar(u8, relative, '/');
        while (components.next()) |component| {
            if (component.len == 0 or
                component.len > std.fs.max_name_bytes or
                std.mem.eql(u8, component, ".") or
                std.mem.eql(u8, component, ".."))
            {
                return error.InvalidTargetPath;
            }
            var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
            @memcpy(name_buffer[0..component.len], component);
            name_buffer[component.len] = 0;
            const name: [*:0]const u8 = @ptrCast(&name_buffer);
            var next = std.c.openat(current, name, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
            if (next < 0 and create and
                std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            {
                if (std.c.mkdirat(current, name, 0o755) != 0 and
                    std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
                {
                    return error.SyscallFailed;
                }
                next = std.c.openat(current, name, .{
                    .ACCMODE = .RDONLY,
                    .DIRECTORY = true,
                    .CLOEXEC = true,
                    .NOFOLLOW = true,
                });
            }
            if (next < 0) {
                return switch (std.c._errno().*) {
                    @intFromEnum(std.posix.E.NOENT) => error.NotFound,
                    @intFromEnum(std.posix.E.LOOP),
                    @intFromEnum(std.posix.E.NOTDIR),
                    => error.UnsafeTargetPath,
                    else => error.SyscallFailed,
                };
            }
            _ = std.c.close(current);
            current = next;
        }
        return current;
    }

    pub fn openPinnedRegular(
        self: *const TxnConfig,
        path: []const u8,
    ) TargetPathError!c_int {
        if (path.len < 2 or path[0] != '/' or path[path.len - 1] == '/')
            return error.InvalidTargetPath;
        const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse
            return error.InvalidTargetPath;
        const parent_path = if (slash == 0) "/" else path[0..slash];
        const basename = path[slash + 1 ..];
        if (basename.len == 0 or basename.len > std.fs.max_name_bytes or
            std.mem.eql(u8, basename, ".") or
            std.mem.eql(u8, basename, ".."))
        {
            return error.InvalidTargetPath;
        }
        const parent = try self.openPinnedDirectory(parent_path, false);
        defer _ = std.c.close(parent);
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..basename.len], basename);
        name_buffer[basename.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const fd = std.c.openat(parent, name, .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (fd < 0) {
            return switch (std.c._errno().*) {
                @intFromEnum(std.posix.E.NOENT) => error.NotFound,
                @intFromEnum(std.posix.E.LOOP),
                @intFromEnum(std.posix.E.NOTDIR),
                => error.UnsafeTargetPath,
                else => error.SyscallFailed,
            };
        }
        errdefer _ = std.c.close(fd);
        const st = fdStat(fd) orelse return error.SyscallFailed;
        if ((st.mode & mode_type_mask) != mode_regular or st.nlink != 1)
            return error.UnsafeTargetPath;
        return fd;
    }

    /// Returns the effective value for a known macro.
    pub fn value(self: *const TxnConfig, macro_name: Macro) []const u8 {
        if (macro_name == .dbpath) {
            if (self.literal_dbpath) |literal| return literal;
        }
        return self.rawValue(macro_name.name()).?;
    }

    /// Returns the unexpanded value of an arbitrary macro.
    pub fn rawValue(self: *const TxnConfig, name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, Macro.dbpath.name())) {
            if (self.literal_dbpath) |literal| return literal;
        }
        const index = self.findMacro(name) orelse return null;
        return self.macros.items[index].value;
    }

    /// Applies a raw rpmdefine string. Arbitrary definitions are retained
    /// because native path macros may reference package- or user-defined
    /// values recursively.
    pub fn applyRpmDefine(
        self: *TxnConfig,
        text: []const u8,
    ) (ParseDefineError || SetMacroError)!bool {
        const parsed = try parseRpmDefine(text);
        try self.setMacroByName(parsed.name, parsed.value);
        return true;
    }

    /// Overrides a known macro with a caller-provided value.
    pub fn setMacro(
        self: *TxnConfig,
        macro_name: Macro,
        macro_value: []const u8,
    ) SetMacroError!void {
        try self.setMacroByName(macro_name.name(), macro_value);
    }

    /// Sets `_dbpath` to exact caller bytes. Unlike an rpm macro definition,
    /// the value is never recursively expanded.
    pub fn setLiteralRpmDbPath(
        self: *TxnConfig,
        path: []const u8,
    ) SetMacroError!void {
        if (self.rpmdb_pin_finalized or path.len == 0 or
            std.mem.indexOfScalar(u8, path, 0) != null)
        {
            return error.InvalidMacroValue;
        }
        const replacement = try self.allocator.dupe(u8, path);
        if (self.literal_dbpath) |old| self.allocator.free(old);
        self.literal_dbpath = replacement;
    }

    /// Overrides or creates an arbitrary macro without expanding its value.
    pub fn setMacroByName(
        self: *TxnConfig,
        name: []const u8,
        macro_value: []const u8,
    ) SetMacroError!void {
        const normalized_name = std.mem.trim(u8, name, " \t\r\n");
        if (!isValidMacroName(normalized_name)) return error.InvalidMacroName;
        if (self.rpmdb_pin_finalized and
            std.mem.eql(u8, normalized_name, Macro.dbpath.name()))
        {
            return error.InvalidMacroValue;
        }

        const normalized_value = std.mem.trim(u8, macro_value, " \t\r\n");
        if (normalized_value.len == 0) return error.InvalidMacroValue;

        const replacement = try self.allocator.dupe(u8, normalized_value);
        errdefer self.allocator.free(replacement);
        if (std.mem.eql(u8, normalized_name, Macro.dbpath.name())) {
            if (self.literal_dbpath) |literal| {
                self.allocator.free(literal);
                self.literal_dbpath = null;
            }
        }

        if (self.findMacro(normalized_name)) |index| {
            const old = self.macros.items[index].value;
            self.macros.items[index].value = replacement;
            self.allocator.free(old);
            return;
        }

        const owned_name = try self.allocator.dupe(u8, normalized_name);
        errdefer self.allocator.free(owned_name);
        try self.macros.append(self.allocator, .{
            .name = owned_name,
            .value = replacement,
        });
    }

    /// Applies the declarative, single-line subset used by conventional rpm
    /// macro files. Control directives and executable expressions remain
    /// unevaluated and are ignored unless a retained macro references them.
    pub fn applyMacroFileBytes(
        self: *TxnConfig,
        bytes: []const u8,
    ) SetMacroError!void {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var conditional_depth: usize = 0;
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len < 2 or line[0] != '%' or line[1] == '#') continue;

            var definition = line[1..];
            if (std.mem.startsWith(u8, definition, "define ") or
                std.mem.startsWith(u8, definition, "global "))
            {
                definition = definition[std.mem.indexOfScalar(u8, definition, ' ').? + 1 ..];
            } else if (definition[0] == '{') {
                continue;
            }

            if (std.mem.eql(u8, definition, "endif")) {
                conditional_depth -|= 1;
                continue;
            }

            const split = std.mem.indexOfAny(u8, definition, " \t") orelse continue;
            const name = definition[0..split];
            if (isConditionalStart(name)) {
                conditional_depth += 1;
                continue;
            }
            if (conditional_depth != 0) continue;
            if (isMacroControlDirective(name)) continue;
            const macro_value = std.mem.trim(u8, definition[split..], " \t\r");
            if (!isValidMacroName(name) or macro_value.len == 0) continue;
            try self.setMacroByName(name, macro_value);
        }
    }

    fn loadMacroGlob(self: *TxnConfig, pattern: []const u8) LoadMacrosError!void {
        const pattern_z = self.allocator.dupeZ(u8, pattern) catch return error.OutOfMemory;
        defer self.allocator.free(pattern_z);

        var matches: c.glob_t = std.mem.zeroes(c.glob_t);
        const rc = c.glob(pattern_z.ptr, 0, null, &matches);
        if (rc == c.GLOB_NOMATCH) return;
        if (rc != 0) return error.GlobFailed;
        defer c.globfree(&matches);

        for (0..matches.gl_pathc) |index| {
            try self.loadMacroFile(std.mem.span(matches.gl_pathv[index]));
        }
    }

    fn loadMacroFile(self: *TxnConfig, path: []const u8) LoadMacrosError!void {
        const path_z = self.allocator.dupeZ(u8, path) catch return error.OutOfMemory;
        defer self.allocator.free(path_z);

        const file = c.fopen(path_z.ptr, "rb") orelse return error.MacroFileOpenFailed;
        defer _ = c.fclose(file);
        if (c.fseek(file, 0, c.SEEK_END) != 0) return error.MacroFileReadFailed;
        const file_size = c.ftell(file);
        if (file_size < 0) return error.MacroFileReadFailed;
        c.rewind(file);

        const bytes = self.allocator.alloc(u8, @intCast(file_size)) catch {
            return error.OutOfMemory;
        };
        defer self.allocator.free(bytes);
        if (bytes.len != 0 and c.fread(bytes.ptr, 1, bytes.len, file) != bytes.len) {
            return error.MacroFileReadFailed;
        }
        try self.applyMacroFileBytes(bytes);
    }

    /// Expands one known macro into caller-owned memory.
    pub fn expandMacroAlloc(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        macro_name: Macro,
    ) ExpandError![]u8 {
        return self.expandNameAlloc(allocator, macro_name.name());
    }

    /// Expands an arbitrary macro into caller-owned memory.
    pub fn expandNameAlloc(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        name: []const u8,
    ) ExpandError![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        var stack: [MAX_EXPANSION_DEPTH][]const u8 = undefined;
        try self.appendExpandedMacro(allocator, &output, name, &stack, 0);
        return output.toOwnedSlice(allocator);
    }

    /// Expands macro expressions embedded in arbitrary caller-supplied text.
    pub fn expandTextAlloc(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        text: []const u8,
    ) ExpandError![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        var stack: [MAX_EXPANSION_DEPTH][]const u8 = undefined;
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, text, cursor, "%{")) |start| {
            try output.appendSlice(allocator, text[cursor..start]);
            const close = std.mem.indexOfScalarPos(u8, text, start + 2, '}') orelse {
                return error.InvalidMacroExpression;
            };
            const expression = text[start + 2 .. close];
            if (expression.len == 0) return error.InvalidMacroExpression;
            if (std.mem.startsWith(u8, expression, "getenv:")) {
                const env_name = expression["getenv:".len..];
                if (!isValidMacroName(env_name)) {
                    return error.InvalidMacroExpression;
                }
                const env_name_z = try allocator.dupeZ(u8, env_name);
                defer allocator.free(env_name_z);
                if (c.getenv(env_name_z.ptr)) |env_value| {
                    try output.appendSlice(allocator, std.mem.span(env_value));
                }
            } else if (self.rawValue(expression) == null) {
                try output.appendSlice(allocator, text[start .. close + 1]);
            } else {
                try self.appendExpandedMacro(
                    allocator,
                    &output,
                    expression,
                    &stack,
                    0,
                );
            }
            cursor = close + 1;
        }
        try output.appendSlice(allocator, text[cursor..]);
        return output.toOwnedSlice(allocator);
    }

    /// Resolves a known install-root-relative macro to a concrete path.
    pub fn resolvePath(
        self: *const TxnConfig,
        macro_name: Macro,
        buf: []u8,
    ) ResolvePathError![]const u8 {
        if (!macro_name.isInstallRootRelative()) return error.NotPathMacro;
        const expanded = try self.expandMacroAlloc(self.allocator, macro_name);
        defer self.allocator.free(expanded);
        return buildInstallRootedPath(buf, self.install_root, expanded);
    }

    /// Resolves the sqlite rpmdb file path under the configured root.
    pub fn resolveRpmDbSqlitePath(
        self: *const TxnConfig,
        buf: []u8,
    ) (ExpandError || error{PathTooLong})![]const u8 {
        const expanded = try self.expandMacroAlloc(self.allocator, .dbpath);
        defer self.allocator.free(expanded);
        return buildRpmDbSqlitePath(buf, self.install_root, expanded);
    }

    fn findMacro(self: *const TxnConfig, name: []const u8) ?usize {
        for (self.macros.items, 0..) |entry, index| {
            if (std.mem.eql(u8, entry.name, name)) return index;
        }
        return null;
    }

    fn appendExpandedMacro(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        output: *std.ArrayList(u8),
        name: []const u8,
        stack: *[MAX_EXPANSION_DEPTH][]const u8,
        depth: usize,
    ) ExpandError!void {
        if (depth >= MAX_EXPANSION_DEPTH) return error.ExpansionTooDeep;
        for (stack[0..depth]) |ancestor| {
            if (std.mem.eql(u8, ancestor, name)) return error.ExpansionCycle;
        }
        if (std.mem.eql(u8, name, Macro.dbpath.name())) {
            if (self.literal_dbpath) |literal| {
                try output.appendSlice(allocator, literal);
                return;
            }
        }

        const raw = self.rawValue(name) orelse return error.UnknownMacro;
        stack[depth] = name;
        try self.appendExpandedText(allocator, output, raw, stack, depth + 1);
    }

    fn appendExpandedText(
        self: *const TxnConfig,
        allocator: std.mem.Allocator,
        output: *std.ArrayList(u8),
        text: []const u8,
        stack: *[MAX_EXPANSION_DEPTH][]const u8,
        depth: usize,
    ) ExpandError!void {
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, text, cursor, "%{")) |start| {
            try output.appendSlice(allocator, text[cursor..start]);
            const close = std.mem.indexOfScalarPos(u8, text, start + 2, '}') orelse {
                return error.InvalidMacroExpression;
            };
            const expression = text[start + 2 .. close];
            if (expression.len == 0) return error.InvalidMacroExpression;

            if (std.mem.startsWith(u8, expression, "getenv:")) {
                const env_name = expression["getenv:".len..];
                if (!isValidMacroName(env_name)) return error.InvalidMacroExpression;
                const env_name_z = try allocator.dupeZ(u8, env_name);
                defer allocator.free(env_name_z);
                if (c.getenv(env_name_z.ptr)) |env_value| {
                    try output.appendSlice(allocator, std.mem.span(env_value));
                }
            } else {
                if (std.mem.indexOfScalar(u8, expression, ':') != null or
                    !isValidMacroName(expression))
                {
                    return error.InvalidMacroExpression;
                }
                try self.appendExpandedMacro(allocator, output, expression, stack, depth);
            }
            cursor = close + 1;
        }
        try output.appendSlice(allocator, text[cursor..]);
    }
};

/// Builds an install-root-relative path for a macro such as `_dbpath`
/// or `_tmppath`.
pub fn buildInstallRootedPath(
    buf: []u8,
    install_root: []const u8,
    macro_value: []const u8,
) error{PathTooLong}![]const u8 {
    const root_prefix = trimRootPrefix(install_root);
    const relative = std.mem.trim(u8, macro_value, "/");

    if (relative.len == 0) {
        if (root_prefix.len == 0) {
            if (buf.len < 2) return error.PathTooLong;
            return std.fmt.bufPrintZ(buf, "/", .{}) catch return error.PathTooLong;
        }
        if (root_prefix.len + 1 > buf.len) return error.PathTooLong;
        return std.fmt.bufPrintZ(buf, "{s}", .{root_prefix}) catch return error.PathTooLong;
    }

    const needed = root_prefix.len + 1 + relative.len + 1;
    if (needed > buf.len) return error.PathTooLong;
    return std.fmt.bufPrintZ(buf, "{s}/{s}", .{ root_prefix, relative }) catch return error.PathTooLong;
}

/// Builds the rooted path to the sqlite rpmdb file.
pub fn buildRpmDbSqlitePath(
    buf: []u8,
    install_root: []const u8,
    dbpath_macro: []const u8,
) error{PathTooLong}![]const u8 {
    const root_prefix = trimRootPrefix(install_root);
    const relative = std.mem.trim(u8, dbpath_macro, "/");

    if (relative.len == 0) {
        const needed = root_prefix.len + 1 + DEFAULT_RPMDB_BASENAME.len + 1;
        if (needed > buf.len) return error.PathTooLong;
        return std.fmt.bufPrintZ(buf, "{s}/{s}", .{ root_prefix, DEFAULT_RPMDB_BASENAME }) catch return error.PathTooLong;
    }

    const needed = root_prefix.len + 1 + relative.len + 1 + DEFAULT_RPMDB_BASENAME.len + 1;
    if (needed > buf.len) return error.PathTooLong;
    return std.fmt.bufPrintZ(
        buf,
        "{s}/{s}/{s}",
        .{ root_prefix, relative, DEFAULT_RPMDB_BASENAME },
    ) catch return error.PathTooLong;
}

/// Convenience helper for the default rpmdb location.
pub fn buildDefaultRpmDbSqlitePath(
    buf: []u8,
    install_root: []const u8,
) error{PathTooLong}![]const u8 {
    return buildRpmDbSqlitePath(buf, install_root, DEFAULT_DBPATH);
}

fn normalizeInstallRootOwned(allocator: std.mem.Allocator, input: []const u8) InitError![]u8 {
    const root = if (input.len == 0) DEFAULT_INSTALL_ROOT else input;
    if (!isExactAbsolutePath(root)) return error.InvalidInstallRoot;
    return allocator.dupe(u8, root);
}

fn isExactAbsolutePath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/' or
        std.mem.indexOfScalar(u8, path, 0) != null or
        std.ascii.isWhitespace(path[path.len - 1]) or
        (path.len > 1 and path[path.len - 1] == '/'))
    {
        return false;
    }
    if (std.mem.eql(u8, path, "/")) return true;
    var components = std.mem.splitScalar(u8, path[1..], '/');
    while (components.next()) |component| {
        if (component.len == 0 or
            std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return false;
        }
    }
    return true;
}

fn isValidMacroName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    }
    return true;
}

fn isMacroControlDirective(name: []const u8) bool {
    const directives = [_][]const u8{
        "if",
        "ifarch",
        "ifnarch",
        "ifos",
        "ifnos",
        "else",
        "endif",
        "include",
        "load",
        "trace",
        "dump",
    };
    for (directives) |directive| {
        if (std.mem.eql(u8, name, directive)) return true;
    }
    return false;
}

fn isConditionalStart(name: []const u8) bool {
    return std.mem.eql(u8, name, "if") or
        std.mem.eql(u8, name, "ifarch") or
        std.mem.eql(u8, name, "ifnarch") or
        std.mem.eql(u8, name, "ifos") or
        std.mem.eql(u8, name, "ifnos");
}

fn trimRootPrefix(input: []const u8) []const u8 {
    const effective = if (input.len == 0) DEFAULT_INSTALL_ROOT else input;
    var trimmed = std.mem.trimEnd(u8, effective, "/");
    if (trimmed.len == 0) trimmed = "";
    return trimmed;
}

test "parseRpmDefine accepts whitespace form" {
    const parsed = try parseRpmDefine("_dbpath /usr/lib/sysimage/rpm/");
    try std.testing.expectEqual(Macro.dbpath, parsed.macro.?);
    try std.testing.expectEqualStrings("_dbpath", parsed.name);
    try std.testing.expectEqualStrings("/usr/lib/sysimage/rpm/", parsed.value);
}

test "parseRpmDefine accepts equals form" {
    const parsed = try parseRpmDefine("%{_tmppath}=/var/tmp/native");
    try std.testing.expectEqual(Macro.tmppath, parsed.macro.?);
    try std.testing.expectEqualStrings("_tmppath", parsed.name);
    try std.testing.expectEqualStrings("/var/tmp/native", parsed.value);
}

test "parseRpmDefine rejects missing value" {
    try std.testing.expectError(error.InvalidDefine, parseRpmDefine("_dbpath"));
}

test "TxnConfig retains arbitrary rpmdefines" {
    var cfg = try TxnConfig.init(std.testing.allocator, "");
    defer cfg.deinit();

    try std.testing.expect(try cfg.applyRpmDefine("_foo /bar"));
    try std.testing.expectEqualStrings("/bar", cfg.rawValue("_foo").?);
    try std.testing.expectEqualStrings(DEFAULT_DBPATH, cfg.value(.dbpath));
}

test "TxnConfig resolves rooted dbpath override" {
    var cfg = try TxnConfig.init(std.testing.allocator, "/mnt/sysroot");
    defer cfg.deinit();

    try std.testing.expect(try cfg.applyRpmDefine("_dbpath=/usr/lib/sysimage/rpm"));

    var buf: [256]u8 = undefined;
    const db_dir = try cfg.resolvePath(.dbpath, &buf);
    try std.testing.expectEqualStrings("/mnt/sysroot/usr/lib/sysimage/rpm", db_dir);

    const db_file = try cfg.resolveRpmDbSqlitePath(&buf);
    try std.testing.expectEqualStrings("/mnt/sysroot/usr/lib/sysimage/rpm/rpmdb.sqlite", db_file);
}

test "TxnConfig resolves tmppath under installroot" {
    var cfg = try TxnConfig.init(std.testing.allocator, "/altroot");
    defer cfg.deinit();

    var buf: [256]u8 = undefined;
    const path = try cfg.resolvePath(.tmppath, &buf);
    try std.testing.expectEqualStrings("/altroot/var/tmp", path);
}

test "TxnConfig exposes install script path without rooting" {
    var cfg = try TxnConfig.init(std.testing.allocator, "/");
    defer cfg.deinit();

    try std.testing.expectEqualStrings(DEFAULT_INSTALL_SCRIPT_PATH, cfg.value(.install_script_path));
    var buf: [256]u8 = undefined;
    try std.testing.expectError(error.NotPathMacro, cfg.resolvePath(.install_script_path, &buf));
}

test "TxnConfig recursively expands arbitrary macros" {
    var cfg = try TxnConfig.init(std.testing.allocator, "/sysroot");
    defer cfg.deinit();

    _ = try cfg.applyRpmDefine("name demo");
    _ = try cfg.applyRpmDefine("_topdir /build/%{name}");
    _ = try cfg.applyRpmDefine("_specdir %{_topdir}/specs");

    const expanded = try cfg.expandMacroAlloc(std.testing.allocator, .specdir);
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("/build/demo/specs", expanded);

    var buf: [256]u8 = undefined;
    const rooted = try cfg.resolvePath(.specdir, &buf);
    try std.testing.expectEqualStrings("/sysroot/build/demo/specs", rooted);
}

test "literal rpmdb path never expands macro or environment expressions" {
    var cfg = try TxnConfig.init(std.testing.allocator, "/sysroot");
    defer cfg.deinit();
    _ = try cfg.applyRpmDefine("redirect expanded");
    const literal = "/literal/%{redirect}/%{getenv:HOME}";
    try cfg.setLiteralRpmDbPath(literal);

    const expanded = try cfg.expandMacroAlloc(
        std.testing.allocator,
        .dbpath,
    );
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings(literal, expanded);

    var clone = try cfg.clone(std.testing.allocator);
    defer clone.deinit();
    const cloned = try clone.expandMacroAlloc(
        std.testing.allocator,
        .dbpath,
    );
    defer std.testing.allocator.free(cloned);
    try std.testing.expectEqualStrings(literal, cloned);

    try cfg.setMacro(.dbpath, "/%{redirect}");
    const ordinary = try cfg.expandMacroAlloc(
        std.testing.allocator,
        .dbpath,
    );
    defer std.testing.allocator.free(ordinary);
    try std.testing.expectEqualStrings("/expanded", ordinary);
}

test "TxnConfig rejects cycles and unsupported expressions" {
    var cfg = try TxnConfig.init(std.testing.allocator, "");
    defer cfg.deinit();

    _ = try cfg.applyRpmDefine("one %{two}");
    _ = try cfg.applyRpmDefine("two %{one}");
    try std.testing.expectError(
        error.ExpansionCycle,
        cfg.expandNameAlloc(std.testing.allocator, "one"),
    );

    _ = try cfg.applyRpmDefine("scripted %{lua:print('no')}");
    try std.testing.expectError(
        error.InvalidMacroExpression,
        cfg.expandNameAlloc(std.testing.allocator, "scripted"),
    );
}

test "pinned config descriptors are CLOEXEC and identity is read-only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/var/lib/rpm");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/var/lib/rpm/rpmdb.sqlite",
        .data = "",
    });
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);

    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();
    var pinned = try config.cloneWithPinnedInstallRoot(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();

    inline for (.{
        pinned.pinnedInstallRootFd().?,
        pinned.pinnedRpmDbDirFd().?,
        pinned.pinnedRpmDbMainFd().?,
    }) |fd| {
        try std.testing.expect(
            (std.c.fcntl(fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
        );
    }
    const status_flags = std.c.fcntl(
        pinned.pinnedRpmDbMainFd().?,
        std.c.F.GETFL,
    );
    try std.testing.expect(status_flags >= 0);
    try std.testing.expectEqual(@as(c_int, 0), status_flags & 3);
}

test "literal rpmdb pin selects the exact supplied path bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(
        std.testing.io,
        "root/literal/%{redirect}",
    );
    try tmp.dir.createDirPath(std.testing.io, "root/expanded");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/literal/%{redirect}/rpmdb.sqlite",
        .data = "",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/expanded/rpmdb.sqlite",
        .data = "",
    });
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);

    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();
    _ = try config.applyRpmDefine("redirect expanded");
    try config.setLiteralRpmDbPath("/literal/%{redirect}");
    var pinned = try config.cloneWithPinnedInstallRoot(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();

    const literal_parent = std.c.openat(root_fd, "literal", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(literal_parent >= 0);
    defer _ = std.c.close(literal_parent);
    const literal_fd = std.c.openat(literal_parent, "%{redirect}", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(literal_fd >= 0);
    defer _ = std.c.close(literal_fd);
    const expanded_fd = std.c.openat(root_fd, "expanded", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(expanded_fd >= 0);
    defer _ = std.c.close(expanded_fd);

    const pinned_identity = fdStat(pinned.pinnedRpmDbDirFd().?).?.identity;
    try std.testing.expect(
        pinned_identity.eql(fdStat(literal_fd).?.identity),
    );
    try std.testing.expect(
        !pinned_identity.eql(fdStat(expanded_fd).?.identity),
    );
}

test "deferred rpmdb pin uses the final macro and then freezes it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/var/lib/rpm");
    try tmp.dir.createDirPath(std.testing.io, "root/custom/rpm");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/var/lib/rpm/rpmdb.sqlite",
        .data = "",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/custom/rpm/rpmdb.sqlite",
        .data = "",
    });
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);

    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();
    var pinned = try config.cloneWithPinnedInstallRootDeferredRpmDb(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();
    try std.testing.expect(pinned.pinnedRpmDbDirFd() == null);
    try pinned.setMacro(.dbpath, "/custom/rpm");
    try pinned.finalizeRpmDbPin();
    const custom_fd = std.c.openat(root_fd, "custom/rpm", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(custom_fd >= 0);
    defer _ = std.c.close(custom_fd);
    const expected = fdStat(custom_fd) orelse
        return error.TestUnexpectedResult;
    const actual = fdStat(pinned.pinnedRpmDbDirFd().?) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(expected.identity.eql(actual.identity));
    try std.testing.expectError(
        error.InvalidMacroValue,
        pinned.setMacro(.dbpath, "/var/lib/rpm"),
    );
}

test "failed rpmdb finalization never adopts a closed descriptor" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/custom/rpm");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside",
        .data = "",
    });
    try tmp.dir.symLink(
        std.testing.io,
        "../../../outside",
        "root/custom/rpm/rpmdb.sqlite",
        .{},
    );
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();

    inline for (0..2) |failure_kind| {
        var pinned = try config.cloneWithPinnedInstallRootDeferredRpmDb(
            std.testing.allocator,
            root,
            root_fd,
        );
        defer pinned.deinit();
        try pinned.setMacro(.dbpath, "/custom/rpm");
        try std.testing.expectError(
            error.RpmDbPinFailed,
            pinned.finalizeRpmDbPin(),
        );
        try std.testing.expect(pinned.pinnedRpmDbDirFd() == null);
        try std.testing.expect(pinned.pinnedRpmDbMainFd() == null);
        try std.testing.expect(std.c.fcntl(root_fd, std.c.F.GETFD) >= 0);

        if (failure_kind == 0) {
            try tmp.dir.deleteFile(
                std.testing.io,
                "root/custom/rpm/rpmdb.sqlite",
            );
            try tmp.dir.createDir(
                std.testing.io,
                "root/custom/rpm/rpmdb.sqlite",
                .default_dir,
            );
        }
    }
}

test "rpmdb symlinks resolve only within the pinned install root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/var/lib");
    try tmp.dir.createDirPath(std.testing.io, "root/usr/lib/sysimage/rpm");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/usr/lib/sysimage/rpm/rpmdb.sqlite",
        .data = "",
    });
    try tmp.dir.symLink(
        std.testing.io,
        "../../usr/lib/sysimage/rpm",
        "root/var/lib/rpm",
        .{},
    );
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();
    var pinned = try config.cloneWithPinnedInstallRoot(
        std.testing.allocator,
        root,
        root_fd,
    );
    pinned.deinit();

    try tmp.dir.deleteFile(std.testing.io, "root/var/lib/rpm");
    try tmp.dir.symLink(
        std.testing.io,
        "../../../outside",
        "root/var/lib/rpm",
        .{},
    );
    try std.testing.expectError(
        error.RpmDbPinFailed,
        config.cloneWithPinnedInstallRoot(
            std.testing.allocator,
            root,
            root_fd,
        ),
    );
}

test "TxnConfig parses declarative macro file entries" {
    var cfg = try TxnConfig.init(std.testing.allocator, "");
    defer cfg.deinit();

    try cfg.applyMacroFileBytes(
        \\# comment
        \\%_topdir /native/build
        \\%global package_name demo
        \\%define derived %{package_name}-value
        \\%if 0
        \\%_topdir /ignored/control
        \\%endif
        \\%_specdir /native/specs
    );

    try std.testing.expectEqualStrings("/native/build", cfg.value(.topdir));
    try std.testing.expectEqualStrings("/native/specs", cfg.value(.specdir));
    const expanded = try cfg.expandNameAlloc(std.testing.allocator, "derived");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("demo-value", expanded);
}

test "TxnConfig rejects relative installroots" {
    inline for (.{
        "relative/root",
        " /root",
        "/root ",
        "/root/",
        "/root//nested",
        "/root/./nested",
        "/root/../nested",
        "/root\x00hidden",
    }) |invalid| {
        try std.testing.expectError(
            error.InvalidInstallRoot,
            TxnConfig.init(std.testing.allocator, invalid),
        );
    }
}

test "buildDefaultRpmDbSqlitePath keeps root slash semantics" {
    var buf: [256]u8 = undefined;
    const path = try buildDefaultRpmDbSqlitePath(&buf, "/");
    try std.testing.expectEqualStrings("/var/lib/rpm/rpmdb.sqlite", path);
}
