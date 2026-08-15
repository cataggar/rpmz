pub const ValueOption = struct {
    name: []const u8,
    short: ?[]const u8 = null,
};

pub const install_root_name = "installroot";
pub const install_root = ValueOption{
    .name = install_root_name,
    .short = "-i",
};
pub const install_root_single_dash = "-" ++ install_root_name;
pub const rpmdb_path_name = "rpmdb-path";
pub const rpmdb_path = ValueOption{ .name = rpmdb_path_name };
pub const architecture_name = "forcearch";
pub const architecture = ValueOption{ .name = architecture_name };

pub const value_options = [_]ValueOption{
    install_root,
    rpmdb_path,
    architecture,
};

/// The legacy long-option matcher accepts every unique non-empty prefix.
pub const json_name = "json";
pub const help_long = "--help";
pub const help_short = "-h";
