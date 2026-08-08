const std = @import("std");

pub const ERROR_TDNF_REPO_PERFORM: u32 = 1006;
pub const ERROR_TDNF_NO_REPOS: u32 = 1008;
pub const ERROR_TDNF_REPO_NOT_FOUND: u32 = 1009;
pub const ERROR_TDNF_INVALID_CONF: u32 = 1010;
pub const ERROR_TDNF_NO_MATCH: u32 = 1011;
pub const ERROR_TDNF_CONF_FILE_LOAD: u32 = 1002;
pub const ERROR_TDNF_NO_DISTROVERPKG: u32 = 1022;
pub const ERROR_TDNF_DISTROVERPKG_READ: u32 = 1023;
pub const ERROR_TDNF_METADATA_EXPIRE_PARSE: u32 = 1029;
pub const ERROR_TDNF_OPERATION_ABORTED: u32 = 1032;
pub const ERROR_TDNF_ALREADY_INSTALLED: u32 = 1026;
pub const ERROR_TDNF_NO_DOWNGRADE_PATH: u32 = 1028;
pub const ERROR_TDNF_CACHE_DIR_OUT_OF_DISK_SPACE: u32 = 1036;
pub const ERROR_TDNF_SET_SSL_SETTINGS: u32 = 1401;
pub const ERROR_TDNF_URL_INVALID: u32 = 1524;
pub const ERROR_TDNF_SYSTEM_BASE: u32 = 1600;
pub const ERROR_TDNF_INVALID_PARAMETER: u32 = fromErrno(.INVAL);
pub const ERROR_TDNF_OUT_OF_MEMORY: u32 = fromErrno(.NOMEM);
pub const ERROR_TDNF_ALREADY_EXISTS: u32 = fromErrno(.EXIST);
pub const ERROR_TDNF_INVALID_DIR: u32 = fromErrno(.NOTDIR);
pub const ERROR_TDNF_CALL_NOT_SUPPORTED: u32 = fromErrno(.NOSYS);
pub const ERROR_TDNF_SOLV_FAILED: u32 = 1301;
pub const ERROR_TDNF_SOLV_IO: u32 = 1304;
pub const ERROR_TDNF_RPM_HEADER_CONVERT_FAILED: u32 = 1509;
pub const ERROR_TDNF_RPMTS_OPENDB_FAILED: u32 = 1526;
pub const ERROR_TDNF_INVALID_REPO_FILE: u32 = 1004;
pub const ERROR_TDNF_FILE_NOT_FOUND: u32 = fromErrno(.NOENT);
pub const ERROR_TDNF_TIMED_OUT: u32 = fromErrno(.TIMEDOUT);
pub const ERROR_TDNF_NO_DATA: u32 = fromErrno(.NODATA);
pub const ERROR_TDNF_HISTORY_ERROR: u32 = 1801;
pub const ERROR_TDNF_HISTORY_NODB: u32 = 1802;

pub fn fromErrno(value: std.posix.E) u32 {
    return ERROR_TDNF_SYSTEM_BASE + @intFromEnum(value);
}

test "system error values match the public Linux ABI" {
    try std.testing.expectEqual(@as(u32, 1612), ERROR_TDNF_OUT_OF_MEMORY);
    try std.testing.expectEqual(@as(u32, 1622), ERROR_TDNF_INVALID_PARAMETER);
    try std.testing.expectEqual(@as(u32, 1638), ERROR_TDNF_CALL_NOT_SUPPORTED);
    try std.testing.expectEqual(@as(u32, 1301), ERROR_TDNF_SOLV_FAILED);
    try std.testing.expectEqual(@as(u32, 1304), ERROR_TDNF_SOLV_IO);
    try std.testing.expectEqual(@as(u32, 1509), ERROR_TDNF_RPM_HEADER_CONVERT_FAILED);
    try std.testing.expectEqual(@as(u32, 1602), ERROR_TDNF_FILE_NOT_FOUND);
    try std.testing.expectEqual(@as(u32, 1710), ERROR_TDNF_TIMED_OUT);
}
