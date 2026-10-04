const std = @import("std");
const Translator = @import("translate_c").Translator;

const Header = struct { source: []const u8, text: []const u8 };
const headers = [_]Header{
    .{ .source = "client/package_query.zig", .text = "#include <sys/vfs.h>\n" },
    .{ .source = "common/lock.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <string.h>\n" },
    .{ .source = "common/memory.zig", .text = "#include <errno.h>\n#include <stdarg.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n" },
    .{ .source = "common/strings.zig", .text = "#include <errno.h>\n#include <string.h>\n#include <stdlib.h>\n" },
    .{ .source = "common/utils.zig", .text = "#define _XOPEN_SOURCE 500\n#define _DEFAULT_SOURCE 1\n#include <ctype.h>\n#include <errno.h>\n#include <ftw.h>\n#include <libgen.h>\n#include <limits.h>\n#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <strings.h>\n#include <sys/stat.h>\n#include <unistd.h>\n#include <../llconf/nodes.h>\n" },
    .{ .source = "llconf/entry.zig", .text = "#include <ctype.h>\n#include <errno.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n#include <entry.h>\n" },
    .{ .source = "llconf/ini.zig", .text = "#define _GNU_SOURCE 1\n#include <ctype.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n#include <lines.h>\n#include <modules.h>\n#include <strutils.h>\n#include <ini.h>\n" },
    .{ .source = "llconf/lines.zig", .text = "#define _GNU_SOURCE 1\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <lines.h>\n" },
    .{ .source = "llconf/modules.zig", .text = "#include <dlfcn.h>\n#include <errno.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n#include <modules.h>\n" },
    .{ .source = "llconf/nodes.zig", .text = "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n" },
    .{ .source = "llconf/strutils.zig", .text = "#include <ctype.h>\n#include <stdlib.h>\n#include <string.h>\n#include <strutils.h>\n" },
    .{ .source = "plugins/builtin.zig", .text = "#include <stddef.h>\n#include <nodes.h>\n" },
    .{ .source = "pytests/test_support.zig", .text = "#include <stdio.h>\n" },
    .{ .source = "repomd/query_native.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include <rpmdb.h>\n" },
    .{ .source = "repomd/solver_oracle_bridge.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include <rpmdb.h>\n#include <solv/chksum.h>\n#include <solv/poolarch.h>\n#include <solv/repodata.h>\n#include <solv/solver.h>\n" },
    .{ .source = "repomd/transaction_native.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <rpmdb.h>\n" },
    .{ .source = "rpmzig/erase.zig", .text = "#include <errno.h>\n#include <sys/stat.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/install.zig", .text = "#include <grp.h>\n#include <pwd.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <sys/stat.h>\n#include <sys/sysmacros.h>\n#include <sys/time.h>\n#include <sys/types.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/lua_scriptlet_zig.zig", .text = "#include <dirent.h>\n#include <errno.h>\n#include <glob.h>\n#include <spawn.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <sys/stat.h>\n#include <sys/time.h>\n#include <sys/utsname.h>\n#include <sys/wait.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/pkgfile.zig", .text = "#include <stdio.h>\n#include <stdlib.h>\n#include <sys/stat.h>\n" },
    .{ .source = "rpmzig/queryformat.zig", .text = "#include <time.h>\n" },
    .{ .source = "rpmzig/rpmdb.zig", .text = "#include <errno.h>\n#include <time.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/rpmdb_write.zig", .text = "#include <errno.h>\n#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n#include <sys/stat.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/scriptlet.zig", .text = "#include <errno.h>\n#include <signal.h>\n#include <stdlib.h>\n#include <string.h>\n#include <sys/stat.h>\n#include <sys/types.h>\n#include <sys/wait.h>\n#include <time.h>\n#include <unistd.h>\n" },
    .{ .source = "rpmzig/source.zig", .text = "#include <unistd.h>\n" },
    .{ .source = "rpmzig/txn_config.zig", .text = "#include <glob.h>\n#include <stdio.h>\n#include <stdlib.h>\n" },
    .{ .source = "tools/cli/lib/api.zig", .text = "#include <errno.h>\n#include <stdio.h>\n" },
    .{ .source = "tools/cli/lib/apimisc.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <string.h>\n#include <strings.h>\n#include <time.h>\n#include <unistd.h>\n" },
    .{ .source = "tools/cli/lib/getopt_c.zig", .text = "#include <getopt.h>\n" },
    .{ .source = "tools/cli/lib/installcmd.zig", .text = "#include <errno.h>\n#include <stdio.h>\n" },
    .{ .source = "tools/cli/lib/options.zig", .text = "#include <errno.h>\n#include <string.h>\n" },
    .{ .source = "tools/cli/lib/output.zig", .text = "#include <errno.h>\n#include <sys/ioctl.h>\n#include <unistd.h>\n" },
    .{ .source = "tools/cli/lib/parseargs.zig", .text = "#include <errno.h>\n#include <stdlib.h>\n#include <string.h>\n#include <strings.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/parsehistoryargs.zig", .text = "#include <errno.h>\n#include <string.h>\n#include <strings.h>\n#include <stdlib.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/parselistargs.zig", .text = "#include <errno.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/parserepoqueryargs.zig", .text = "#include <errno.h>\n#include <string.h>\n#include <strings.h>\n#include <stdlib.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/parsereposyncargs.zig", .text = "#include <errno.h>\n#include <string.h>\n#include <strings.h>\n#include <stdlib.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/parseupdateinfo.zig", .text = "#include <errno.h>\n#include <stdlib.h>\n#include <string.h>\n#include <nodes.h>\n" },
    .{ .source = "tools/cli/lib/root.zig", .text = "#include <getopt.h>\n" },
    .{ .source = "tools/cli/lib/updateinfocmd.zig", .text = "#include <errno.h>\n#include <stdio.h>\n" },
    .{ .source = "tools/cli/main.zig", .text = "#include <errno.h>\n#include <stdio.h>\n#include <string.h>\n#include <unistd.h>\n" },
    .{ .source = "tools/config/main.zig", .text = "#include <ctype.h>\n#include <errno.h>\n#include <getopt.h>\n#include <glob.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <llconf/nodes.h>\n#include <llconf/modules.h>\n#include <llconf/entry.h>\n#include <llconf/ini.h>\n" },
};

pub fn wire(b: *std.Build) void {
    var steps: std.AutoHashMap(*std.Build.Step, void) = .init(b.allocator);
    var modules: std.AutoHashMap(*std.Build.Module, void) = .init(b.allocator);
    for (b.modules.values()) |module| wireModule(b, module, &modules);
    for (b.top_level_steps.values()) |top| wireStep(b, &top.step, &steps, &modules);
}

fn wireStep(b: *std.Build, step: *std.Build.Step, steps: *std.AutoHashMap(*std.Build.Step, void), modules: *std.AutoHashMap(*std.Build.Module, void)) void {
    const entry = steps.getOrPut(step) catch @panic("OOM");
    if (entry.found_existing) return;
    const dependencies = b.allocator.dupe(*std.Build.Step, step.dependencies.items) catch @panic("OOM");
    for (dependencies) |dependency| wireStep(b, dependency, steps, modules);
    if (step.cast(std.Build.Step.Compile)) |compile| wireModule(b, compile.root_module, modules);
}

fn wireModule(b: *std.Build, module: *std.Build.Module, modules: *std.AutoHashMap(*std.Build.Module, void)) void {
    const entry = modules.getOrPut(module) catch @panic("OOM");
    if (entry.found_existing or module.owner != b) return;
    const imports = b.allocator.dupe(*std.Build.Module, module.import_table.values()) catch @panic("OOM");
    for (imports) |import| wireModule(b, import, modules);
    for (module.link_objects.items) |object| {
        if (object == .other_step) wireModule(b, object.other_step.root_module, modules);
    }
    const source = module.root_source_file orelse return;
    if (source != .src_path or source.src_path.owner != b) return;
    var files: std.StringHashMap(void) = .init(b.allocator);
    scan(b, module, source.src_path.sub_path, &files);
}

fn scan(b: *std.Build, module: *std.Build.Module, source: []const u8, files: *std.StringHashMap(void)) void {
    const entry = files.getOrPut(source) catch @panic("OOM");
    if (entry.found_existing) return;
    b.dependOnFileContents(b.path(source));
    const root = b.root.openDir(b.graph.io, ".", .{}) catch @panic("unable to open package root");
    defer root.close(b.graph.io);
    const bytes = root.readFileAlloc(b.graph.io, source, b.allocator, .limited(4 * 1024 * 1024)) catch |err|
        std.debug.panic("reading C-binding graph source {s}: {t}", .{ source, err });
    const text = b.allocator.dupeSentinel(u8, bytes, 0) catch @panic("OOM");
    var tree = std.zig.Ast.parse(b.allocator, text, .{}) catch @panic("OOM");
    defer tree.deinit(b.allocator);
    const tags = tree.tokens.items(.tag);
    for (tags, 0..) |tag, index| {
        if (tag != .builtin or !std.mem.eql(u8, tree.tokenSlice(@intCast(index)), "@import")) continue;
        if (index + 2 >= tags.len or tags[index + 2] != .string_literal) continue;
        const name = std.zig.string_literal.parseAlloc(b.allocator, tree.tokenSlice(@intCast(index + 2))) catch @panic("invalid import string");
        if (std.mem.startsWith(u8, name, "c.")) {
            addBinding(b, module, name);
        } else if (std.mem.endsWith(u8, name, ".zig")) {
            const root_path = @import("install_paths.zig").rootPath(b);
            const absolute = std.fs.path.resolve(b.allocator, &.{ root_path, std.fs.path.dirname(source) orelse "", name }) catch @panic("OOM");
            const relative = std.fs.path.relativeAlloc(b.allocator, root_path, null, root_path, absolute) catch @panic("OOM");
            scan(b, module, relative, files);
        }
    }
}

fn addBinding(b: *std.Build, module: *std.Build.Module, name: []const u8) void {
    if (module.import_table.contains(name)) return;
    for (headers) |header| {
        const stem = std.mem.replaceOwned(u8, b.allocator, header.source[0 .. header.source.len - 4], "/", ".") catch @panic("OOM");
        if (!std.mem.eql(u8, name[2..], stem)) continue;
        if (std.mem.eql(u8, stem, "repomd.solver_oracle_bridge")) {
            var oracle_in_scope = false;
            for (module.c_macros.items) |macro| {
                if (std.mem.startsWith(u8, macro, "-DTDNF_VENDORED_LIBSOLV_VERSION_PATCH="))
                    oracle_in_scope = true;
            }
            if (!oracle_in_scope) return;
        }
        const translator: Translator = .init(b.dependency("translate_c", .{}), .{
            .name = name,
            .c_source_file = b.addWriteFiles().add(b.fmt("{s}.h", .{name}), header.text),
            .target = module.resolved_target orelse b.graph.host,
            .optimize = module.optimize orelse .debug,
            .extra_args = module.c_macros.items,
        });
        translator.addIncludePath(b.path(std.fs.path.dirname(header.source) orelse "."));
        for (module.include_dirs.items) |include| switch (include) {
            .path => |path| translator.addIncludePath(path),
            .path_system => |path| translator.addSystemIncludePath(path),
            .path_after => |path| translator.addAfterIncludePath(path),
            .other_step => |compile| translator.addIncludePath(compile.getEmittedIncludeTree()),
            .config_header_step => |config| translator.addIncludePath(config.getOutputDir()),
            else => {},
        };
        module.addImport(name, translator.mod);
        return;
    }
    std.debug.panic("no private C translation unit for {s}", .{name});
}
