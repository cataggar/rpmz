//! Private declarations for the C-shaped JSON dump exports.

pub const JsonDump = extern struct {
    buf: [*c]u8 = null,
    buf_size: c_uint = 0,
    pos: c_uint = 0,
};

pub extern fn jd_create(size: c_uint) ?*JsonDump;
pub extern fn jd_destroy(jd: ?*JsonDump) void;
pub extern fn jd_map_start(jd: ?*JsonDump) c_int;
pub extern fn jd_map_add_string(
    jd: ?*JsonDump,
    key: [*c]const u8,
    value: [*c]const u8,
) c_int;
pub extern fn jd_map_add_int(
    jd: ?*JsonDump,
    key: [*c]const u8,
    value: c_int,
) c_int;
pub extern fn jd_map_add_int64(
    jd: ?*JsonDump,
    key: [*c]const u8,
    value: i64,
) c_int;
pub extern fn jd_map_add_bool(
    jd: ?*JsonDump,
    key: [*c]const u8,
    value: c_int,
) c_int;
pub extern fn jd_map_add_null(jd: ?*JsonDump, key: [*c]const u8) c_int;
pub extern fn jd_map_add_child(
    jd: ?*JsonDump,
    key: [*c]const u8,
    child: ?*const JsonDump,
) c_int;
pub extern fn jd_list_start(jd: ?*JsonDump) c_int;
pub extern fn jd_list_add_string(
    jd: ?*JsonDump,
    value: [*c]const u8,
) c_int;
pub extern fn jd_list_add_int(jd: ?*JsonDump, value: c_int) c_int;
pub extern fn jd_list_add_int64(jd: ?*JsonDump, value: i64) c_int;
pub extern fn jd_list_add_bool(jd: ?*JsonDump, value: c_int) c_int;
pub extern fn jd_list_add_null(jd: ?*JsonDump) c_int;
pub extern fn jd_list_add_child(
    jd: ?*JsonDump,
    child: ?*const JsonDump,
) c_int;
