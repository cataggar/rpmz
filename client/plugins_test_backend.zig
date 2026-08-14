const plugin_metadata = @import("plugin_metadata");

pub fn BuiltinMetalinkCreate(_: ?*anyopaque, _: ?*?*anyopaque) u32 {
    return 1622;
}

pub fn BuiltinMetalinkDestroy(_: ?*anyopaque) void {}

pub fn BuiltinMetalinkRepoConfig(_: ?*anyopaque, _: ?*const anyopaque) u32 {
    return 1622;
}

pub fn BuiltinMetalinkRepoMDDownloadStart(
    _: ?*anyopaque,
    _: ?[*:0]const u8,
    _: ?*const plugin_metadata.PinnedDirectory,
) u32 {
    return 1622;
}

pub fn BuiltinMetalinkRepoMDDownloadEnd(
    _: ?*anyopaque,
    _: ?[*:0]const u8,
    _: ?*const plugin_metadata.PinnedFile,
) u32 {
    return 1622;
}

pub fn BuiltinRepoGPGCheckCreate(_: ?*anyopaque, _: ?*?*anyopaque) u32 {
    return 1622;
}

pub fn BuiltinRepoGPGCheckDestroy(_: ?*anyopaque) void {}

pub fn BuiltinRepoGPGCheckRepoConfig(
    _: ?*anyopaque,
    _: ?*const anyopaque,
) u32 {
    return 1622;
}

pub fn BuiltinRepoGPGCheckRepoMDDownloadEnd(
    _: ?*anyopaque,
    _: ?[*:0]const u8,
    _: ?*const plugin_metadata.PinnedFile,
) u32 {
    return 1622;
}
