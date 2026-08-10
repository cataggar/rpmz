// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1.

const __root = @This();
const common = @import("tdnf_common");
const canonical_abi = @import("client_abi");
const transaction_plan_abi = @import("transaction_plan_capture_abi");
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
pub const ptrdiff_t = c_long;
pub const wchar_t = c_int;
pub const max_align_t = extern struct {
    __aro_max_align_ll: c_longlong = 0,
    __aro_max_align_ld: c_longdouble = 0,
};
pub const struct___va_list_tag_1 = extern struct {
    unnamed_0: c_uint = 0,
    unnamed_1: c_uint = 0,
    unnamed_2: ?*anyopaque = null,
    unnamed_3: ?*anyopaque = null,
};
pub const __builtin_va_list = [1]struct___va_list_tag_1;
pub const va_list = __builtin_va_list;
pub const __gnuc_va_list = __builtin_va_list;
pub const __u_char = u8;
pub const __u_short = c_ushort;
pub const __u_int = c_uint;
pub const __u_long = c_ulong;
pub const __int8_t = i8;
pub const __uint8_t = u8;
pub const __int16_t = c_short;
pub const __uint16_t = c_ushort;
pub const __int32_t = c_int;
pub const __uint32_t = c_uint;
pub const __int64_t = c_long;
pub const __uint64_t = c_ulong;
pub const __int_least8_t = __int8_t;
pub const __uint_least8_t = __uint8_t;
pub const __int_least16_t = __int16_t;
pub const __uint_least16_t = __uint16_t;
pub const __int_least32_t = __int32_t;
pub const __uint_least32_t = __uint32_t;
pub const __int_least64_t = __int64_t;
pub const __uint_least64_t = __uint64_t;
pub const __quad_t = c_long;
pub const __u_quad_t = c_ulong;
pub const __intmax_t = c_long;
pub const __uintmax_t = c_ulong;
pub const __dev_t = c_ulong;
pub const __uid_t = c_uint;
pub const __gid_t = c_uint;
pub const __ino_t = c_ulong;
pub const __ino64_t = c_ulong;
pub const __mode_t = c_uint;
pub const __nlink_t = c_ulong;
pub const __off_t = c_long;
pub const __off64_t = c_long;
pub const __pid_t = c_int;
pub const __fsid_t = extern struct {
    __val: [2]c_int = @import("std").mem.zeroes([2]c_int),
};
pub const __clock_t = c_long;
pub const __rlim_t = c_ulong;
pub const __rlim64_t = c_ulong;
pub const __id_t = c_uint;
pub const __time_t = c_long;
pub const __useconds_t = c_uint;
pub const __suseconds_t = c_long;
pub const __suseconds64_t = c_long;
pub const __daddr_t = c_int;
pub const __key_t = c_int;
pub const __clockid_t = c_int;
pub const __timer_t = ?*anyopaque;
pub const __blksize_t = c_long;
pub const __blkcnt_t = c_long;
pub const __blkcnt64_t = c_long;
pub const __fsblkcnt_t = c_ulong;
pub const __fsblkcnt64_t = c_ulong;
pub const __fsfilcnt_t = c_ulong;
pub const __fsfilcnt64_t = c_ulong;
pub const __fsword_t = c_long;
pub const __ssize_t = c_long;
pub const __syscall_slong_t = c_long;
pub const __syscall_ulong_t = c_ulong;
pub const __loff_t = __off64_t;
pub const __caddr_t = [*c]u8;
pub const __intptr_t = c_long;
pub const __socklen_t = c_uint;
pub const __sig_atomic_t = c_int;
const union_unnamed_2 = extern union {
    __wch: c_uint,
    __wchb: [4]u8,
};
pub const __mbstate_t = extern struct {
    __count: c_int = 0,
    __value: union_unnamed_2 = @import("std").mem.zeroes(union_unnamed_2),
};
pub const struct__G_fpos_t = extern struct {
    __pos: __off_t = 0,
    __state: __mbstate_t = @import("std").mem.zeroes(__mbstate_t),
};
pub const __fpos_t = struct__G_fpos_t;
pub const struct__G_fpos64_t = extern struct {
    __pos: __off64_t = 0,
    __state: __mbstate_t = @import("std").mem.zeroes(__mbstate_t),
};
pub const __fpos64_t = struct__G_fpos64_t;
pub const struct__IO_marker = opaque {};
pub const _IO_lock_t = anyopaque;
pub const struct__IO_codecvt = opaque {};
pub const struct__IO_wide_data = opaque {};
pub const struct__IO_FILE = extern struct {
    _flags: c_int = 0,
    _IO_read_ptr: [*c]u8 = null,
    _IO_read_end: [*c]u8 = null,
    _IO_read_base: [*c]u8 = null,
    _IO_write_base: [*c]u8 = null,
    _IO_write_ptr: [*c]u8 = null,
    _IO_write_end: [*c]u8 = null,
    _IO_buf_base: [*c]u8 = null,
    _IO_buf_end: [*c]u8 = null,
    _IO_save_base: [*c]u8 = null,
    _IO_backup_base: [*c]u8 = null,
    _IO_save_end: [*c]u8 = null,
    _markers: ?*struct__IO_marker = null,
    _chain: [*c]struct__IO_FILE = null,
    _fileno: c_int = 0,
    _flags2: c_int = 0,
    _old_offset: __off_t = 0,
    _cur_column: c_ushort = 0,
    _vtable_offset: i8 = 0,
    _shortbuf: [1]u8 = @import("std").mem.zeroes([1]u8),
    _lock: ?*_IO_lock_t = null,
    _offset: __off64_t = 0,
    _codecvt: ?*struct__IO_codecvt = null,
    _wide_data: ?*struct__IO_wide_data = null,
    _freeres_list: [*c]struct__IO_FILE = null,
    _freeres_buf: ?*anyopaque = null,
    __pad5: usize = 0,
    _mode: c_int = 0,
    _unused2: [20]u8 = @import("std").mem.zeroes([20]u8),
    pub const fclose = __root.fclose;
    pub const fflush = __root.fflush;
    pub const fflush_unlocked = __root.fflush_unlocked;
    pub const setbuf = __root.setbuf;
    pub const setvbuf = __root.setvbuf;
    pub const setbuffer = __root.setbuffer;
    pub const setlinebuf = __root.setlinebuf;
    pub const fprintf = __root.fprintf;
    pub const vfprintf = __root.vfprintf;
    pub const fscanf = __root.fscanf;
    pub const vfscanf = __root.vfscanf;
    pub const fgetc = __root.fgetc;
    pub const getc = __root.getc;
    pub const getc_unlocked = __root.getc_unlocked;
    pub const fgetc_unlocked = __root.fgetc_unlocked;
    pub const getw = __root.getw;
    pub const fseek = __root.fseek;
    pub const ftell = __root.ftell;
    pub const rewind = __root.rewind;
    pub const fseeko = __root.fseeko;
    pub const ftello = __root.ftello;
    pub const fgetpos = __root.fgetpos;
    pub const fsetpos = __root.fsetpos;
    pub const clearerr = __root.clearerr;
    pub const feof = __root.feof;
    pub const ferror = __root.ferror;
    pub const clearerr_unlocked = __root.clearerr_unlocked;
    pub const feof_unlocked = __root.feof_unlocked;
    pub const ferror_unlocked = __root.ferror_unlocked;
    pub const fileno = __root.fileno;
    pub const fileno_unlocked = __root.fileno_unlocked;
    pub const pclose = __root.pclose;
    pub const flockfile = __root.flockfile;
    pub const ftrylockfile = __root.ftrylockfile;
    pub const funlockfile = __root.funlockfile;
    pub const __uflow = __root.__uflow;
    pub const __overflow = __root.__overflow;
    pub const unlocked = __root.fflush_unlocked;
    pub const uflow = __root.__uflow;
    pub const overflow = __root.__overflow;
};
pub const __FILE = struct__IO_FILE;
pub const FILE = struct__IO_FILE;
pub const cookie_read_function_t = fn (__cookie: ?*anyopaque, __buf: [*c]u8, __nbytes: usize) callconv(.c) __ssize_t;
pub const cookie_write_function_t = fn (__cookie: ?*anyopaque, __buf: [*c]const u8, __nbytes: usize) callconv(.c) __ssize_t;
pub const cookie_seek_function_t = fn (__cookie: ?*anyopaque, __pos: [*c]__off64_t, __w: c_int) callconv(.c) c_int;
pub const cookie_close_function_t = fn (__cookie: ?*anyopaque) callconv(.c) c_int;
pub const struct__IO_cookie_io_functions_t = extern struct {
    read: ?*const cookie_read_function_t = null,
    write: ?*const cookie_write_function_t = null,
    seek: ?*const cookie_seek_function_t = null,
    close: ?*const cookie_close_function_t = null,
};
pub const cookie_io_functions_t = struct__IO_cookie_io_functions_t;
pub const off_t = __off_t;
pub const fpos_t = __fpos_t;
pub extern var stdin: [*c]FILE;
pub extern var stdout: [*c]FILE;
pub extern var stderr: [*c]FILE;
pub extern fn remove(__filename: [*c]const u8) c_int;
pub extern fn rename(__old: [*c]const u8, __new: [*c]const u8) c_int;
pub extern fn renameat(__oldfd: c_int, __old: [*c]const u8, __newfd: c_int, __new: [*c]const u8) c_int;
pub extern fn fclose(__stream: [*c]FILE) c_int;
pub extern fn tmpfile() [*c]FILE;
pub extern fn tmpnam([*c]u8) [*c]u8;
pub extern fn tmpnam_r(__s: [*c]u8) [*c]u8;
pub extern fn tempnam(__dir: [*c]const u8, __pfx: [*c]const u8) [*c]u8;
pub extern fn fflush(__stream: [*c]FILE) c_int;
pub extern fn fflush_unlocked(__stream: [*c]FILE) c_int;
pub extern fn fopen(noalias __filename: [*c]const u8, noalias __modes: [*c]const u8) [*c]FILE;
pub extern fn freopen(noalias __filename: [*c]const u8, noalias __modes: [*c]const u8, noalias __stream: [*c]FILE) [*c]FILE;
pub extern fn fdopen(__fd: c_int, __modes: [*c]const u8) [*c]FILE;
pub extern fn fopencookie(noalias __magic_cookie: ?*anyopaque, noalias __modes: [*c]const u8, __io_funcs: cookie_io_functions_t) [*c]FILE;
pub extern fn fmemopen(__s: ?*anyopaque, __len: usize, __modes: [*c]const u8) [*c]FILE;
pub extern fn open_memstream(__bufloc: [*c][*c]u8, __sizeloc: [*c]usize) [*c]FILE;
pub extern fn setbuf(noalias __stream: [*c]FILE, noalias __buf: [*c]u8) void;
pub extern fn setvbuf(noalias __stream: [*c]FILE, noalias __buf: [*c]u8, __modes: c_int, __n: usize) c_int;
pub extern fn setbuffer(noalias __stream: [*c]FILE, noalias __buf: [*c]u8, __size: usize) void;
pub extern fn setlinebuf(__stream: [*c]FILE) void;
pub extern fn fprintf(noalias __stream: [*c]FILE, noalias __format: [*c]const u8, ...) c_int;
pub extern fn printf(noalias __format: [*c]const u8, ...) c_int;
pub extern fn sprintf(noalias __s: [*c]u8, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vfprintf(noalias __s: [*c]FILE, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn vprintf(noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn vsprintf(noalias __s: [*c]u8, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn snprintf(noalias __s: [*c]u8, __maxlen: usize, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vsnprintf(noalias __s: [*c]u8, __maxlen: usize, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn vasprintf(noalias __ptr: [*c][*c]u8, noalias __f: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn __asprintf(noalias __ptr: [*c][*c]u8, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn asprintf(noalias __ptr: [*c][*c]u8, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn vdprintf(__fd: c_int, noalias __fmt: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn dprintf(__fd: c_int, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn fscanf(noalias __stream: [*c]FILE, noalias __format: [*c]const u8, ...) c_int;
pub extern fn scanf(noalias __format: [*c]const u8, ...) c_int;
pub extern fn sscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vfscanf(noalias __s: [*c]FILE, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn vscanf(noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn vsscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, __arg: [*c]struct___va_list_tag_1) c_int;
pub extern fn fgetc(__stream: [*c]FILE) c_int;
pub extern fn getc(__stream: [*c]FILE) c_int;
pub extern fn getchar() c_int;
pub extern fn getc_unlocked(__stream: [*c]FILE) c_int;
pub extern fn getchar_unlocked() c_int;
pub extern fn fgetc_unlocked(__stream: [*c]FILE) c_int;
pub extern fn fputc(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn putc(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn putchar(__c: c_int) c_int;
pub extern fn fputc_unlocked(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn putc_unlocked(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn putchar_unlocked(__c: c_int) c_int;
pub extern fn getw(__stream: [*c]FILE) c_int;
pub extern fn putw(__w: c_int, __stream: [*c]FILE) c_int;
pub extern fn fgets(noalias __s: [*c]u8, __n: c_int, noalias __stream: [*c]FILE) [*c]u8;
pub extern fn __getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn getline(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, noalias __stream: [*c]FILE) __ssize_t;
pub extern fn fputs(noalias __s: [*c]const u8, noalias __stream: [*c]FILE) c_int;
pub extern fn puts(__s: [*c]const u8) c_int;
pub extern fn ungetc(__c: c_int, __stream: [*c]FILE) c_int;
pub extern fn fread(noalias __ptr: ?*anyopaque, __size: usize, __n: usize, noalias __stream: [*c]FILE) usize;
pub extern fn fwrite(noalias __ptr: ?*const anyopaque, __size: usize, __n: usize, noalias __s: [*c]FILE) usize;
pub extern fn fread_unlocked(noalias __ptr: ?*anyopaque, __size: usize, __n: usize, noalias __stream: [*c]FILE) usize;
pub extern fn fwrite_unlocked(noalias __ptr: ?*const anyopaque, __size: usize, __n: usize, noalias __stream: [*c]FILE) usize;
pub extern fn fseek(__stream: [*c]FILE, __off: c_long, __whence: c_int) c_int;
pub extern fn ftell(__stream: [*c]FILE) c_long;
pub extern fn rewind(__stream: [*c]FILE) void;
pub extern fn fseeko(__stream: [*c]FILE, __off: __off_t, __whence: c_int) c_int;
pub extern fn ftello(__stream: [*c]FILE) __off_t;
pub extern fn fgetpos(noalias __stream: [*c]FILE, noalias __pos: [*c]fpos_t) c_int;
pub extern fn fsetpos(__stream: [*c]FILE, __pos: [*c]const fpos_t) c_int;
pub extern fn clearerr(__stream: [*c]FILE) void;
pub extern fn feof(__stream: [*c]FILE) c_int;
pub extern fn ferror(__stream: [*c]FILE) c_int;
pub extern fn clearerr_unlocked(__stream: [*c]FILE) void;
pub extern fn feof_unlocked(__stream: [*c]FILE) c_int;
pub extern fn ferror_unlocked(__stream: [*c]FILE) c_int;
pub extern fn perror(__s: [*c]const u8) void;
pub extern fn fileno(__stream: [*c]FILE) c_int;
pub extern fn fileno_unlocked(__stream: [*c]FILE) c_int;
pub extern fn pclose(__stream: [*c]FILE) c_int;
pub extern fn popen(__command: [*c]const u8, __modes: [*c]const u8) [*c]FILE;
pub extern fn ctermid(__s: [*c]u8) [*c]u8;
pub extern fn flockfile(__stream: [*c]FILE) void;
pub extern fn ftrylockfile(__stream: [*c]FILE) c_int;
pub extern fn funlockfile(__stream: [*c]FILE) void;
pub extern fn __uflow([*c]FILE) c_int;
pub extern fn __overflow([*c]FILE, c_int) c_int;
pub const int_least8_t = __int_least8_t;
pub const int_least16_t = __int_least16_t;
pub const int_least32_t = __int_least32_t;
pub const int_least64_t = __int_least64_t;
pub const uint_least8_t = __uint_least8_t;
pub const uint_least16_t = __uint_least16_t;
pub const uint_least32_t = __uint_least32_t;
pub const uint_least64_t = __uint_least64_t;
pub const int_fast8_t = i8;
pub const int_fast16_t = c_long;
pub const int_fast32_t = c_long;
pub const int_fast64_t = c_long;
pub const uint_fast8_t = u8;
pub const uint_fast16_t = c_ulong;
pub const uint_fast32_t = c_ulong;
pub const uint_fast64_t = c_ulong;
pub const intmax_t = __intmax_t;
pub const uintmax_t = __uintmax_t;
pub const div_t = extern struct {
    quot: c_int = 0,
    rem: c_int = 0,
};
pub const ldiv_t = extern struct {
    quot: c_long = 0,
    rem: c_long = 0,
};
pub const lldiv_t = extern struct {
    quot: c_longlong = 0,
    rem: c_longlong = 0,
};
pub extern fn __ctype_get_mb_cur_max() usize;
pub extern fn atof(__nptr: [*c]const u8) f64;
pub extern fn atoi(__nptr: [*c]const u8) c_int;
pub extern fn atol(__nptr: [*c]const u8) c_long;
pub extern fn atoll(__nptr: [*c]const u8) c_longlong;
pub extern fn strtod(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f64;
pub extern fn strtof(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) f32;
pub extern fn strtold(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8) c_longdouble;
pub extern fn strtol(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_long;
pub extern fn strtoul(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulong;
pub extern fn strtoq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtouq(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn strtoll(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_longlong;
pub extern fn strtoull(noalias __nptr: [*c]const u8, noalias __endptr: [*c][*c]u8, __base: c_int) c_ulonglong;
pub extern fn l64a(__n: c_long) [*c]u8;
pub extern fn a64l(__s: [*c]const u8) c_long;
pub const u_char = __u_char;
pub const u_short = __u_short;
pub const u_int = __u_int;
pub const u_long = __u_long;
pub const quad_t = __quad_t;
pub const u_quad_t = __u_quad_t;
pub const fsid_t = __fsid_t;
pub const loff_t = __loff_t;
pub const ino_t = __ino_t;
pub const dev_t = __dev_t;
pub const gid_t = __gid_t;
pub const mode_t = __mode_t;
pub const nlink_t = __nlink_t;
pub const uid_t = __uid_t;
pub const pid_t = __pid_t;
pub const id_t = __id_t;
pub const daddr_t = __daddr_t;
pub const caddr_t = __caddr_t;
pub const key_t = __key_t;
pub const clock_t = __clock_t;
pub const clockid_t = __clockid_t;
pub const time_t = __time_t;
pub const timer_t = __timer_t;
pub const ulong = c_ulong;
pub const ushort = c_ushort;
pub const uint = c_uint;
pub const u_int8_t = __uint8_t;
pub const u_int16_t = __uint16_t;
pub const u_int32_t = __uint32_t;
pub const u_int64_t = __uint64_t;
pub const register_t = c_int;
pub fn __bswap_16(arg___bsx: __uint16_t) callconv(.c) __uint16_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @byteSwap(@as(__uint16_t, __bsx));
}
pub fn __bswap_32(arg___bsx: __uint32_t) callconv(.c) __uint32_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_int, @byteSwap(@as(c_int, @bitCast(@as(c_uint, @truncate(__bsx)))))));
}
pub fn __bswap_64(arg___bsx: __uint64_t) callconv(.c) __uint64_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @bitCast(@as(c_long, @byteSwap(@as(c_long, @bitCast(@as(c_ulong, @truncate(__bsx)))))));
}
pub fn __uint16_identity(arg___x: __uint16_t) callconv(.c) __uint16_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint32_identity(arg___x: __uint32_t) callconv(.c) __uint32_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint64_identity(arg___x: __uint64_t) callconv(.c) __uint64_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub const __sigset_t = extern struct {
    __val: [16]c_ulong = @import("std").mem.zeroes([16]c_ulong),
};
pub const sigset_t = __sigset_t;
pub const struct_timeval = extern struct {
    tv_sec: __time_t = 0,
    tv_usec: __suseconds_t = 0,
};
pub const struct_timespec = extern struct {
    tv_sec: __time_t = 0,
    tv_nsec: __syscall_slong_t = 0,
    pub const nanosleep = __root.nanosleep;
    pub const timespec_get = __root.timespec_get;
    pub const get = __root.timespec_get;
};
pub const suseconds_t = __suseconds_t;
pub const __fd_mask = c_long;
pub const fd_set = extern struct {
    __fds_bits: [16]__fd_mask = @import("std").mem.zeroes([16]__fd_mask),
};
pub const fd_mask = __fd_mask;
pub extern fn select(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]struct_timeval) c_int;
pub extern fn pselect(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]const struct_timespec, noalias __sigmask: [*c]const __sigset_t) c_int;
pub const blksize_t = __blksize_t;
pub const blkcnt_t = __blkcnt_t;
pub const fsblkcnt_t = __fsblkcnt_t;
pub const fsfilcnt_t = __fsfilcnt_t;
const struct_unnamed_3 = extern struct {
    __low: c_uint = 0,
    __high: c_uint = 0,
};
pub const __atomic_wide_counter = extern union {
    __value64: c_ulonglong,
    __value32: struct_unnamed_3,
};
pub const struct___pthread_internal_list = extern struct {
    __prev: [*c]struct___pthread_internal_list = null,
    __next: [*c]struct___pthread_internal_list = null,
};
pub const __pthread_list_t = struct___pthread_internal_list;
pub const struct___pthread_internal_slist = extern struct {
    __next: [*c]struct___pthread_internal_slist = null,
};
pub const __pthread_slist_t = struct___pthread_internal_slist;
pub const struct___pthread_mutex_s = extern struct {
    __lock: c_int = 0,
    __count: c_uint = 0,
    __owner: c_int = 0,
    __nusers: c_uint = 0,
    __kind: c_int = 0,
    __spins: c_short = 0,
    __elision: c_short = 0,
    __list: __pthread_list_t = @import("std").mem.zeroes(__pthread_list_t),
};
pub const struct___pthread_rwlock_arch_t = extern struct {
    __readers: c_uint = 0,
    __writers: c_uint = 0,
    __wrphase_futex: c_uint = 0,
    __writers_futex: c_uint = 0,
    __pad3: c_uint = 0,
    __pad4: c_uint = 0,
    __cur_writer: c_int = 0,
    __shared: c_int = 0,
    __rwelision: i8 = 0,
    __pad1: [7]u8 = @import("std").mem.zeroes([7]u8),
    __pad2: c_ulong = 0,
    __flags: c_uint = 0,
};
pub const struct___pthread_cond_s = extern struct {
    __wseq: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g1_start: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g_size: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __g1_orig_size: c_uint = 0,
    __wrefs: c_uint = 0,
    __g_signals: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __unused_initialized_1: c_uint = 0,
    __unused_initialized_2: c_uint = 0,
};
pub const __tss_t = c_uint;
pub const __thrd_t = c_ulong;
pub const __once_flag = extern struct {
    __data: c_int = 0,
};
pub const pthread_t = c_ulong;
pub const pthread_mutexattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_condattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub const pthread_key_t = c_uint;
pub const pthread_once_t = c_int;
pub const union_pthread_attr_t = extern union {
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_attr_t = union_pthread_attr_t;
pub const pthread_mutex_t = extern union {
    __data: struct___pthread_mutex_s,
    __size: [40]u8,
    __align: c_long,
};
pub const pthread_cond_t = extern union {
    __data: struct___pthread_cond_s,
    __size: [48]u8,
    __align: c_longlong,
};
pub const pthread_rwlock_t = extern union {
    __data: struct___pthread_rwlock_arch_t,
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_rwlockattr_t = extern union {
    __size: [8]u8,
    __align: c_long,
};
pub const pthread_spinlock_t = c_int;
pub const pthread_barrier_t = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const pthread_barrierattr_t = extern union {
    __size: [4]u8,
    __align: c_int,
};
pub extern fn random() c_long;
pub extern fn srandom(__seed: c_uint) void;
pub extern fn initstate(__seed: c_uint, __statebuf: [*c]u8, __statelen: usize) [*c]u8;
pub extern fn setstate(__statebuf: [*c]u8) [*c]u8;
pub const struct_random_data = extern struct {
    fptr: [*c]i32 = null,
    rptr: [*c]i32 = null,
    state: [*c]i32 = null,
    rand_type: c_int = 0,
    rand_deg: c_int = 0,
    rand_sep: c_int = 0,
    end_ptr: [*c]i32 = null,
    pub const random_r = __root.random_r;
    pub const r = __root.random_r;
};
pub extern fn random_r(noalias __buf: [*c]struct_random_data, noalias __result: [*c]i32) c_int;
pub extern fn srandom_r(__seed: c_uint, __buf: [*c]struct_random_data) c_int;
pub extern fn initstate_r(__seed: c_uint, noalias __statebuf: [*c]u8, __statelen: usize, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn setstate_r(noalias __statebuf: [*c]u8, noalias __buf: [*c]struct_random_data) c_int;
pub extern fn rand() c_int;
pub extern fn srand(__seed: c_uint) void;
pub extern fn rand_r(__seed: [*c]c_uint) c_int;
pub extern fn drand48() f64;
pub extern fn erand48(__xsubi: [*c]c_ushort) f64;
pub extern fn lrand48() c_long;
pub extern fn nrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn mrand48() c_long;
pub extern fn jrand48(__xsubi: [*c]c_ushort) c_long;
pub extern fn srand48(__seedval: c_long) void;
pub extern fn seed48(__seed16v: [*c]c_ushort) [*c]c_ushort;
pub extern fn lcong48(__param: [*c]c_ushort) void;
pub const struct_drand48_data = extern struct {
    __x: [3]c_ushort = @import("std").mem.zeroes([3]c_ushort),
    __old_x: [3]c_ushort = @import("std").mem.zeroes([3]c_ushort),
    __c: c_ushort = 0,
    __init: c_ushort = 0,
    __a: c_ulonglong = 0,
    pub const drand48_r = __root.drand48_r;
    pub const lrand48_r = __root.lrand48_r;
    pub const mrand48_r = __root.mrand48_r;
    pub const r = __root.drand48_r;
};
pub extern fn drand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn erand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]f64) c_int;
pub extern fn lrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn nrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn mrand48_r(noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn jrand48_r(__xsubi: [*c]c_ushort, noalias __buffer: [*c]struct_drand48_data, noalias __result: [*c]c_long) c_int;
pub extern fn srand48_r(__seedval: c_long, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn seed48_r(__seed16v: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn lcong48_r(__param: [*c]c_ushort, __buffer: [*c]struct_drand48_data) c_int;
pub extern fn arc4random() __uint32_t;
pub extern fn arc4random_buf(__buf: ?*anyopaque, __size: usize) void;
pub extern fn arc4random_uniform(__upper_bound: __uint32_t) __uint32_t;
pub extern fn malloc(__size: usize) ?*anyopaque;
pub extern fn calloc(__nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn realloc(__ptr: ?*anyopaque, __size: usize) ?*anyopaque;
pub extern fn free(__ptr: ?*anyopaque) void;
pub extern fn reallocarray(__ptr: ?*anyopaque, __nmemb: usize, __size: usize) ?*anyopaque;
pub extern fn alloca(__size: usize) ?*anyopaque;
pub extern fn valloc(__size: usize) ?*anyopaque;
pub extern fn posix_memalign(__memptr: [*c]?*anyopaque, __alignment: usize, __size: usize) c_int;
pub extern fn aligned_alloc(__alignment: usize, __size: usize) ?*anyopaque;
pub extern fn abort() noreturn;
pub extern fn atexit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn at_quick_exit(__func: ?*const fn () callconv(.c) void) c_int;
pub extern fn on_exit(__func: ?*const fn (__status: c_int, __arg: ?*anyopaque) callconv(.c) void, __arg: ?*anyopaque) c_int;
pub extern fn exit(__status: c_int) noreturn;
pub extern fn quick_exit(__status: c_int) noreturn;
pub extern fn _Exit(__status: c_int) noreturn;
pub extern fn getenv(__name: [*c]const u8) [*c]u8;
pub extern fn putenv(__string: [*c]u8) c_int;
pub extern fn setenv(__name: [*c]const u8, __value: [*c]const u8, __replace: c_int) c_int;
pub extern fn unsetenv(__name: [*c]const u8) c_int;
pub extern fn clearenv() c_int;
pub extern fn mktemp(__template: [*c]u8) [*c]u8;
pub extern fn mkstemp(__template: [*c]u8) c_int;
pub extern fn mkstemps(__template: [*c]u8, __suffixlen: c_int) c_int;
pub extern fn mkdtemp(__template: [*c]u8) [*c]u8;
pub extern fn system(__command: [*c]const u8) c_int;
pub extern fn realpath(noalias __name: [*c]const u8, noalias __resolved: [*c]u8) [*c]u8;
pub const __compar_fn_t = ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;
pub extern fn bsearch(__key: ?*const anyopaque, __base: ?*const anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) ?*anyopaque;
pub extern fn qsort(__base: ?*anyopaque, __nmemb: usize, __size: usize, __compar: __compar_fn_t) void;
pub extern fn abs(__x: c_int) c_int;
pub extern fn labs(__x: c_long) c_long;
pub extern fn llabs(__x: c_longlong) c_longlong;
pub extern fn div(__numer: c_int, __denom: c_int) div_t;
pub extern fn ldiv(__numer: c_long, __denom: c_long) ldiv_t;
pub extern fn lldiv(__numer: c_longlong, __denom: c_longlong) lldiv_t;
pub extern fn ecvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn fcvt(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn gcvt(__value: f64, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn qecvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qfcvt(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int) [*c]u8;
pub extern fn qgcvt(__value: c_longdouble, __ndigit: c_int, __buf: [*c]u8) [*c]u8;
pub extern fn ecvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn fcvt_r(__value: f64, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qecvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn qfcvt_r(__value: c_longdouble, __ndigit: c_int, noalias __decpt: [*c]c_int, noalias __sign: [*c]c_int, noalias __buf: [*c]u8, __len: usize) c_int;
pub extern fn mblen(__s: [*c]const u8, __n: usize) c_int;
pub extern fn mbtowc(noalias __pwc: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) c_int;
pub extern fn wctomb(__s: [*c]u8, __wchar: wchar_t) c_int;
pub extern fn mbstowcs(noalias __pwcs: [*c]wchar_t, noalias __s: [*c]const u8, __n: usize) usize;
pub extern fn wcstombs(noalias __s: [*c]u8, noalias __pwcs: [*c]const wchar_t, __n: usize) usize;
pub extern fn rpmatch(__response: [*c]const u8) c_int;
pub extern fn getsubopt(noalias __optionp: [*c][*c]u8, noalias __tokens: [*c]const [*c]u8, noalias __valuep: [*c][*c]u8) c_int;
pub extern fn getloadavg(__loadavg: [*c]f64, __nelem: c_int) c_int;
pub extern fn memcpy(noalias __dest: ?*anyopaque, noalias __src: ?*const anyopaque, __n: usize) ?*anyopaque;
pub extern fn memmove(__dest: ?*anyopaque, __src: ?*const anyopaque, __n: usize) ?*anyopaque;
pub extern fn memccpy(noalias __dest: ?*anyopaque, noalias __src: ?*const anyopaque, __c: c_int, __n: usize) ?*anyopaque;
pub extern fn memset(__s: ?*anyopaque, __c: c_int, __n: usize) ?*anyopaque;
pub extern fn memcmp(__s1: ?*const anyopaque, __s2: ?*const anyopaque, __n: usize) c_int;
pub extern fn __memcmpeq(__s1: ?*const anyopaque, __s2: ?*const anyopaque, __n: usize) c_int;
pub extern fn memchr(__s: ?*const anyopaque, __c: c_int, __n: usize) ?*anyopaque;
pub extern fn strcpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8) [*c]u8;
pub extern fn strncpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) [*c]u8;
pub extern fn strcat(noalias __dest: [*c]u8, noalias __src: [*c]const u8) [*c]u8;
pub extern fn strncat(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) [*c]u8;
pub extern fn strcmp(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strncmp(__s1: [*c]const u8, __s2: [*c]const u8, __n: usize) c_int;
pub extern fn strcoll(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strxfrm(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) usize;
pub const struct___locale_data_4 = opaque {};
pub const struct___locale_struct = extern struct {
    __locales: [13]?*struct___locale_data_4 = @import("std").mem.zeroes([13]?*struct___locale_data_4),
    __ctype_b: [*c]const c_ushort = null,
    __ctype_tolower: [*c]const c_int = null,
    __ctype_toupper: [*c]const c_int = null,
    __names: [13][*c]const u8 = @import("std").mem.zeroes([13][*c]const u8),
};
pub const __locale_t = [*c]struct___locale_struct;
pub const locale_t = __locale_t;
pub extern fn strcoll_l(__s1: [*c]const u8, __s2: [*c]const u8, __l: locale_t) c_int;
pub extern fn strxfrm_l(__dest: [*c]u8, __src: [*c]const u8, __n: usize, __l: locale_t) usize;
pub extern fn strdup(__s: [*c]const u8) [*c]u8;
pub extern fn strndup(__string: [*c]const u8, __n: usize) [*c]u8;
pub extern fn strchr(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn strrchr(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn strchrnul(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn strcspn(__s: [*c]const u8, __reject: [*c]const u8) usize;
pub extern fn strspn(__s: [*c]const u8, __accept: [*c]const u8) usize;
pub extern fn strpbrk(__s: [*c]const u8, __accept: [*c]const u8) [*c]u8;
pub extern fn strstr(__haystack: [*c]const u8, __needle: [*c]const u8) [*c]u8;
pub extern fn strtok(noalias __s: [*c]u8, noalias __delim: [*c]const u8) [*c]u8;
pub extern fn __strtok_r(noalias __s: [*c]u8, noalias __delim: [*c]const u8, noalias __save_ptr: [*c][*c]u8) [*c]u8;
pub extern fn strtok_r(noalias __s: [*c]u8, noalias __delim: [*c]const u8, noalias __save_ptr: [*c][*c]u8) [*c]u8;
pub extern fn strcasestr(__haystack: [*c]const u8, __needle: [*c]const u8) [*c]u8;
pub extern fn memmem(__haystack: ?*const anyopaque, __haystacklen: usize, __needle: ?*const anyopaque, __needlelen: usize) ?*anyopaque;
pub extern fn __mempcpy(noalias __dest: ?*anyopaque, noalias __src: ?*const anyopaque, __n: usize) ?*anyopaque;
pub extern fn mempcpy(noalias __dest: ?*anyopaque, noalias __src: ?*const anyopaque, __n: usize) ?*anyopaque;
pub extern fn strlen(__s: [*c]const u8) usize;
pub extern fn strnlen(__string: [*c]const u8, __maxlen: usize) usize;
pub extern fn strerror(__errnum: c_int) [*c]u8;
pub extern fn strerror_r(__errnum: c_int, __buf: [*c]u8, __buflen: usize) c_int;
pub extern fn strerror_l(__errnum: c_int, __l: locale_t) [*c]u8;
pub extern fn bcmp(__s1: ?*const anyopaque, __s2: ?*const anyopaque, __n: usize) c_int;
pub extern fn bcopy(__src: ?*const anyopaque, __dest: ?*anyopaque, __n: usize) void;
pub extern fn bzero(__s: ?*anyopaque, __n: usize) void;
pub extern fn index(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn rindex(__s: [*c]const u8, __c: c_int) [*c]u8;
pub extern fn ffs(__i: c_int) c_int;
pub extern fn ffsl(__l: c_long) c_int;
pub extern fn ffsll(__ll: c_longlong) c_int;
pub extern fn strcasecmp(__s1: [*c]const u8, __s2: [*c]const u8) c_int;
pub extern fn strncasecmp(__s1: [*c]const u8, __s2: [*c]const u8, __n: usize) c_int;
pub extern fn strcasecmp_l(__s1: [*c]const u8, __s2: [*c]const u8, __loc: locale_t) c_int;
pub extern fn strncasecmp_l(__s1: [*c]const u8, __s2: [*c]const u8, __n: usize, __loc: locale_t) c_int;
pub extern fn explicit_bzero(__s: ?*anyopaque, __n: usize) void;
pub extern fn strsep(noalias __stringp: [*c][*c]u8, noalias __delim: [*c]const u8) [*c]u8;
pub extern fn strsignal(__sig: c_int) [*c]u8;
pub extern fn __stpcpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8) [*c]u8;
pub extern fn stpcpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8) [*c]u8;
pub extern fn __stpncpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) [*c]u8;
pub extern fn stpncpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) [*c]u8;
pub extern fn strlcpy(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) usize;
pub extern fn strlcat(noalias __dest: [*c]u8, noalias __src: [*c]const u8, __n: usize) usize;
pub extern fn __errno_location() [*c]c_int;
pub const useconds_t = __useconds_t;
pub const socklen_t = __socklen_t;
pub extern fn access(__name: [*c]const u8, __type: c_int) c_int;
pub extern fn faccessat(__fd: c_int, __file: [*c]const u8, __type: c_int, __flag: c_int) c_int;
pub extern fn lseek(__fd: c_int, __offset: __off_t, __whence: c_int) __off_t;
pub extern fn close(__fd: c_int) c_int;
pub extern fn closefrom(__lowfd: c_int) void;
pub extern fn read(__fd: c_int, __buf: ?*anyopaque, __nbytes: usize) isize;
pub extern fn write(__fd: c_int, __buf: ?*const anyopaque, __n: usize) isize;
pub extern fn pread(__fd: c_int, __buf: ?*anyopaque, __nbytes: usize, __offset: __off_t) isize;
pub extern fn pwrite(__fd: c_int, __buf: ?*const anyopaque, __n: usize, __offset: __off_t) isize;
pub extern fn pipe(__pipedes: [*c]c_int) c_int;
pub extern fn alarm(__seconds: c_uint) c_uint;
pub extern fn sleep(__seconds: c_uint) c_uint;
pub extern fn ualarm(__value: __useconds_t, __interval: __useconds_t) __useconds_t;
pub extern fn usleep(__useconds: __useconds_t) c_int;
pub extern fn pause() c_int;
pub extern fn chown(__file: [*c]const u8, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn fchown(__fd: c_int, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn lchown(__file: [*c]const u8, __owner: __uid_t, __group: __gid_t) c_int;
pub extern fn fchownat(__fd: c_int, __file: [*c]const u8, __owner: __uid_t, __group: __gid_t, __flag: c_int) c_int;
pub extern fn chdir(__path: [*c]const u8) c_int;
pub extern fn fchdir(__fd: c_int) c_int;
pub extern fn getcwd(__buf: [*c]u8, __size: usize) [*c]u8;
pub extern fn getwd(__buf: [*c]u8) [*c]u8;
pub extern fn dup(__fd: c_int) c_int;
pub extern fn dup2(__fd: c_int, __fd2: c_int) c_int;
pub extern var __environ: [*c][*c]u8;
pub extern fn execve(__path: [*c]const u8, __argv: [*c]const [*c]u8, __envp: [*c]const [*c]u8) c_int;
pub extern fn fexecve(__fd: c_int, __argv: [*c]const [*c]u8, __envp: [*c]const [*c]u8) c_int;
pub extern fn execv(__path: [*c]const u8, __argv: [*c]const [*c]u8) c_int;
pub extern fn execle(__path: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn execl(__path: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn execvp(__file: [*c]const u8, __argv: [*c]const [*c]u8) c_int;
pub extern fn execlp(__file: [*c]const u8, __arg: [*c]const u8, ...) c_int;
pub extern fn nice(__inc: c_int) c_int;
pub extern fn _exit(__status: c_int) noreturn;
pub const _PC_LINK_MAX: c_int = 0;
pub const _PC_MAX_CANON: c_int = 1;
pub const _PC_MAX_INPUT: c_int = 2;
pub const _PC_NAME_MAX: c_int = 3;
pub const _PC_PATH_MAX: c_int = 4;
pub const _PC_PIPE_BUF: c_int = 5;
pub const _PC_CHOWN_RESTRICTED: c_int = 6;
pub const _PC_NO_TRUNC: c_int = 7;
pub const _PC_VDISABLE: c_int = 8;
pub const _PC_SYNC_IO: c_int = 9;
pub const _PC_ASYNC_IO: c_int = 10;
pub const _PC_PRIO_IO: c_int = 11;
pub const _PC_SOCK_MAXBUF: c_int = 12;
pub const _PC_FILESIZEBITS: c_int = 13;
pub const _PC_REC_INCR_XFER_SIZE: c_int = 14;
pub const _PC_REC_MAX_XFER_SIZE: c_int = 15;
pub const _PC_REC_MIN_XFER_SIZE: c_int = 16;
pub const _PC_REC_XFER_ALIGN: c_int = 17;
pub const _PC_ALLOC_SIZE_MIN: c_int = 18;
pub const _PC_SYMLINK_MAX: c_int = 19;
pub const _PC_2_SYMLINKS: c_int = 20;
const enum_unnamed_5 = c_uint;
pub const _SC_ARG_MAX: c_int = 0;
pub const _SC_CHILD_MAX: c_int = 1;
pub const _SC_CLK_TCK: c_int = 2;
pub const _SC_NGROUPS_MAX: c_int = 3;
pub const _SC_OPEN_MAX: c_int = 4;
pub const _SC_STREAM_MAX: c_int = 5;
pub const _SC_TZNAME_MAX: c_int = 6;
pub const _SC_JOB_CONTROL: c_int = 7;
pub const _SC_SAVED_IDS: c_int = 8;
pub const _SC_REALTIME_SIGNALS: c_int = 9;
pub const _SC_PRIORITY_SCHEDULING: c_int = 10;
pub const _SC_TIMERS: c_int = 11;
pub const _SC_ASYNCHRONOUS_IO: c_int = 12;
pub const _SC_PRIORITIZED_IO: c_int = 13;
pub const _SC_SYNCHRONIZED_IO: c_int = 14;
pub const _SC_FSYNC: c_int = 15;
pub const _SC_MAPPED_FILES: c_int = 16;
pub const _SC_MEMLOCK: c_int = 17;
pub const _SC_MEMLOCK_RANGE: c_int = 18;
pub const _SC_MEMORY_PROTECTION: c_int = 19;
pub const _SC_MESSAGE_PASSING: c_int = 20;
pub const _SC_SEMAPHORES: c_int = 21;
pub const _SC_SHARED_MEMORY_OBJECTS: c_int = 22;
pub const _SC_AIO_LISTIO_MAX: c_int = 23;
pub const _SC_AIO_MAX: c_int = 24;
pub const _SC_AIO_PRIO_DELTA_MAX: c_int = 25;
pub const _SC_DELAYTIMER_MAX: c_int = 26;
pub const _SC_MQ_OPEN_MAX: c_int = 27;
pub const _SC_MQ_PRIO_MAX: c_int = 28;
pub const _SC_VERSION: c_int = 29;
pub const _SC_PAGESIZE: c_int = 30;
pub const _SC_RTSIG_MAX: c_int = 31;
pub const _SC_SEM_NSEMS_MAX: c_int = 32;
pub const _SC_SEM_VALUE_MAX: c_int = 33;
pub const _SC_SIGQUEUE_MAX: c_int = 34;
pub const _SC_TIMER_MAX: c_int = 35;
pub const _SC_BC_BASE_MAX: c_int = 36;
pub const _SC_BC_DIM_MAX: c_int = 37;
pub const _SC_BC_SCALE_MAX: c_int = 38;
pub const _SC_BC_STRING_MAX: c_int = 39;
pub const _SC_COLL_WEIGHTS_MAX: c_int = 40;
pub const _SC_EQUIV_CLASS_MAX: c_int = 41;
pub const _SC_EXPR_NEST_MAX: c_int = 42;
pub const _SC_LINE_MAX: c_int = 43;
pub const _SC_RE_DUP_MAX: c_int = 44;
pub const _SC_CHARCLASS_NAME_MAX: c_int = 45;
pub const _SC_2_VERSION: c_int = 46;
pub const _SC_2_C_BIND: c_int = 47;
pub const _SC_2_C_DEV: c_int = 48;
pub const _SC_2_FORT_DEV: c_int = 49;
pub const _SC_2_FORT_RUN: c_int = 50;
pub const _SC_2_SW_DEV: c_int = 51;
pub const _SC_2_LOCALEDEF: c_int = 52;
pub const _SC_PII: c_int = 53;
pub const _SC_PII_XTI: c_int = 54;
pub const _SC_PII_SOCKET: c_int = 55;
pub const _SC_PII_INTERNET: c_int = 56;
pub const _SC_PII_OSI: c_int = 57;
pub const _SC_POLL: c_int = 58;
pub const _SC_SELECT: c_int = 59;
pub const _SC_UIO_MAXIOV: c_int = 60;
pub const _SC_IOV_MAX: c_int = 60;
pub const _SC_PII_INTERNET_STREAM: c_int = 61;
pub const _SC_PII_INTERNET_DGRAM: c_int = 62;
pub const _SC_PII_OSI_COTS: c_int = 63;
pub const _SC_PII_OSI_CLTS: c_int = 64;
pub const _SC_PII_OSI_M: c_int = 65;
pub const _SC_T_IOV_MAX: c_int = 66;
pub const _SC_THREADS: c_int = 67;
pub const _SC_THREAD_SAFE_FUNCTIONS: c_int = 68;
pub const _SC_GETGR_R_SIZE_MAX: c_int = 69;
pub const _SC_GETPW_R_SIZE_MAX: c_int = 70;
pub const _SC_LOGIN_NAME_MAX: c_int = 71;
pub const _SC_TTY_NAME_MAX: c_int = 72;
pub const _SC_THREAD_DESTRUCTOR_ITERATIONS: c_int = 73;
pub const _SC_THREAD_KEYS_MAX: c_int = 74;
pub const _SC_THREAD_STACK_MIN: c_int = 75;
pub const _SC_THREAD_THREADS_MAX: c_int = 76;
pub const _SC_THREAD_ATTR_STACKADDR: c_int = 77;
pub const _SC_THREAD_ATTR_STACKSIZE: c_int = 78;
pub const _SC_THREAD_PRIORITY_SCHEDULING: c_int = 79;
pub const _SC_THREAD_PRIO_INHERIT: c_int = 80;
pub const _SC_THREAD_PRIO_PROTECT: c_int = 81;
pub const _SC_THREAD_PROCESS_SHARED: c_int = 82;
pub const _SC_NPROCESSORS_CONF: c_int = 83;
pub const _SC_NPROCESSORS_ONLN: c_int = 84;
pub const _SC_PHYS_PAGES: c_int = 85;
pub const _SC_AVPHYS_PAGES: c_int = 86;
pub const _SC_ATEXIT_MAX: c_int = 87;
pub const _SC_PASS_MAX: c_int = 88;
pub const _SC_XOPEN_VERSION: c_int = 89;
pub const _SC_XOPEN_XCU_VERSION: c_int = 90;
pub const _SC_XOPEN_UNIX: c_int = 91;
pub const _SC_XOPEN_CRYPT: c_int = 92;
pub const _SC_XOPEN_ENH_I18N: c_int = 93;
pub const _SC_XOPEN_SHM: c_int = 94;
pub const _SC_2_CHAR_TERM: c_int = 95;
pub const _SC_2_C_VERSION: c_int = 96;
pub const _SC_2_UPE: c_int = 97;
pub const _SC_XOPEN_XPG2: c_int = 98;
pub const _SC_XOPEN_XPG3: c_int = 99;
pub const _SC_XOPEN_XPG4: c_int = 100;
pub const _SC_CHAR_BIT: c_int = 101;
pub const _SC_CHAR_MAX: c_int = 102;
pub const _SC_CHAR_MIN: c_int = 103;
pub const _SC_INT_MAX: c_int = 104;
pub const _SC_INT_MIN: c_int = 105;
pub const _SC_LONG_BIT: c_int = 106;
pub const _SC_WORD_BIT: c_int = 107;
pub const _SC_MB_LEN_MAX: c_int = 108;
pub const _SC_NZERO: c_int = 109;
pub const _SC_SSIZE_MAX: c_int = 110;
pub const _SC_SCHAR_MAX: c_int = 111;
pub const _SC_SCHAR_MIN: c_int = 112;
pub const _SC_SHRT_MAX: c_int = 113;
pub const _SC_SHRT_MIN: c_int = 114;
pub const _SC_UCHAR_MAX: c_int = 115;
pub const _SC_UINT_MAX: c_int = 116;
pub const _SC_ULONG_MAX: c_int = 117;
pub const _SC_USHRT_MAX: c_int = 118;
pub const _SC_NL_ARGMAX: c_int = 119;
pub const _SC_NL_LANGMAX: c_int = 120;
pub const _SC_NL_MSGMAX: c_int = 121;
pub const _SC_NL_NMAX: c_int = 122;
pub const _SC_NL_SETMAX: c_int = 123;
pub const _SC_NL_TEXTMAX: c_int = 124;
pub const _SC_XBS5_ILP32_OFF32: c_int = 125;
pub const _SC_XBS5_ILP32_OFFBIG: c_int = 126;
pub const _SC_XBS5_LP64_OFF64: c_int = 127;
pub const _SC_XBS5_LPBIG_OFFBIG: c_int = 128;
pub const _SC_XOPEN_LEGACY: c_int = 129;
pub const _SC_XOPEN_REALTIME: c_int = 130;
pub const _SC_XOPEN_REALTIME_THREADS: c_int = 131;
pub const _SC_ADVISORY_INFO: c_int = 132;
pub const _SC_BARRIERS: c_int = 133;
pub const _SC_BASE: c_int = 134;
pub const _SC_C_LANG_SUPPORT: c_int = 135;
pub const _SC_C_LANG_SUPPORT_R: c_int = 136;
pub const _SC_CLOCK_SELECTION: c_int = 137;
pub const _SC_CPUTIME: c_int = 138;
pub const _SC_THREAD_CPUTIME: c_int = 139;
pub const _SC_DEVICE_IO: c_int = 140;
pub const _SC_DEVICE_SPECIFIC: c_int = 141;
pub const _SC_DEVICE_SPECIFIC_R: c_int = 142;
pub const _SC_FD_MGMT: c_int = 143;
pub const _SC_FIFO: c_int = 144;
pub const _SC_PIPE: c_int = 145;
pub const _SC_FILE_ATTRIBUTES: c_int = 146;
pub const _SC_FILE_LOCKING: c_int = 147;
pub const _SC_FILE_SYSTEM: c_int = 148;
pub const _SC_MONOTONIC_CLOCK: c_int = 149;
pub const _SC_MULTI_PROCESS: c_int = 150;
pub const _SC_SINGLE_PROCESS: c_int = 151;
pub const _SC_NETWORKING: c_int = 152;
pub const _SC_READER_WRITER_LOCKS: c_int = 153;
pub const _SC_SPIN_LOCKS: c_int = 154;
pub const _SC_REGEXP: c_int = 155;
pub const _SC_REGEX_VERSION: c_int = 156;
pub const _SC_SHELL: c_int = 157;
pub const _SC_SIGNALS: c_int = 158;
pub const _SC_SPAWN: c_int = 159;
pub const _SC_SPORADIC_SERVER: c_int = 160;
pub const _SC_THREAD_SPORADIC_SERVER: c_int = 161;
pub const _SC_SYSTEM_DATABASE: c_int = 162;
pub const _SC_SYSTEM_DATABASE_R: c_int = 163;
pub const _SC_TIMEOUTS: c_int = 164;
pub const _SC_TYPED_MEMORY_OBJECTS: c_int = 165;
pub const _SC_USER_GROUPS: c_int = 166;
pub const _SC_USER_GROUPS_R: c_int = 167;
pub const _SC_2_PBS: c_int = 168;
pub const _SC_2_PBS_ACCOUNTING: c_int = 169;
pub const _SC_2_PBS_LOCATE: c_int = 170;
pub const _SC_2_PBS_MESSAGE: c_int = 171;
pub const _SC_2_PBS_TRACK: c_int = 172;
pub const _SC_SYMLOOP_MAX: c_int = 173;
pub const _SC_STREAMS: c_int = 174;
pub const _SC_2_PBS_CHECKPOINT: c_int = 175;
pub const _SC_V6_ILP32_OFF32: c_int = 176;
pub const _SC_V6_ILP32_OFFBIG: c_int = 177;
pub const _SC_V6_LP64_OFF64: c_int = 178;
pub const _SC_V6_LPBIG_OFFBIG: c_int = 179;
pub const _SC_HOST_NAME_MAX: c_int = 180;
pub const _SC_TRACE: c_int = 181;
pub const _SC_TRACE_EVENT_FILTER: c_int = 182;
pub const _SC_TRACE_INHERIT: c_int = 183;
pub const _SC_TRACE_LOG: c_int = 184;
pub const _SC_LEVEL1_ICACHE_SIZE: c_int = 185;
pub const _SC_LEVEL1_ICACHE_ASSOC: c_int = 186;
pub const _SC_LEVEL1_ICACHE_LINESIZE: c_int = 187;
pub const _SC_LEVEL1_DCACHE_SIZE: c_int = 188;
pub const _SC_LEVEL1_DCACHE_ASSOC: c_int = 189;
pub const _SC_LEVEL1_DCACHE_LINESIZE: c_int = 190;
pub const _SC_LEVEL2_CACHE_SIZE: c_int = 191;
pub const _SC_LEVEL2_CACHE_ASSOC: c_int = 192;
pub const _SC_LEVEL2_CACHE_LINESIZE: c_int = 193;
pub const _SC_LEVEL3_CACHE_SIZE: c_int = 194;
pub const _SC_LEVEL3_CACHE_ASSOC: c_int = 195;
pub const _SC_LEVEL3_CACHE_LINESIZE: c_int = 196;
pub const _SC_LEVEL4_CACHE_SIZE: c_int = 197;
pub const _SC_LEVEL4_CACHE_ASSOC: c_int = 198;
pub const _SC_LEVEL4_CACHE_LINESIZE: c_int = 199;
pub const _SC_IPV6: c_int = 235;
pub const _SC_RAW_SOCKETS: c_int = 236;
pub const _SC_V7_ILP32_OFF32: c_int = 237;
pub const _SC_V7_ILP32_OFFBIG: c_int = 238;
pub const _SC_V7_LP64_OFF64: c_int = 239;
pub const _SC_V7_LPBIG_OFFBIG: c_int = 240;
pub const _SC_SS_REPL_MAX: c_int = 241;
pub const _SC_TRACE_EVENT_NAME_MAX: c_int = 242;
pub const _SC_TRACE_NAME_MAX: c_int = 243;
pub const _SC_TRACE_SYS_MAX: c_int = 244;
pub const _SC_TRACE_USER_EVENT_MAX: c_int = 245;
pub const _SC_XOPEN_STREAMS: c_int = 246;
pub const _SC_THREAD_ROBUST_PRIO_INHERIT: c_int = 247;
pub const _SC_THREAD_ROBUST_PRIO_PROTECT: c_int = 248;
pub const _SC_MINSIGSTKSZ: c_int = 249;
pub const _SC_SIGSTKSZ: c_int = 250;
const enum_unnamed_6 = c_uint;
pub const _CS_PATH: c_int = 0;
pub const _CS_V6_WIDTH_RESTRICTED_ENVS: c_int = 1;
pub const _CS_GNU_LIBC_VERSION: c_int = 2;
pub const _CS_GNU_LIBPTHREAD_VERSION: c_int = 3;
pub const _CS_V5_WIDTH_RESTRICTED_ENVS: c_int = 4;
pub const _CS_V7_WIDTH_RESTRICTED_ENVS: c_int = 5;
pub const _CS_LFS_CFLAGS: c_int = 1000;
pub const _CS_LFS_LDFLAGS: c_int = 1001;
pub const _CS_LFS_LIBS: c_int = 1002;
pub const _CS_LFS_LINTFLAGS: c_int = 1003;
pub const _CS_LFS64_CFLAGS: c_int = 1004;
pub const _CS_LFS64_LDFLAGS: c_int = 1005;
pub const _CS_LFS64_LIBS: c_int = 1006;
pub const _CS_LFS64_LINTFLAGS: c_int = 1007;
pub const _CS_XBS5_ILP32_OFF32_CFLAGS: c_int = 1100;
pub const _CS_XBS5_ILP32_OFF32_LDFLAGS: c_int = 1101;
pub const _CS_XBS5_ILP32_OFF32_LIBS: c_int = 1102;
pub const _CS_XBS5_ILP32_OFF32_LINTFLAGS: c_int = 1103;
pub const _CS_XBS5_ILP32_OFFBIG_CFLAGS: c_int = 1104;
pub const _CS_XBS5_ILP32_OFFBIG_LDFLAGS: c_int = 1105;
pub const _CS_XBS5_ILP32_OFFBIG_LIBS: c_int = 1106;
pub const _CS_XBS5_ILP32_OFFBIG_LINTFLAGS: c_int = 1107;
pub const _CS_XBS5_LP64_OFF64_CFLAGS: c_int = 1108;
pub const _CS_XBS5_LP64_OFF64_LDFLAGS: c_int = 1109;
pub const _CS_XBS5_LP64_OFF64_LIBS: c_int = 1110;
pub const _CS_XBS5_LP64_OFF64_LINTFLAGS: c_int = 1111;
pub const _CS_XBS5_LPBIG_OFFBIG_CFLAGS: c_int = 1112;
pub const _CS_XBS5_LPBIG_OFFBIG_LDFLAGS: c_int = 1113;
pub const _CS_XBS5_LPBIG_OFFBIG_LIBS: c_int = 1114;
pub const _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS: c_int = 1115;
pub const _CS_POSIX_V6_ILP32_OFF32_CFLAGS: c_int = 1116;
pub const _CS_POSIX_V6_ILP32_OFF32_LDFLAGS: c_int = 1117;
pub const _CS_POSIX_V6_ILP32_OFF32_LIBS: c_int = 1118;
pub const _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS: c_int = 1119;
pub const _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS: c_int = 1120;
pub const _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS: c_int = 1121;
pub const _CS_POSIX_V6_ILP32_OFFBIG_LIBS: c_int = 1122;
pub const _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS: c_int = 1123;
pub const _CS_POSIX_V6_LP64_OFF64_CFLAGS: c_int = 1124;
pub const _CS_POSIX_V6_LP64_OFF64_LDFLAGS: c_int = 1125;
pub const _CS_POSIX_V6_LP64_OFF64_LIBS: c_int = 1126;
pub const _CS_POSIX_V6_LP64_OFF64_LINTFLAGS: c_int = 1127;
pub const _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS: c_int = 1128;
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS: c_int = 1129;
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LIBS: c_int = 1130;
pub const _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS: c_int = 1131;
pub const _CS_POSIX_V7_ILP32_OFF32_CFLAGS: c_int = 1132;
pub const _CS_POSIX_V7_ILP32_OFF32_LDFLAGS: c_int = 1133;
pub const _CS_POSIX_V7_ILP32_OFF32_LIBS: c_int = 1134;
pub const _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS: c_int = 1135;
pub const _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS: c_int = 1136;
pub const _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS: c_int = 1137;
pub const _CS_POSIX_V7_ILP32_OFFBIG_LIBS: c_int = 1138;
pub const _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS: c_int = 1139;
pub const _CS_POSIX_V7_LP64_OFF64_CFLAGS: c_int = 1140;
pub const _CS_POSIX_V7_LP64_OFF64_LDFLAGS: c_int = 1141;
pub const _CS_POSIX_V7_LP64_OFF64_LIBS: c_int = 1142;
pub const _CS_POSIX_V7_LP64_OFF64_LINTFLAGS: c_int = 1143;
pub const _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS: c_int = 1144;
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS: c_int = 1145;
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LIBS: c_int = 1146;
pub const _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS: c_int = 1147;
pub const _CS_V6_ENV: c_int = 1148;
pub const _CS_V7_ENV: c_int = 1149;
const enum_unnamed_7 = c_uint;
pub extern fn pathconf(__path: [*c]const u8, __name: c_int) c_long;
pub extern fn fpathconf(__fd: c_int, __name: c_int) c_long;
pub extern fn sysconf(__name: c_int) c_long;
pub extern fn confstr(__name: c_int, __buf: [*c]u8, __len: usize) usize;
pub extern fn getpid() __pid_t;
pub extern fn getppid() __pid_t;
pub extern fn getpgrp() __pid_t;
pub extern fn __getpgid(__pid: __pid_t) __pid_t;
pub extern fn getpgid(__pid: __pid_t) __pid_t;
pub extern fn setpgid(__pid: __pid_t, __pgid: __pid_t) c_int;
pub extern fn setpgrp() c_int;
pub extern fn setsid() __pid_t;
pub extern fn getsid(__pid: __pid_t) __pid_t;
pub extern fn getuid() __uid_t;
pub extern fn geteuid() __uid_t;
pub extern fn getgid() __gid_t;
pub extern fn getegid() __gid_t;
pub extern fn getgroups(__size: c_int, __list: [*c]__gid_t) c_int;
pub extern fn setuid(__uid: __uid_t) c_int;
pub extern fn setreuid(__ruid: __uid_t, __euid: __uid_t) c_int;
pub extern fn seteuid(__uid: __uid_t) c_int;
pub extern fn setgid(__gid: __gid_t) c_int;
pub extern fn setregid(__rgid: __gid_t, __egid: __gid_t) c_int;
pub extern fn setegid(__gid: __gid_t) c_int;
pub extern fn fork() __pid_t;
pub extern fn vfork() __pid_t;
pub extern fn ttyname(__fd: c_int) [*c]u8;
pub extern fn ttyname_r(__fd: c_int, __buf: [*c]u8, __buflen: usize) c_int;
pub extern fn isatty(__fd: c_int) c_int;
pub extern fn ttyslot() c_int;
pub extern fn link(__from: [*c]const u8, __to: [*c]const u8) c_int;
pub extern fn linkat(__fromfd: c_int, __from: [*c]const u8, __tofd: c_int, __to: [*c]const u8, __flags: c_int) c_int;
pub extern fn symlink(__from: [*c]const u8, __to: [*c]const u8) c_int;
pub extern fn readlink(noalias __path: [*c]const u8, noalias __buf: [*c]u8, __len: usize) isize;
pub extern fn symlinkat(__from: [*c]const u8, __tofd: c_int, __to: [*c]const u8) c_int;
pub extern fn readlinkat(__fd: c_int, noalias __path: [*c]const u8, noalias __buf: [*c]u8, __len: usize) isize;
pub extern fn unlink(__name: [*c]const u8) c_int;
pub extern fn unlinkat(__fd: c_int, __name: [*c]const u8, __flag: c_int) c_int;
pub extern fn rmdir(__path: [*c]const u8) c_int;
pub extern fn tcgetpgrp(__fd: c_int) __pid_t;
pub extern fn tcsetpgrp(__fd: c_int, __pgrp_id: __pid_t) c_int;
pub extern fn getlogin() [*c]u8;
pub extern fn getlogin_r(__name: [*c]u8, __name_len: usize) c_int;
pub extern fn setlogin(__name: [*c]const u8) c_int;
pub extern var optarg: [*c]u8;
pub extern var optind: c_int;
pub extern var opterr: c_int;
pub extern var optopt: c_int;
pub extern fn getopt(___argc: c_int, ___argv: [*c]const [*c]u8, __shortopts: [*c]const u8) c_int;
pub extern fn gethostname(__name: [*c]u8, __len: usize) c_int;
pub extern fn sethostname(__name: [*c]const u8, __len: usize) c_int;
pub extern fn sethostid(__id: c_long) c_int;
pub extern fn getdomainname(__name: [*c]u8, __len: usize) c_int;
pub extern fn setdomainname(__name: [*c]const u8, __len: usize) c_int;
pub extern fn vhangup() c_int;
pub extern fn revoke(__file: [*c]const u8) c_int;
pub extern fn profil(__sample_buffer: [*c]c_ushort, __size: usize, __offset: usize, __scale: c_uint) c_int;
pub extern fn acct(__name: [*c]const u8) c_int;
pub extern fn getusershell() [*c]u8;
pub extern fn endusershell() void;
pub extern fn setusershell() void;
pub extern fn daemon(__nochdir: c_int, __noclose: c_int) c_int;
pub extern fn chroot(__path: [*c]const u8) c_int;
pub extern fn getpass(__prompt: [*c]const u8) [*c]u8;
pub extern fn fsync(__fd: c_int) c_int;
pub extern fn gethostid() c_long;
pub extern fn sync() void;
pub extern fn getpagesize() c_int;
pub extern fn getdtablesize() c_int;
pub extern fn truncate(__file: [*c]const u8, __length: __off_t) c_int;
pub extern fn ftruncate(__fd: c_int, __length: __off_t) c_int;
pub extern fn brk(__addr: ?*anyopaque) c_int;
pub extern fn sbrk(__delta: isize) ?*anyopaque;
pub extern fn syscall(__sysno: c_long, ...) c_long;
pub extern fn lockf(__fd: c_int, __cmd: c_int, __len: __off_t) c_int;
pub extern fn fdatasync(__fildes: c_int) c_int;
pub extern fn crypt(__key: [*c]const u8, __salt: [*c]const u8) [*c]u8;
pub extern fn getentropy(__buffer: ?*anyopaque, __length: usize) c_int;
pub const struct_flock = extern struct {
    l_type: c_short = 0,
    l_whence: c_short = 0,
    l_start: __off_t = 0,
    l_len: __off_t = 0,
    l_pid: __pid_t = 0,
};
pub const struct_stat = extern struct {
    st_dev: __dev_t = 0,
    st_ino: __ino_t = 0,
    st_nlink: __nlink_t = 0,
    st_mode: __mode_t = 0,
    st_uid: __uid_t = 0,
    st_gid: __gid_t = 0,
    __pad0: c_int = 0,
    st_rdev: __dev_t = 0,
    st_size: __off_t = 0,
    st_blksize: __blksize_t = 0,
    st_blocks: __blkcnt_t = 0,
    st_atim: struct_timespec = @import("std").mem.zeroes(struct_timespec),
    st_mtim: struct_timespec = @import("std").mem.zeroes(struct_timespec),
    st_ctim: struct_timespec = @import("std").mem.zeroes(struct_timespec),
    __glibc_reserved: [3]__syscall_slong_t = @import("std").mem.zeroes([3]__syscall_slong_t),
};
pub extern fn fcntl(__fd: c_int, __cmd: c_int, ...) c_int;
pub extern fn open(__file: [*c]const u8, __oflag: c_int, ...) c_int;
pub extern fn openat(__fd: c_int, __file: [*c]const u8, __oflag: c_int, ...) c_int;
pub extern fn creat(__file: [*c]const u8, __mode: mode_t) c_int;
pub extern fn posix_fadvise(__fd: c_int, __offset: off_t, __len: off_t, __advise: c_int) c_int;
pub extern fn posix_fallocate(__fd: c_int, __offset: off_t, __len: off_t) c_int;
pub extern fn stat(noalias __file: [*c]const u8, noalias __buf: [*c]struct_stat) c_int;
pub extern fn fstat(__fd: c_int, __buf: [*c]struct_stat) c_int;
pub extern fn fstatat(__fd: c_int, noalias __file: [*c]const u8, noalias __buf: [*c]struct_stat, __flag: c_int) c_int;
pub extern fn lstat(noalias __file: [*c]const u8, noalias __buf: [*c]struct_stat) c_int;
pub extern fn chmod(__file: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn lchmod(__file: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn fchmod(__fd: c_int, __mode: __mode_t) c_int;
pub extern fn fchmodat(__fd: c_int, __file: [*c]const u8, __mode: __mode_t, __flag: c_int) c_int;
pub extern fn umask(__mask: __mode_t) __mode_t;
pub extern fn mkdir(__path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn mkdirat(__fd: c_int, __path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn mknod(__path: [*c]const u8, __mode: __mode_t, __dev: __dev_t) c_int;
pub extern fn mknodat(__fd: c_int, __path: [*c]const u8, __mode: __mode_t, __dev: __dev_t) c_int;
pub extern fn mkfifo(__path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn mkfifoat(__fd: c_int, __path: [*c]const u8, __mode: __mode_t) c_int;
pub extern fn utimensat(__fd: c_int, __path: [*c]const u8, __times: [*c]const struct_timespec, __flags: c_int) c_int;
pub extern fn futimens(__fd: c_int, __times: [*c]const struct_timespec) c_int;
pub const FTW_F: c_int = 0;
pub const FTW_D: c_int = 1;
pub const FTW_DNR: c_int = 2;
pub const FTW_NS: c_int = 3;
pub const FTW_SL: c_int = 4;
const enum_unnamed_8 = c_uint;
pub const __ftw_func_t = ?*const fn (__filename: [*c]const u8, __status: [*c]const struct_stat, __flag: c_int) callconv(.c) c_int;
pub extern fn ftw(__dir: [*c]const u8, __func: __ftw_func_t, __descriptors: c_int) c_int;
pub const struct_tm = extern struct {
    tm_sec: c_int = 0,
    tm_min: c_int = 0,
    tm_hour: c_int = 0,
    tm_mday: c_int = 0,
    tm_mon: c_int = 0,
    tm_year: c_int = 0,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = 0,
    tm_gmtoff: c_long = 0,
    tm_zone: [*c]const u8 = null,
    pub const mktime = __root.mktime;
    pub const asctime = __root.asctime;
    pub const asctime_r = __root.asctime_r;
    pub const timegm = __root.timegm;
    pub const timelocal = __root.timelocal;
    pub const r = __root.asctime_r;
};
pub const struct_itimerspec = extern struct {
    it_interval: struct_timespec = @import("std").mem.zeroes(struct_timespec),
    it_value: struct_timespec = @import("std").mem.zeroes(struct_timespec),
};
pub const struct_sigevent = opaque {};
pub extern fn clock() clock_t;
pub extern fn time(__timer: [*c]time_t) time_t;
pub extern fn difftime(__time1: time_t, __time0: time_t) f64;
pub extern fn mktime(__tp: [*c]struct_tm) time_t;
pub extern fn strftime(noalias __s: [*c]u8, __maxsize: usize, noalias __format: [*c]const u8, noalias __tp: [*c]const struct_tm) usize;
pub extern fn strftime_l(noalias __s: [*c]u8, __maxsize: usize, noalias __format: [*c]const u8, noalias __tp: [*c]const struct_tm, __loc: locale_t) usize;
pub extern fn gmtime(__timer: [*c]const time_t) [*c]struct_tm;
pub extern fn localtime(__timer: [*c]const time_t) [*c]struct_tm;
pub extern fn gmtime_r(noalias __timer: [*c]const time_t, noalias __tp: [*c]struct_tm) [*c]struct_tm;
pub extern fn localtime_r(noalias __timer: [*c]const time_t, noalias __tp: [*c]struct_tm) [*c]struct_tm;
pub extern fn asctime(__tp: [*c]const struct_tm) [*c]u8;
pub extern fn ctime(__timer: [*c]const time_t) [*c]u8;
pub extern fn asctime_r(noalias __tp: [*c]const struct_tm, noalias __buf: [*c]u8) [*c]u8;
pub extern fn ctime_r(noalias __timer: [*c]const time_t, noalias __buf: [*c]u8) [*c]u8;
pub extern var __tzname: [2][*c]u8;
pub extern var __daylight: c_int;
pub extern var __timezone: c_long;
pub extern var tzname: [2][*c]u8;
pub extern fn tzset() void;
pub extern var daylight: c_int;
pub extern var timezone: c_long;
pub extern fn timegm(__tp: [*c]struct_tm) time_t;
pub extern fn timelocal(__tp: [*c]struct_tm) time_t;
pub extern fn dysize(__year: c_int) c_int;
pub extern fn nanosleep(__requested_time: [*c]const struct_timespec, __remaining: [*c]struct_timespec) c_int;
pub extern fn clock_getres(__clock_id: clockid_t, __res: [*c]struct_timespec) c_int;
pub extern fn clock_gettime(__clock_id: clockid_t, __tp: [*c]struct_timespec) c_int;
pub extern fn clock_settime(__clock_id: clockid_t, __tp: [*c]const struct_timespec) c_int;
pub extern fn clock_nanosleep(__clock_id: clockid_t, __flags: c_int, __req: [*c]const struct_timespec, __rem: [*c]struct_timespec) c_int;
pub extern fn clock_getcpuclockid(__pid: pid_t, __clock_id: [*c]clockid_t) c_int;
pub extern fn timer_create(__clock_id: clockid_t, noalias __evp: ?*struct_sigevent, noalias __timerid: [*c]timer_t) c_int;
pub extern fn timer_delete(__timerid: timer_t) c_int;
pub extern fn timer_settime(__timerid: timer_t, __flags: c_int, noalias __value: [*c]const struct_itimerspec, noalias __ovalue: [*c]struct_itimerspec) c_int;
pub extern fn timer_gettime(__timerid: timer_t, __value: [*c]struct_itimerspec) c_int;
pub extern fn timer_getoverrun(__timerid: timer_t) c_int;
pub extern fn timespec_get(__ts: [*c]struct_timespec, __base: c_int) c_int;
pub const struct_utimbuf = extern struct {
    actime: __time_t = 0,
    modtime: __time_t = 0,
};
pub extern fn utime(__file: [*c]const u8, __file_times: [*c]const struct_utimbuf) c_int;
pub extern fn fnmatch(__pattern: [*c]const u8, __name: [*c]const u8, __flags: c_int) c_int;
pub extern fn dirname(__path: [*c]u8) [*c]u8;
pub extern fn __xpg_basename(__path: [*c]u8) [*c]u8;
pub const _ISupper: c_int = 256;
pub const _ISlower: c_int = 512;
pub const _ISalpha: c_int = 1024;
pub const _ISdigit: c_int = 2048;
pub const _ISxdigit: c_int = 4096;
pub const _ISspace: c_int = 8192;
pub const _ISprint: c_int = 16384;
pub const _ISgraph: c_int = 32768;
pub const _ISblank: c_int = 1;
pub const _IScntrl: c_int = 2;
pub const _ISpunct: c_int = 4;
pub const _ISalnum: c_int = 8;
const enum_unnamed_9 = c_uint;
pub extern fn __ctype_b_loc() [*c][*c]const c_ushort;
pub extern fn __ctype_tolower_loc() [*c][*c]const __int32_t;
pub extern fn __ctype_toupper_loc() [*c][*c]const __int32_t;
pub extern fn isalnum(c_int) c_int;
pub extern fn isalpha(c_int) c_int;
pub extern fn iscntrl(c_int) c_int;
pub extern fn isdigit(c_int) c_int;
pub extern fn islower(c_int) c_int;
pub extern fn isgraph(c_int) c_int;
pub extern fn isprint(c_int) c_int;
pub extern fn ispunct(c_int) c_int;
pub extern fn isspace(c_int) c_int;
pub extern fn isupper(c_int) c_int;
pub extern fn isxdigit(c_int) c_int;
pub extern fn tolower(__c: c_int) c_int;
pub extern fn toupper(__c: c_int) c_int;
pub extern fn isblank(c_int) c_int;
pub extern fn isascii(__c: c_int) c_int;
pub extern fn toascii(__c: c_int) c_int;
pub extern fn _toupper(c_int) c_int;
pub extern fn _tolower(c_int) c_int;
pub extern fn isalnum_l(c_int, locale_t) c_int;
pub extern fn isalpha_l(c_int, locale_t) c_int;
pub extern fn iscntrl_l(c_int, locale_t) c_int;
pub extern fn isdigit_l(c_int, locale_t) c_int;
pub extern fn islower_l(c_int, locale_t) c_int;
pub extern fn isgraph_l(c_int, locale_t) c_int;
pub extern fn isprint_l(c_int, locale_t) c_int;
pub extern fn ispunct_l(c_int, locale_t) c_int;
pub extern fn isspace_l(c_int, locale_t) c_int;
pub extern fn isupper_l(c_int, locale_t) c_int;
pub extern fn isxdigit_l(c_int, locale_t) c_int;
pub extern fn isblank_l(c_int, locale_t) c_int;
pub extern fn __tolower_l(__c: c_int, __l: locale_t) c_int;
pub extern fn tolower_l(__c: c_int, __l: locale_t) c_int;
pub extern fn __toupper_l(__c: c_int, __l: locale_t) c_int;
pub extern fn toupper_l(__c: c_int, __l: locale_t) c_int;
pub extern fn flock(__fd: c_int, __operation: c_int) c_int;
pub const struct_utsname = extern struct {
    sysname: [65]u8 = @import("std").mem.zeroes([65]u8),
    nodename: [65]u8 = @import("std").mem.zeroes([65]u8),
    release: [65]u8 = @import("std").mem.zeroes([65]u8),
    version: [65]u8 = @import("std").mem.zeroes([65]u8),
    machine: [65]u8 = @import("std").mem.zeroes([65]u8),
    __domainname: [65]u8 = @import("std").mem.zeroes([65]u8),
    pub const uname = __root.uname;
};
pub extern fn uname(__name: [*c]struct_utsname) c_int;
pub const struct_statfs = extern struct {
    f_type: __fsword_t = 0,
    f_bsize: __fsword_t = 0,
    f_blocks: __fsblkcnt_t = 0,
    f_bfree: __fsblkcnt_t = 0,
    f_bavail: __fsblkcnt_t = 0,
    f_files: __fsfilcnt_t = 0,
    f_ffree: __fsfilcnt_t = 0,
    f_fsid: __fsid_t = @import("std").mem.zeroes(__fsid_t),
    f_namelen: __fsword_t = 0,
    f_frsize: __fsword_t = 0,
    f_flags: __fsword_t = 0,
    f_spare: [4]__fsword_t = @import("std").mem.zeroes([4]__fsword_t),
};
pub extern fn statfs(__file: [*c]const u8, __buf: [*c]struct_statfs) c_int;
pub extern fn fstatfs(__fildes: c_int, __buf: [*c]struct_statfs) c_int;
pub const struct_dirent = extern struct {
    d_ino: __ino_t = 0,
    d_off: __off_t = 0,
    d_reclen: c_ushort = 0,
    d_type: u8 = 0,
    d_name: [256]u8 = @import("std").mem.zeroes([256]u8),
};
pub const DT_UNKNOWN: c_int = 0;
pub const DT_FIFO: c_int = 1;
pub const DT_CHR: c_int = 2;
pub const DT_DIR: c_int = 4;
pub const DT_BLK: c_int = 6;
pub const DT_REG: c_int = 8;
pub const DT_LNK: c_int = 10;
pub const DT_SOCK: c_int = 12;
pub const DT_WHT: c_int = 14;
const enum_unnamed_10 = c_uint;
pub const struct___dirstream = opaque {
    pub const closedir = __root.closedir;
    pub const readdir = __root.readdir;
    pub const readdir_r = __root.readdir_r;
    pub const rewinddir = __root.rewinddir;
    pub const seekdir = __root.seekdir;
    pub const telldir = __root.telldir;
    pub const dirfd = __root.dirfd;
    pub const r = __root.readdir_r;
};
pub const DIR = struct___dirstream;
pub extern fn closedir(__dirp: ?*DIR) c_int;
pub extern fn opendir(__name: [*c]const u8) ?*DIR;
pub extern fn fdopendir(__fd: c_int) ?*DIR;
pub extern fn readdir(__dirp: ?*DIR) [*c]struct_dirent;
pub extern fn readdir_r(noalias __dirp: ?*DIR, noalias __entry: [*c]struct_dirent, noalias __result: [*c][*c]struct_dirent) c_int;
pub extern fn rewinddir(__dirp: ?*DIR) void;
pub extern fn seekdir(__dirp: ?*DIR, __pos: c_long) void;
pub extern fn telldir(__dirp: ?*DIR) c_long;
pub extern fn dirfd(__dirp: ?*DIR) c_int;
pub extern fn scandir(noalias __dir: [*c]const u8, noalias __namelist: [*c][*c][*c]struct_dirent, __selector: ?*const fn ([*c]const struct_dirent) callconv(.c) c_int, __cmp: ?*const fn ([*c][*c]const struct_dirent, [*c][*c]const struct_dirent) callconv(.c) c_int) c_int;
pub extern fn alphasort(__e1: [*c][*c]const struct_dirent, __e2: [*c][*c]const struct_dirent) c_int;
pub extern fn getdirentries(__fd: c_int, noalias __buf: [*c]u8, __nbytes: usize, noalias __basep: [*c]__off_t) __ssize_t;
pub const TDNF_RPMTRANS_FLAGS = u32;
comptime {
    if (!(@sizeOf(TDNF_RPMTRANS_FLAGS) == @as(c_ulong, 4))) @compileError("static assertion failed \"transaction flags must be uint32\"");
}
comptime {
    if (!(@as(c_uint, 1) == (@as(c_uint, 1) << @intCast(@as(c_uint, 0))))) @compileError("static assertion failed \"TEST flag value changed\"");
}
comptime {
    if (!(@as(c_uint, 128) == (@as(c_uint, 1) << @intCast(@as(c_uint, 7))))) @compileError("static assertion failed \"NOPLUGINS flag value changed\"");
}
comptime {
    if (!(@as(c_uint, 134217728) == (@as(c_uint, 1) << @intCast(@as(c_uint, 27))))) @compileError("static assertion failed \"NOFILEDIGEST flag value changed\"");
}
comptime {
    if (!(@as(c_uint, 2147483648) == (@as(c_uint, 1) << @intCast(@as(c_uint, 31))))) @compileError("static assertion failed \"DEPLOOPS flag value changed\"");
}
pub const CONF_FLAG_IPV4: c_int = 0;
pub const CONF_FLAG_IPV6: c_int = 1;
pub const CONF_FLAG_ALLOWERASING: c_int = 2;
pub const CONF_FLAG_ASSUMENO: c_int = 3;
pub const CONF_FLAG_BEST: c_int = 4;
pub const CONF_FLAG_CACHEONLY: c_int = 5;
pub const CONF_FLAG_DEBUGSOLVER: c_int = 6;
pub const CONF_FLAG_REFRESHMETADATA: c_int = 7;
pub const CONF_FLAG_GPGCHECK: c_int = 8;
pub const CONF_FLAG_QUIET: c_int = 9;
pub const CONF_FLAG_SHOWDUPS: c_int = 10;
pub const CONF_FLAG_VERBOSE: c_int = 11;
pub const TDNF_CONF_FLAG = c_uint;
pub const CONF_TYPE_CONFIG_FILE: c_int = 0;
pub const CONF_TYPE_DEBUG_LEVEL: c_int = 1;
pub const CONF_TYPE_DISABLE_EXCLUDES: c_int = 2;
pub const CONF_TYPE_DISABLE_REPO: c_int = 3;
pub const CONF_TYPE_ENABLE_REPO: c_int = 4;
pub const CONF_TYPE_EXCLUDE_PACKAGE: c_int = 5;
pub const CONF_TYPE_INSTALL_ROOT: c_int = 6;
pub const CONF_TYPE_RELEASE_VER: c_int = 7;
pub const CONF_TYPE_RPM_VERBOSITY: c_int = 8;
pub const TDNF_CONF_TYPE = c_uint;
pub const ALTER_AUTOERASE: c_int = 0;
pub const ALTER_AUTOERASEALL: c_int = 1;
pub const ALTER_DOWNGRADE: c_int = 2;
pub const ALTER_DOWNGRADEALL: c_int = 3;
pub const ALTER_ERASE: c_int = 4;
pub const ALTER_INSTALL: c_int = 5;
pub const ALTER_REINSTALL: c_int = 6;
pub const ALTER_UPGRADE: c_int = 7;
pub const ALTER_UPGRADEALL: c_int = 8;
pub const ALTER_DISTRO_SYNC: c_int = 9;
pub const ALTER_OBSOLETED: c_int = 10;
pub const TDNF_ALTERTYPE = c_uint;
pub const TDNF_RPMLOG_EMERG: c_int = 0;
pub const TDNF_RPMLOG_ALERT: c_int = 1;
pub const TDNF_RPMLOG_CRIT: c_int = 2;
pub const TDNF_RPMLOG_ERR: c_int = 3;
pub const TDNF_RPMLOG_WARNING: c_int = 4;
pub const TDNF_RPMLOG_NOTICE: c_int = 5;
pub const TDNF_RPMLOG_INFO: c_int = 6;
pub const TDNF_RPMLOG_DEBUG: c_int = 7;
pub const TDNF_RPMLOG = c_uint;
pub const SCOPE_NONE: c_int = -1;
pub const SCOPE_ALL: c_int = 0;
pub const SCOPE_INSTALLED: c_int = 1;
pub const SCOPE_AVAILABLE: c_int = 2;
pub const SCOPE_EXTRAS: c_int = 3;
pub const SCOPE_OBSOLETES: c_int = 4;
pub const SCOPE_RECENT: c_int = 5;
pub const SCOPE_UPGRADES: c_int = 6;
pub const SCOPE_DOWNGRADES: c_int = 7;
pub const SCOPE_SOURCE: c_int = 8;
pub const TDNF_SCOPE = c_int;
pub const AVAIL_AVAILABLE: c_int = 0;
pub const AVAIL_INSTALLED: c_int = 1;
pub const AVAIL_UPDATES: c_int = 2;
pub const TDNF_AVAIL = c_uint;
pub const OUTPUT_SUMMARY: c_int = 0;
pub const OUTPUT_LIST: c_int = 1;
pub const OUTPUT_INFO: c_int = 2;
pub const TDNF_UPDATEINFO_OUTPUT = c_uint;
pub const UPDATE_UNKNOWN: c_int = 0;
pub const UPDATE_SECURITY: c_int = 1;
pub const UPDATE_BUGFIX: c_int = 2;
pub const UPDATE_ENHANCEMENT: c_int = 3;
pub const TDNF_UPDATEINFO_TYPE = c_uint;
pub const REPOLISTFILTER_ALL: c_int = 0;
pub const REPOLISTFILTER_ENABLED: c_int = 1;
pub const REPOLISTFILTER_DISABLED: c_int = 2;
pub const TDNF_REPOLISTFILTER = c_uint;
pub const SKIPPROBLEM_NONE: c_int = 0;
pub const SKIPPROBLEM_CONFLICTS: c_int = 1;
pub const SKIPPROBLEM_OBSOLETES: c_int = 2;
pub const SKIPPROBLEM_DISABLED: c_int = 4;
pub const SKIPPROBLEM_BROKEN: c_int = 8;
pub const TDNF_SKIPPROBLEM_TYPE = c_uint;
pub const struct__TDNF_PACKAGE_CONTEXT = opaque {
    pub const TDNFPackageContextFree = __root.TDNFPackageContextFree;
    pub const TDNFPackageContextCacheDir = __root.TDNFPackageContextCacheDir;
    pub const TDNFPackageContextRootDir = __root.TDNFPackageContextRootDir;
    pub const TDNFPackageContextInitCommandLine = __root.TDNFPackageContextInitCommandLine;
    pub const TDNFPackageContextResetCommandLine = __root.TDNFPackageContextResetCommandLine;
    pub const TDNFPackageContextAddRpm = __root.TDNFPackageContextAddRpm;
    pub const TDNFPackageContextGetFields = __root.TDNFPackageContextGetFields;
    pub const TDNFPackageContextGetRepoNevra = __root.TDNFPackageContextGetRepoNevra;
    pub const TDNFPackageContextGetInstalledPkgIds = __root.TDNFPackageContextGetInstalledPkgIds;
    pub const TDNFPackageContextGetAllPkgIds = __root.TDNFPackageContextGetAllPkgIds;
    pub const TDNFPackageContextGetRepoDataList = __root.TDNFPackageContextGetRepoDataList;
    pub const TDNFNativeQueryInstalledPkgIds = __root.TDNFNativeQueryInstalledPkgIds;
    pub const TDNFNativeQuerySerializePackageId = __root.TDNFNativeQuerySerializePackageId;
    pub const TDNFNativeQuerySerializeQueuePackageRefs = __root.TDNFNativeQuerySerializeQueuePackageRefs;
    pub const TDNFNativeQueryResolvePackageRefArrayToQueue = __root.TDNFNativeQueryResolvePackageRefArrayToQueue;
    pub const TDNFNativeQueryResolveSinglePackageRef = __root.TDNFNativeQueryResolveSinglePackageRef;
    pub const TDNFAddPackagesForInstall = __root.TDNFAddPackagesForInstall;
    pub const TDNFMatchForReinstall = __root.TDNFMatchForReinstall;
    pub const TDNFPopulatePkgInfosFromRefs = __root.TDNFPopulatePkgInfosFromRefs;
    pub const TDNFPkgInfoFilterNewest = __root.TDNFPkgInfoFilterNewest;
    pub const TDNFAddPackagesForErase = __root.TDNFAddPackagesForErase;
    pub const TDNFAddPackagesForUpgrade = __root.TDNFAddPackagesForUpgrade;
};
pub const PTDNF_PACKAGE_CONTEXT = ?*struct__TDNF_PACKAGE_CONTEXT;
pub const struct_cnfnode = extern struct {
    next: [*c]struct_cnfnode = null,
    name: [*c]u8 = null,
    value: [*c]u8 = null,
    first_child: [*c]struct_cnfnode = null,
    parent: [*c]struct_cnfnode = null,
    pub const clone_cnfnode = __root.clone_cnfnode;
    pub const clone_cnftree = __root.clone_cnftree;
    pub const cnfnode_getval = __root.cnfnode_getval;
    pub const cnfnode_getname = __root.cnfnode_getname;
    pub const cnfnode_setval = __root.cnfnode_setval;
    pub const cnfnode_setname = __root.cnfnode_setname;
    pub const cnfnode_setname_n = __root.cnfnode_setname_n;
    pub const destroy_cnfnode = __root.destroy_cnfnode;
    pub const destroy_cnftree = __root.destroy_cnftree;
    pub const append_node = __root.append_node;
    pub const insert_node_before = __root.insert_node_before;
    pub const unlink_node = __root.unlink_node;
    pub const find_node = __root.find_node;
    pub const compare_cnfnode = __root.compare_cnfnode;
    pub const compare_cnftree = __root.compare_cnftree;
    pub const compare_cnftree_children = __root.compare_cnftree_children;
    pub const dump_nodes = __root.dump_nodes;
    pub const replace_vars = __root.replace_vars;
    pub const cnftree = __root.clone_cnftree;
    pub const getval = __root.cnfnode_getval;
    pub const getname = __root.cnfnode_getname;
    pub const setval = __root.cnfnode_setval;
    pub const setname = __root.cnfnode_setname;
    pub const setname_n = __root.cnfnode_setname_n;
    pub const node = __root.append_node;
    pub const before = __root.insert_node_before;
    pub const children = __root.compare_cnftree_children;
    pub const nodes = __root.dump_nodes;
    pub const vars = __root.replace_vars;
};
pub const struct__TDNF_CMD_ARGS = extern struct {
    nAllDeps: c_int = 0,
    nAllowErasing: c_int = 0,
    nAssumeNo: c_int = 0,
    nAssumeYes: c_int = 0,
    nBest: c_int = 0,
    nCacheOnly: c_int = 0,
    nDebugSolver: c_int = 0,
    nShowHelp: c_int = 0,
    nRefresh: c_int = 0,
    nRpmVerbosity: c_int = 0,
    nShowDuplicates: c_int = 0,
    nShowVersion: c_int = 0,
    nNoDeps: c_int = 0,
    nNoGPGCheck: c_int = 0,
    nNoCmdLineGPGCheck: c_int = 0,
    nSkipSignature: c_int = 0,
    nSkipDigest: c_int = 0,
    nNoOutput: c_int = 0,
    nQuiet: c_int = 0,
    nVerbose: c_int = 0,
    nIPv4: c_int = 0,
    nIPv6: c_int = 0,
    nDisableExcludes: c_int = 0,
    nDownloadOnly: c_int = 0,
    nUrlsOnly: c_int = 0,
    nNoAutoRemove: c_int = 0,
    nJsonOutput: c_int = 0,
    nTestOnly: c_int = 0,
    nSkipBroken: c_int = 0,
    nSource: c_int = 0,
    nBuildDeps: c_int = 0,
    pszArch: [*c]u8 = null,
    pszDownloadDir: [*c]u8 = null,
    pszInstallRoot: [*c]u8 = null,
    pszConfFile: [*c]u8 = null,
    pszReleaseVer: [*c]u8 = null,
    ppszCmds: [*c][*c]u8 = null,
    nCmdCount: c_int = 0,
    cn_setopts: [*c]struct_cnfnode = null,
    cn_repoopts: [*c]struct_cnfnode = null,
    nArgc: c_int = 0,
    ppszArgv: [*c][*c]u8 = null,
    pub const TDNFOpenHandle = __root.TDNFOpenHandle;
    pub const TDNFFreeCmdArgs = __root.TDNFFreeCmdArgs;
    pub const TDNFYesOrNo = __root.TDNFYesOrNo;
};
pub const PTDNF_CMD_ARGS = [*c]struct__TDNF_CMD_ARGS;
pub const struct__TDNF_CONF = extern struct {
    nGPGCheck: c_int = 0,
    nCliGPGCheck: c_int = 0,
    nSSLVerify: c_int = 0,
    nInstallOnlyLimit: c_int = 0,
    nCleanRequirementsOnRemove: c_int = 0,
    nKeepCache: c_int = 0,
    nOpenMax: c_int = 0,
    nCheckUpdateCompat: c_int = 0,
    nDistroSyncReinstallChanged: c_int = 0,
    nConnectTimeout: c_int = 0,
    rpmTransFlags: TDNF_RPMTRANS_FLAGS = 0,
    nPluginsEnabled: c_int = 0,
    nSkipDigest: c_int = 0,
    nSkipSignature: c_int = 0,
    pszRepoDir: [*c]u8 = null,
    pszCacheDir: [*c]u8 = null,
    pszPersistDir: [*c]u8 = null,
    pszProxy: [*c]u8 = null,
    pszProxyUserPass: [*c]u8 = null,
    ppszDistroVerPkgs: [*c][*c]u8 = null,
    pszBaseArch: [*c]u8 = null,
    pszVarReleaseVer: [*c]u8 = null,
    pszVarBaseArch: [*c]u8 = null,
    pszUserAgentHeader: [*c]u8 = null,
    pszOSName: [*c]u8 = null,
    pszOSVersion: [*c]u8 = null,
    ppszExcludes: [*c][*c]u8 = null,
    ppszMinVersions: [*c][*c]u8 = null,
    ppszPkgLocks: [*c][*c]u8 = null,
    ppszProtectedPkgs: [*c][*c]u8 = null,
    ppszInstallOnlyPkgs: [*c][*c]u8 = null,
    ppszVarsDirs: [*c][*c]u8 = null,
    pszPluginPath: [*c]u8 = null,
    pszPluginConfPath: [*c]u8 = null,
    pub const TDNFGetAvailableCacheBytes = __root.TDNFGetAvailableCacheBytes;
    pub const TDNFFreeConfig = __root.TDNFFreeConfig;
};
pub const PTDNF_CONF = [*c]struct__TDNF_CONF;
pub const struct_tdnf_rpm_config = opaque {
    pub const tdnf_rpm_config_destroy = __root.tdnf_rpm_config_destroy;
    pub const tdnf_rpm_config_apply_define = __root.tdnf_rpm_config_apply_define;
    pub const tdnf_rpm_config_expand = __root.tdnf_rpm_config_expand;
    pub const tdnf_rpm_config_resolve_path = __root.tdnf_rpm_config_resolve_path;
    pub const TDNFRepoMdNativeAutoInstalledOrphanLinesConfig = __root.TDNFRepoMdNativeAutoInstalledOrphanLinesConfig;
    pub const tdnf_rpmdb_count_packages_config = __root.tdnf_rpmdb_count_packages_config;
    pub const tdnf_rpm_config_install_root = __root.tdnf_rpm_config_install_root;
    pub const tdnf_rpm_config_open_root_fd = __root.tdnf_rpm_config_open_root_fd;
    pub const tdnf_rpmdb_cookie_config = __root.tdnf_rpmdb_cookie_config;
    pub const tdnf_rpmdb_iter_open_config = __root.tdnf_rpmdb_iter_open_config;
    pub const tdnf_rpmdb_resolve_provider_version_config = __root.tdnf_rpmdb_resolve_provider_version_config;
    pub const tdnf_rpmdb_write_install_config = __root.tdnf_rpmdb_write_install_config;
    pub const tdnf_rpmdb_write_install_file_config = __root.tdnf_rpmdb_write_install_file_config;
    pub const tdnf_rpmdb_write_replace_config = __root.tdnf_rpmdb_write_replace_config;
    pub const tdnf_rpmdb_write_replace_file_config = __root.tdnf_rpmdb_write_replace_file_config;
    pub const tdnf_rpmdb_write_erase_hnum_config = __root.tdnf_rpmdb_write_erase_hnum_config;
    pub const tdnf_rpmdb_find_hnum_by_nevra_config = __root.tdnf_rpmdb_find_hnum_by_nevra_config;
    pub const tdnf_rpmdb_find_hnums_by_name_config = __root.tdnf_rpmdb_find_hnums_by_name_config;
    pub const tdnf_rpmdb_find_label_matches_config = __root.tdnf_rpmdb_find_label_matches_config;
    pub const tdnf_rpmdb_read_header_blob_config = __root.tdnf_rpmdb_read_header_blob_config;
    pub const tdnf_rpmdb_import_pubkeys_config = __root.tdnf_rpmdb_import_pubkeys_config;
    pub const tdnf_rpmdb_pubkeys_open_config = __root.tdnf_rpmdb_pubkeys_open_config;
    pub const tdnf_rpm_canonical_path_config = __root.tdnf_rpm_canonical_path_config;
    pub const TdnfGetReleaseVersionConfig = __root.TdnfGetReleaseVersionConfig;
    pub const destroy = __root.tdnf_rpm_config_destroy;
    pub const apply_define = __root.tdnf_rpm_config_apply_define;
    pub const expand = __root.tdnf_rpm_config_expand;
    pub const resolve_path = __root.tdnf_rpm_config_resolve_path;
    pub const config = __root.tdnf_rpmdb_count_packages_config;
    pub const install_root = __root.tdnf_rpm_config_install_root;
    pub const open_root_fd = __root.tdnf_rpm_config_open_root_fd;
};
pub const tdnf_rpm_config = struct_tdnf_rpm_config;
pub const struct_s_Repo = opaque {
    pub const TDNFRepoMdNativeLoadSolvRepo = __root.TDNFRepoMdNativeLoadSolvRepo;
    pub const TDNFRepoMdNativeLoadInstalledSolvRepo = __root.TDNFRepoMdNativeLoadInstalledSolvRepo;
    pub const TDNFRepoMdNativeLoadInstalledSolvRepoConfig = __root.TDNFRepoMdNativeLoadInstalledSolvRepoConfig;
    pub const TDNFRepoMdNativeAddRpm = __root.TDNFRepoMdNativeAddRpm;
};
pub const Repo = struct_s_Repo;
pub const struct__TDNF_REPO_DATA = extern struct {
    nEnabled: c_int = 0,
    nSkipIfUnavailable: c_int = 0,
    nGPGCheck: c_int = 0,
    nHasMetaData: c_int = 0,
    lMetadataExpire: c_long = 0,
    pszId: [*c]u8 = null,
    pszName: [*c]u8 = null,
    ppszBaseUrls: [*c][*c]u8 = null,
    pszMetaLink: [*c]u8 = null,
    pszMirrorList: [*c]u8 = null,
    pszSnapshotUrl: [*c]u8 = null,
    pszSnapshotFile: [*c]u8 = null,
    ppszUrlGPGKeys: [*c][*c]u8 = null,
    nSSLVerify: c_int = 0,
    pszSSLCaCert: [*c]u8 = null,
    pszSSLClientCert: [*c]u8 = null,
    pszSSLClientKey: [*c]u8 = null,
    pszUser: [*c]u8 = null,
    pszPass: [*c]u8 = null,
    nPriority: c_int = 0,
    nTimeout: c_long = 0,
    nMinrate: c_long = 0,
    nThrottle: c_long = 0,
    nRetries: c_int = 0,
    nSkipMDFileLists: c_int = 0,
    nSkipMDUpdateInfo: c_int = 0,
    nSkipMDOther: c_int = 0,
    pszCacheName: [*c]u8 = null,
    pRepo: ?*Repo = null,
    pNext: [*c]struct__TDNF_REPO_DATA = null,
    pub const TDNFFreeRepos = __root.TDNFFreeRepos;
    pub const TDNFCreatePackageUrl = __root.TDNFCreatePackageUrl;
    pub const TDNFCloneRepo = __root.TDNFCloneRepo;
    pub const TDNFFreeReposInternal = __root.TDNFFreeReposInternal;
};
pub const PTDNF_REPO_DATA = [*c]struct__TDNF_REPO_DATA;
pub const PTDNF_REPOSITORY_CONTEXT = ?*Repo;
pub const TDNF_BUILTIN_PLUGIN_METALINK: c_int = 0;
pub const TDNF_BUILTIN_PLUGIN_REPOGPGCHECK: c_int = 1;
const enum_unnamed_11 = c_uint;
pub const struct__TDNF_PLUGIN_ = extern struct {
    pszName: [*c]u8 = null,
    nEnabled: c_int = 0,
    nKind: enum_unnamed_11 = @import("std").mem.zeroes(enum_unnamed_11),
    pHandle: ?*anyopaque = null,
    pNext: [*c]struct__TDNF_PLUGIN_ = null,
    pub const TDNFFreePlugins = __root.TDNFFreePlugins;
};
pub const PTDNF_PLUGIN = [*c]struct__TDNF_PLUGIN_;
pub const struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE = opaque {
    pub const TDNFTransactionPlanRequestTraceDestroy = __root.TDNFTransactionPlanRequestTraceDestroy;
    pub const TDNFTransactionPlanRequestTraceRecordGoalRange = __root.TDNFTransactionPlanRequestTraceRecordGoalRange;
    pub const TDNFTransactionPlanRequestTraceRecordHistoryGoal = __root.TDNFTransactionPlanRequestTraceRecordHistoryGoal;
    pub const TDNFTransactionPlanRequestTraceRecordRequestOutcome = __root.TDNFTransactionPlanRequestTraceRecordRequestOutcome;
    pub const TDNFTransactionPlanRequestTraceCommitGoal = __root.TDNFTransactionPlanRequestTraceCommitGoal;
    pub const TDNFTransactionPlanRequestTraceRecordPackageJob = __root.TDNFTransactionPlanRequestTraceRecordPackageJob;
    pub const TDNFTransactionPlanRequestTraceRecordPackageJobRange = __root.TDNFTransactionPlanRequestTraceRecordPackageJobRange;
    pub const TDNFTransactionPlanRequestTraceRecordNameJob = __root.TDNFTransactionPlanRequestTraceRecordNameJob;
    pub const TDNFTransactionPlanRequestTraceRecordAllJob = __root.TDNFTransactionPlanRequestTraceRecordAllJob;
    pub const TDNFTransactionPlanRequestTraceRecordCapabilityJob = __root.TDNFTransactionPlanRequestTraceRecordCapabilityJob;
    pub const TDNFTransactionPlanRequestTraceRecordPolicies = __root.TDNFTransactionPlanRequestTraceRecordPolicies;
    pub const TDNFTransactionPlanRequestTraceFinalize = __root.TDNFTransactionPlanRequestTraceFinalize;
    pub const TDNFTransactionPlanRequestTraceGetView = __root.TDNFTransactionPlanRequestTraceGetView;
    pub const TDNFTransactionPlanRequestTraceGetError = __root.TDNFTransactionPlanRequestTraceGetError;
    pub const TDNFTransactionPlanRequestTraceCaptureFactsCreate = __root.TDNFTransactionPlanRequestTraceCaptureFactsCreate;
};
pub const TDNF_TRANSACTION_PLAN_REQUEST_TRACE = struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE;
pub const struct_TDNF_TRANSACTION_PLAN_STATE = opaque {
    pub const TDNFTransactionPlanStateIsEnabled = __root.TDNFTransactionPlanStateIsEnabled;
    pub const TDNFTransactionPlanStateRepositoryRecordCount = __root.TDNFTransactionPlanStateRepositoryRecordCount;
    pub const TDNFTransactionPlanStateFailNextRepositoryRecord = __root.TDNFTransactionPlanStateFailNextRepositoryRecord;
    pub const TDNFTransactionPlanStateFailNextCapture = __root.TDNFTransactionPlanStateFailNextCapture;
    pub const TDNFTransactionPlanStateFailNextCaptureIntegrity = __root.TDNFTransactionPlanStateFailNextCaptureIntegrity;
    pub const TDNFTransactionPlanStateClear = __root.TDNFTransactionPlanStateClear;
    pub const TDNFTransactionPlanStatePublish = __root.TDNFTransactionPlanStatePublish;
    pub const TDNFTransactionPlanStateHasPendingProblem = __root.TDNFTransactionPlanStateHasPendingProblem;
    pub const TDNFTransactionPlanStatePublishProblem = __root.TDNFTransactionPlanStatePublishProblem;
    pub const TDNFTransactionPlanStateDestroy = __root.TDNFTransactionPlanStateDestroy;
    pub const TDNFTransactionPlanStateGetCanonicalJson = __root.TDNFTransactionPlanStateGetCanonicalJson;
    pub const TDNFTransactionPlanIntegrationCapturePending = __root.TDNFTransactionPlanIntegrationCapturePending;
};
pub const TDNF_TRANSACTION_PLAN_STATE = struct_TDNF_TRANSACTION_PLAN_STATE;
pub const TDNF_PKG_ID = i32;
pub const struct__TDNF_ = extern struct {
    pSack: PTDNF_PACKAGE_CONTEXT = null,
    pArgs: PTDNF_CMD_ARGS = null,
    pConf: PTDNF_CONF = null,
    pRpmConfig: ?*tdnf_rpm_config = null,
    pRepos: PTDNF_REPO_DATA = null,
    pCmdLineRepo: PTDNF_REPOSITORY_CONTEXT = null,
    pPlugins: PTDNF_PLUGIN = null,
    ppszRepoFromDirIds: [*c][*c]u8 = null,
    pRequestTrace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE = null,
    pTransactionPlanState: ?*TDNF_TRANSACTION_PLAN_STATE = null,
    ppszHiddenRefs: [*c][*c]u8 = null,
    dwHiddenRefCount: u32 = 0,
    pdwCmdLinePkgIds: [*c]TDNF_PKG_ID = null,
    ppszCmdLinePkgPaths: [*c][*c]u8 = null,
    dwCmdLinePkgCount: u32 = 0,
    nTestReloadFailureStage: u32 = 0,
    pub const TDNFRefresh = __root.TDNFRefresh;
    pub const TDNFCheckUpdates = __root.TDNFCheckUpdates;
    pub const TDNFClean = __root.TDNFClean;
    pub const TDNFList = __root.TDNFList;
    pub const TDNFInfo = __root.TDNFInfo;
    pub const TDNFRepoList = __root.TDNFRepoList;
    pub const TDNFCheckPackages = __root.TDNFCheckPackages;
    pub const TDNFCheckLocalPackages = __root.TDNFCheckLocalPackages;
    pub const TDNFProvides = __root.TDNFProvides;
    pub const TDNFRepoSync = __root.TDNFRepoSync;
    pub const TDNFRepoQuery = __root.TDNFRepoQuery;
    pub const TDNFUpdateInfo = __root.TDNFUpdateInfo;
    pub const TDNFUpdateInfoSummary = __root.TDNFUpdateInfoSummary;
    pub const TDNFHistoryResolve = __root.TDNFHistoryResolve;
    pub const TDNFHistoryList = __root.TDNFHistoryList;
    pub const TDNFGetPackageUrls = __root.TDNFGetPackageUrls;
    pub const TDNFHistoryGetId = __root.TDNFHistoryGetId;
    pub const TDNFCountCommand = __root.TDNFCountCommand;
    pub const TDNFSearchCommand = __root.TDNFSearchCommand;
    pub const TDNFResolve = __root.TDNFResolve;
    pub const TDNFTransactionPlanSetEnabled = __root.TDNFTransactionPlanSetEnabled;
    pub const TDNFTransactionPlanGetCanonicalJson = __root.TDNFTransactionPlanGetCanonicalJson;
    pub const TDNFTransactionPlanGetDigestHex = __root.TDNFTransactionPlanGetDigestHex;
    pub const TDNFAlterCommand = __root.TDNFAlterCommand;
    pub const TDNFAlterHistoryCommand = __root.TDNFAlterHistoryCommand;
    pub const TDNFMark = __root.TDNFMark;
    pub const TDNFCloseHandle = __root.TDNFCloseHandle;
    pub const TDNFRepoRemoveCacheDir = __root.TDNFRepoRemoveCacheDir;
    pub const TDNFRepoRemoveCache = __root.TDNFRepoRemoveCache;
    pub const TDNFRemoveRpmCache = __root.TDNFRemoveRpmCache;
    pub const TDNFRemoveLastRefreshMarker = __root.TDNFRemoveLastRefreshMarker;
    pub const TDNFRemoveMirrorList = __root.TDNFRemoveMirrorList;
    pub const TDNFRemoveSnapshot = __root.TDNFRemoveSnapshot;
    pub const TDNFRemoveSolvCache = __root.TDNFRemoveSolvCache;
    pub const TDNFRemoveKeysCache = __root.TDNFRemoveKeysCache;
    pub const TDNFGetCachePath = __root.TDNFGetCachePath;
    pub const RepoutilsGetRpmCachePath = __root.RepoutilsGetRpmCachePath;
    pub const TDNFFindRepoById = __root.TDNFFindRepoById;
    pub const TDNFDownloadFileFromRepo = __root.TDNFDownloadFileFromRepo;
    pub const TDNFDownloadFile = __root.TDNFDownloadFile;
    pub const TDNFDownloadPackageToCache = __root.TDNFDownloadPackageToCache;
    pub const TDNFDownloadPackageToTree = __root.TDNFDownloadPackageToTree;
    pub const TDNFDownloadPackageToDirectory = __root.TDNFDownloadPackageToDirectory;
    pub const TDNFNativeQueryBuildRepoInputs = __root.TDNFNativeQueryBuildRepoInputs;
    pub const TDNFNativeQueryBuildSingleRepoInput = __root.TDNFNativeQueryBuildSingleRepoInput;
    pub const TDNFNativeQueryInstallRoot = __root.TDNFNativeQueryInstallRoot;
    pub const TDNFNativeQueryFilterUserInstalled = __root.TDNFNativeQueryFilterUserInstalled;
    pub const TDNFNativeQueryApplyLocationUrls = __root.TDNFNativeQueryApplyLocationUrls;
    pub const TDNFNativeQuerySerializeAutoInstalledRefs = __root.TDNFNativeQuerySerializeAutoInstalledRefs;
    pub const TDNFAddPackagesForDowngrade = __root.TDNFAddPackagesForDowngrade;
    pub const TDNFGPGCheckPackageEx = __root.TDNFGPGCheckPackageEx;
    pub const TDNFGPGCheckPackageWithFile = __root.TDNFGPGCheckPackageWithFile;
    pub const TDNFFetchRemoteGPGKey = __root.TDNFFetchRemoteGPGKey;
    pub const TDNFGetHistoryCtx = __root.TDNFGetHistoryCtx;
    pub const TDNFRefreshSack = __root.TDNFRefreshSack;
    pub const TDNFGoal = __root.TDNFGoal;
    pub const TDNFGoalNoDeps = __root.TDNFGoalNoDeps;
    pub const TDNFHistoryGoal = __root.TDNFHistoryGoal;
    pub const TDNFSolv = __root.TDNFSolv;
    pub const TDNFAddUserInstall = __root.TDNFAddUserInstall;
    pub const TDNFMarkAutoInstalledSinglePkg = __root.TDNFMarkAutoInstalledSinglePkg;
    pub const TDNFMarkAutoInstalled = __root.TDNFMarkAutoInstalled;
    pub const TDNFAddGoal = __root.TDNFAddGoal;
    pub const TDNFPkgsToExclude = __root.TDNFPkgsToExclude;
    pub const TDNFGoalAddHiddenPackages = __root.TDNFGoalAddHiddenPackages;
    pub const TDNFReadConfig = __root.TDNFReadConfig;
    pub const TDNFConfigExpandVars = __root.TDNFConfigExpandVars;
    pub const TDNFConfigReplaceVars = __root.TDNFConfigReplaceVars;
    pub const TDNFInitRepo = __root.TDNFInitRepo;
    pub const TDNFGetGPGKeys = __root.TDNFGetGPGKeys;
    pub const TDNFGetRepoMD = __root.TDNFGetRepoMD;
    pub const TDNFDownloadMetadata = __root.TDNFDownloadMetadata;
    pub const TDNFLoadRepoData = __root.TDNFLoadRepoData;
    pub const TDNFRepoListFinalize = __root.TDNFRepoListFinalize;
    pub const TDNFPrepareAllPackages = __root.TDNFPrepareAllPackages;
    pub const TDNFResolveBuildDependencies = __root.TDNFResolveBuildDependencies;
    pub const TDNFRpmExecTransaction = __root.TDNFRpmExecTransaction;
    pub const TDNFRpmExecHistoryTransaction = __root.TDNFRpmExecHistoryTransaction;
    pub const TDNFGetSecuritySeverityOption = __root.TDNFGetSecuritySeverityOption;
    pub const TDNFGetUpdatePkgs = __root.TDNFGetUpdatePkgs;
    pub const TDNFGetRebootRequiredOption = __root.TDNFGetRebootRequiredOption;
    pub const TDNFGetSkipProblemOption = __root.TDNFGetSkipProblemOption;
    pub const TDNFLoadPlugins = __root.TDNFLoadPlugins;
    pub const BuiltinPluginsRepoConfig = __root.BuiltinPluginsRepoConfig;
    pub const BuiltinPluginsRepoMDDownloadStart = __root.BuiltinPluginsRepoMDDownloadStart;
    pub const BuiltinPluginsRepoMDDownloadEnd = __root.BuiltinPluginsRepoMDDownloadEnd;
    pub const TDNFFilterPackages = __root.TDNFFilterPackages;
    pub const TDNFGetAutoInstalledOrphans = __root.TDNFGetAutoInstalledOrphans;
    pub const TDNFPrepareSinglePkg = __root.TDNFPrepareSinglePkg;
    pub const TDNFResolveListPackages = __root.TDNFResolveListPackages;
    pub const TDNFResolveCollectCmdLineRpmPaths = __root.TDNFResolveCollectCmdLineRpmPaths;
};
pub const PTDNF = [*c]struct__TDNF_;
pub const struct__TDNF_PKG_CHANGELOG_ENTRY = extern struct {
    timeTime: time_t = 0,
    pszAuthor: [*c]u8 = null,
    pszText: [*c]u8 = null,
    pNext: [*c]struct__TDNF_PKG_CHANGELOG_ENTRY = null,
    pub const TDNFFreeChangeLogEntry = __root.TDNFFreeChangeLogEntry;
};
pub const TDNF_PKG_CHANGELOG_ENTRY = struct__TDNF_PKG_CHANGELOG_ENTRY;
pub const PTDNF_PKG_CHANGELOG_ENTRY = [*c]struct__TDNF_PKG_CHANGELOG_ENTRY;
pub const struct__TDNF_PKG_INFO = extern struct {
    dwEpoch: u32 = 0,
    dwInstallSizeBytes: u32 = 0,
    dwDownloadSizeBytes: u32 = 0,
    nChecksumType: c_int = 0,
    pszName: [*c]u8 = null,
    pszRepoName: [*c]u8 = null,
    pszVersion: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszSummary: [*c]u8 = null,
    pszURL: [*c]u8 = null,
    pszLicense: [*c]u8 = null,
    pszDescription: [*c]u8 = null,
    pszFormattedSize: [*c]u8 = null,
    pszFormattedDownloadSize: [*c]u8 = null,
    pszRelease: [*c]u8 = null,
    pszLocation: [*c]u8 = null,
    pppszDependencies: [*c][*c][*c]u8 = null,
    ppszFileList: [*c][*c]u8 = null,
    pszSourcePkg: [*c]u8 = null,
    pbChecksum: [*c]u8 = null,
    pChangeLogEntries: PTDNF_PKG_CHANGELOG_ENTRY = null,
    pNext: [*c]struct__TDNF_PKG_INFO = null,
    pub const TDNFFreePackageInfo = __root.TDNFFreePackageInfo;
    pub const TDNFFreePackageInfoArray = __root.TDNFFreePackageInfoArray;
    pub const TDNFNativeQuerySerializePackageInfoRefs = __root.TDNFNativeQuerySerializePackageInfoRefs;
    pub const TDNFFreePackageInfoContents = __root.TDNFFreePackageInfoContents;
};
pub const TDNF_PKG_INFO = struct__TDNF_PKG_INFO;
pub const PTDNF_PKG_INFO = [*c]struct__TDNF_PKG_INFO;
pub const struct__TDNF_SOLVED_PKG_INFO = extern struct {
    nNeedAction: c_int = 0,
    nNeedDownload: c_int = 0,
    nAlterType: TDNF_ALTERTYPE = @import("std").mem.zeroes(TDNF_ALTERTYPE),
    pPkgsNotAvailable: PTDNF_PKG_INFO = null,
    pPkgsExisting: PTDNF_PKG_INFO = null,
    pPkgsToInstall: PTDNF_PKG_INFO = null,
    pPkgsToDowngrade: PTDNF_PKG_INFO = null,
    pPkgsToUpgrade: PTDNF_PKG_INFO = null,
    pPkgsToRemove: PTDNF_PKG_INFO = null,
    pPkgsUnNeeded: PTDNF_PKG_INFO = null,
    pPkgsToReinstall: PTDNF_PKG_INFO = null,
    pPkgsObsoleted: PTDNF_PKG_INFO = null,
    pPkgsRemovedByDowngrade: PTDNF_PKG_INFO = null,
    ppszPkgsNotResolved: [*c][*c]u8 = null,
    ppszPkgsUserInstall: [*c][*c]u8 = null,
    pub const TDNFFreeSolvedPackageInfo = __root.TDNFFreeSolvedPackageInfo;
    pub const TDNFCheckDownloadCacheBytes = __root.TDNFCheckDownloadCacheBytes;
};
pub const TDNF_SOLVED_PKG_INFO = struct__TDNF_SOLVED_PKG_INFO;
pub const PTDNF_SOLVED_PKG_INFO = [*c]struct__TDNF_SOLVED_PKG_INFO;
pub const struct__TDNF_CMD_OPT = extern struct {
    pszOptName: [*c]u8 = null,
    pszOptValue: [*c]u8 = null,
    pNext: [*c]struct__TDNF_CMD_OPT = null,
    pub const TDNFFreeCmdOpt = __root.TDNFFreeCmdOpt;
};
pub const TDNF_CMD_OPT = struct__TDNF_CMD_OPT;
pub const PTDNF_CMD_OPT = [*c]struct__TDNF_CMD_OPT;
pub const TDNF_CMD_ARGS = struct__TDNF_CMD_ARGS;
pub const TDNF_CONF = struct__TDNF_CONF;
pub const TDNF_REPO_DATA = struct__TDNF_REPO_DATA;
pub const struct__TDNF_ERROR_DESC = extern struct {
    nCode: c_int = 0,
    pszName: [*c]const u8 = null,
    pszDesc: [*c]const u8 = null,
};
pub const TDNF_ERROR_DESC = struct__TDNF_ERROR_DESC;
pub const PTDNF_ERROR_DESC = [*c]struct__TDNF_ERROR_DESC;
pub const struct__TDNF_UPDATEINFO_REF = extern struct {
    pszID: [*c]u8 = null,
    pszLink: [*c]u8 = null,
    pszTitle: [*c]u8 = null,
    pszType: [*c]u8 = null,
    pNext: [*c]struct__TDNF_UPDATEINFO_REF = null,
};
pub const TDNF_UPDATEINFO_REF = struct__TDNF_UPDATEINFO_REF;
pub const PTDNF_UPDATEINFO_REF = [*c]struct__TDNF_UPDATEINFO_REF;
pub const struct__TDNF_UPDATEINFO_PKG = extern struct {
    pszName: [*c]u8 = null,
    pszFileName: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pNext: [*c]struct__TDNF_UPDATEINFO_PKG = null,
    pub const TDNFFreeUpdateInfoPackages = __root.TDNFFreeUpdateInfoPackages;
};
pub const TDNF_UPDATEINFO_PKG = struct__TDNF_UPDATEINFO_PKG;
pub const PTDNF_UPDATEINFO_PKG = [*c]struct__TDNF_UPDATEINFO_PKG;
pub const struct__TDNF_UPDATEINFO = extern struct {
    nType: c_int = 0,
    pszID: [*c]u8 = null,
    pszDate: [*c]u8 = null,
    pszDescription: [*c]u8 = null,
    nRebootRequired: c_int = 0,
    pReferences: PTDNF_UPDATEINFO_REF = null,
    pPackages: PTDNF_UPDATEINFO_PKG = null,
    pNext: [*c]struct__TDNF_UPDATEINFO = null,
    pub const TDNFFreeUpdateInfo = __root.TDNFFreeUpdateInfo;
};
pub const TDNF_UPDATEINFO = struct__TDNF_UPDATEINFO;
pub const PTDNF_UPDATEINFO = [*c]struct__TDNF_UPDATEINFO;
pub const struct__TDNF_UPDATEINFO_SUMMARY = extern struct {
    nCount: c_int = 0,
    nType: c_int = 0,
    pub const TDNFFreeUpdateInfoSummary = __root.TDNFFreeUpdateInfoSummary;
};
pub const TDNF_UPDATEINFO_SUMMARY = struct__TDNF_UPDATEINFO_SUMMARY;
pub const PTDNF_UPDATEINFO_SUMMARY = [*c]struct__TDNF_UPDATEINFO_SUMMARY;
pub const struct__TDNF_REPOSYNC_ARGS = extern struct {
    nDelete: c_int = 0,
    nDownloadMetadata: c_int = 0,
    nGPGCheck: c_int = 0,
    nNewestOnly: c_int = 0,
    nPrintUrlsOnly: c_int = 0,
    nNoRepoPath: c_int = 0,
    nSourceOnly: c_int = 0,
    pszDownloadPath: [*c]u8 = null,
    pszMetaDataPath: [*c]u8 = null,
    ppszArchs: [*c][*c]u8 = null,
};
pub const TDNF_REPOSYNC_ARGS = struct__TDNF_REPOSYNC_ARGS;
pub const PTDNF_REPOSYNC_ARGS = [*c]struct__TDNF_REPOSYNC_ARGS;
pub const REPOQUERY_WHAT_KEY_PROVIDES: c_int = 0;
pub const REPOQUERY_WHAT_KEY_OBSOLETES: c_int = 1;
pub const REPOQUERY_WHAT_KEY_CONFLICTS: c_int = 2;
pub const REPOQUERY_WHAT_KEY_REQUIRES: c_int = 3;
pub const REPOQUERY_WHAT_KEY_RECOMMENDS: c_int = 4;
pub const REPOQUERY_WHAT_KEY_SUGGESTS: c_int = 5;
pub const REPOQUERY_WHAT_KEY_SUPPLEMENTS: c_int = 6;
pub const REPOQUERY_WHAT_KEY_ENHANCES: c_int = 7;
pub const REPOQUERY_WHAT_KEY_DEPENDS: c_int = 8;
pub const REPOQUERY_WHAT_KEY_COUNT: c_int = 9;
pub const REPOQUERY_WHAT_KEY = c_uint;
pub const REPOQUERY_DEP_KEY_PROVIDES: c_int = 0;
pub const REPOQUERY_DEP_KEY_OBSOLETES: c_int = 1;
pub const REPOQUERY_DEP_KEY_CONFLICTS: c_int = 2;
pub const REPOQUERY_DEP_KEY_REQUIRES: c_int = 3;
pub const REPOQUERY_DEP_KEY_RECOMMENDS: c_int = 4;
pub const REPOQUERY_DEP_KEY_SUGGESTS: c_int = 5;
pub const REPOQUERY_DEP_KEY_SUPPLEMENTS: c_int = 6;
pub const REPOQUERY_DEP_KEY_ENHANCES: c_int = 7;
pub const REPOQUERY_DEP_KEY_DEPENDS: c_int = 8;
pub const REPOQUERY_DEP_KEY_REQUIRES_PRE: c_int = 9;
pub const REPOQUERY_DEP_KEY_COUNT: c_int = 10;
pub const REPOQUERY_DEP_KEY = c_uint;
pub const struct__TDNF_REPOQUERY_ARGS = extern struct {
    pszSpec: [*c]u8 = null,
    nAvailable: c_int = 0,
    nDuplicates: c_int = 0,
    nExtras: c_int = 0,
    nLocation: c_int = 0,
    nInstalled: c_int = 0,
    nUpgrades: c_int = 0,
    nDowngrades: c_int = 0,
    nUserInstalled: c_int = 0,
    pszFile: [*c]u8 = null,
    pppszWhatKeys: [*c][*c][*c]u8 = null,
    ppszArchs: [*c][*c]u8 = null,
    nChangeLogs: c_int = 0,
    depKeySet: c_uint = 0,
    nList: c_int = 0,
    pszQueryFormat: [*c]u8 = null,
    nSource: c_int = 0,
};
pub const TDNF_REPOQUERY_ARGS = struct__TDNF_REPOQUERY_ARGS;
pub const PTDNF_REPOQUERY_ARGS = [*c]struct__TDNF_REPOQUERY_ARGS;
pub const HISTORY_CMD_LIST: c_int = 0;
pub const HISTORY_CMD_INIT: c_int = 1;
pub const HISTORY_CMD_ROLLBACK: c_int = 2;
pub const HISTORY_CMD_UNDO: c_int = 3;
pub const HISTORY_CMD_REDO: c_int = 4;
pub const HISTORY_CMD_ID: c_int = 5;
pub const HISTORY_CMD = c_uint;
pub const struct__TDNF_HISTORY_ARGS = extern struct {
    nCommand: HISTORY_CMD = @import("std").mem.zeroes(HISTORY_CMD),
    nInfo: c_int = 0,
    nFrom: c_int = 0,
    nTo: c_int = 0,
    nReverse: c_int = 0,
    pszSpec: [*c]u8 = null,
};
pub const TDNF_HISTORY_ARGS = struct__TDNF_HISTORY_ARGS;
pub const PTDNF_HISTORY_ARGS = [*c]struct__TDNF_HISTORY_ARGS;
pub const struct__TDNF_HISTORY_INFO_ITEM = extern struct {
    nId: c_int = 0,
    nType: c_int = 0,
    pszCmdLine: [*c]u8 = null,
    timeStamp: time_t = 0,
    nAddedCount: c_int = 0,
    nRemovedCount: c_int = 0,
    ppszAddedPkgs: [*c][*c]u8 = null,
    ppszRemovedPkgs: [*c][*c]u8 = null,
    pub const TDNFFreeHistoryInfoItems = __root.TDNFFreeHistoryInfoItems;
};
pub const TDNF_HISTORY_INFO_ITEM = struct__TDNF_HISTORY_INFO_ITEM;
pub const PTDNF_HISTORY_INFO_ITEM = [*c]struct__TDNF_HISTORY_INFO_ITEM;
pub const struct__TDNF_HISTORY_INFO = extern struct {
    nItemCount: c_int = 0,
    pItems: PTDNF_HISTORY_INFO_ITEM = null,
    pub const TDNFFreeHistoryInfo = __root.TDNFFreeHistoryInfo;
};
pub const TDNF_HISTORY_INFO = struct__TDNF_HISTORY_INFO;
pub const PTDNF_HISTORY_INFO = [*c]struct__TDNF_HISTORY_INFO;
pub extern fn TDNFInit() u32;
pub extern fn TDNFOpenHandle(pArgs: PTDNF_CMD_ARGS, pTdnf: [*c]PTDNF) u32;
pub extern fn TDNFRefresh(pTdnf: PTDNF) u32;
pub extern fn TDNFCheckUpdates(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFClean(pTdnf: PTDNF, nCleanType: u32) u32;
pub extern fn TDNFList(pTdnf: PTDNF, nScope: TDNF_SCOPE, ppszPackageNameSpecs: [*c][*c]u8, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFInfo(pTdnf: PTDNF, nScope: TDNF_SCOPE, ppszPackageNameSpecs: [*c][*c]u8, ppPkgListInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoList(pTdnf: PTDNF, nFilter: TDNF_REPOLISTFILTER, ppRepoData: [*c]PTDNF_REPO_DATA) u32;
pub extern fn TDNFCheckPackages(pTdnf: PTDNF) u32;
pub extern fn TDNFCheckLocalPackages(pTdnf: PTDNF, pszLocalPath: [*c]const u8) u32;
pub extern fn TDNFProvides(pTdnf: PTDNF, pszSpec: [*c]const u8, ppPkgInfo: [*c]PTDNF_PKG_INFO) u32;
pub extern fn TDNFRepoSync(pTdnf: PTDNF, pReposyncArgs: PTDNF_REPOSYNC_ARGS) u32;
pub extern fn TDNFRepoQuery(pTdnf: PTDNF, pRepoqueryArgs: PTDNF_REPOQUERY_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFUpdateInfo(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppUpdateInfo: [*c]PTDNF_UPDATEINFO) u32;
pub extern fn TDNFUpdateInfoSummary(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppSummary: [*c]PTDNF_UPDATEINFO_SUMMARY) u32;
pub extern fn TDNFHistoryResolve(pTdnf: PTDNF, pHistoryArgs: PTDNF_HISTORY_ARGS, ppSolvedPkgInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFHistoryList(pTdnf: PTDNF, pHistoryArgs: PTDNF_HISTORY_ARGS, ppHistoryInfo: [*c]PTDNF_HISTORY_INFO) u32;
pub extern fn TDNFGetPackageUrls(pTdnf: PTDNF, pSolvedPkgInfo: PTDNF_SOLVED_PKG_INFO, pppszUrls: [*c][*c][*c]u8, pnCount: [*c]c_int) u32;
pub extern fn TDNFHistoryGetId(pTdnf: PTDNF, pnId: [*c]c_int) u32;
pub extern fn TDNFCountCommand(pTdnf: PTDNF, pdwCount: [*c]u32) u32;
pub extern fn TDNFGetVersion() [*c]const u8;
pub extern fn TDNFGetPackageName() [*c]const u8;
pub extern fn TDNFSearchCommand(pTdnf: PTDNF, pCmdArgs: PTDNF_CMD_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFResolve(pTdnf: PTDNF, nAlterType: TDNF_ALTERTYPE, ppSolvedPkgInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFTransactionPlanSetEnabled(pTdnf: PTDNF, dwEnabled: u32) u32;
pub extern fn TDNFTransactionPlanGetCanonicalJson(pTdnf: PTDNF, ppszJson: [*c][*c]u8) u32;
pub extern fn TDNFTransactionPlanFreeCanonicalJson(pszJson: [*c]u8) void;
pub extern fn TDNFTransactionPlanGetDigestHex(pTdnf: PTDNF, pszDigestHex: [*c]u8) u32;
pub extern fn TDNFAlterCommand(pTdnf: PTDNF, pSolvedInfo: PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFAlterHistoryCommand(pTdnf: PTDNF, pSolvedInfo: PTDNF_SOLVED_PKG_INFO, pHistoryArgs: PTDNF_HISTORY_ARGS) u32;
pub extern fn TDNFMark(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, dwValue: u32) u32;
pub extern fn TDNFGetErrorString(dwErrorCode: u32, ppszErrorString: [*c][*c]u8) u32;
pub extern fn TDNFCloseHandle(pTdnf: PTDNF) void;
pub extern fn TDNFFreeCmdArgs(pCmdArgs: PTDNF_CMD_ARGS) void;
pub extern fn TDNFFreePackageInfo(pPkgInfo: PTDNF_PKG_INFO) void;
pub extern fn TDNFFreePackageInfoArray(pPkgInfo: PTDNF_PKG_INFO, dwLength: u32) void;
pub extern fn TDNFFreeChangeLogEntry(pEntry: PTDNF_PKG_CHANGELOG_ENTRY) void;
pub extern fn TDNFFreeRepos(pRepos: PTDNF_REPO_DATA) void;
pub extern fn TDNFFreeSolvedPackageInfo(pSolvedPkgInfo: PTDNF_SOLVED_PKG_INFO) void;
pub extern fn TDNFFreeUpdateInfo(pUpdateInfo: PTDNF_UPDATEINFO) void;
pub extern fn TDNFFreeUpdateInfoSummary(pSummary: PTDNF_UPDATEINFO_SUMMARY) void;
pub extern fn TDNFFreeCmdOpt(pCmdOpt: PTDNF_CMD_OPT) void;
pub extern fn TDNFFreeHistoryInfo(pHistoryInfo: PTDNF_HISTORY_INFO) void;
pub extern fn TDNFUriIsRemote(pszKeyUrl: [*c]const u8, nRemote: [*c]c_int) u32;
pub extern fn TDNFPathFromUri(pszKeyUrl: [*c]const u8, ppszPath: [*c][*c]u8) u32;
pub extern fn TDNFUninit() void;
pub const TDNF_ZIG_XFERINFOFUNCTION = ?*const fn (pUserData: ?*anyopaque, nDownloadTotal: i64, nDownloadedNow: i64, nUploadTotal: i64, nUploadedNow: i64) callconv(.c) c_int;
pub const struct__TDNF_ZIG_DOWNLOAD_REQUEST = extern struct {
    pszUrl: [*c]const u8 = null,
    pszDestination: [*c]const u8 = null,
    pfnProgress: TDNF_ZIG_XFERINFOFUNCTION = null,
    pProgressData: ?*anyopaque = null,
    pszUserAgent: [*c]const u8 = null,
    pszProxy: [*c]const u8 = null,
    pszProxyUserPwd: [*c]const u8 = null,
    pszUserName: [*c]const u8 = null,
    pszPassword: [*c]const u8 = null,
    pszSSLCaCert: [*c]const u8 = null,
    pszSSLClientCert: [*c]const u8 = null,
    pszSSLClientKey: [*c]const u8 = null,
    nSSLVerify: c_int = 0,
    nConnectTimeout: c_long = 0,
    nTimeout: c_long = 0,
    nLowSpeedLimit: c_long = 0,
    nLowSpeedTime: c_long = 0,
    nMaxRecvSpeed: c_long = 0,
    pub const TDNFZigDownloadFile = __root.TDNFZigDownloadFile;
};
pub const TDNF_ZIG_DOWNLOAD_REQUEST = struct__TDNF_ZIG_DOWNLOAD_REQUEST;
pub extern fn TDNFZigDownloadFile(pRequest: [*c]const TDNF_ZIG_DOWNLOAD_REQUEST, pnResponseCode: [*c]c_long) u32;
pub extern fn TDNFZigDownloadLastError() [*c]const u8;
pub extern fn tdnf_rpm_config_last_error() [*c]const u8;
pub extern fn tdnf_rpm_config_create(pszInstallRoot: [*c]const u8) ?*tdnf_rpm_config;
pub extern fn tdnf_rpm_config_destroy(pConfig: ?*tdnf_rpm_config) void;
pub extern fn tdnf_rpm_config_apply_define(pConfig: ?*tdnf_rpm_config, pszDefinition: [*c]const u8) c_int;
pub extern fn tdnf_rpm_config_expand(pConfig: ?*const tdnf_rpm_config, pszName: [*c]const u8) [*c]u8;
pub extern fn tdnf_rpm_config_resolve_path(pConfig: ?*const tdnf_rpm_config, pszName: [*c]const u8) [*c]u8;
pub extern fn tdnf_rpm_config_string_free(pszValue: [*c]u8) void;
pub const struct_tdnf_repomd_doc = opaque {
    pub const TDNFRepoMdFree = __root.TDNFRepoMdFree;
    pub const TDNFRepoMdGetRevision = __root.TDNFRepoMdGetRevision;
    pub const TDNFRepoMdGetRecordCount = __root.TDNFRepoMdGetRecordCount;
    pub const TDNFRepoMdGetRecord = __root.TDNFRepoMdGetRecord;
};
pub const TDNF_REPOMD_DOC = struct_tdnf_repomd_doc;
pub const TDNF_REPOMD_RECORD_KIND_UNKNOWN: c_int = 0;
pub const TDNF_REPOMD_RECORD_KIND_PRIMARY: c_int = 1;
pub const TDNF_REPOMD_RECORD_KIND_FILELISTS: c_int = 2;
pub const TDNF_REPOMD_RECORD_KIND_OTHER: c_int = 3;
pub const TDNF_REPOMD_RECORD_KIND_UPDATEINFO: c_int = 4;
const enum_unnamed_12 = c_uint;
pub const struct__TDNF_REPOMD_CHECKSUM = extern struct {
    pszType: [*c]const u8 = null,
    pszValue: [*c]const u8 = null,
};
pub const TDNF_REPOMD_CHECKSUM = struct__TDNF_REPOMD_CHECKSUM;
pub const struct__TDNF_REPOMD_RECORD = extern struct {
    pszType: [*c]const u8 = null,
    dwKind: u32 = 0,
    pszLocationHref: [*c]const u8 = null,
    checksum: TDNF_REPOMD_CHECKSUM = @import("std").mem.zeroes(TDNF_REPOMD_CHECKSUM),
    openChecksum: TDNF_REPOMD_CHECKSUM = @import("std").mem.zeroes(TDNF_REPOMD_CHECKSUM),
    nTimestamp: u64 = 0,
    nSize: u64 = 0,
    nOpenSize: u64 = 0,
    nDatabaseVersion: u64 = 0,
    nHasTimestamp: c_int = 0,
    nHasSize: c_int = 0,
    nHasOpenSize: c_int = 0,
    nHasDatabaseVersion: c_int = 0,
};
pub const TDNF_REPOMD_RECORD = struct__TDNF_REPOMD_RECORD;
pub const struct__TDNF_REPOMD_NATIVE_REPO_INPUT = extern struct {
    pszId: [*c]const u8 = null,
    pszCacheDir: [*c]const u8 = null,
    pszSnapshotFile: [*c]const u8 = null,
    pszDirectory: [*c]const u8 = null,
    pub const TDNFRepoMdNativeList = __root.TDNFRepoMdNativeList;
    pub const TDNFRepoMdNativeSearch = __root.TDNFRepoMdNativeSearch;
    pub const TDNFRepoMdNativeProvides = __root.TDNFRepoMdNativeProvides;
    pub const TDNFRepoMdNativeRepoQuery = __root.TDNFRepoMdNativeRepoQuery;
    pub const TDNFRepoMdNativeUpdateAdvisoryIds = __root.TDNFRepoMdNativeUpdateAdvisoryIds;
    pub const TDNFRepoMdNativeFindNevraMatches = __root.TDNFRepoMdNativeFindNevraMatches;
    pub const TDNFRepoMdNativeFindNameEvrMatches = __root.TDNFRepoMdNativeFindNameEvrMatches;
    pub const TDNFRepoMdNativeUpdateInfoSummaryLines = __root.TDNFRepoMdNativeUpdateInfoSummaryLines;
    pub const TDNFRepoMdNativeUpdateInfoLines = __root.TDNFRepoMdNativeUpdateInfoLines;
    pub const TDNFRepoMdNativeMinVersionExcludeLines = __root.TDNFRepoMdNativeMinVersionExcludeLines;
    pub const TDNFRepoMdNativeDowngradeCandidateLines = __root.TDNFRepoMdNativeDowngradeCandidateLines;
    pub const TDNFRepoMdNativeRequiresForPackageRefs = __root.TDNFRepoMdNativeRequiresForPackageRefs;
    pub const TDNFRepoMdNativePackageInfoForRefs = __root.TDNFRepoMdNativePackageInfoForRefs;
    pub const TDNFRepoMdNativeListConfig = __root.TDNFRepoMdNativeListConfig;
    pub const TDNFRepoMdNativeSearchConfig = __root.TDNFRepoMdNativeSearchConfig;
    pub const TDNFRepoMdNativeProvidesConfig = __root.TDNFRepoMdNativeProvidesConfig;
    pub const TDNFRepoMdNativeRepoQueryConfig = __root.TDNFRepoMdNativeRepoQueryConfig;
    pub const TDNFRepoMdNativeFindNevraMatchesConfig = __root.TDNFRepoMdNativeFindNevraMatchesConfig;
    pub const TDNFRepoMdNativePackageRefLinesConfig = __root.TDNFRepoMdNativePackageRefLinesConfig;
    pub const TDNFRepoMdNativeBestPackageRefConfig = __root.TDNFRepoMdNativeBestPackageRefConfig;
    pub const TDNFRepoMdNativeUpdateInfoSummaryLinesConfig = __root.TDNFRepoMdNativeUpdateInfoSummaryLinesConfig;
    pub const TDNFRepoMdNativeUpdateInfoLinesConfig = __root.TDNFRepoMdNativeUpdateInfoLinesConfig;
    pub const TDNFRepoMdNativeMinVersionExcludeLinesConfig = __root.TDNFRepoMdNativeMinVersionExcludeLinesConfig;
    pub const TDNFRepoMdNativeExcludeLinesConfig = __root.TDNFRepoMdNativeExcludeLinesConfig;
    pub const TDNFRepoMdNativeRequiresForPackageRefsConfig = __root.TDNFRepoMdNativeRequiresForPackageRefsConfig;
    pub const TDNFRepoMdNativePackageInfoForRefsConfig = __root.TDNFRepoMdNativePackageInfoForRefsConfig;
    pub const TDNFNativeQueryFreeRepoInputs = __root.TDNFNativeQueryFreeRepoInputs;
};
pub const TDNF_REPOMD_NATIVE_REPO_INPUT = struct__TDNF_REPOMD_NATIVE_REPO_INPUT;
pub const PTDNF_REPOMD_NATIVE_REPO_INPUT = [*c]struct__TDNF_REPOMD_NATIVE_REPO_INPUT;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_INSTALL: c_int = 1;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_REINSTALL: c_int = 2;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_ERASE: c_int = 3;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_UPGRADE: c_int = 4;
const enum_unnamed_13 = c_uint;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM = extern struct {
    dwOperation: u32 = 0,
    pszPath: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszEVR: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pub const TDNFRepoMdNativeTransactionSolve = __root.TDNFRepoMdNativeTransactionSolve;
    pub const TDNFRepoMdNativeTransactionPlanSolve = __root.TDNFRepoMdNativeTransactionPlanSolve;
    pub const TDNFRepoMdNativeTransactionSolveConfig = __root.TDNFRepoMdNativeTransactionSolveConfig;
    pub const TDNFRepoMdNativeTransactionPlanSolveConfig = __root.TDNFRepoMdNativeTransactionPlanSolveConfig;
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM;
pub const PTDNF_REPOMD_NATIVE_TRANSACTION_ITEM = [*c]struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = extern struct {
    dwOperation: u32 = 0,
    pszPath: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszEVR: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    dwRpmDbHnum: u32 = 0,
    pub const TDNFRepoMdNativeTransactionSolveV2 = __root.TDNFRepoMdNativeTransactionSolveV2;
    pub const TDNFRepoMdNativeTransactionPlanSolveV2 = __root.TDNFRepoMdNativeTransactionPlanSolveV2;
    pub const TDNFRepoMdNativeTransactionSolveConfigV2 = __root.TDNFRepoMdNativeTransactionSolveConfigV2;
    pub const TDNFRepoMdNativeTransactionPlanSolveConfigV2 = __root.TDNFRepoMdNativeTransactionPlanSolveConfigV2;
    pub const tdnf_repomd_native_verified_transaction_solve_config = __root.tdnf_repomd_native_verified_transaction_solve_config;
    pub const config = __root.tdnf_repomd_native_verified_transaction_solve_config;
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2;
pub const PTDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = [*c]struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2;
pub const TDNF_REPOMD_NATIVE_PROBLEM_DEPENDENCY: c_int = 1;
pub const TDNF_REPOMD_NATIVE_PROBLEM_PRETRANS: c_int = 2;
pub const TDNF_REPOMD_NATIVE_PROBLEM_CONFLICT: c_int = 3;
pub const TDNF_REPOMD_NATIVE_PROBLEM_OBSOLETES: c_int = 4;
pub const TDNF_REPOMD_NATIVE_PROBLEM_FILE_CONFLICT: c_int = 5;
pub const TDNF_REPOMD_NATIVE_PROBLEM_UNSUPPORTED_MULTIPLE: c_int = 6;
pub const enum__TDNF_REPOMD_NATIVE_PROBLEM_TYPE = c_uint;
pub const TDNF_REPOMD_NATIVE_PROBLEM_TYPE = enum__TDNF_REPOMD_NATIVE_PROBLEM_TYPE;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = extern struct {
    nType: TDNF_REPOMD_NATIVE_PROBLEM_TYPE = @import("std").mem.zeroes(TDNF_REPOMD_NATIVE_PROBLEM_TYPE),
    dwInputIndex: u32 = 0,
    pszPackage: [*c]const u8 = null,
    pszRelatedPackage: [*c]const u8 = null,
    pszSubject: [*c]const u8 = null,
    dwCount: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = extern struct {
    dwPriorOffset: u32 = 0,
    dwPriorCount: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = extern struct {
    dwItemCount: u32 = 0,
    pdwOrderIndices: [*c]u32 = null,
    pItems: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = null,
    dwPriorHnumCount: u32 = 0,
    pdwPriorHnums: [*c]u32 = null,
    dwProblemCount: u32 = 0,
    pProblems: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = null,
    pub const TDNFRepoMdNativeTransactionPlanFree = __root.TDNFRepoMdNativeTransactionPlanFree;
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_INSTALL: c_int = 1;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_ERASE: c_int = 2;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_UPGRADE: c_int = 3;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_DOWNGRADE: c_int = 4;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_REINSTALL: c_int = 5;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_OBSOLETE: c_int = 6;
pub const enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_KIND = c_uint;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_KIND;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_USER: c_int = 1;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_DEPENDENCY: c_int = 2;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_WEAK_DEPENDENCY: c_int = 3;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_CLEANUP: c_int = 4;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_OBSOLETES: c_int = 5;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_INSTALL_ONLY: c_int = 6;
pub const TDNF_REPOMD_NATIVE_SOLVER_REASON_POLICY: c_int = 7;
pub const enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_REASON = c_uint;
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION_REASON = enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_REASON;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_UNSATISFIED_REQUIREMENT: c_int = 1;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_CONFLICT: c_int = 2;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_OBSOLETES: c_int = 3;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_NO_CANDIDATE: c_int = 4;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_NOT_INSTALLABLE: c_int = 5;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_PROTECTED_PACKAGE: c_int = 6;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_INSTALL_ONLY_LIMIT: c_int = 7;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_SAME_NAME: c_int = 8;
pub const enum__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_KIND = c_uint;
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_KIND;
pub const TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_INSTALLED: c_int = 1;
pub const TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_AVAILABLE: c_int = 2;
pub const TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_COMMAND_LINE: c_int = 3;
pub const enum__TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_KIND = c_uint;
pub const TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_KIND;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_NONE: c_int = 0;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_EQUAL: c_int = 1;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_LESS: c_int = 2;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_LESS_OR_EQUAL: c_int = 3;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_GREATER: c_int = 4;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON_GREATER_OR_EQUAL: c_int = 5;
pub const enum__TDNF_REPOMD_NATIVE_SOLVER_COMPARISON = c_uint;
pub const TDNF_REPOMD_NATIVE_SOLVER_COMPARISON = enum__TDNF_REPOMD_NATIVE_SOLVER_COMPARISON;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = extern struct {
    pszRepository: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pszChecksumType: [*c]const u8 = null,
    pszChecksumValue: [*c]const u8 = null,
    pszLocationHref: [*c]const u8 = null,
    pszLocationBase: [*c]const u8 = null,
    pszSummary: [*c]const u8 = null,
    nPackageSize: u64 = 0,
    nInstalledSize: u64 = 0,
    dwPackageId: u32 = 0,
    dwRepositoryId: u32 = 0,
    dwEpoch: u32 = 0,
    dwRpmDbHnum: u32 = 0,
    nRepositoryKind: c_int = 0,
    nHasEpoch: c_int = 0,
    nHasRpmDbHnum: c_int = 0,
    nChecksumIsPkgId: c_int = 0,
    nChecksumIsHeaderOnly: c_int = 0,
    nHasPackageSize: c_int = 0,
    nHasInstalledSize: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = struct__TDNF_REPOMD_NATIVE_SOLVER_PACKAGE;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_ACTION = extern struct {
    dwPackageRef: u32 = 0,
    dwKind: u32 = 0,
    dwReason: u32 = 0,
    dwPriorOffset: u32 = 0,
    dwPriorCount: u32 = 0,
    dwRequestedJobId: u32 = 0,
    nHasRequestedJobId: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION = struct__TDNF_REPOMD_NATIVE_SOLVER_ACTION;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_RELATION = extern struct {
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszFlags: [*c]const u8 = null,
    dwComparison: u32 = 0,
    dwEpoch: u32 = 0,
    dwSense: u32 = 0,
    nHasEpoch: c_int = 0,
    nPre: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_RELATION = struct__TDNF_REPOMD_NATIVE_SOLVER_RELATION;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = extern struct {
    capability: TDNF_REPOMD_NATIVE_SOLVER_RELATION = @import("std").mem.zeroes(TDNF_REPOMD_NATIVE_SOLVER_RELATION),
    dwKind: u32 = 0,
    dwPackageRef: u32 = 0,
    dwRelatedPackageRef: u32 = 0,
    dwJobId: u32 = 0,
    dwCount: u32 = 0,
    nHasPackageRef: c_int = 0,
    nHasRelatedPackageRef: c_int = 0,
    nHasCapability: c_int = 0,
    nHasJobId: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = struct__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_RESULT = extern struct {
    pPackages: [*c]TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = null,
    pdwSelectedPackageRefs: [*c]u32 = null,
    pActions: [*c]TDNF_REPOMD_NATIVE_SOLVER_ACTION = null,
    pdwPriorPackageRefs: [*c]u32 = null,
    pdwPriorHnums: [*c]u32 = null,
    pProblems: [*c]TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = null,
    pdwSkippedJobIds: [*c]u32 = null,
    dwPackageCount: u32 = 0,
    dwSelectedPackageCount: u32 = 0,
    dwActionCount: u32 = 0,
    dwPriorPackageRefCount: u32 = 0,
    dwProblemCount: u32 = 0,
    dwSkippedJobCount: u32 = 0,
    pub const TDNFRepoMdNativeSolverResultFree = __root.TDNFRepoMdNativeSolverResultFree;
};
pub const TDNF_REPOMD_NATIVE_SOLVER_RESULT = struct__TDNF_REPOMD_NATIVE_SOLVER_RESULT;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = extern struct {
    pszId: [*c]const u8 = null,
    pszCacheDir: [*c]const u8 = null,
    pszSnapshotFile: [*c]const u8 = null,
    pszDirectory: [*c]const u8 = null,
    nPriority: i32 = 0,
    dwCost: u32 = 0,
    pub const TDNFRepoMdNativeSolverLiveSolve = __root.TDNFRepoMdNativeSolverLiveSolve;
};
pub const TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16;
pub const PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = [*c]struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = extern struct {
    pszRepository: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pszChecksumType: [*c]const u8 = null,
    pszChecksumValue: [*c]const u8 = null,
    dwEpoch: u32 = 0,
    nChecksumIsPkgId: c_int = 0,
    dwQueuePair: u32 = 0,
    nHasQueuePair: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB;
pub const PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = [*c]struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB;
pub const TDNF_REPOMD_NATIVE_SOLVER_DEFAULT_REPOSITORY_COST: c_int = 1000;
const enum_unnamed_14 = c_uint;
pub extern fn TDNFRepoMdParseBuffer(buf: [*c]const u8, len: usize, ppDoc: [*c]?*TDNF_REPOMD_DOC) u32;
pub extern fn TDNFRepoMdParseFile(pszPath: [*c]const u8, ppDoc: [*c]?*TDNF_REPOMD_DOC) u32;
pub extern fn TDNFRepoMdLastError() [*c]const u8;
pub extern fn TDNFRepoMdCalculateCookieForFile(pszFilePath: [*c]const u8, pszCookie: [*c]u8) u32;
pub extern fn TDNFRepoMdCreateRepoCacheName(pszName: [*c]const u8, pszUrl: [*c]const u8, ppszCacheName: [*c][*c]u8) u32;
pub extern fn TDNFRepoMdFree(pDoc: ?*TDNF_REPOMD_DOC) void;
pub extern fn TDNFRepoMdGetRevision(pDoc: ?*const TDNF_REPOMD_DOC) [*c]const u8;
pub extern fn TDNFRepoMdGetRecordCount(pDoc: ?*const TDNF_REPOMD_DOC) u32;
pub extern fn TDNFRepoMdGetRecord(pDoc: ?*const TDNF_REPOMD_DOC, dwIndex: u32) [*c]const TDNF_REPOMD_RECORD;
pub extern fn TDNFRepoMdNativeLastError() [*c]const u8;
pub extern fn TDNFRepoMdNativeQueryLastError() [*c]const u8;
pub extern fn TDNFRepoMdNativeTransactionLastError() [*c]const u8;
pub extern fn TDNFRepoMdNativeLoadSolvRepo(pRepo: ?*Repo, pszRepomd: [*c]const u8, pszPrimary: [*c]const u8, pszFilelists: [*c]const u8, pszUpdateinfo: [*c]const u8, pszOther: [*c]const u8) u32;
pub extern fn TDNFRepoMdNativeLoadInstalledSolvRepo(pRepo: ?*Repo, pszRootDir: [*c]const u8, nFlags: c_int) u32;
pub extern fn TDNFRepoMdNativeLoadInstalledSolvRepoConfig(pRepo: ?*Repo, pConfig: ?*const tdnf_rpm_config, nFlags: c_int) u32;
pub extern fn TDNFRepoMdNativeAddRpm(pRepo: ?*Repo, pszPath: [*c]const u8, nFlags: c_int, pdwSolvableId: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeList(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, nScope: c_int, ppszPackageNameSpecs: [*c][*c]u8, nDetail: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeSearch(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszSearchStrings: [*c][*c]u8, nStartIndex: c_int, nEndIndex: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, punCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeProvides(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, pszSpec: [*c]const u8, ppPkgInfo: [*c]PTDNF_PKG_INFO) u32;
pub extern fn TDNFRepoMdNativeTransactionSolve(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM, dwItemCount: u32, pszInstallRoot: [*c]const u8, pppszOrderLines: [*c][*c][*c]u8, pdwOrderCount: [*c]u32, pppszProblemLines: [*c][*c][*c]u8, pdwProblemCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeTransactionSolveV2(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, dwItemCount: u32, pszInstallRoot: [*c]const u8, pppszOrderLines: [*c][*c][*c]u8, pdwOrderCount: [*c]u32, pppszProblemLines: [*c][*c][*c]u8, pdwProblemCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanSolve(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM, dwItemCount: u32, pszInstallRoot: [*c]const u8, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanSolveV2(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, dwItemCount: u32, pszInstallRoot: [*c]const u8, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanFree(pPlan: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) void;
pub extern fn TDNFRepoMdNativeSolverResultFree(pResult: [*c]TDNF_REPOMD_NATIVE_SOLVER_RESULT) void;
pub extern fn TDNFRepoMdNativeSolverLiveSolve(pRepositories: [*c]const TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16, dwRepositoryCount: u32, pJobs: [*c]const TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB, dwJobCount: u32, pEraseJobs: [*c]const TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB, dwEraseJobCount: u32, pHiddenAvailable: [*c]const TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB, dwHiddenAvailableCount: u32, nAllDeps: c_int, nBest: c_int, nCleanDeps: c_int, nSkipBroken: c_int, nAllowErasing: c_int, nUpdateAll: c_int, nDistSyncAll: c_int, ppszLockedPackages: [*c]const [*c]const u8, pdwLockedQueuePairs: [*c]const u32, dwGlobalQueuePair: u32, nHasGlobalQueuePair: c_int, ppszInstallOnlyPackages: [*c]const [*c]const u8, dwInstallOnlyLimit: u32, ppszProtectedPackages: [*c]const [*c]const u8, ppszUserInstalledPackages: [*c]const [*c]const u8, pdwUserInstalledQueuePairs: [*c]const u32, ppszCmdLineRpmPaths: [*c]const [*c]const u8, nReInstall: c_int, pRpmConfig: ?*const tdnf_rpm_config, pszNativeArch: [*c]const u8, nPrepareOnly: c_int, nRefuteUnsat: c_int, ppSolved: [*c]PTDNF_SOLVED_PKG_INFO, ppHandle: [*c]?*anyopaque) u32;
pub extern fn TDNFRepoMdNativeSolverLiveSolveRelease(pHandle: ?*anyopaque) void;
pub extern fn TDNFRepoMdNativeSolverCheckLocal(pszDirectory: [*c]const u8, pszNativeArch: [*c]const u8, pdwPackageCount: [*c]u32, ppHandle: [*c]?*anyopaque, ppszErrorPath: [*c][*c]const u8) u32;
pub extern fn TDNFRepoMdNativeSolverRefutedProblemCount(pHandle: ?*anyopaque, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeSolverRefutedProblem(pHandle: ?*anyopaque, dwIndex: u32, dwSkipMask: u32, pdwReported: [*c]u32, ppszMessage: [*c][*c]const u8) u32;
pub extern fn TDNFRepoMdNativeRepoQuery(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, pRepoqueryArgs: [*c]const TDNF_REPOQUERY_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeUpdateAdvisoryIds(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszName: [*c]const u8, pszArch: [*c]const u8, pszEvr: [*c]const u8, pppszAdvisoryIds: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeFindNevraMatches(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, pszNevra: [*c]const u8, nInstalled: c_int, pppszMatches: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeFindNameEvrMatches(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszNameEvr: [*c]const u8, pppszMatches: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeUpdateInfoSummaryLines(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszPackageNameSpecs: [*c][*c]u8, dwSecurity: u32, pszSeverity: [*c]const u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeUpdateInfoLines(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszPackageNameSpecs: [*c][*c]u8, dwSecurity: u32, pszSeverity: [*c]const u8, dwRebootRequired: u32, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeMinVersionExcludeLines(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszMinVersions: [*c][*c]u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeDowngradeCandidateLines(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszMinVersions: [*c][*c]u8, pszInstalledRepoNevra: [*c]const u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeRequiresForPackageRefs(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszPackageRefs: [*c][*c]u8, pppszDeps: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativePackageInfoForRefs(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pszInstallRoot: [*c]const u8, ppszPackageRefs: [*c][*c]u8, nDetail: c_int, nQueryFormat: c_int, dwDependencyMask: u32, nFileList: c_int, nChecksum: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeRequiresForCmdLineRpmPaths(ppszCmdLineRpmPaths: [*c]const [*c]const u8, dwPathCount: u32, pppszDeps: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeCompareEvr(pszLeftEvr: [*c]const u8, pszRightEvr: [*c]const u8, pnResult: [*c]c_int) u32;
pub extern fn TDNFRepoMdNativeAutoInstalledOrphanLines(pszInstallRoot: [*c]const u8, ppszAutoInstalledRefs: [*c][*c]u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeListConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, nScope: c_int, ppszPackageNameSpecs: [*c][*c]u8, nDetail: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeSearchConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszSearchStrings: [*c][*c]u8, nStartIndex: c_int, nEndIndex: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, punCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeProvidesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, pszSpec: [*c]const u8, ppPkgInfo: [*c]PTDNF_PKG_INFO) u32;
pub extern fn TDNFRepoMdNativeTransactionSolveConfig(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM, dwItemCount: u32, pConfig: ?*const tdnf_rpm_config, pppszOrderLines: [*c][*c][*c]u8, pdwOrderCount: [*c]u32, pppszProblemLines: [*c][*c][*c]u8, pdwProblemCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeTransactionSolveConfigV2(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, dwItemCount: u32, pConfig: ?*const tdnf_rpm_config, pppszOrderLines: [*c][*c][*c]u8, pdwOrderCount: [*c]u32, pppszProblemLines: [*c][*c][*c]u8, pdwProblemCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanSolveConfig(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM, dwItemCount: u32, pConfig: ?*const tdnf_rpm_config, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanSolveConfigV2(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, dwItemCount: u32, pConfig: ?*const tdnf_rpm_config, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRepoMdNativeRepoQueryConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, pRepoqueryArgs: [*c]const TDNF_REPOQUERY_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeFindNevraMatchesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, pszNevra: [*c]const u8, nInstalled: c_int, pppszMatches: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativePackageRefLinesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, nScope: c_int, pszSpec: [*c]const u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeBestPackageRefConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, nScope: c_int, pszSpec: [*c]const u8, nSourceOnly: c_int, nHighest: c_int, ppszLine: [*c][*c]u8) u32;
pub extern fn TDNFRepoMdNativeUpdateInfoSummaryLinesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszPackageNameSpecs: [*c][*c]u8, dwSecurity: u32, pszSeverity: [*c]const u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeUpdateInfoLinesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszPackageNameSpecs: [*c][*c]u8, dwSecurity: u32, pszSeverity: [*c]const u8, dwRebootRequired: u32, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeMinVersionExcludeLinesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszMinVersions: [*c][*c]u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeExcludeLinesConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszExcludes: [*c][*c]u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeRequiresForPackageRefsConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszPackageRefs: [*c][*c]u8, pppszDeps: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativePackageInfoForRefsConfig(pRepos: [*c]const TDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32, pConfig: ?*const tdnf_rpm_config, ppszPackageRefs: [*c][*c]u8, nDetail: c_int, nQueryFormat: c_int, dwDependencyMask: u32, nFileList: c_int, nChecksum: c_int, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeAutoInstalledOrphanLinesConfig(pConfig: ?*const tdnf_rpm_config, ppszAutoInstalledRefs: [*c][*c]u8, pppszLines: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub const struct_tdnf_rpm_file = opaque {
    pub const tdnf_rpm_file_close = __root.tdnf_rpm_file_close;
    pub const tdnf_rpm_file_nevra = __root.tdnf_rpm_file_nevra;
    pub const tdnf_rpm_file_package_kind = __root.tdnf_rpm_file_package_kind;
    pub const tdnf_rpm_file_get_metadata = __root.tdnf_rpm_file_get_metadata;
    pub const tdnf_rpm_file_main_header_blob = __root.tdnf_rpm_file_main_header_blob;
    pub const tdnf_rpm_file_bytes = __root.tdnf_rpm_file_bytes;
    pub const tdnf_rpm_file_digest = __root.tdnf_rpm_file_digest;
    pub const tdnf_rpm_file_compressor = __root.tdnf_rpm_file_compressor;
    pub const tdnf_rpm_file_payload_offset = __root.tdnf_rpm_file_payload_offset;
    pub const tdnf_rpm_file_is_signed = __root.tdnf_rpm_file_is_signed;
    pub const tdnf_rpm_file_signature_kind = __root.tdnf_rpm_file_signature_kind;
    pub const tdnf_rpm_file_verify_digests = __root.tdnf_rpm_file_verify_digests;
    pub const tdnf_rpm_file_verify_signatures_config = __root.tdnf_rpm_file_verify_signatures_config;
    pub const tdnf_rpm_file_decompress_payload = __root.tdnf_rpm_file_decompress_payload;
    pub const tdnf_rpm_file_extract_source_config = __root.tdnf_rpm_file_extract_source_config;
    pub const tdnf_rpm_file_install = __root.tdnf_rpm_file_install;
    pub const tdnf_rpm_file_files_open = __root.tdnf_rpm_file_files_open;
    pub const tdnf_rpm_file_signed_range = __root.tdnf_rpm_file_signed_range;
    pub const nevra = __root.tdnf_rpm_file_nevra;
    pub const package_kind = __root.tdnf_rpm_file_package_kind;
    pub const get_metadata = __root.tdnf_rpm_file_get_metadata;
    pub const main_header_blob = __root.tdnf_rpm_file_main_header_blob;
    pub const bytes = __root.tdnf_rpm_file_bytes;
    pub const digest = __root.tdnf_rpm_file_digest;
    pub const compressor = __root.tdnf_rpm_file_compressor;
    pub const payload_offset = __root.tdnf_rpm_file_payload_offset;
    pub const is_signed = __root.tdnf_rpm_file_is_signed;
    pub const signature_kind = __root.tdnf_rpm_file_signature_kind;
    pub const verify_digests = __root.tdnf_rpm_file_verify_digests;
    pub const verify_signatures_config = __root.tdnf_rpm_file_verify_signatures_config;
    pub const decompress_payload = __root.tdnf_rpm_file_decompress_payload;
    pub const extract_source_config = __root.tdnf_rpm_file_extract_source_config;
    pub const install = __root.tdnf_rpm_file_install;
    pub const files_open = __root.tdnf_rpm_file_files_open;
    pub const signed_range = __root.tdnf_rpm_file_signed_range;
};
pub const tdnf_rpm_file = struct_tdnf_rpm_file;
pub extern fn tdnf_rpmdb_count_packages(root: [*c]const u8) i64;
pub extern fn tdnf_rpmdb_count_packages_config(config: ?*const tdnf_rpm_config) i64;
pub extern fn tdnf_rpmdb_last_error() [*c]const u8;
pub extern fn tdnf_rpm_config_install_root(config: ?*const tdnf_rpm_config) [*c]u8;
pub extern fn tdnf_rpm_config_open_root_fd(config: ?*const tdnf_rpm_config) c_int;
pub extern fn tdnf_rpmdb_cookie(root: [*c]const u8) [*c]u8;
pub extern fn tdnf_rpmdb_cookie_config(config: ?*const tdnf_rpm_config) [*c]u8;
pub const struct_tdnf_rpmdb_iter = opaque {
    pub const tdnf_rpmdb_iter_close = __root.tdnf_rpmdb_iter_close;
    pub const tdnf_rpmdb_iter_next_nevra = __root.tdnf_rpmdb_iter_next_nevra;
    pub const tdnf_rpmdb_iter_next_header_blob = __root.tdnf_rpmdb_iter_next_header_blob;
    pub const tdnf_rpmdb_iter_next_header_blob_hnum = __root.tdnf_rpmdb_iter_next_header_blob_hnum;
    pub const next_nevra = __root.tdnf_rpmdb_iter_next_nevra;
    pub const next_header_blob = __root.tdnf_rpmdb_iter_next_header_blob;
    pub const next_header_blob_hnum = __root.tdnf_rpmdb_iter_next_header_blob_hnum;
};
pub const tdnf_rpmdb_iter = struct_tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_open(root: [*c]const u8) ?*tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_open_config(config: ?*const tdnf_rpm_config) ?*tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_close(it: ?*tdnf_rpmdb_iter) void;
pub extern fn tdnf_rpmdb_iter_next_nevra(it: ?*tdnf_rpmdb_iter, nevra_out: [*c][*c]u8) c_int;
pub extern fn tdnf_rpmdb_iter_next_header_blob(it: ?*tdnf_rpmdb_iter, blob_out: [*c][*c]const u8, blob_len_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_iter_next_header_blob_hnum(it: ?*tdnf_rpmdb_iter, hnum_out: [*c]u32, blob_out: [*c][*c]const u8, blob_len_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_string_free(s: [*c]u8) void;
pub extern fn tdnf_rpmdb_resolve_provider_version_config(config: ?*const tdnf_rpm_config, provide_name: [*c]const u8, version_out: [*c][*c]u8) c_int;
pub extern fn tdnf_rpmdb_write_install(root: [*c]const u8, rpm_path: [*c]const u8, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_install_config(config: ?*const tdnf_rpm_config, rpm_path: [*c]const u8, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_install_file_config(config: ?*const tdnf_rpm_config, fh: ?*tdnf_rpm_file, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_replace(root: [*c]const u8, old_hnum: u32, rpm_path: [*c]const u8, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, new_hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_replace_config(config: ?*const tdnf_rpm_config, old_hnum: u32, rpm_path: [*c]const u8, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, new_hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_replace_file_config(config: ?*const tdnf_rpm_config, old_hnum: u32, fh: ?*tdnf_rpm_file, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, new_hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_erase_hnum(root: [*c]const u8, hnum: u32) c_int;
pub extern fn tdnf_rpmdb_write_erase_hnum_config(config: ?*const tdnf_rpm_config, hnum: u32) c_int;
pub extern fn tdnf_rpmdb_find_hnum_by_nevra(root: [*c]const u8, nevra: [*c]const u8, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_find_hnum_by_nevra_config(config: ?*const tdnf_rpm_config, nevra: [*c]const u8, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_find_hnums_by_name(root: [*c]const u8, name: [*c]const u8, hnums_out: [*c][*c]u32, count_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_find_hnums_by_name_config(config: ?*const tdnf_rpm_config, name: [*c]const u8, hnums_out: [*c][*c]u32, count_out: [*c]usize) c_int;
pub const struct_tdnf_rpmdb_label_match = extern struct {
    hnum: u32 = 0,
    name: [*c]u8 = null,
    evr: [*c]u8 = null,
    arch: [*c]u8 = null,
    pub const tdnf_rpmdb_label_matches_free = __root.tdnf_rpmdb_label_matches_free;
};
pub const tdnf_rpmdb_label_match = struct_tdnf_rpmdb_label_match;
pub extern fn tdnf_rpmdb_find_label_matches_config(config: ?*const tdnf_rpm_config, name: [*c]const u8, evr: [*c]const u8, matches_out: [*c][*c]tdnf_rpmdb_label_match, count_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_label_matches_free(matches: [*c]tdnf_rpmdb_label_match, count: usize) void;
pub extern fn tdnf_rpmdb_hnums_free(hnums: [*c]u32) void;
pub extern fn tdnf_rpmdb_read_header_blob(root: [*c]const u8, hnum: u32, blob_out: [*c][*c]u8, len_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_read_header_blob_config(config: ?*const tdnf_rpm_config, hnum: u32, blob_out: [*c][*c]u8, len_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_blob_free(blob: [*c]u8) void;
pub const struct_tdnf_rpmdb_pubkeys_iter = opaque {
    pub const tdnf_rpmdb_pubkeys_close = __root.tdnf_rpmdb_pubkeys_close;
    pub const tdnf_rpmdb_pubkeys_next = __root.tdnf_rpmdb_pubkeys_next;
    pub const next = __root.tdnf_rpmdb_pubkeys_next;
};
pub const tdnf_rpmdb_pubkeys_iter = struct_tdnf_rpmdb_pubkeys_iter;
pub extern fn tdnf_rpmdb_import_pubkeys(root: [*c]const u8, data: ?*const anyopaque, len: usize, imported_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_import_pubkeys_config(config: ?*const tdnf_rpm_config, data: ?*const anyopaque, len: usize, imported_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_pubkeys_open(root: [*c]const u8) ?*tdnf_rpmdb_pubkeys_iter;
pub extern fn tdnf_rpmdb_pubkeys_open_config(config: ?*const tdnf_rpm_config) ?*tdnf_rpmdb_pubkeys_iter;
pub extern fn tdnf_rpmdb_pubkeys_close(it: ?*tdnf_rpmdb_pubkeys_iter) void;
pub extern fn tdnf_rpmdb_pubkeys_next(it: ?*tdnf_rpmdb_pubkeys_iter, key_out: [*c][*c]u8, key_len_out: [*c]usize, keyid_out: [*c][*c]u8) c_int;
pub extern fn tdnf_rpm_file_open(path: [*c]const u8) ?*tdnf_rpm_file;
pub extern fn tdnf_rpm_file_close(fh: ?*tdnf_rpm_file) void;
pub extern fn tdnf_rpm_file_nevra(fh: ?*tdnf_rpm_file) [*c]u8;
pub const TDNF_RPM_PACKAGE_KIND_BINARY: c_int = 0;
pub const TDNF_RPM_PACKAGE_KIND_SOURCE: c_int = 1;
pub const TDNF_RPM_PACKAGE_KIND_NOSRC: c_int = 2;
const enum_unnamed_15 = c_uint;
pub extern fn tdnf_rpm_file_package_kind(fh: ?*tdnf_rpm_file) c_int;
pub const struct_tdnf_rpm_file_metadata = extern struct {
    name: [*c]const u8 = null,
    version: [*c]const u8 = null,
    release: [*c]const u8 = null,
    arch: [*c]const u8 = null,
    epoch: u32 = 0,
    has_epoch: c_int = 0,
    package_kind: c_int = 0,
    main_header_blob: [*c]const u8 = null,
    main_header_blob_len: usize = 0,
};
pub const tdnf_rpm_file_metadata = struct_tdnf_rpm_file_metadata;
pub const struct_tdnf_rpm_header_view = extern struct {
    blob: [*c]const u8 = null,
    len: usize = 0,
};
pub const tdnf_rpm_header_view = struct_tdnf_rpm_header_view;
pub extern fn tdnf_rpm_header_name_equals(header_blob: [*c]const u8, header_len: usize, name: [*c]const u8) c_int;
pub extern fn tdnf_rpm_header_owns_path(header_blob: [*c]const u8, header_len: usize, path: [*c]const u8) c_int;
pub extern fn tdnf_rpm_canonical_path_config(config: ?*const tdnf_rpm_config, path: [*c]const u8, output: [*c]u8, output_len: usize) c_int;
pub extern fn tdnf_rpm_header_owns_path_config(header_blob: [*c]const u8, header_len: usize, path: [*c]const u8, config: ?*const tdnf_rpm_config) c_int;
pub extern fn tdnf_rpm_file_get_metadata(fh: ?*tdnf_rpm_file, metadata_out: [*c]tdnf_rpm_file_metadata) c_int;
pub extern fn tdnf_rpm_file_main_header_blob(fh: ?*tdnf_rpm_file, out: [*c][*c]const u8, out_len: [*c]usize) c_int;
pub extern fn tdnf_rpm_file_bytes(fh: ?*tdnf_rpm_file, out: [*c][*c]const u8, out_len: [*c]usize) c_int;
pub extern fn tdnf_rpm_file_digest(fh: ?*tdnf_rpm_file, kind: c_int, out_digest: [*c]u8, out_len: usize) c_int;
pub extern fn tdnf_rpm_file_compressor(fh: ?*tdnf_rpm_file) [*c]const u8;
pub extern fn tdnf_rpm_file_payload_offset(fh: ?*tdnf_rpm_file) i64;
pub extern fn tdnf_rpm_file_is_signed(fh: ?*tdnf_rpm_file) c_int;
pub extern fn tdnf_rpm_file_signature_kind(fh: ?*tdnf_rpm_file) [*c]const u8;
pub const TDNF_RPMZIG_INTEGRITY_OK: c_int = 0;
pub const TDNF_RPMZIG_INTEGRITY_MISSING: c_int = 1;
pub const TDNF_RPMZIG_INTEGRITY_BAD: c_int = 2;
pub const TDNF_RPMZIG_INTEGRITY_UNSUPPORTED: c_int = 3;
pub const TDNF_RPMZIG_INTEGRITY_MALFORMED: c_int = 4;
pub const TDNF_RPMZIG_INTEGRITY_INTERNAL: c_int = 5;
const enum_unnamed_16 = c_uint;
pub extern fn tdnf_rpm_file_verify_digests(fh: ?*tdnf_rpm_file, outcome_out: [*c]c_int) c_int;
pub extern fn tdnf_rpm_file_verify_signatures_config(fh: ?*tdnf_rpm_file, config: ?*const tdnf_rpm_config, fresh_key_blobs: [*c]const ?*const anyopaque, fresh_key_lens: [*c]const usize, fresh_key_count: usize, outcome_out: [*c]c_int) c_int;
pub extern fn tdnf_rpm_file_decompress_payload(fh: ?*tdnf_rpm_file, out: [*c][*c]u8, out_size: [*c]usize) c_int;
pub extern fn tdnf_rpm_file_extract_source_config(fh: ?*tdnf_rpm_file, config: ?*const tdnf_rpm_config, trans_flags: u32) c_int;
pub const TDNF_RPM_INSTALL_KIND_INSTALL: c_int = 0;
pub const TDNF_RPM_INSTALL_KIND_UPGRADE: c_int = 1;
pub const TDNF_RPM_INSTALL_KIND_REINSTALL: c_int = 2;
pub const enum_tdnf_rpm_install_kind = c_uint;
pub const tdnf_rpm_install_kind = enum_tdnf_rpm_install_kind;
pub const struct_tdnf_rpm_install_prior_header = extern struct {
    blob: [*c]const u8 = null,
    len: usize = 0,
};
pub const tdnf_rpm_install_prior_header = struct_tdnf_rpm_install_prior_header;
pub const tdnf_rpm_install_conflict_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const tdnf_rpm_changed_path_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const struct_tdnf_rpm_install_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    trans_flags: u32 = 0,
    install_kind: tdnf_rpm_install_kind = @import("std").mem.zeroes(tdnf_rpm_install_kind),
    prior_headers: [*c]const tdnf_rpm_install_prior_header = null,
    prior_header_count: usize = 0,
    conflict_fn: tdnf_rpm_install_conflict_fn = null,
    conflict_fn_data: ?*anyopaque = null,
    changed_path_fn: tdnf_rpm_changed_path_fn = null,
    changed_path_fn_data: ?*anyopaque = null,
};
pub const tdnf_rpm_install_options = struct_tdnf_rpm_install_options;
pub extern fn tdnf_rpm_file_install(fh: ?*tdnf_rpm_file, options: [*c]const tdnf_rpm_install_options) c_int;
pub const TDNF_RPM_SCRIPTLET_PHASE_PRE: c_int = 0;
pub const TDNF_RPM_SCRIPTLET_PHASE_POST: c_int = 1;
pub const TDNF_RPM_SCRIPTLET_PHASE_PREUN: c_int = 2;
pub const TDNF_RPM_SCRIPTLET_PHASE_POSTUN: c_int = 3;
pub const TDNF_RPM_SCRIPTLET_PHASE_PRETRANS: c_int = 4;
pub const TDNF_RPM_SCRIPTLET_PHASE_POSTTRANS: c_int = 5;
pub const enum_tdnf_rpm_scriptlet_phase = c_uint;
pub const tdnf_rpm_scriptlet_phase = enum_tdnf_rpm_scriptlet_phase;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_NOT_RUN: c_int = 0;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_OK: c_int = 1;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_EXITED: c_int = 2;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_SIGNALED: c_int = 3;
pub const enum_tdnf_rpm_scriptlet_outcome = c_uint;
pub const tdnf_rpm_scriptlet_outcome = enum_tdnf_rpm_scriptlet_outcome;
pub const struct_tdnf_rpm_scriptlet_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    arg1: c_int = 0,
    arg2: c_int = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
};
pub const tdnf_rpm_scriptlet_options = struct_tdnf_rpm_scriptlet_options;
pub const struct_tdnf_rpm_scriptlet_result = extern struct {
    ran: c_int = 0,
    critical: c_int = 0,
    outcome: tdnf_rpm_scriptlet_outcome = @import("std").mem.zeroes(tdnf_rpm_scriptlet_outcome),
    exit_status: c_int = 0,
    signal_number: c_int = 0,
};
pub const tdnf_rpm_scriptlet_result = struct_tdnf_rpm_scriptlet_result;
pub extern fn tdnf_rpm_header_run_scriptlet(header_blob: [*c]const u8, header_len: usize, phase: tdnf_rpm_scriptlet_phase, options: [*c]const tdnf_rpm_scriptlet_options, result_out: [*c]tdnf_rpm_scriptlet_result) c_int;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERIN: c_int = 0;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERUN: c_int = 1;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN: c_int = 2;
pub const enum_tdnf_rpm_trigger_phase = c_uint;
pub const tdnf_rpm_trigger_phase = enum_tdnf_rpm_trigger_phase;
pub const struct_tdnf_rpm_trigger_options = extern struct {
    db_root: [*c]const u8 = null,
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
    arg2_override_present: c_int = 0,
    arg2_override_value: c_int = 0,
    transaction_headers: [*c]const tdnf_rpm_header_view = null,
    transaction_header_count: usize = 0,
    transaction_view_present: c_int = 0,
    trigger_owner_headers: [*c]const tdnf_rpm_header_view = null,
    trigger_owner_header_count: usize = 0,
    trigger_owner_view_present: c_int = 0,
};
pub const tdnf_rpm_trigger_options = struct_tdnf_rpm_trigger_options;
pub const struct_tdnf_rpm_trigger_result = extern struct {
    ran: c_int = 0,
    critical: c_int = 0,
    outcome: tdnf_rpm_scriptlet_outcome = @import("std").mem.zeroes(tdnf_rpm_scriptlet_outcome),
    exit_status: c_int = 0,
    signal_number: c_int = 0,
};
pub const tdnf_rpm_trigger_result = struct_tdnf_rpm_trigger_result;
pub extern fn tdnf_rpm_header_run_triggers(header_blob: [*c]const u8, header_len: usize, phase: tdnf_rpm_trigger_phase, options: [*c]const tdnf_rpm_trigger_options, result_out: [*c]tdnf_rpm_trigger_result) c_int;
pub const TDNF_RPM_FILE_TRIGGER_KIND_PACKAGE: c_int = 0;
pub const TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION: c_int = 1;
pub const enum_tdnf_rpm_file_trigger_kind = c_uint;
pub const tdnf_rpm_file_trigger_kind = enum_tdnf_rpm_file_trigger_kind;
pub const TDNF_RPM_TRIGGER_PRIORITY_ALL: c_int = 0;
pub const TDNF_RPM_TRIGGER_PRIORITY_HIGH: c_int = 1;
pub const TDNF_RPM_TRIGGER_PRIORITY_LOW: c_int = 2;
pub const enum_tdnf_rpm_trigger_priority_class = c_uint;
pub const tdnf_rpm_trigger_priority_class = enum_tdnf_rpm_trigger_priority_class;
pub const struct_tdnf_rpm_trigger_path = extern struct {
    path: [*c]const u8 = null,
    source_header_blob: [*c]const u8 = null,
    source_header_len: usize = 0,
};
pub const tdnf_rpm_trigger_path = struct_tdnf_rpm_trigger_path;
pub const struct_tdnf_rpm_file_trigger_owner = extern struct {
    header_blob: [*c]const u8 = null,
    header_len: usize = 0,
    paths: [*c]const tdnf_rpm_trigger_path = null,
    path_count: usize = 0,
    order: u64 = 0,
    pub const tdnf_rpm_run_file_triggers = __root.tdnf_rpm_run_file_triggers;
    pub const triggers = __root.tdnf_rpm_run_file_triggers;
};
pub const tdnf_rpm_file_trigger_owner = struct_tdnf_rpm_file_trigger_owner;
pub const struct_tdnf_rpm_file_trigger_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
    suppress_stdin: c_int = 0,
};
pub const tdnf_rpm_file_trigger_options = struct_tdnf_rpm_file_trigger_options;
pub extern fn tdnf_rpm_header_validate_trigger_metadata(header_blob: [*c]const u8, header_len: usize) c_int;
pub extern fn tdnf_rpm_header_validate_trigger_scripts_config(header_blob: [*c]const u8, header_len: usize, config: ?*const tdnf_rpm_config) c_int;
pub extern fn tdnf_rpm_header_has_file_trigger_metadata(header_blob: [*c]const u8, header_len: usize, kind: tdnf_rpm_file_trigger_kind) c_int;
pub extern fn tdnf_rpm_header_foreach_trigger_file(header_blob: [*c]const u8, header_len: usize, trans_flags: u32, callback: tdnf_rpm_changed_path_fn, callback_data: ?*anyopaque) c_int;
pub extern fn tdnf_rpm_run_file_triggers(owners: [*c]const tdnf_rpm_file_trigger_owner, owner_count: usize, phase: tdnf_rpm_trigger_phase, kind: tdnf_rpm_file_trigger_kind, priority_class: tdnf_rpm_trigger_priority_class, options: [*c]const tdnf_rpm_file_trigger_options, result_out: [*c]tdnf_rpm_trigger_result) c_int;
pub const tdnf_rpm_erase_keep_path_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const struct_tdnf_rpm_erase_options = extern struct {
    config: ?*const tdnf_rpm_config = null,
    trans_flags: u32 = 0,
    keep_path_fn: tdnf_rpm_erase_keep_path_fn = null,
    keep_path_fn_data: ?*anyopaque = null,
};
pub const tdnf_rpm_erase_options = struct_tdnf_rpm_erase_options;
pub extern fn tdnf_rpm_erase_hnum(root: [*c]const u8, hnum: u32, options: [*c]const tdnf_rpm_erase_options) c_int;
pub extern fn tdnf_rpm_erase_header_blob(root: [*c]const u8, blob: [*c]const u8, blob_len: usize, options: [*c]const tdnf_rpm_erase_options) c_int;
pub const struct_tdnf_rpm_files_iter = opaque {
    pub const tdnf_rpm_file_files_close = __root.tdnf_rpm_file_files_close;
    pub const tdnf_rpm_file_files_next = __root.tdnf_rpm_file_files_next;
    pub const next = __root.tdnf_rpm_file_files_next;
};
pub const tdnf_rpm_files_iter = struct_tdnf_rpm_files_iter;
pub extern fn tdnf_rpm_file_files_open(fh: ?*tdnf_rpm_file) ?*tdnf_rpm_files_iter;
pub extern fn tdnf_rpm_file_files_close(it: ?*tdnf_rpm_files_iter) void;
pub extern fn tdnf_rpm_file_files_next(it: ?*tdnf_rpm_files_iter, name_out: [*c][*c]const u8, mode_out: [*c]u32) c_int;
pub extern fn tdnf_rpm_file_signed_range(fh: ?*tdnf_rpm_file, sig_out: [*c][*c]const u8, sig_len_out: [*c]usize, signed_out: [*c][*c]const u8, signed_len_out: [*c]usize) c_int;
pub extern fn TDNFRepoRemoveCacheDir(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRepoRemoveCache(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveRpmCache(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveLastRefreshMarker(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveMirrorList(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveSnapshot(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveTmpRepodata(pszTmpRepodataDir: [*c]const u8) u32;
pub extern fn TDNFRemoveSolvCache(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFRemoveKeysCache(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA) u32;
pub extern fn TDNFGetCachePath(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszSubDir: [*c]const u8, pszFileName: [*c]const u8, ppszPath: [*c][*c]u8) u32;
pub extern fn RepoutilsGetRpmCachePath(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, ppszPath: [*c][*c]u8) u32;
pub extern fn TDNFFindRepoById(pTdnf: PTDNF, pszRepo: [*c]const u8, ppRepo: [*c]PTDNF_REPO_DATA) u32;
pub extern fn TDNFTouchFile(pszFile: [*c]const u8) u32;
pub extern fn TDNFShouldSyncMetadata(pszRepoDataFolder: [*c]const u8, lMetadataExpire: c_long, pnShouldSync: [*c]c_int) u32;
pub extern fn TDNFDownloadFileFromRepo(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszLocation: [*c]const u8, pszFile: [*c]const u8, pszProgressData: [*c]const u8) u32;
pub extern fn TDNFDownloadFile(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszFileUrl: [*c]const u8, pszFile: [*c]const u8, pszProgressData: [*c]const u8, nRequireHttps: c_int) u32;
pub extern fn TDNFCreatePackageUrl(pRepo: PTDNF_REPO_DATA, pszPackageLocation: [*c]const u8, ppszPackageUrl: [*c][*c]u8) u32;
pub extern fn TDNFDownloadPackageToCache(pTdnf: PTDNF, pszPackageLocation: [*c]const u8, pszPkgName: [*c]const u8, pRepo: PTDNF_REPO_DATA, ppszFilePath: [*c][*c]u8) u32;
pub extern fn TDNFDownloadPackageToTree(pTdnf: PTDNF, pszPackageLocation: [*c]const u8, pszPkgName: [*c]const u8, pRepo: PTDNF_REPO_DATA, pszNormalRpmCacheDir: [*c]u8, ppszFilePath: [*c][*c]u8) u32;
pub extern fn TDNFDownloadPackageToDirectory(pTdnf: PTDNF, pszPackageLocation: [*c]const u8, pszPkgName: [*c]const u8, pRepo: PTDNF_REPO_DATA, pszDirectory: [*c]const u8, ppszFilePath: [*c][*c]u8) u32;
pub extern fn TDNFIsFileOrSymlink(pszPath: [*c]const u8, pnPathIsFile: [*c]c_int) u32;
pub extern fn TDNFGetFileSize(pszPath: [*c]const u8, pnSize: [*c]c_int) u32;
pub extern fn TDNFIsGlob(pszString: [*c]const u8) c_int;
pub extern fn TDNFUtilsMakeDir(pszPath: [*c]const u8) u32;
pub extern fn TDNFUtilsMakeDirs(pszPath: [*c]const u8) u32;
pub extern fn TDNFGetReleaseVersion(pszRootDir: [*c]const u8, pszDistroVerPkg: [*c]const u8, ppszVersion: [*c][*c]u8) u32;
pub extern fn TdnfGetReleaseVersionConfig(pRpmConfig: ?*const tdnf_rpm_config, pszDistroVerPkg: [*c]const u8, ppszVersion: [*c][*c]u8) u32;
pub extern fn TDNFGetKernelArch(ppszArch: [*c][*c]u8) u32;
pub extern fn TDNFParseMetadataExpire(pszMetadataExpire: [*c]const u8, plMetadataExpire: [*c]c_long) u32;
pub extern fn TDNFAppendPath(pszBase: [*c]const u8, pszPart: [*c]const u8, ppszPath: [*c][*c]u8) u32;
pub extern fn TDNFFreeHistoryInfoItems(pHistoryItems: PTDNF_HISTORY_INFO_ITEM, nCount: c_int) void;
pub const struct__TDNF_ID_LIST = extern struct {
    pnElements: [*c]i32 = null,
    dwCount: u32 = 0,
    dwCapacity: u32 = 0,
    pub const TDNFIdListInit = __root.TDNFIdListInit;
    pub const TDNFIdListFree = __root.TDNFIdListFree;
    pub const TDNFIdListEmpty = __root.TDNFIdListEmpty;
    pub const TDNFIdListPush = __root.TDNFIdListPush;
    pub const TDNFIdListPush2 = __root.TDNFIdListPush2;
    pub const TDNFIdListPushUnique = __root.TDNFIdListPushUnique;
};
pub const TDNF_ID_LIST = struct__TDNF_ID_LIST;
pub const PTDNF_ID_LIST = [*c]struct__TDNF_ID_LIST;
pub const TDNF_PACKAGE_CONTEXT = struct__TDNF_PACKAGE_CONTEXT;
pub const struct__TDNF_PKG_FIELDS = extern struct {
    pszName: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pszEvr: [*c]const u8 = null,
    pszRepo: [*c]const u8 = null,
};
pub const TDNF_PKG_FIELDS = struct__TDNF_PKG_FIELDS;
pub const PTDNF_PKG_FIELDS = [*c]struct__TDNF_PKG_FIELDS;
pub extern fn TDNFPackageContextCreate(pszCacheDir: [*c]const u8, pszRootDir: [*c]const u8, pszArch: [*c]const u8, pRpmConfig: ?*const tdnf_rpm_config, nIncludeInstalled: c_int, ppContext: [*c]PTDNF_PACKAGE_CONTEXT) u32;
pub extern fn TDNFPackageContextFree(pContext: PTDNF_PACKAGE_CONTEXT) void;
pub extern fn TDNFPackageContextCacheDir(pContext: ?*const TDNF_PACKAGE_CONTEXT) [*c]const u8;
pub extern fn TDNFPackageContextRootDir(pContext: ?*const TDNF_PACKAGE_CONTEXT) [*c]const u8;
pub extern fn TDNFPackageContextInitCommandLine(pContext: PTDNF_PACKAGE_CONTEXT, ppRepository: [*c]PTDNF_REPOSITORY_CONTEXT) u32;
pub extern fn TDNFPackageContextResetCommandLine(pContext: PTDNF_PACKAGE_CONTEXT, ppRepository: [*c]PTDNF_REPOSITORY_CONTEXT) u32;
pub extern fn TDNFPackageContextAddRpm(pContext: PTDNF_PACKAGE_CONTEXT, pRepository: PTDNF_REPOSITORY_CONTEXT, pszPath: [*c]const u8, pdwPkgId: [*c]u32) u32;
pub extern fn TDNFPackageContextGetFields(pContext: PTDNF_PACKAGE_CONTEXT, dwPkgId: TDNF_PKG_ID, pFields: PTDNF_PKG_FIELDS) u32;
pub extern fn TDNFPackageContextGetRepoNevra(pContext: PTDNF_PACKAGE_CONTEXT, dwPkgId: TDNF_PKG_ID, ppszRepo: [*c][*c]const u8, ppszNevra: [*c][*c]u8) u32;
pub extern fn TDNFPackageContextGetInstalledPkgIds(pContext: PTDNF_PACKAGE_CONTEXT, pIdList: PTDNF_ID_LIST) u32;
pub extern fn TDNFPackageContextGetAllPkgIds(pContext: PTDNF_PACKAGE_CONTEXT, pIdList: PTDNF_ID_LIST) u32;
pub extern fn TDNFPackageContextGetRepoDataList(pContext: PTDNF_PACKAGE_CONTEXT, pppRepoData: [*c][*c]PTDNF_REPO_DATA, pdwCount: [*c]u32) u32;
pub const struct_TDNF_TRANSACTION_PLAN_CAPTURE_OWNER = opaque {
    pub const TDNFTransactionPlanCaptureDestroy = __root.TDNFTransactionPlanCaptureDestroy;
};
pub const TDNF_TRANSACTION_PLAN_CAPTURE_OWNER = struct_TDNF_TRANSACTION_PLAN_CAPTURE_OWNER;
pub const struct__TDNF_REPO_METADATA = extern struct {
    pszRepoCacheDir: [*c]u8 = null,
    pszRepo: [*c]u8 = null,
    pszRepoMD: [*c]u8 = null,
    pszPrimary: [*c]u8 = null,
    pszFileLists: [*c]u8 = null,
    pszUpdateInfo: [*c]u8 = null,
    pszOther: [*c]u8 = null,
    pub const TDNFFreeRepoMetadata = __root.TDNFFreeRepoMetadata;
};
pub const struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER = opaque {
    pub const TDNFTransactionPlanRequestTraceCaptureFactsDestroy = __root.TDNFTransactionPlanRequestTraceCaptureFactsDestroy;
};
pub const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER = struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER;
pub extern fn TDNFTransactionPlanCaptureCreate(input: [*c]const transaction_plan_abi.Capture, owner: [*c]?*TDNF_TRANSACTION_PLAN_CAPTURE_OWNER) u32;
pub extern fn TDNFTransactionPlanCaptureDestroy(owner: ?*TDNF_TRANSACTION_PLAN_CAPTURE_OWNER) void;
pub extern fn TDNFTransactionPlanStateSetEnabled(state: [*c]?*TDNF_TRANSACTION_PLAN_STATE, enabled: u32) u32;
pub extern fn TDNFTransactionPlanStateIsEnabled(state: ?*const TDNF_TRANSACTION_PLAN_STATE) u32;
pub extern fn TDNFTransactionPlanInitRepository(input: [*c]const transaction_plan_abi.RepositoryInitInput, loaded_repo: [*c]?*anyopaque) u32;
pub extern fn TDNFTransactionPlanInitCommandLineRepository(sack: ?*anyopaque, command_line_repository_slot: [*c]?*anyopaque) u32;
pub extern fn TDNFTransactionPlanReloadRepository(input: [*c]const transaction_plan_abi.RepositoryInitInput, loaded_repo: [*c]?*anyopaque) u32;
pub extern fn TDNFTransactionPlanRefreshSack(input: [*c]const transaction_plan_abi.RepositoryRefreshInput, clean_metadata: c_int) u32;
pub extern fn TDNFTransactionPlanStateRecordRepository(state: [*c]?*TDNF_TRANSACTION_PLAN_STATE, repository: ?*anyopaque, cookie_sha256: [*c]const u8, include_filelists: u32, include_updateinfo: u32, include_other: u32) u32;
pub extern fn TDNFTransactionPlanStateRepositoryRecordCount(state: ?*const TDNF_TRANSACTION_PLAN_STATE, repository: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanStateFailNextRepositoryRecord(state: ?*TDNF_TRANSACTION_PLAN_STATE) void;
pub extern fn TDNFTransactionPlanStateFailNextCapture(state: ?*TDNF_TRANSACTION_PLAN_STATE) void;
pub extern fn TDNFTransactionPlanStateFailNextCaptureIntegrity(state: ?*TDNF_TRANSACTION_PLAN_STATE) void;
pub extern fn TDNFTransactionPlanTestWriteFileProvider(rpm_config: ?*const anyopaque) c_int;
pub extern fn TDNFTransactionPlanStateClear(state: ?*TDNF_TRANSACTION_PLAN_STATE) void;
pub extern fn TDNFTransactionPlanStatePublish(state: ?*TDNF_TRANSACTION_PLAN_STATE) u32;
pub extern fn TDNFTransactionPlanStateHasPendingProblem(state: ?*const TDNF_TRANSACTION_PLAN_STATE) u32;
pub extern fn TDNFTransactionPlanStatePublishProblem(state: ?*TDNF_TRANSACTION_PLAN_STATE) u32;
pub extern fn TDNFTransactionPlanStateDestroy(state: ?*TDNF_TRANSACTION_PLAN_STATE) void;
pub extern fn TDNFTransactionPlanStateGetCanonicalJson(state: ?*const TDNF_TRANSACTION_PLAN_STATE, data: [*c][*c]const u8, length: [*c]usize) u32;
pub extern fn TDNFTransactionPlanStateFreeCanonicalJson(data: [*c]const u8, length: usize) void;
pub extern fn TDNFTransactionPlanIntegrationCapturePending(state: ?*TDNF_TRANSACTION_PLAN_STATE, pool: ?*anyopaque, native_solve: ?*const anyopaque, trace: [*c]const transaction_plan_abi.RequestTraceView, problems_accepted: u32, unresolved_count: u32, terminal_problem_kind: u32, repositories: [*c]const transaction_plan_abi.IntegrationRepository, repository_count: u32, environment: [*c]const transaction_plan_abi.IntegrationEnvironment) u32;
pub extern fn TDNFTransactionPlanCaptureSetEnabled(tdnf_handle: ?*anyopaque, enabled: u32) u32;
pub extern fn TDNFTransactionPlanCaptureGetCanonicalJson(tdnf_handle: ?*anyopaque, data: [*c][*c]const u8, length: [*c]usize) u32;
pub extern fn TDNFTransactionPlanCaptureFailNextRepositoryRecord(tdnf_handle: ?*anyopaque) void;
pub extern fn TDNFTransactionPlanCaptureFailNextComposition(tdnf_handle: ?*anyopaque) void;
pub extern fn TDNFTransactionPlanCaptureFailNextIntegrity(tdnf_handle: ?*anyopaque) void;
pub extern fn TDNFTransactionPlanTestFailNextReload(tdnf_handle: ?*anyopaque, stage: u32) void;
pub extern fn TDNFTransactionPlanTestPoolIdentity(tdnf_handle: ?*anyopaque) usize;
pub extern fn TDNFTransactionPlanTestPoolSolvableCount(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestPoolRepoCount(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestVisibleSolvableCount(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestSackSolvableCount(sack: ?*anyopaque, count: [*c]u32) u32;
pub extern fn TDNFTransactionPlanTestRepoDataCount(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestRetireNullSack(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestPublicInitRepo(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestReloadRepo(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestInitRepoInSack(tdnf_handle: ?*anyopaque, sack: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestRepoIdentity(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) usize;
pub extern fn TDNFTransactionPlanTestRepoId(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestRepoPackageCount(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestRepoBindingCount(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestRepoRecordCount(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFTransactionPlanTestRepoRecordDigest(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8, digest: [*c]u8) u32;
pub extern fn TDNFTransactionPlanTestInitRepoValidation(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestPoolIndexesHealthy(tdnf_handle: ?*anyopaque) u32;
pub extern fn TDNFTransactionPlanTestEnableRepo(tdnf_handle: ?*anyopaque, repo_id: [*c]const u8) u32;
pub extern fn TDNFHistoryGoalWithUnresolved(tdnf_handle: ?*anyopaque, install_queue: ?*anyopaque, erase_queue: ?*anyopaque, unresolved_count: u32, solved_info: ?*anyopaque) u32;
pub extern fn TDNFInitRepoWithResult(tdnf_handle: ?*anyopaque, repo_data: ?*anyopaque, sack: ?*anyopaque, loaded_repo: [*c]?*anyopaque) u32;
pub extern fn TDNFTransactionPlanRequestTraceCreate(alter_type: u32, subjects: [*c]const [*c]const u8, subject_count: u32) ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE;
pub extern fn TDNFTransactionPlanRequestTraceCreateHistory() ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE;
pub extern fn TDNFTransactionPlanRequestTraceDestroy(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordGoalRange(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, ids: [*c]const i32, start: u32, end: u32, alter_type: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordHistoryGoal(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, subject: [*c]const u8, request_kind: u32, action: u32, ids: [*c]const i32, start: u32, end: u32, outcome: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordRequestOutcome(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, request_ref: u32, outcome: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceCommitGoal(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, selection_id: i32, alter_type: u32, queue: [*c]const i32, start: u32, end: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordPackageJob(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue_pair_index: u32, action: u32, selection_id: i32, raw_how: i32, raw_flags: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordPackageJobRange(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue: [*c]const i32, start: u32, end: u32, action: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordNameJob(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue_pair_index: u32, action: u32, selection_name: [*c]const u8, raw_how: i32, raw_flags: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordAllJob(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue_pair_index: u32, action: u32, raw_how: i32, raw_flags: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordCapabilityJob(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue_pair_index: u32, action: u32, capability: [*c]const transaction_plan_abi.Capability, raw_how: i32, raw_flags: u32, reason: u32, request_ref: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceRecordPolicies(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, excludes: [*c]const [*c]const u8, installonly_names: [*c]const [*c]const u8, locked_names: [*c]const [*c]const u8, min_versions: [*c]const [*c]const u8, protected_names: [*c]const [*c]const u8, allow_erasing: u32) void;
pub extern fn TDNFTransactionPlanRequestTraceFinalize(trace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE, queue: [*c]const i32, element_count: u32, clean_deps_mask: i32, force_best_mask: i32) void;
pub extern fn TDNFTransactionPlanRequestTraceGetView(trace: ?*const TDNF_TRANSACTION_PLAN_REQUEST_TRACE) [*c]const transaction_plan_abi.RequestTraceView;
pub extern fn TDNFTransactionPlanRequestTraceGetError(trace: ?*const TDNF_TRANSACTION_PLAN_REQUEST_TRACE) u32;
pub extern fn TDNFTransactionPlanRequestTraceTestFailNextCreate() void;
pub extern fn TDNFTransactionPlanRequestTraceTestFailNextRecord() void;
pub extern fn TDNFTransactionPlanRequestTraceCaptureFactsCreate(trace: ?*const TDNF_TRANSACTION_PLAN_REQUEST_TRACE, package_refs: [*c]const transaction_plan_abi.RequestTracePackageRef, package_ref_count: u32, facts: [*c][*c]const transaction_plan_abi.RequestTraceCaptureFacts, owner: [*c]?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER) u32;
pub extern fn TDNFTransactionPlanRequestTraceCaptureFactsDestroy(owner: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER) void;
pub const TDNF_PLUGIN = struct__TDNF_PLUGIN_;
pub const TDNF = struct__TDNF_;
pub const struct__TDNF_CACHED_RPM_ENTRY = extern struct {
    pszFilePath: [*c]u8 = null,
    pNext: [*c]struct__TDNF_CACHED_RPM_ENTRY = null,
};
pub const TDNF_CACHED_RPM_ENTRY = struct__TDNF_CACHED_RPM_ENTRY;
pub const PTDNF_CACHED_RPM_ENTRY = [*c]struct__TDNF_CACHED_RPM_ENTRY;
pub const struct__TDNF_CACHED_RPM_LIST = extern struct {
    nSize: c_int = 0,
    pHead: PTDNF_CACHED_RPM_ENTRY = null,
};
pub const TDNF_CACHED_RPM_LIST = struct__TDNF_CACHED_RPM_LIST;
pub const PTDNF_CACHED_RPM_LIST = [*c]struct__TDNF_CACHED_RPM_LIST;
pub const TDNF_RPM_TS_ITEM_INSTALL: c_int = 1;
pub const TDNF_RPM_TS_ITEM_UPGRADE: c_int = 2;
pub const TDNF_RPM_TS_ITEM_REINSTALL: c_int = 3;
pub const TDNF_RPM_TS_ITEM_ERASE: c_int = 4;
pub const TDNF_RPM_TS_ITEM_TYPE = c_uint;
pub const struct__TDNF_RPM_TS_ITEM = extern struct {
    nType: TDNF_RPM_TS_ITEM_TYPE = @import("std").mem.zeroes(TDNF_RPM_TS_ITEM_TYPE),
    pRpmFile: ?*tdnf_rpm_file = null,
    dwRpmDbHnum: u32 = 0,
    nPackageKind: c_int = 0,
    pszPath: [*c]u8 = null,
    pszName: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pNext: [*c]struct__TDNF_RPM_TS_ITEM = null,
};
pub const TDNF_RPM_TS_ITEM = struct__TDNF_RPM_TS_ITEM;
pub const PTDNF_RPM_TS_ITEM = [*c]struct__TDNF_RPM_TS_ITEM;
pub const struct__TDNF_RPM_TS_ = extern struct {
    nQuiet: c_int = 0,
    nTransFlags: TDNF_RPMTRANS_FLAGS = 0,
    pCachedRpmsArray: PTDNF_CACHED_RPM_LIST = null,
    dwTransactionItemCount: u32 = 0,
    pTransactionItems: PTDNF_RPM_TS_ITEM = null,
    pTransactionItemsTail: PTDNF_RPM_TS_ITEM = null,
    pNativePlan: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = null,
};
pub const TDNFRPMTS = struct__TDNF_RPM_TS_;
pub const PTDNFRPMTS = [*c]struct__TDNF_RPM_TS_;
pub const TDNF_REPO_METADATA = struct__TDNF_REPO_METADATA;
pub const PTDNF_REPO_METADATA = [*c]struct__TDNF_REPO_METADATA;
pub const struct_progress_cb_data = extern struct {
    cur_time: time_t = 0,
    prev_time: time_t = 0,
    pszData: [64]u8 = @import("std").mem.zeroes([64]u8),
};
pub const pcb_data = struct_progress_cb_data;
pub extern fn create_cnfnode(name: [*c]const u8) [*c]struct_cnfnode;
pub extern fn create_cnfnode_keyval(keyval: [*c]const u8) [*c]struct_cnfnode;
pub extern fn clone_cnfnode(cn: [*c]const struct_cnfnode) [*c]struct_cnfnode;
pub extern fn clone_cnftree(cn_root: [*c]const struct_cnfnode) [*c]struct_cnfnode;
pub extern fn cnfnode_getval(cn: [*c]const struct_cnfnode) [*c]const u8;
pub extern fn cnfnode_getname(cn: [*c]const struct_cnfnode) [*c]const u8;
pub extern fn cnfnode_setval(cn: [*c]struct_cnfnode, value: [*c]const u8) void;
pub extern fn cnfnode_setname(cn: [*c]struct_cnfnode, name: [*c]const u8) void;
pub extern fn cnfnode_setname_n(cn: [*c]struct_cnfnode, name: [*c]const u8, n: usize) void;
pub extern fn destroy_cnfnode(cn: [*c]struct_cnfnode) void;
pub extern fn destroy_cnftree(cn: [*c]struct_cnfnode) void;
pub extern fn append_node(cn_parent: [*c]struct_cnfnode, cn: [*c]struct_cnfnode) void;
pub extern fn insert_node_before(cn_before: [*c]struct_cnfnode, cn: [*c]struct_cnfnode) void;
pub extern fn unlink_node(cn: [*c]struct_cnfnode) void;
pub extern fn find_node(cn_list: [*c]struct_cnfnode, name: [*c]const u8) [*c]struct_cnfnode;
pub extern fn compare_cnfnode(cn1: [*c]const struct_cnfnode, cn2: [*c]const struct_cnfnode) c_int;
pub extern fn compare_cnftree(cn_root1: [*c]const struct_cnfnode, cn_root2: [*c]const struct_cnfnode) c_int;
pub extern fn compare_cnftree_children(cn_root1: [*c]const struct_cnfnode, cn_root2: [*c]const struct_cnfnode) c_int;
pub extern fn dump_nodes(cn_root: [*c]struct_cnfnode, level: c_int) void;
pub const struct_history_ctx = opaque {
    pub const destroy_history_ctx = __root.destroy_history_ctx;
    pub const history_get_current_transaction_id = __root.history_get_current_transaction_id;
    pub const history_sync = __root.history_sync;
    pub const history_sync_config = __root.history_sync_config;
    pub const history_nevra_from_id = __root.history_nevra_from_id;
    pub const history_nevra_map = __root.history_nevra_map;
    pub const history_get_delta = __root.history_get_delta;
    pub const history_get_delta_range = __root.history_get_delta_range;
    pub const history_add_transaction = __root.history_add_transaction;
    pub const history_record_state = __root.history_record_state;
    pub const history_update_state = __root.history_update_state;
    pub const history_update_state_config = __root.history_update_state_config;
    pub const history_get_transactions = __root.history_get_transactions;
    pub const history_set_auto_flag = __root.history_set_auto_flag;
    pub const history_get_auto_flag = __root.history_get_auto_flag;
    pub const history_restore_auto_flags = __root.history_restore_auto_flags;
    pub const history_replay_auto_flags = __root.history_replay_auto_flags;
    pub const history_get_flags_delta = __root.history_get_flags_delta;
    pub const ctx = __root.destroy_history_ctx;
    pub const id = __root.history_get_current_transaction_id;
    pub const config = __root.history_sync_config;
    pub const map = __root.history_nevra_map;
    pub const delta = __root.history_get_delta;
    pub const range = __root.history_get_delta_range;
    pub const transaction = __root.history_add_transaction;
    pub const state = __root.history_record_state;
    pub const transactions = __root.history_get_transactions;
    pub const flag = __root.history_set_auto_flag;
    pub const flags = __root.history_restore_auto_flags;
};
pub extern fn TDNFNativeQueryBuildRepoInputs(pTdnf: PTDNF, ppRepos: [*c]PTDNF_REPOMD_NATIVE_REPO_INPUT, pdwRepoCount: [*c]u32) u32;
pub extern fn TDNFNativeQueryBuildSingleRepoInput(pTdnf: PTDNF, pRepoData: PTDNF_REPO_DATA, pRepo: [*c]TDNF_REPOMD_NATIVE_REPO_INPUT) u32;
pub extern fn TDNFNativeQueryFreeRepoInputs(pRepos: PTDNF_REPOMD_NATIVE_REPO_INPUT, dwRepoCount: u32) void;
pub extern fn TDNFNativeQueryInstallRoot(pTdnf: PTDNF) [*c]const u8;
pub extern fn TDNFNativeQueryFilterUserInstalled(pTdnf: PTDNF, pPkgInfos: PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFNativeQueryApplyLocationUrls(pTdnf: PTDNF, pPkgInfos: PTDNF_PKG_INFO, dwCount: u32) u32;
pub extern fn TDNFNativeQueryInstalledPkgIds(pSack: PTDNF_PACKAGE_CONTEXT, pQueue: PTDNF_ID_LIST) u32;
pub extern fn TDNFNativeQuerySerializePackageId(pSack: PTDNF_PACKAGE_CONTEXT, dwPkgId: TDNF_PKG_ID, ppszLine: [*c][*c]u8) u32;
pub extern fn TDNFNativeQuerySerializeQueuePackageRefs(pSack: PTDNF_PACKAGE_CONTEXT, pQueue: PTDNF_ID_LIST, pppszRefs: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFNativeQuerySerializePackageInfoRefs(pPkgInfos: PTDNF_PKG_INFO, dwCount: u32, pppszRefs: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFNativeQuerySerializeAutoInstalledRefs(pTdnf: PTDNF, pHistoryCtx: ?*struct_history_ctx, pppszRefs: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFNativeQueryResolvePackageRefArrayToQueue(pSack: PTDNF_PACKAGE_CONTEXT, ppszPackageRefs: [*c][*c]u8, dwCount: u32, nInstalledOnly: c_int, pQueue: PTDNF_ID_LIST) u32;
pub extern fn TDNFNativeQueryResolveSinglePackageRef(pSack: PTDNF_PACKAGE_CONTEXT, pszPackageRef: [*c]const u8, nInstalledOnly: c_int, pdwPkgId: [*c]TDNF_PKG_ID) u32;
pub extern fn TDNFNativeQuerySplitPackageRef(pszRef: [*c]const u8, ppszRepo: [*c][*c]u8, pdwEpoch: [*c]u32, ppszName: [*c][*c]u8, ppszVersion: [*c][*c]u8, ppszRelease: [*c][*c]u8, ppszArch: [*c][*c]u8) u32;
pub extern fn TDNFNativeQueryBuildUpdateInfoSummary(ppszLines: [*c][*c]u8, dwCount: u32, ppSummary: [*c]PTDNF_UPDATEINFO_SUMMARY) u32;
pub extern fn TDNFNativeQueryBuildUpdateInfo(ppszLines: [*c][*c]u8, dwCount: u32, ppInfo: [*c]PTDNF_UPDATEINFO) u32;
pub extern fn TDNFAddPackagesForInstall(pSack: PTDNF_PACKAGE_CONTEXT, pQueueGoal: PTDNF_ID_LIST, pszPkgName: [*c]const u8, nSource: c_int, nInstallOnly: c_int) u32;
pub extern fn TDNFMatchForReinstall(pSack: PTDNF_PACKAGE_CONTEXT, pszName: [*c]const u8, pQueueGoal: PTDNF_ID_LIST) u32;
pub extern fn TDNFPopulatePkgInfosFromRefs(pSack: PTDNF_PACKAGE_CONTEXT, ppszPackageRefs: [*c][*c]u8, dwRefCount: u32, ppPkgInfo: [*c]PTDNF_PKG_INFO) u32;
pub extern fn TDNFPkgInfoFilterNewest(pSack: PTDNF_PACKAGE_CONTEXT, pPkgInfos: PTDNF_PKG_INFO) u32;
pub extern fn TDNFAddPackagesForErase(pSack: PTDNF_PACKAGE_CONTEXT, pQueueGoal: PTDNF_ID_LIST, pszPkgName: [*c]const u8) u32;
pub extern fn TDNFAddPackagesForUpgrade(pSack: PTDNF_PACKAGE_CONTEXT, pQueueGoal: PTDNF_ID_LIST, pszPkgName: [*c]const u8) u32;
pub extern fn TDNFAddPackagesForDowngrade(pTdnf: PTDNF, pSack: PTDNF_PACKAGE_CONTEXT, pQueueGoal: PTDNF_ID_LIST, pszPkgName: [*c]const u8) u32;
pub extern fn TDNFGetAvailableCacheBytes(pConf: PTDNF_CONF, pqwAvailCacheBytes: [*c]u64) u32;
pub extern fn TDNFCheckDownloadCacheBytes(pSolvedPkgInfo: PTDNF_SOLVED_PKG_INFO, qwAvailCacheBytes: u64) u32;
pub extern fn ReadGPGKeyFile(pszFile: [*c]const u8, ppszKeyData: [*c][*c]u8, pnSize: [*c]c_int) u32;
pub extern fn TDNFGPGCheckPackageEx(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszFilePath: [*c]const u8, ppRpmFile: [*c]?*tdnf_rpm_file, pnPolicyRejected: [*c]c_int) u32;
pub extern fn TDNFGPGCheckPackageWithFile(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszFilePath: [*c]const u8, pRpmFile: ?*tdnf_rpm_file, pnPolicyRejected: [*c]c_int) u32;
pub extern fn TDNFFetchRemoteGPGKey(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszUrlGPGKey: [*c]const u8, ppszKeyLocation: [*c][*c]u8) u32;
pub const struct__KEYVALUE_ = extern struct {
    pszKey: [*c]u8 = null,
    pszValue: [*c]u8 = null,
    pNext: [*c]struct__KEYVALUE_ = null,
};
pub const KEYVALUE = struct__KEYVALUE_;
pub const PKEYVALUE = [*c]struct__KEYVALUE_;
pub const struct__CONF_SECTION_ = extern struct {
    pszName: [*c]u8 = null,
    pKeyValues: PKEYVALUE = null,
    pNext: [*c]struct__CONF_SECTION_ = null,
    pub const TDNFConfigReadProxySettings = __root.TDNFConfigReadProxySettings;
};
pub const CONF_SECTION = struct__CONF_SECTION_;
pub const PCONF_SECTION = [*c]struct__CONF_SECTION_;
pub const struct__CONF_DATA_ = extern struct {
    pszConfFile: [*c]u8 = null,
    pSections: PCONF_SECTION = null,
};
pub const CONF_DATA = struct__CONF_DATA_;
pub const PCONF_DATA = [*c]struct__CONF_DATA_;
pub const PFN_CONF_SECTION_CB = ?*const fn (pData: PCONF_DATA, pszSection: [*c]const u8) callconv(.c) u32;
pub const PFN_CONF_KEYVALUE_CB = ?*const fn (pData: PCONF_DATA, pszKey: [*c]const u8, pszValue: [*c]const u8) callconv(.c) u32;
pub const TDNF_HASH_MD5: c_int = 0;
pub const TDNF_HASH_SHA1: c_int = 1;
pub const TDNF_HASH_SHA256: c_int = 2;
pub const TDNF_HASH_SHA512: c_int = 3;
pub const TDNF_HASH_SENTINEL: c_int = 4;
const enum_unnamed_17 = c_uint;
pub const struct__hash_op = extern struct {
    hash_type: [*c]const u8 = null,
    length: c_uint = 0,
};
pub const hash_op = struct__hash_op;
pub const struct__hash_type = extern struct {
    hash_name: [*c]const u8 = null,
    hash_value: c_uint = 0,
};
pub const hash_type = struct__hash_type;
pub extern var hash_ops: [4]hash_op;
pub extern var hashType: [7]hash_type;
pub extern fn TDNFAllocateMemory(nNumElements: usize, nSize: usize, ppMemory: [*c]?*anyopaque) u32;
pub extern fn TDNFReAllocateMemory(nSize: usize, ppMemory: [*c]?*anyopaque) u32;
pub extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;
pub extern fn TDNFAllocateString(pszSrc: [*c]const u8, ppszDst: [*c][*c]u8) u32;
pub extern fn TDNFSafeAllocateString(pszSrc: [*c]const u8, ppszDst: [*c][*c]u8) u32;
pub extern fn TDNFStringSepCount(pszBuf: [*c]const u8, pszSep: [*c]const u8, nSepCount: [*c]usize) u32;
pub extern fn TDNFSplitStringToArray(pszBuf: [*c]const u8, pszSep: [*c]const u8, pppszTokens: [*c][*c][*c]u8) u32;
pub extern fn TDNFMergeStringArrays(pppszArray0: [*c][*c][*c]u8, ppszArray1: [*c][*c]u8) u32;
pub extern fn TDNFAddStringArray(pppszArray: [*c][*c][*c]u8, pszValue: [*c]u8) u32;
pub extern fn TDNFJoinArrayToString(ppszArray: [*c][*c]u8, pszSep: [*c]const u8, count: c_int, ppszResult: [*c][*c]u8) u32;
pub extern fn TDNFJoinArrayToStringSorted(ppszDependencies: [*c][*c]u8, pszSep: [*c]const u8, ppszResult: [*c][*c]u8) u32;
pub extern fn TDNFAllocateStringArray(ppszSrc: [*c][*c]u8, pppszDst: [*c][*c][*c]u8) u32;
pub extern fn TDNFAllocateStringN(pszSrc: [*c]const u8, dwNumElements: u32, ppszDst: [*c][*c]u8) u32;
pub extern fn TDNFReplaceString(pszSource: [*c]const u8, pszSearch: [*c]const u8, pszReplace: [*c]const u8, ppszDst: [*c][*c]u8) u32;
pub extern fn TDNFTrimSuffix(pszSource: [*c]u8, pszSuffix: [*c]const u8) u32;
pub extern fn TDNFStringEndsWith(pszSource: [*c]u8, pszSuffix: [*c]const u8) u32;
pub extern fn TDNFFreeStringArray(ppszArray: [*c][*c]u8) void;
pub extern fn TDNFFreeStringArrayWithCount(ppszArray: [*c][*c]u8, nCount: c_int) void;
pub extern fn TDNFStringArrayCount(ppszStringArray: [*c][*c]u8, pnCount: [*c]c_int) u32;
pub extern fn TDNFStringArraySort(ppszArray: [*c][*c]u8) u32;
pub extern fn TDNFIdListInit(pList: PTDNF_ID_LIST) void;
pub extern fn TDNFIdListFree(pList: PTDNF_ID_LIST) void;
pub extern fn TDNFIdListEmpty(pList: PTDNF_ID_LIST) void;
pub extern fn TDNFIdListPush(pList: PTDNF_ID_LIST, nValue: i32) u32;
pub extern fn TDNFIdListPush2(pList: PTDNF_ID_LIST, nFirst: i32, nSecond: i32) u32;
pub extern fn TDNFIdListPushUnique(pList: PTDNF_ID_LIST, nValue: i32) u32;
pub extern fn TDNFCreateAndWriteToFile(pszFile: [*c]const u8, data: [*c]const u8) u32;
pub extern fn TDNFFileReadAllText(pszFileName: [*c]const u8, ppszText: [*c][*c]u8, pnLength: [*c]c_int) u32;
pub extern fn TDNFLeftTrim(pszStr: [*c]const u8) [*c]const u8;
pub extern fn TDNFRightTrim(pszStart: [*c]const u8, pszEnd: [*c]const u8) [*c]const u8;
pub extern fn TDNFUtilsFormatSize(unSize: u64, ppszFormattedSize: [*c][*c]u8) u32;
pub extern fn TDNFFreePackageInfoContents(pPkgInfo: PTDNF_PKG_INFO) void;
pub extern fn TDNFYesOrNo(pArgs: PTDNF_CMD_ARGS, pszQuestion: [*c]const u8, pAnswer: [*c]c_int) u32;
pub extern fn TDNFNormalizePath(pszPath: [*c]const u8, ppszNormalPath: [*c][*c]u8) u32;
pub extern fn TDNFRecursivelyRemoveDir(pszPath: [*c]const u8) u32;
pub extern fn TDNFStringMatchesOneOf(pszSearch: [*c]const u8, ppszList: [*c][*c]u8, pRet: [*c]c_int) u32;
pub extern fn TDNFReadFileToStringArray(pszFile: [*c]const u8, pppszArray: [*c][*c][*c]u8) u32;
pub extern fn TDNFIsDir(pszPath: [*c]const u8, pnPathIsDir: [*c]c_int) u32;
pub extern fn TDNFDirName(pszPath: [*c]const u8, ppszDirName: [*c][*c]u8) u32;
pub extern fn TDNFStrIsValidRepoName(str: [*c]const u8) c_int;
pub extern fn GlobalSetQuiet(val: i32) void;
pub extern fn GlobalSetJson(val: i32) void;
pub extern fn GlobalSetDnfCheckUpdateCompat(val: i32) void;
pub extern fn GlobalGetDnfCheckUpdateCompat() bool;
pub extern fn tdnfLockAcquire(lockPath: [*c]const u8) c_int;
pub extern fn tdnfLockFree(lockPath: [*c]const u8, lockFd: c_int) void;
pub extern fn strtoi(ptr: [*c]const u8) i32;
pub extern fn isTrue(str: [*c]const u8) c_int;
pub extern fn TDNFGetDigestForFile(filename: [*c]const u8, @"type": c_int, digest: [*c]u8) u32;
pub extern fn TDNFCheckHash(filename: [*c]const u8, digest: [*c]const u8, @"type": c_int) u32;
pub extern fn TDNFCheckHexDigest(hex_digest: [*c]const u8, digest_length: c_int) u32;
pub extern fn TDNFHexToUint(hex_digest: [*c]const u8, uintValue: [*c]u8) u32;
pub extern fn TDNFChecksumFromHexDigest(hex_digest: [*c]const u8, ppdigest: [*c]u8) u32;
pub extern fn TDNFFreeUpdateInfoPackages(pPkg: PTDNF_UPDATEINFO_PKG) void;
pub const struct_history_delta = extern struct {
    added_ids: [*c]c_int = null,
    added_count: c_int = 0,
    removed_ids: [*c]c_int = null,
    removed_count: c_int = 0,
    pub const history_free_delta = __root.history_free_delta;
    pub const delta = __root.history_free_delta;
};
pub const struct_history_flags_delta = extern struct {
    changed_ids: [*c]c_int = null,
    values: [*c]c_int = null,
    count: c_int = 0,
    pub const history_free_flags_delta = __root.history_free_flags_delta;
    pub const delta = __root.history_free_flags_delta;
};
pub const struct_history_transaction = extern struct {
    id: c_int = 0,
    type: c_int = 0,
    cmdline: [*c]u8 = null,
    timestamp: time_t = 0,
    cookie: [*c]u8 = null,
    delta: struct_history_delta = @import("std").mem.zeroes(struct_history_delta),
    flags_delta: struct_history_flags_delta = @import("std").mem.zeroes(struct_history_flags_delta),
    pub const history_free_transactions = __root.history_free_transactions;
    pub const transactions = __root.history_free_transactions;
};
pub const struct_history_nevra_map = extern struct {
    count: c_int = 0,
    idmap: [*c][*c]u8 = null,
    pub const history_free_nevra_map = __root.history_free_nevra_map;
    pub const history_get_nevra = __root.history_get_nevra;
    pub const map = __root.history_free_nevra_map;
    pub const nevra = __root.history_get_nevra;
};
pub extern fn create_history_ctx(db_filename: [*c]const u8) ?*struct_history_ctx;
pub extern fn destroy_history_ctx(ctx: ?*struct_history_ctx) void;
pub extern fn history_get_current_transaction_id(ctx: ?*struct_history_ctx) c_int;
pub extern fn history_sync(ctx: ?*struct_history_ctx, root: [*c]const u8) c_int;
pub extern fn history_sync_config(ctx: ?*struct_history_ctx, config: ?*const tdnf_rpm_config) c_int;
pub extern fn history_nevra_from_id(ctx: ?*struct_history_ctx, id: c_int) [*c]u8;
pub extern fn history_nevra_map(ctx: ?*struct_history_ctx) [*c]struct_history_nevra_map;
pub extern fn history_free_nevra_map([*c]struct_history_nevra_map) void;
pub extern fn history_get_nevra(hnm: [*c]struct_history_nevra_map, id: c_int) [*c]u8;
pub extern fn history_free_delta(hd: [*c]struct_history_delta) void;
pub extern fn history_get_delta(ctx: ?*struct_history_ctx, trans_id: c_int) [*c]struct_history_delta;
pub extern fn history_get_delta_range(ctx: ?*struct_history_ctx, trans_id0: c_int, trans_id1: c_int) [*c]struct_history_delta;
pub extern fn history_add_transaction(ctx: ?*struct_history_ctx, cmdline: [*c]const u8) c_int;
pub extern fn history_record_state(ctx: ?*struct_history_ctx) c_int;
pub extern fn history_update_state(ctx: ?*struct_history_ctx, root: [*c]const u8, cmdline: [*c]const u8) c_int;
pub extern fn history_update_state_config(ctx: ?*struct_history_ctx, config: ?*const tdnf_rpm_config, cmdline: [*c]const u8) c_int;
pub extern fn history_get_transactions(ctx: ?*struct_history_ctx, ptas: [*c][*c]struct_history_transaction, pcount: [*c]c_int, reverse: c_int, from: c_int, to: c_int) c_int;
pub extern fn history_free_transactions(tas: [*c]struct_history_transaction, count: c_int) void;
pub extern fn history_set_auto_flag(ctx: ?*struct_history_ctx, name: [*c]const u8, value: c_int) c_int;
pub extern fn history_get_auto_flag(ctx: ?*struct_history_ctx, name: [*c]const u8, pvalue: [*c]c_int) c_int;
pub extern fn history_restore_auto_flags(ctx: ?*struct_history_ctx, trans_id: c_int) c_int;
pub extern fn history_replay_auto_flags(ctx: ?*struct_history_ctx, from: c_int, to: c_int) c_int;
pub extern fn history_free_flags_delta(hfd: [*c]struct_history_flags_delta) void;
pub extern fn history_get_flags_delta(ctx: ?*struct_history_ctx, from: c_int, to: c_int) [*c]struct_history_flags_delta;
pub const DETAIL_LIST: c_int = 0;
pub const DETAIL_INFO: c_int = 1;
pub const DETAIL_CHANGELOG: c_int = 2;
pub const DETAIL_SOURCEPKG: c_int = 3;
pub const DETAIL_LOCATION: c_int = 4;
pub const TDNF_PKG_DETAIL = c_uint;
pub const TDNF_ML_FREE_FUNC = ?*const fn (data: ?*anyopaque) callconv(.c) void;
pub extern fn BuiltinRefreshRequested(pTdnf: ?*anyopaque) c_int;
pub extern fn BuiltinGetEnv(pszName: [*c]const u8) [*c]const u8;
pub extern fn BuiltinFileExists(pszPath: [*c]const u8) c_int;
pub extern fn BuiltinUnlink(pszPath: [*c]const u8) void;
pub extern fn BuiltinMakeDirs(pszPath: [*c]const u8) u32;
pub extern fn BuiltinFindRepo(pTdnf: ?*anyopaque, pszRepoId: [*c]const u8, ppRepo: [*c]?*anyopaque) u32;
pub extern fn BuiltinDownloadMetalink(pTdnf: ?*anyopaque, pRepo: ?*anyopaque, pszDestination: [*c]const u8) u32;
pub extern fn BuiltinDownloadRepoFile(pTdnf: ?*anyopaque, pRepo: ?*anyopaque, pszLocation: [*c]const u8, pszDestination: [*c]const u8, pszProgress: [*c]const u8) u32;
pub extern fn BuiltinReplaceBaseUrls(pRepo: ?*anyopaque, ppszBaseUrls: [*c][*c]u8) void;
pub extern fn rpmzig_verify_detached_armored(pSig: [*c]const u8, nSig: usize, pData: [*c]const u8, nData: usize, ppKeys: [*c]const [*c]const u8, pnKeyLengths: [*c]const usize, nKeyCount: usize) c_int;
pub extern fn TDNFGetHistoryCtx(pTdnf: PTDNF, ppCtx: [*c]?*struct_history_ctx, nMustExist: c_int) u32;
pub extern var gEuid: uid_t;
pub extern fn tdnf_repomd_native_verified_transaction_solve_config(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, ppbHeaders: [*c]const [*c]const u8, pnHeaderLengths: [*c]const usize, pqwPackageSizes: [*c]const u64, dwItemCount: u32, pConfig: ?*const tdnf_rpm_config, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRefreshSack(pTdnf: PTDNF, pSack: PTDNF_PACKAGE_CONTEXT, nCleanMetadata: c_int) u32;
pub extern fn TDNFGoal(pTdnf: PTDNF, pkgList: PTDNF_ID_LIST, ppInfo: [*c]PTDNF_SOLVED_PKG_INFO, nAlterType: TDNF_ALTERTYPE, nUnresolved: c_int) u32;
pub extern fn TDNFGoalNoDeps(pTdnf: PTDNF, pQueuePkgList: PTDNF_ID_LIST, ppInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFHistoryGoal(pTdnf: PTDNF, pqInstall: PTDNF_ID_LIST, pqErase: PTDNF_ID_LIST, ppInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFSolv(pTdnf: PTDNF, pQueueJobs: PTDNF_ID_LIST, ppszExcludes: [*c][*c]u8, dwExcludeCount: u32, nAllowErasing: c_int, nAutoErase: c_int, nReInstall: c_int, nUnresolved: c_int, ppInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFAddUserInstall(pTdnf: PTDNF, pQueueGoal: [*c]const TDNF_ID_LIST, ppInfo: PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFMarkAutoInstalledSinglePkg(pTdnf: PTDNF, pszPkgName: [*c]const u8) u32;
pub extern fn TDNFMarkAutoInstalled(pTdnf: PTDNF, pHistoryCtx: ?*struct_history_ctx, ppInfo: PTDNF_SOLVED_PKG_INFO, nAutoOnly: c_int) u32;
pub extern fn TDNFAddGoal(pTdnf: PTDNF, nAlterType: TDNF_ALTERTYPE, pQueueJobs: PTDNF_ID_LIST, dwId: TDNF_PKG_ID, dwCount: u32, ppszExcludes: [*c][*c]u8) u32;
pub extern fn TDNFPkgsToExclude(pTdnf: PTDNF, pdwPkgsToExclude: [*c]u32, pppszExclude: [*c][*c][*c]u8) u32;
pub extern fn TDNFGoalAddHiddenPackages(pTdnf: PTDNF, ppszExcludes: [*c][*c]u8) u32;
pub extern fn TDNFReadConfig(pTdnf: PTDNF, pszConfFile: [*c]const u8, pszConfGroup: [*c]const u8) u32;
pub extern fn TDNFConfigExpandVars(pTdnf: PTDNF) u32;
pub extern fn TDNFConfigReadProxySettings(pSection: PCONF_SECTION, pConf: PTDNF_CONF) u32;
pub extern fn TDNFFreeConfig(pConf: PTDNF_CONF) void;
pub extern fn TDNFConfigReplaceVars(pTdnf: PTDNF, pszString: [*c][*c]u8) u32;
pub extern fn TDNFInitRepo(pTdnf: PTDNF, pRepoData: PTDNF_REPO_DATA, pSack: PTDNF_PACKAGE_CONTEXT) u32;
pub extern fn TDNFGetGPGKeys(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pppszUrlGPGKeys: [*c][*c][*c]u8) u32;
pub extern fn TDNFGetRepoMD(pTdnf: PTDNF, pRepoData: PTDNF_REPO_DATA, pszRepoDataDir: [*c]const u8, ppRepoMD: [*c]PTDNF_REPO_METADATA) u32;
pub extern fn TDNFFreeRepoMetadata(pRepoMD: PTDNF_REPO_METADATA) void;
pub extern fn TDNFDownloadMetadata(pTdnf: PTDNF, pRepo: PTDNF_REPO_DATA, pszRepoDir: [*c]const u8, nPrintOnly: c_int) u32;
pub extern fn TDNFLoadRepoData(pTdnf: PTDNF, ppReposAll: [*c]PTDNF_REPO_DATA) u32;
pub extern fn TDNFRepoListFinalize(pTdnf: PTDNF) u32;
pub extern fn TDNFCloneRepo(pRepoIn: PTDNF_REPO_DATA, ppRepo: [*c]PTDNF_REPO_DATA) u32;
pub extern fn TDNFFreeReposInternal(pRepos: PTDNF_REPO_DATA) void;

const builtin = @import("builtin");
threadlocal var prepare_all_test_error_after_update_pkgs: u32 = 0;
threadlocal var prepare_all_test_update_pkgs_frees: usize = 0;

pub fn prepareAllPackagesTestFailAfterUpdatePkgs(error_code: u32) void {
    if (builtin.is_test) prepare_all_test_error_after_update_pkgs = error_code;
}

pub fn prepareAllPackagesTestResetUpdatePkgsFrees() void {
    if (builtin.is_test) prepare_all_test_update_pkgs_frees = 0;
}

pub fn prepareAllPackagesTestUpdatePkgsFrees() usize {
    return if (builtin.is_test) prepare_all_test_update_pkgs_frees else 0;
}

pub export fn TDNFPrepareAllPackages(pTdnf: PTDNF, pAlterType: [*c]TDNF_ALTERTYPE, ppszPkgsNotResolved: [*c][*c]u8, queueGoal: PTDNF_ID_LIST) u32 {
    var rc: u32 = 0;
    var severity: [*c]u8 = null;
    var pkg_infos: PTDNF_PKG_INFO = null;
    var pkg_info_count: u32 = 0;
    defer {
        if (severity != null) TDNFFreeMemory(@ptrCast(severity));
        if (pkg_infos != null) TDNFFreePackageInfoArray(pkg_infos, pkg_info_count);
    }

    process: {
        if (pTdnf == null or pTdnf.*.pSack == null or pTdnf.*.pArgs == null or ppszPkgsNotResolved == null or queueGoal == null or pAlterType == null) {
            rc = ERROR_TDNF_INVALID_PARAMETER;
            break :process;
        }
        const args = pTdnf.*.pArgs;
        const alter_type = pAlterType.*;
        if (alter_type == ALTER_DOWNGRADEALL) {
            rc = TDNFFilterPackages(pTdnf, alter_type, ppszPkgsNotResolved, queueGoal);
            if (rc != 0) break :process;
        } else if (alter_type == ALTER_AUTOERASEALL) {
            const trace_start = queueGoal.*.dwCount;
            rc = TDNFGetAutoInstalledOrphans(pTdnf, queueGoal);
            if (rc != 0) break :process;
            TDNFTransactionPlanRequestTraceRecordGoalRange(pTdnf.*.pRequestTrace, queueGoal.*.pnElements, trace_start, queueGoal.*.dwCount, ALTER_AUTOERASEALL, 3, 0);
        }

        var security: u32 = 0;
        rc = TDNFGetSecuritySeverityOption(pTdnf, &security, &severity);
        if (rc != 0) break :process;
        var reboot_required: u32 = 0;
        rc = TDNFGetRebootRequiredOption(pTdnf, &reboot_required);
        if (rc != 0) break :process;
        if ((alter_type == ALTER_UPGRADEALL or alter_type == ALTER_UPGRADE) and (security != 0 or severity != null or reboot_required != 0)) {
            pAlterType.* = ALTER_UPGRADE;
            var pkgs: [*c][*c]u8 = null;
            var count: u32 = 0;
            rc = TDNFGetUpdatePkgs(pTdnf, &pkgs, &count);
            if (rc != 0) break :process;
            defer {
                if (builtin.is_test and pkgs != null) {
                    prepare_all_test_update_pkgs_frees += 1;
                }
                TDNFFreeStringArray(pkgs);
            }
            if (builtin.is_test and prepare_all_test_error_after_update_pkgs != 0) {
                rc = prepare_all_test_error_after_update_pkgs;
                prepare_all_test_error_after_update_pkgs = 0;
                break :process;
            }
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                var request_ref: u32 = if (alter_type == ALTER_UPGRADEALL) 0 else transaction_plan_abi.request_trace_no_request;
                var cmd_index: c_int = 1;
                while (alter_type == ALTER_UPGRADE and cmd_index < args.*.nCmdCount) : (cmd_index += 1) {
                    if (request_ref == transaction_plan_abi.request_trace_no_request and fnmatch(args.*.ppszCmds[@intCast(cmd_index)], pkgs[i], 0) == 0) request_ref = @intCast(cmd_index - 1);
                }
                rc = TDNFPrepareSinglePkg(pTdnf, pkgs[i], pAlterType.*, ppszPkgsNotResolved, queueGoal, request_ref);
                if (rc != 0) break :process;
            }
        } else {
            var cmd_index: c_int = 1;
            while (cmd_index < args.*.nCmdCount) : (cmd_index += 1) {
                const pkg_name = args.*.ppszCmds[@intCast(cmd_index)];
                if (TDNFIsGlob(pkg_name) != 0) {
                    const installed = alter_type == ALTER_ERASE or alter_type == ALTER_AUTOERASE or alter_type == ALTER_UPGRADE or alter_type == ALTER_DOWNGRADE or alter_type == ALTER_REINSTALL;
                    var spec = [_][*c]u8{ pkg_name, null };
                    if (pkg_infos != null) {
                        TDNFFreePackageInfoArray(pkg_infos, pkg_info_count);
                        pkg_infos = null;
                        pkg_info_count = 0;
                    }
                    rc = TDNFResolveListPackages(pTdnf, if (installed) SCOPE_INSTALLED else SCOPE_AVAILABLE, &spec, &pkg_infos, &pkg_info_count);
                    if (rc == ERROR_TDNF_NO_MATCH) rc = 0;
                    if (rc != 0) break :process;
                    if (pkg_info_count == 0) {
                        rc = TDNFAddNotResolved(ppszPkgsNotResolved, pkg_name);
                        if (rc != 0) break :process;
                        TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, @intCast(cmd_index - 1), 3);
                    } else {
                        var i: u32 = 0;
                        while (i < pkg_info_count) : (i += 1) {
                            rc = TDNFPrepareSinglePkg(pTdnf, pkg_infos[i].pszName, alter_type, ppszPkgsNotResolved, queueGoal, @intCast(cmd_index - 1));
                            if (rc != 0) break :process;
                        }
                    }
                } else {
                    if (fnmatch("*.rpm", pkg_name, 0) == 0) continue;
                    rc = TDNFPrepareSinglePkg(pTdnf, pkg_name, alter_type, ppszPkgsNotResolved, queueGoal, @intCast(cmd_index - 1));
                    if (rc != 0) break :process;
                }
            }
        }
    }
    return rc;
}
pub export fn TDNFAddNotResolved(arg_ppszPkgsNotResolved: [*c][*c]u8, arg_pszPkgName: [*c]const u8) u32 {
    var ppszPkgsNotResolved = arg_ppszPkgsNotResolved;
    _ = &ppszPkgsNotResolved;
    var pszPkgName = arg_pszPkgName;
    _ = &pszPkgName;
    var dwError: u32 = 0;
    _ = &dwError;
    var nIndex: c_int = 0;
    _ = &nIndex;
    if (!(ppszPkgsNotResolved != null) or (!(pszPkgName != null) or !(@as(c_int, pszPkgName.*) != 0))) {
        dwError = @bitCast(@as(c_int, ERROR_TDNF_SYSTEM_BASE + EINVAL));
        while (true) {
            if (dwError != @as(u32, 0)) return dwError;
            if (!false) break;
        }
    }
    while (ppszPkgsNotResolved[
        @bitCast(@as(isize, @intCast(blk: {
            const ref = &nIndex;
            const tmp = ref.*;
            ref.* += 1;
            break :blk tmp;
        })))
    ] != null) {}
    dwError = TDNFAllocateString(pszPkgName, &ppszPkgsNotResolved[
        @bitCast(@as(isize, @intCast(blk: {
            const ref = &nIndex;
            ref.* -= 1;
            break :blk ref.*;
        })))
    ]);
    while (true) {
        if (dwError != @as(u32, 0)) return dwError;
        if (!false) break;
    }
    return dwError;
}
pub export fn TDNFResolveBuildDependencies(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppszPkgsNotResolved: [*c][*c]u8, queueGoal: PTDNF_ID_LIST) u32 {
    var rc: u32 = 0;
    var repos: PTDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    var pkg_infos: PTDNF_PKG_INFO = null;
    var pkg_count: u32 = 0;
    var goal_refs: [*c][*c]u8 = null;
    var goal_deps: [*c][*c]u8 = null;
    var pkg_refs: [*c][*c]u8 = null;
    var pkg_deps: [*c][*c]u8 = null;
    var cmdline_paths: [*c][*c]u8 = null;
    defer {
        TDNFFreeStringArray(goal_refs);
        TDNFFreeStringArray(goal_deps);
        TDNFFreeStringArray(pkg_refs);
        TDNFFreeStringArray(pkg_deps);
        TDNFFreeStringArray(cmdline_paths);
        TDNFNativeQueryFreeRepoInputs(repos, repo_count);
        if (pkg_infos != null) TDNFFreePackageInfoArray(pkg_infos, pkg_count);
    }

    process: {
        if (pTdnf == null or pTdnf.*.pSack == null or ppszPackageNameSpecs == null or ppszPkgsNotResolved == null or queueGoal == null) {
            rc = ERROR_TDNF_INVALID_PARAMETER;
            break :process;
        }
        var cmdline_count: u32 = 0;
        if (queueGoal.*.dwCount > 0) {
            rc = TDNFResolveCollectCmdLineRpmPaths(pTdnf, &cmdline_paths, &cmdline_count);
            if (rc != 0) break :process;
        }
        if ((queueGoal.*.dwCount > 0 and cmdline_count == 0) or ppszPackageNameSpecs[0] != null) {
            rc = TDNFNativeQueryBuildRepoInputs(pTdnf, &repos, &repo_count);
            if (rc != 0) break :process;
        }
        var goal_dep_count: u32 = 0;
        if (queueGoal.*.dwCount > 0) {
            if (cmdline_count != 0) {
                rc = TDNFRepoMdNativeRequiresForCmdLineRpmPaths(@ptrCast(cmdline_paths), cmdline_count, &goal_deps, &goal_dep_count);
            } else {
                var goal_ref_count: u32 = 0;
                rc = TDNFNativeQuerySerializeQueuePackageRefs(pTdnf.*.pSack, queueGoal, &goal_refs, &goal_ref_count);
                if (rc == 0) rc = TDNFRepoMdNativeRequiresForPackageRefsConfig(repos, repo_count, pTdnf.*.pRpmConfig, goal_refs, &goal_deps, &goal_dep_count);
            }
            if (rc != 0) break :process;
        }
        TDNFIdListEmpty(queueGoal);
        var pkg_dep_count: u32 = 0;
        if (ppszPackageNameSpecs[0] != null) {
            rc = TDNFRepoMdNativeListConfig(repos, repo_count, pTdnf.*.pRpmConfig, SCOPE_SOURCE, ppszPackageNameSpecs, DETAIL_LIST, &pkg_infos, &pkg_count);
            if (rc != 0) break :process;
            var pkg_ref_count: u32 = 0;
            rc = TDNFNativeQuerySerializePackageInfoRefs(pkg_infos, pkg_count, &pkg_refs, &pkg_ref_count);
            if (rc == 0) rc = TDNFRepoMdNativeRequiresForPackageRefsConfig(repos, repo_count, pTdnf.*.pRpmConfig, pkg_refs, &pkg_deps, &pkg_dep_count);
            if (rc != 0) break :process;
        }
        var arrays = [_]struct { deps: [*c][*c]u8, count: u32 }{
            .{ .deps = goal_deps, .count = goal_dep_count },
            .{ .deps = pkg_deps, .count = pkg_dep_count },
        };
        for (&arrays) |entry| {
            var i: u32 = 0;
            while (i < entry.count) : (i += 1) {
                const dep = entry.deps[i];
                if (dep == null or strncmp(dep, "rpmlib(", 7) == 0) continue;
                rc = TDNFPrepareSinglePkg(pTdnf, dep, ALTER_INSTALL, ppszPkgsNotResolved, queueGoal, transaction_plan_abi.request_trace_no_request);
                if (rc != 0) break :process;
            }
        }
    }
    return rc;
}
pub extern fn TDNFRpmExecTransaction(pTdnf: PTDNF, pInfo: PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFRpmExecHistoryTransaction(pTdnf: PTDNF, pSolvedInfo: PTDNF_SOLVED_PKG_INFO, pHistoryArgs: PTDNF_HISTORY_ARGS) u32;
pub extern fn TDNFGetSecuritySeverityOption(pTdnf: PTDNF, pdwSecurity: [*c]u32, ppszSeverity: [*c][*c]u8) u32;
pub extern fn TDNFGetUpdatePkgs(pTdnf: PTDNF, pppszPkgs: [*c][*c][*c]u8, pdwCount: [*c]u32) u32;
pub extern fn TDNFGetRebootRequiredOption(pTdnf: PTDNF, pdwRebootRequired: [*c]u32) u32;
pub extern fn TDNFGetSkipProblemOption(pTdnf: PTDNF, pdwSkipProblem: [*c]TDNF_SKIPPROBLEM_TYPE) u32;
pub extern fn TDNFReportNativeSolverProblems(pHandle: ?*anyopaque, dwSkipProblem: TDNF_SKIPPROBLEM_TYPE) u32;
pub extern fn TDNFLoadPlugins(pTdnf: PTDNF) u32;
pub extern fn TDNFFreePlugins(pPlugins: PTDNF_PLUGIN) void;
pub extern fn BuiltinPluginsRepoConfig(pTdnf: PTDNF, pSection: [*c]const struct_cnfnode) u32;
pub extern fn BuiltinPluginsRepoMDDownloadStart(pTdnf: PTDNF, pszRepoId: [*c]const u8, pszRepoDataDir: [*c]const u8) u32;
pub extern fn BuiltinPluginsRepoMDDownloadEnd(pTdnf: PTDNF, pszRepoId: [*c]const u8, pszRepoMDFile: [*c]const u8) u32;
pub extern fn parse_varsdirs(dirs: [*c][*c]u8) [*c]struct_cnfnode;
pub extern fn replace_vars(cn_vars: [*c]struct_cnfnode, source: [*c]const u8) [*c]u8;
pub fn TDNFFilterPackages(pTdnf: PTDNF, nAlterType: TDNF_ALTERTYPE, ppszPkgsNotResolved: [*c][*c]u8, queueGoal: PTDNF_ID_LIST) callconv(.c) u32 {
    var infos: PTDNF_PKG_INFO = null;
    var count: u32 = 0;
    defer if (infos != null) TDNFFreePackageInfoArray(infos, count);
    if (pTdnf == null or pTdnf.*.pSack == null or queueGoal == null or ppszPkgsNotResolved == null) return ERROR_TDNF_INVALID_PARAMETER;
    var rc = TDNFResolveListPackages(pTdnf, SCOPE_INSTALLED, null, &infos, &count);
    if (rc == ERROR_TDNF_NO_MATCH) rc = 0;
    if (rc != 0) return rc;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        rc = TDNFPrepareSinglePkg(pTdnf, infos[i].pszName, nAlterType, ppszPkgsNotResolved, queueGoal, 0);
        if (rc != 0) return rc;
    }
    return 0;
}
pub fn TDNFGetAutoInstalledOrphans(pTdnf: PTDNF, queueGoal: PTDNF_ID_LIST) callconv(.c) u32 {
    if (pTdnf == null or pTdnf.*.pSack == null or queueGoal == null) return ERROR_TDNF_INVALID_PARAMETER;
    var history: ?*struct_history_ctx = null;
    var rc = TDNFGetHistoryCtx(pTdnf, &history, 1);
    if (rc != 0) return rc;
    defer if (history != null) destroy_history_ctx(history);

    var auto_refs: [*c][*c]u8 = null;
    var orphan_refs: [*c][*c]u8 = null;
    defer TDNFFreeStringArray(auto_refs);
    defer TDNFFreeStringArray(orphan_refs);
    var auto_count: u32 = 0;
    rc = TDNFNativeQuerySerializeAutoInstalledRefs(pTdnf, history, &auto_refs, &auto_count);
    if (rc != 0 or auto_count == 0) return rc;
    var orphan_count: u32 = 0;
    rc = TDNFRepoMdNativeAutoInstalledOrphanLinesConfig(pTdnf.*.pRpmConfig, auto_refs, &orphan_refs, &orphan_count);
    if (rc != 0) return rc;
    return TDNFNativeQueryResolvePackageRefArrayToQueue(pTdnf.*.pSack, orphan_refs, orphan_count, 1, queueGoal);
}
pub fn TDNFPrepareSinglePkg(
    pTdnf: PTDNF,
    pszPkgName: [*c]const u8,
    nAlterType: TDNF_ALTERTYPE,
    ppszPkgsNotResolved: [*c][*c]u8,
    queueGoal: PTDNF_ID_LIST,
    dwRequestRef: u32,
) callconv(.c) u32 {
    var rc: u32 = 0;
    var count: u32 = 0;
    var trace_start: c_int = 0;
    var pkg_infos: PTDNF_PKG_INFO = null;
    var pkg_spec = [_][*c]u8{ @ptrCast(@constCast(pszPkgName)), null };
    defer if (pkg_infos != null) TDNFFreePackageInfoArray(pkg_infos, count);

    process: {
        if (pTdnf == null or pTdnf.*.pSack == null or ppszPkgsNotResolved == null or pszPkgName == null or pszPkgName.* == 0 or queueGoal == null) {
            rc = ERROR_TDNF_INVALID_PARAMETER;
            break :process;
        }
        trace_start = @bitCast(queueGoal.*.dwCount);
        rc = TDNFResolveListPackages(pTdnf, if (pTdnf.*.pArgs.*.nSource != 0) SCOPE_SOURCE else SCOPE_ALL, &pkg_spec, &pkg_infos, &count);
        if (rc == ERROR_TDNF_NO_MATCH) {
            common.log(LOG_ERR, "%s package not found or not installed\n", .{pszPkgName});
            if (pTdnf.*.pArgs.*.nSkipBroken != 0) rc = 0;
        }
        if (rc != 0) break :process;
        if (count == 0) {
            rc = ERROR_TDNF_NO_SEARCH_RESULTS;
            break :process;
        }

        if (nAlterType == ALTER_REINSTALL) {
            rc = TDNFMatchForReinstall(pTdnf.*.pSack, pszPkgName, queueGoal);
            if (rc != 0) break :process;
        }
        if (nAlterType == ALTER_ERASE or nAlterType == ALTER_AUTOERASE) {
            if (pkg_infos != null) {
                TDNFFreePackageInfoArray(pkg_infos, count);
                pkg_infos = null;
                count = 0;
            }
            rc = TDNFResolveListPackages(pTdnf, SCOPE_INSTALLED, &pkg_spec, &pkg_infos, &count);
            if (rc == ERROR_TDNF_NO_MATCH) rc = ERROR_TDNF_ERASE_NEEDS_INSTALL;
            if (rc != 0) break :process;
            if (count == 0) {
                rc = ERROR_TDNF_ERASE_NEEDS_INSTALL;
                break :process;
            }
            rc = TDNFAddPackagesForErase(pTdnf.*.pSack, queueGoal, pszPkgName);
            if (rc != 0) break :process;
        } else if (nAlterType == ALTER_INSTALL) {
            var install_only: c_int = 0;
            if (pTdnf.*.pConf.*.ppszInstallOnlyPkgs != null) {
                var item: usize = 0;
                while (pTdnf.*.pConf.*.ppszInstallOnlyPkgs[item] != null) : (item += 1) {
                    if (strcmp(pTdnf.*.pConf.*.ppszInstallOnlyPkgs[item], pszPkgName) == 0) install_only = 1;
                }
            }
            rc = TDNFAddPackagesForInstall(pTdnf.*.pSack, queueGoal, pszPkgName, pTdnf.*.pArgs.*.nSource, install_only);
            if (rc == ERROR_TDNF_ALREADY_INSTALLED) {
                const mark_rc = TDNFMarkAutoInstalledSinglePkg(pTdnf, pszPkgName);
                if (mark_rc != 0) {
                    rc = mark_rc;
                    break :process;
                }
                rc = ERROR_TDNF_ALREADY_INSTALLED;
            }
            if (rc != 0) break :process;
        } else if (nAlterType == ALTER_UPGRADE) {
            rc = TDNFAddPackagesForUpgrade(pTdnf.*.pSack, queueGoal, pszPkgName);
            if (rc != 0) break :process;
        } else if (nAlterType == ALTER_DOWNGRADE or nAlterType == ALTER_DOWNGRADEALL) {
            rc = TDNFAddPackagesForDowngrade(pTdnf, pTdnf.*.pSack, queueGoal, pszPkgName);
            if (rc != 0) break :process;
        }
    }

    if (rc == ERROR_TDNF_ALREADY_INSTALLED) {
        var show: c_int = 1;
        if (pTdnf != null and pTdnf.*.pArgs != null and strcmp(pTdnf.*.pArgs.*.ppszCmds[0], "check") == 0) show = 0;
        rc = 0;
        if (dwRequestRef != transaction_plan_abi.request_trace_no_request) TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, dwRequestRef, transaction_plan_abi.request_outcome.satisfied);
        if (show != 0) common.log(LOG_ERR, "Package %s is already installed.\n", .{pszPkgName});
    } else if (rc == ERROR_TDNF_NO_UPGRADE_PATH) {
        rc = 0;
        if (dwRequestRef != transaction_plan_abi.request_trace_no_request) TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, dwRequestRef, transaction_plan_abi.request_outcome.satisfied);
        common.log(LOG_ERR, "There is no upgrade path for %s.\n", .{pszPkgName});
    } else if (rc == ERROR_TDNF_NO_DOWNGRADE_PATH) {
        rc = 0;
        if (dwRequestRef != transaction_plan_abi.request_trace_no_request) TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, dwRequestRef, transaction_plan_abi.request_outcome.satisfied);
        common.log(LOG_ERR, "There is no downgrade path for %s.\n", .{pszPkgName});
    } else if (rc == ERROR_TDNF_NO_SEARCH_RESULTS) {
        rc = TDNFAddNotResolved(ppszPkgsNotResolved, pszPkgName);
        if (rc != 0) {
            common.log(LOG_ERR, "Error while adding not resolved packages: '%s'\n", .{pszPkgName});
        } else if (dwRequestRef != transaction_plan_abi.request_trace_no_request) {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, dwRequestRef, transaction_plan_abi.request_outcome.no_candidate);
        }
    } else if (rc == ERROR_TDNF_ERASE_NEEDS_INSTALL) {
        rc = 0;
        if (dwRequestRef != transaction_plan_abi.request_trace_no_request) TDNFTransactionPlanRequestTraceRecordRequestOutcome(pTdnf.*.pRequestTrace, dwRequestRef, transaction_plan_abi.request_outcome.satisfied);
    } else if (rc == ERROR_TDNF_NO_MATCH) {
        common.log(LOG_ERR, "Package '%s' not found\n", .{pszPkgName});
    }

    if (rc == 0) {
        TDNFTransactionPlanRequestTraceRecordGoalRange(pTdnf.*.pRequestTrace, queueGoal.*.pnElements, @bitCast(trace_start), queueGoal.*.dwCount, nAlterType, transaction_plan_abi.request_reason.user, dwRequestRef);
    } else {
        common.log(LOG_ERR, "Error while processing package: '%s'\n", .{pszPkgName});
    }
    return rc;
}

pub fn TDNFResolveListPackages(pTdnf: PTDNF, nScope: TDNF_SCOPE, ppszPackageNameSpecs: [*c][*c]u8, ppPkgInfos: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) callconv(.c) u32 {
    if (ppPkgInfos != null) ppPkgInfos.* = null;
    if (pdwCount != null) pdwCount.* = 0;
    if (pTdnf == null or ppPkgInfos == null or pdwCount == null) return ERROR_TDNF_INVALID_PARAMETER;

    var repos: PTDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var infos: PTDNF_PKG_INFO = null;
    var count: u32 = 0;
    var transferred = false;
    defer if (!transferred and infos != null) TDNFFreePackageInfoArray(infos, count);

    if (nScope != SCOPE_INSTALLED) {
        const rc = TDNFNativeQueryBuildRepoInputs(pTdnf, &repos, &repo_count);
        if (rc != 0) return rc;
    }
    const rc = TDNFRepoMdNativeListConfig(repos, repo_count, pTdnf.*.pRpmConfig, nScope, ppszPackageNameSpecs, DETAIL_LIST, &infos, &count);
    if (rc != 0) return rc;
    ppPkgInfos.* = infos;
    pdwCount.* = count;
    transferred = true;
    return 0;
}
pub fn TDNFResolveCollectCmdLineRpmPaths(pTdnf: PTDNF, pppszPaths: [*c][*c][*c]u8, pdwCount: [*c]u32) callconv(.c) u32 {
    if (pppszPaths != null) pppszPaths.* = null;
    if (pdwCount != null) pdwCount.* = 0;
    if (pTdnf == null or pTdnf.*.pArgs == null or pppszPaths == null or pdwCount == null) return ERROR_TDNF_INVALID_PARAMETER;

    const args = pTdnf.*.pArgs;
    var count: u32 = 0;
    var cmd_index: c_int = 1;
    while (cmd_index < args.*.nCmdCount) : (cmd_index += 1) {
        if (fnmatch("*.rpm", args.*.ppszCmds[@intCast(cmd_index)], 0) == 0) count += 1;
    }
    if (count == 0) return 0;

    var paths: [*c][*c]u8 = null;
    var rc = TDNFAllocateMemory(count + 1, @sizeOf([*c]u8), @ptrCast(&paths));
    if (rc != 0) return rc;
    var transferred = false;
    defer if (!transferred) TDNFFreeStringArray(paths);
    var path: [*c]u8 = null;
    var copy: [*c]u8 = null;
    defer {
        if (path != null) TDNFFreeMemory(@ptrCast(path));
        if (copy != null) TDNFFreeMemory(@ptrCast(copy));
    }

    var path_index: u32 = 0;
    cmd_index = 1;
    while (cmd_index < args.*.nCmdCount) : (cmd_index += 1) {
        const pkg_name = args.*.ppszCmds[@intCast(cmd_index)];
        if (fnmatch("*.rpm", pkg_name, 0) != 0) continue;
        var is_file: c_int = 0;
        rc = TDNFIsFileOrSymlink(pkg_name, &is_file);
        if (rc != 0) return rc;
        if (is_file != 0) {
            path = realpath(pkg_name, null);
            if (path == null) return @bitCast(@as(c_int, ERROR_TDNF_SYSTEM_BASE + __errno_location().*));
        } else {
            var is_remote: c_int = 0;
            rc = TDNFUriIsRemote(pkg_name, &is_remote);
            if (rc == ERROR_TDNF_URL_INVALID) {
                rc = 0;
                continue;
            }
            if (rc != 0) return rc;
            if (is_remote == 0) {
                rc = TDNFPathFromUri(pkg_name, &path);
                if (rc != 0) return rc;
            } else {
                var repo: PTDNF_REPO_DATA = null;
                rc = TDNFAllocateString(pkg_name, &copy);
                if (rc != 0) return rc;
                rc = TDNFFindRepoById(pTdnf, "@cmdline", &repo);
                if (rc != 0) return rc;
                rc = TDNFDownloadPackageToCache(pTdnf, pkg_name, __xpg_basename(copy), repo, &path);
                if (rc != 0) return rc;
                TDNFFreeMemory(@ptrCast(copy));
                copy = null;
            }
        }
        paths[path_index] = path;
        path_index += 1;
        path = null;
    }
    pppszPaths.* = paths;
    pdwCount.* = path_index;
    transferred = true;
    return 0;
}

pub const __VERSION__ = "Aro aro-zig";
pub const __Aro__ = "";
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __GNUC__ = @as(c_int, 7);
pub const __GNUC_MINOR__ = @as(c_int, 1);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 0);
pub const __ARO_EMULATE_NO__ = @as(c_int, 0);
pub const __ARO_EMULATE_CLANG__ = @as(c_int, 1);
pub const __ARO_EMULATE_GCC__ = @as(c_int, 2);
pub const __ARO_EMULATE_MSVC__ = @as(c_int, 3);
pub const __ARO_EMULATE__ = __ARO_EMULATE_GCC__;
pub inline fn __building_module(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const linux = @as(c_int, 1);
pub const __linux = @as(c_int, 1);
pub const __linux__ = @as(c_int, 1);
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const __code_model_small__ = @as(c_int, 1);
pub const __amd64__ = @as(c_int, 1);
pub const __amd64 = @as(c_int, 1);
pub const __x86_64__ = @as(c_int, 1);
pub const __x86_64 = @as(c_int, 1);
pub const __SEG_GS = @as(c_int, 1);
pub const __SEG_FS = @as(c_int, 1);
pub const __seg_gs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:33:9
pub const __seg_fs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:34:9
pub const __FXSR__ = @as(c_int, 1);
pub const __SSE2__ = @as(c_int, 1);
pub const __SSE__ = @as(c_int, 1);
pub const __SSE_MATH__ = @as(c_int, 1);
pub const __MMX__ = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __SIZEOF_FLOAT128__ = @as(c_int, 16);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __FLOAT128__ = @as(c_int, 1);
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const __ELF__ = @as(c_int, 1);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __ATOMIC_BOOL_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WINT_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_SHORT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_INT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LLONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_POINTER_LOCK_FREE = @as(c_int, 1);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SCHAR_WIDTH__ = @as(c_int, 8);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __LONG_LONG_WIDTH__ = @as(c_int, 64);
pub const __WCHAR_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIG_ATOMIC_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __BITINT_MAXWIDTH__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 10);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_WINT_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTPTR_TYPE__ = c_long;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:116:9
pub const __INTMAX_C = __helpers.L_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:119:9
pub const __UINTMAX_C = __helpers.UL_SUFFIX;
pub const __PTRDIFF_TYPE__ = c_long;
pub const __SIZE_TYPE__ = c_ulong;
pub const __WCHAR_TYPE__ = c_int;
pub const __WINT_TYPE__ = c_uint;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub inline fn __INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub inline fn __INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub inline fn __INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT64_TYPE__ = c_long;
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // <builtin>:145:9
pub const __INT64_C = __helpers.L_SUFFIX;
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub inline fn __UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub inline fn __UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // <builtin>:170:9
pub const __UINT32_C = __helpers.U_SUFFIX;
pub const __UINT32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // <builtin>:179:9
pub const __UINT64_C = __helpers.UL_SUFFIX;
pub const __UINT64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const INT_LEAST8_FMTd__ = "hhd";
pub const INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const UINT_LEAST8_FMTo__ = "hho";
pub const UINT_LEAST8_FMTu__ = "hhu";
pub const UINT_LEAST8_FMTx__ = "hhx";
pub const UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const INT_FAST8_FMTd__ = "hhd";
pub const INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const UINT_FAST8_FMTo__ = "hho";
pub const UINT_FAST8_FMTu__ = "hhu";
pub const UINT_FAST8_FMTx__ = "hhx";
pub const UINT_FAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const INT_LEAST16_FMTd__ = "hd";
pub const INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST16_FMTo__ = "ho";
pub const UINT_LEAST16_FMTu__ = "hu";
pub const UINT_LEAST16_FMTx__ = "hx";
pub const UINT_LEAST16_FMTX__ = "hX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const INT_FAST16_FMTd__ = "hd";
pub const INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_FAST16_FMTo__ = "ho";
pub const UINT_FAST16_FMTu__ = "hu";
pub const UINT_FAST16_FMTx__ = "hx";
pub const UINT_FAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const INT_LEAST32_FMTd__ = "d";
pub const INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST32_FMTo__ = "o";
pub const UINT_LEAST32_FMTu__ = "u";
pub const UINT_LEAST32_FMTx__ = "x";
pub const UINT_LEAST32_FMTX__ = "X";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const INT_FAST32_FMTd__ = "d";
pub const INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_FAST32_FMTo__ = "o";
pub const UINT_FAST32_FMTu__ = "u";
pub const UINT_FAST32_FMTx__ = "x";
pub const UINT_FAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const INT_LEAST64_FMTd__ = "ld";
pub const INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_LEAST64_FMTo__ = "lo";
pub const UINT_LEAST64_FMTu__ = "lu";
pub const UINT_LEAST64_FMTx__ = "lx";
pub const UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const INT_FAST64_FMTd__ = "ld";
pub const INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_FMTo__ = "lo";
pub const UINT_FAST64_FMTu__ = "lu";
pub const UINT_FAST64_FMTx__ = "lx";
pub const UINT_FAST64_FMTX__ = "lX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_HAS_DENORM__ = "";
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = "";
pub const __FLT16_HAS_QUIET_NAN__ = "";
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = "";
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = "";
pub const __FLT_HAS_QUIET_NAN__ = "";
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = "";
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = "";
pub const __DBL_HAS_QUIET_NAN__ = "";
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = "";
pub const __LDBL_DIG__ = @as(c_int, 18);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 21);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = "";
pub const __LDBL_HAS_QUIET_NAN__ = "";
pub const __LDBL_MANT_DIG__ = @as(c_int, 64);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __FLT_EVAL_METHOD__ = @as(c_int, 0);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const TDNF_CLIENT_LIBSOLV_IN_SCOPE = @as(c_int, 1);
pub const __CLIENT_INCLUDES_H__ = "";
pub const _STDIO_H = @as(c_int, 1);
pub const _FEATURES_H = @as(c_int, 1);
pub const __KERNEL_STRICT_NAMES = "";
pub inline fn __GNUC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub inline fn __glibc_clang_prereq(maj: anytype, min: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &maj;
    _ = &min;
    return @as(c_int, 0);
}
pub const __GLIBC_USE = @compileError("unable to translate macro: undefined identifier `__GLIBC_USE_`"); // /usr/include/features.h:188:9
pub const _DEFAULT_SOURCE = @as(c_int, 1);
pub const __GLIBC_USE_ISOC2X = @as(c_int, 0);
pub const __USE_ISOC11 = @as(c_int, 1);
pub const __USE_POSIX_IMPLICITLY = @as(c_int, 1);
pub const _POSIX_SOURCE = @as(c_int, 1);
pub const _POSIX_C_SOURCE = @as(c_long, 200809);
pub const __USE_POSIX = @as(c_int, 1);
pub const __USE_POSIX2 = @as(c_int, 1);
pub const __USE_POSIX199309 = @as(c_int, 1);
pub const __USE_POSIX199506 = @as(c_int, 1);
pub const __USE_XOPEN2K = @as(c_int, 1);
pub const __USE_ISOC95 = @as(c_int, 1);
pub const __USE_ISOC99 = @as(c_int, 1);
pub const __USE_XOPEN2K8 = @as(c_int, 1);
pub const _ATFILE_SOURCE = @as(c_int, 1);
pub const __WORDSIZE = @as(c_int, 64);
pub const __WORDSIZE_TIME64_COMPAT32 = @as(c_int, 1);
pub const __SYSCALL_WORDSIZE = @as(c_int, 64);
pub const __TIMESIZE = __WORDSIZE;
pub const __USE_MISC = @as(c_int, 1);
pub const __USE_ATFILE = @as(c_int, 1);
pub const __USE_FORTIFY_LEVEL = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_GETS = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_SCANF = @as(c_int, 0);
pub const __GLIBC_USE_C2X_STRTOL = @as(c_int, 0);
pub const _STDC_PREDEF_H = @as(c_int, 1);
pub const __STDC_IEC_559__ = @as(c_int, 1);
pub const __STDC_IEC_60559_BFP__ = @as(c_long, 201404);
pub const __STDC_IEC_559_COMPLEX__ = @as(c_int, 1);
pub const __STDC_IEC_60559_COMPLEX__ = @as(c_long, 201404);
pub const __STDC_ISO_10646__ = @as(c_long, 201706);
pub const __GNU_LIBRARY__ = @as(c_int, 6);
pub const __GLIBC__ = @as(c_int, 2);
pub const __GLIBC_MINOR__ = @as(c_int, 38);
pub inline fn __GLIBC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub const _SYS_CDEFS_H = @as(c_int, 1);
pub const __glibc_has_attribute = @compileError("unable to translate macro: undefined identifier `__has_attribute`"); // /usr/include/sys/cdefs.h:45:10
pub inline fn __glibc_has_builtin(name: anytype) @TypeOf(__builtin.has_builtin(name)) {
    _ = &name;
    return __builtin.has_builtin(name);
}
pub const __glibc_has_extension = @compileError("unable to translate macro: undefined identifier `__has_extension`"); // /usr/include/sys/cdefs.h:55:10
pub const __LEAF = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:65:11
pub const __LEAF_ATTR = @compileError("unable to translate macro: undefined identifier `__leaf__`"); // /usr/include/sys/cdefs.h:66:11
pub const __THROW = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:79:11
pub const __THROWNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:80:11
pub const __NTH = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:81:11
pub const __NTHNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`"); // /usr/include/sys/cdefs.h:82:11
pub const __COLD = @compileError("unable to translate macro: undefined identifier `__cold__`"); // /usr/include/sys/cdefs.h:102:11
pub inline fn __P(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub inline fn __PMT(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token '##'"); // /usr/include/sys/cdefs.h:131:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token ''"); // /usr/include/sys/cdefs.h:132:9
pub const __ptr_t = ?*anyopaque;
pub const __BEGIN_DECLS = "";
pub const __END_DECLS = "";
pub inline fn __bos(ptr: anytype) @TypeOf(__builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1))) {
    _ = &ptr;
    return __builtin.object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1));
}
pub inline fn __bos0(ptr: anytype) @TypeOf(__builtin.object_size(ptr, @as(c_int, 0))) {
    _ = &ptr;
    return __builtin.object_size(ptr, @as(c_int, 0));
}
pub inline fn __glibc_objsize0(__o: anytype) @TypeOf(__bos0(__o)) {
    _ = &__o;
    return __bos0(__o);
}
pub inline fn __glibc_objsize(__o: anytype) @TypeOf(__bos(__o)) {
    _ = &__o;
    return __bos(__o);
}
pub const __warnattr = @compileError("unable to translate macro: undefined identifier `__warning__`"); // /usr/include/sys/cdefs.h:212:10
pub const __errordecl = @compileError("unable to translate macro: undefined identifier `__error__`"); // /usr/include/sys/cdefs.h:213:10
pub const __flexarr = @compileError("unable to translate C expr: unexpected token '['"); // /usr/include/sys/cdefs.h:225:10
pub const __glibc_c99_flexarr_available = @as(c_int, 1);
pub const __REDIRECT = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:256:10
pub const __REDIRECT_NTH = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:263:11
pub const __REDIRECT_NTHNL = @compileError("unable to translate C expr: unexpected token '__asm__'"); // /usr/include/sys/cdefs.h:265:11
pub const __ASMNAME = @compileError("unable to translate macro: undefined identifier `__USER_LABEL_PREFIX__`"); // /usr/include/sys/cdefs.h:268:10
pub inline fn __ASMNAME2(prefix: anytype, cname: anytype) @TypeOf(__STRING(prefix) ++ cname) {
    _ = &prefix;
    _ = &cname;
    return __STRING(prefix) ++ cname;
}
pub const __REDIRECT_FORTIFY = __REDIRECT;
pub const __REDIRECT_FORTIFY_NTH = __REDIRECT_NTH;
pub const __attribute_malloc__ = @compileError("unable to translate macro: undefined identifier `__malloc__`"); // /usr/include/sys/cdefs.h:298:10
pub const __attribute_alloc_size__ = @compileError("unable to translate macro: undefined identifier `__alloc_size__`"); // /usr/include/sys/cdefs.h:306:10
pub const __attribute_alloc_align__ = @compileError("unable to translate macro: undefined identifier `__alloc_align__`"); // /usr/include/sys/cdefs.h:315:10
pub const __attribute_pure__ = @compileError("unable to translate macro: undefined identifier `__pure__`"); // /usr/include/sys/cdefs.h:325:10
pub const __attribute_const__ = @compileError("unable to translate C expr: unexpected token '__attribute__'"); // /usr/include/sys/cdefs.h:332:10
pub const __attribute_maybe_unused__ = @compileError("unable to translate macro: undefined identifier `__unused__`"); // /usr/include/sys/cdefs.h:338:10
pub const __attribute_used__ = @compileError("unable to translate macro: undefined identifier `__used__`"); // /usr/include/sys/cdefs.h:347:10
pub const __attribute_noinline__ = @compileError("unable to translate macro: undefined identifier `__noinline__`"); // /usr/include/sys/cdefs.h:348:10
pub const __attribute_deprecated__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:356:10
pub const __attribute_deprecated_msg__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`"); // /usr/include/sys/cdefs.h:366:10
pub const __attribute_format_arg__ = @compileError("unable to translate macro: undefined identifier `__format_arg__`"); // /usr/include/sys/cdefs.h:379:10
pub const __attribute_format_strfmon__ = @compileError("unable to translate macro: undefined identifier `__format__`"); // /usr/include/sys/cdefs.h:389:10
pub const __attribute_nonnull__ = @compileError("unable to translate macro: undefined identifier `__nonnull__`"); // /usr/include/sys/cdefs.h:401:11
pub inline fn __nonnull(params: anytype) @TypeOf(__attribute_nonnull__(params)) {
    _ = &params;
    return __attribute_nonnull__(params);
}
pub const __returns_nonnull = @compileError("unable to translate macro: undefined identifier `__returns_nonnull__`"); // /usr/include/sys/cdefs.h:414:10
pub const __attribute_warn_unused_result__ = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`"); // /usr/include/sys/cdefs.h:423:10
pub const __wur = "";
pub const __always_inline = @compileError("unable to translate macro: undefined identifier `__always_inline__`"); // /usr/include/sys/cdefs.h:441:10
pub const __attribute_artificial__ = @compileError("unable to translate macro: undefined identifier `__artificial__`"); // /usr/include/sys/cdefs.h:450:10
pub const __extern_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:472:11
pub const __extern_always_inline = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/sys/cdefs.h:473:11
pub const __fortify_function = __extern_always_inline ++ __attribute_artificial__;
pub const __va_arg_pack = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack`"); // /usr/include/sys/cdefs.h:484:10
pub const __va_arg_pack_len = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg_pack_len`"); // /usr/include/sys/cdefs.h:485:10
pub const __restrict_arr = @compileError("unable to translate C expr: unexpected token '__restrict'"); // /usr/include/sys/cdefs.h:512:10
pub inline fn __glibc_unlikely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 0))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 0));
}
pub inline fn __glibc_likely(cond: anytype) @TypeOf(__builtin.expect(cond, @as(c_int, 1))) {
    _ = &cond;
    return __builtin.expect(cond, @as(c_int, 1));
}
pub const __attribute_nonstring__ = "";
pub inline fn __attribute_copy__(arg: anytype) void {
    _ = &arg;
    return;
}
pub const __LDOUBLE_REDIRECTS_TO_FLOAT128_ABI = @as(c_int, 0);
pub inline fn __LDBL_REDIR1(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR(name: anytype, proto: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR1_NTH(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR_NTH(name: anytype, proto: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR2_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __LDBL_REDIR_DECL(name: anytype) void {
    _ = &name;
    return;
}
pub inline fn __REDIRECT_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT(name, proto, alias);
}
pub inline fn __REDIRECT_NTH_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT_NTH(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT_NTH(name, proto, alias);
}
pub const __glibc_macro_warning1 = @compileError("unable to translate macro: undefined identifier `_Pragma`"); // /usr/include/sys/cdefs.h:653:10
pub const __glibc_macro_warning = @compileError("unable to translate macro: undefined identifier `GCC`"); // /usr/include/sys/cdefs.h:654:10
pub const __HAVE_GENERIC_SELECTION = @as(c_int, 1);
pub inline fn __fortified_attr_access(a: anytype, o: anytype, s: anytype) void {
    _ = &a;
    _ = &o;
    _ = &s;
    return;
}
pub inline fn __attr_access(x: anytype) void {
    _ = &x;
    return;
}
pub inline fn __attr_access_none(argno: anytype) void {
    _ = &argno;
    return;
}
pub inline fn __attr_dealloc(dealloc: anytype, argno: anytype) void {
    _ = &dealloc;
    _ = &argno;
    return;
}
pub const __attr_dealloc_free = "";
pub const __attribute_returns_twice__ = @compileError("unable to translate macro: undefined identifier `__returns_twice__`"); // /usr/include/sys/cdefs.h:718:10
pub const __stub___compat_bdflush = "";
pub const __stub_chflags = "";
pub const __stub_fchflags = "";
pub const __stub_gtty = "";
pub const __stub_revoke = "";
pub const __stub_setlogin = "";
pub const __stub_sigreturn = "";
pub const __stub_stty = "";
pub const __need_size_t = "";
pub const __need_NULL = "";
pub const __STDC_VERSION_STDDEF_H__ = @as(c_long, 202311);
pub const NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stddef.h:18:9
pub const __need___va_list = "";
pub const __STDC_VERSION_STDARG_H__ = @as(c_int, 0);
pub const va_start = @compileError("unable to translate macro: undefined identifier `__builtin_va_start`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stdarg.h:12:9
pub const va_end = @compileError("unable to translate macro: undefined identifier `__builtin_va_end`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stdarg.h:14:9
pub const va_arg = @compileError("unable to translate macro: undefined identifier `__builtin_va_arg`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stdarg.h:15:9
pub const __va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stdarg.h:18:9
pub const va_copy = @compileError("unable to translate macro: undefined identifier `__builtin_va_copy`"); // /home/g/.local/share/ghr/tools/ctaggart/zig/zig-x86_64-linux-0.16.0/lib/compiler/aro/include/stdarg.h:22:9
pub const __GNUC_VA_LIST = @as(c_int, 1);
pub const _BITS_TYPES_H = @as(c_int, 1);
pub const __S16_TYPE = c_short;
pub const __U16_TYPE = c_ushort;
pub const __S32_TYPE = c_int;
pub const __U32_TYPE = c_uint;
pub const __SLONGWORD_TYPE = c_long;
pub const __ULONGWORD_TYPE = c_ulong;
pub const __SQUAD_TYPE = c_long;
pub const __UQUAD_TYPE = c_ulong;
pub const __SWORD_TYPE = c_long;
pub const __UWORD_TYPE = c_ulong;
pub const __SLONG32_TYPE = c_int;
pub const __ULONG32_TYPE = c_uint;
pub const __S64_TYPE = c_long;
pub const __U64_TYPE = c_ulong;
pub const _BITS_TYPESIZES_H = @as(c_int, 1);
pub const __SYSCALL_SLONG_TYPE = __SLONGWORD_TYPE;
pub const __SYSCALL_ULONG_TYPE = __ULONGWORD_TYPE;
pub const __DEV_T_TYPE = __UQUAD_TYPE;
pub const __UID_T_TYPE = __U32_TYPE;
pub const __GID_T_TYPE = __U32_TYPE;
pub const __INO_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __INO64_T_TYPE = __UQUAD_TYPE;
pub const __MODE_T_TYPE = __U32_TYPE;
pub const __NLINK_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSWORD_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __OFF64_T_TYPE = __SQUAD_TYPE;
pub const __PID_T_TYPE = __S32_TYPE;
pub const __RLIM_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __RLIM64_T_TYPE = __UQUAD_TYPE;
pub const __BLKCNT_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __BLKCNT64_T_TYPE = __SQUAD_TYPE;
pub const __FSBLKCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSBLKCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSFILCNT_T_TYPE = __SYSCALL_ULONG_TYPE;
pub const __FSFILCNT64_T_TYPE = __UQUAD_TYPE;
pub const __ID_T_TYPE = __U32_TYPE;
pub const __CLOCK_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __TIME_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __USECONDS_T_TYPE = __U32_TYPE;
pub const __SUSECONDS_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __SUSECONDS64_T_TYPE = __SQUAD_TYPE;
pub const __DADDR_T_TYPE = __S32_TYPE;
pub const __KEY_T_TYPE = __S32_TYPE;
pub const __CLOCKID_T_TYPE = __S32_TYPE;
pub const __TIMER_T_TYPE = ?*anyopaque;
pub const __BLKSIZE_T_TYPE = __SYSCALL_SLONG_TYPE;
pub const __FSID_T_TYPE = @compileError("unable to translate macro: undefined identifier `__val`"); // /usr/include/bits/typesizes.h:73:9
pub const __SSIZE_T_TYPE = __SWORD_TYPE;
pub const __CPU_MASK_TYPE = __SYSCALL_ULONG_TYPE;
pub const __OFF_T_MATCHES_OFF64_T = @as(c_int, 1);
pub const __INO_T_MATCHES_INO64_T = @as(c_int, 1);
pub const __RLIM_T_MATCHES_RLIM64_T = @as(c_int, 1);
pub const __STATFS_MATCHES_STATFS64 = @as(c_int, 1);
pub const __KERNEL_OLD_TIMEVAL_MATCHES_TIMEVAL64 = @as(c_int, 1);
pub const __FD_SETSIZE = @as(c_int, 1024);
pub const _BITS_TIME64_H = @as(c_int, 1);
pub const __TIME64_T_TYPE = __TIME_T_TYPE;
pub const _____fpos_t_defined = @as(c_int, 1);
pub const ____mbstate_t_defined = @as(c_int, 1);
pub const _____fpos64_t_defined = @as(c_int, 1);
pub const ____FILE_defined = @as(c_int, 1);
pub const __FILE_defined = @as(c_int, 1);
pub const __struct_FILE_defined = @as(c_int, 1);
pub const __getc_unlocked_body = @compileError("TODO postfix inc/dec expr"); // /usr/include/bits/types/struct_FILE.h:102:9
pub const __putc_unlocked_body = @compileError("TODO postfix inc/dec expr"); // /usr/include/bits/types/struct_FILE.h:106:9
pub const _IO_EOF_SEEN = @as(c_int, 0x0010);
pub inline fn __feof_unlocked_body(_fp: anytype) @TypeOf((_fp.*._flags & _IO_EOF_SEEN) != @as(c_int, 0)) {
    _ = &_fp;
    return (_fp.*._flags & _IO_EOF_SEEN) != @as(c_int, 0);
}
pub const _IO_ERR_SEEN = @as(c_int, 0x0020);
pub inline fn __ferror_unlocked_body(_fp: anytype) @TypeOf((_fp.*._flags & _IO_ERR_SEEN) != @as(c_int, 0)) {
    _ = &_fp;
    return (_fp.*._flags & _IO_ERR_SEEN) != @as(c_int, 0);
}
pub const _IO_USER_LOCK = __helpers.promoteIntLiteral(c_int, 0x8000, .hex);
pub const __cookie_io_functions_t_defined = @as(c_int, 1);
pub const _VA_LIST_DEFINED = "";
pub const __off_t_defined = "";
pub const __ssize_t_defined = "";
pub const _IOFBF = @as(c_int, 0);
pub const _IOLBF = @as(c_int, 1);
pub const _IONBF = @as(c_int, 2);
pub const BUFSIZ = @as(c_int, 8192);
pub const EOF = -@as(c_int, 1);
pub const SEEK_SET = @as(c_int, 0);
pub const SEEK_CUR = @as(c_int, 1);
pub const SEEK_END = @as(c_int, 2);
pub const P_tmpdir = "/tmp";
pub const L_tmpnam = @as(c_int, 20);
pub const TMP_MAX = __helpers.promoteIntLiteral(c_int, 238328, .decimal);
pub const _BITS_STDIO_LIM_H = @as(c_int, 1);
pub const FILENAME_MAX = @as(c_int, 4096);
pub const L_ctermid = @as(c_int, 9);
pub const FOPEN_MAX = @as(c_int, 16);
pub const __attr_dealloc_fclose = __attr_dealloc(fclose, @as(c_int, 1));
pub const _BITS_FLOATN_H = "";
pub const __HAVE_FLOAT128 = @as(c_int, 1);
pub const __HAVE_DISTINCT_FLOAT128 = @as(c_int, 1);
pub const __HAVE_FLOAT64X = @as(c_int, 1);
pub const __HAVE_FLOAT64X_LONG_DOUBLE = @as(c_int, 1);
pub const __f128 = @compileError("unable to translate macro: undefined identifier `f128`"); // /usr/include/bits/floatn.h:65:12
pub const __CFLOAT128 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn.h:77:12
pub const _BITS_FLOATN_COMMON_H = "";
pub const __HAVE_FLOAT16 = @as(c_int, 0);
pub const __HAVE_FLOAT32 = @as(c_int, 1);
pub const __HAVE_FLOAT64 = @as(c_int, 1);
pub const __HAVE_FLOAT32X = @as(c_int, 1);
pub const __HAVE_FLOAT128X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT16 = __HAVE_FLOAT16;
pub const __HAVE_DISTINCT_FLOAT32 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT32X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT128X = __HAVE_FLOAT128X;
pub const __HAVE_FLOAT128_UNLIKE_LDBL = (__HAVE_DISTINCT_FLOAT128 != 0) and (__LDBL_MANT_DIG__ != @as(c_int, 113));
pub const __HAVE_FLOATN_NOT_TYPEDEF = @as(c_int, 1);
pub const __f32 = @compileError("unable to translate macro: undefined identifier `f32`"); // /usr/include/bits/floatn-common.h:93:12
pub const __f64 = @compileError("unable to translate macro: undefined identifier `f64`"); // /usr/include/bits/floatn-common.h:105:12
pub const __f32x = @compileError("unable to translate macro: undefined identifier `f32x`"); // /usr/include/bits/floatn-common.h:113:12
pub const __f64x = @compileError("unable to translate macro: undefined identifier `f64x`"); // /usr/include/bits/floatn-common.h:125:12
pub const __CFLOAT32 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:151:12
pub const __CFLOAT64 = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:163:12
pub const __CFLOAT32X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:171:12
pub const __CFLOAT64X = @compileError("unable to translate: invalid numeric type"); // /usr/include/bits/floatn-common.h:183:12
pub const _STDINT_H = @as(c_int, 1);
pub const _BITS_WCHAR_H = @as(c_int, 1);
pub const __WCHAR_MAX = __WCHAR_MAX__;
pub const __WCHAR_MIN = -__WCHAR_MAX - @as(c_int, 1);
pub const _BITS_STDINT_INTN_H = @as(c_int, 1);
pub const _BITS_STDINT_UINTN_H = @as(c_int, 1);
pub const __intptr_t_defined = "";
pub const INT8_MIN = -@as(c_int, 128);
pub const INT16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT32_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT8_MAX = @as(c_int, 127);
pub const INT16_MAX = @as(c_int, 32767);
pub const INT32_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT8_MAX = @as(c_int, 255);
pub const UINT16_MAX = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT32_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_LEAST8_MIN = -@as(c_int, 128);
pub const INT_LEAST16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT_LEAST32_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT_LEAST64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_LEAST8_MAX = @as(c_int, 127);
pub const INT_LEAST16_MAX = @as(c_int, 32767);
pub const INT_LEAST32_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT_LEAST64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_LEAST8_MAX = @as(c_int, 255);
pub const UINT_LEAST16_MAX = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST32_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_FAST8_MIN = -@as(c_int, 128);
pub const INT_FAST16_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST32_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST64_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_FAST8_MAX = @as(c_int, 127);
pub const INT_FAST16_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST32_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST64_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_FAST8_MAX = @as(c_int, 255);
pub const UINT_FAST16_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST32_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INTPTR_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INTPTR_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const UINTPTR_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const INTMAX_MIN = -__INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INTMAX_MAX = __INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINTMAX_MAX = __UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const PTRDIFF_MIN = -__helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const PTRDIFF_MAX = __helpers.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const SIG_ATOMIC_MIN = -__helpers.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const SIG_ATOMIC_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const SIZE_MAX = __helpers.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const WCHAR_MIN = __WCHAR_MIN;
pub const WCHAR_MAX = __WCHAR_MAX;
pub const WINT_MIN = @as(c_uint, 0);
pub const WINT_MAX = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub inline fn INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const INT64_C = __helpers.L_SUFFIX;
pub inline fn UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const UINT32_C = __helpers.U_SUFFIX;
pub const UINT64_C = __helpers.UL_SUFFIX;
pub const INTMAX_C = __helpers.L_SUFFIX;
pub const UINTMAX_C = __helpers.UL_SUFFIX;
pub const __need_wchar_t = "";
pub const _STDLIB_H = @as(c_int, 1);
pub const WNOHANG = @as(c_int, 1);
pub const WUNTRACED = @as(c_int, 2);
pub const WSTOPPED = @as(c_int, 2);
pub const WEXITED = @as(c_int, 4);
pub const WCONTINUED = @as(c_int, 8);
pub const WNOWAIT = __helpers.promoteIntLiteral(c_int, 0x01000000, .hex);
pub const __WNOTHREAD = __helpers.promoteIntLiteral(c_int, 0x20000000, .hex);
pub const __WALL = __helpers.promoteIntLiteral(c_int, 0x40000000, .hex);
pub const __WCLONE = __helpers.promoteIntLiteral(c_int, 0x80000000, .hex);
pub inline fn __WEXITSTATUS(status: anytype) @TypeOf((status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8)) {
    _ = &status;
    return (status & __helpers.promoteIntLiteral(c_int, 0xff00, .hex)) >> @as(c_int, 8);
}
pub inline fn __WTERMSIG(status: anytype) @TypeOf(status & @as(c_int, 0x7f)) {
    _ = &status;
    return status & @as(c_int, 0x7f);
}
pub inline fn __WSTOPSIG(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn __WIFEXITED(status: anytype) @TypeOf(__WTERMSIG(status) == @as(c_int, 0)) {
    _ = &status;
    return __WTERMSIG(status) == @as(c_int, 0);
}
pub inline fn __WIFSIGNALED(status: anytype) @TypeOf((__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0)) {
    _ = &status;
    return (__helpers.cast(i8, (status & @as(c_int, 0x7f)) + @as(c_int, 1)) >> @as(c_int, 1)) > @as(c_int, 0);
}
pub inline fn __WIFSTOPPED(status: anytype) @TypeOf((status & @as(c_int, 0xff)) == @as(c_int, 0x7f)) {
    _ = &status;
    return (status & @as(c_int, 0xff)) == @as(c_int, 0x7f);
}
pub inline fn __WIFCONTINUED(status: anytype) @TypeOf(status == __W_CONTINUED) {
    _ = &status;
    return status == __W_CONTINUED;
}
pub inline fn __WCOREDUMP(status: anytype) @TypeOf(status & __WCOREFLAG) {
    _ = &status;
    return status & __WCOREFLAG;
}
pub inline fn __W_EXITCODE(ret: anytype, sig: anytype) @TypeOf((ret << @as(c_int, 8)) | sig) {
    _ = &ret;
    _ = &sig;
    return (ret << @as(c_int, 8)) | sig;
}
pub inline fn __W_STOPCODE(sig: anytype) @TypeOf((sig << @as(c_int, 8)) | @as(c_int, 0x7f)) {
    _ = &sig;
    return (sig << @as(c_int, 8)) | @as(c_int, 0x7f);
}
pub const __W_CONTINUED = __helpers.promoteIntLiteral(c_int, 0xffff, .hex);
pub const __WCOREFLAG = @as(c_int, 0x80);
pub inline fn WEXITSTATUS(status: anytype) @TypeOf(__WEXITSTATUS(status)) {
    _ = &status;
    return __WEXITSTATUS(status);
}
pub inline fn WTERMSIG(status: anytype) @TypeOf(__WTERMSIG(status)) {
    _ = &status;
    return __WTERMSIG(status);
}
pub inline fn WSTOPSIG(status: anytype) @TypeOf(__WSTOPSIG(status)) {
    _ = &status;
    return __WSTOPSIG(status);
}
pub inline fn WIFEXITED(status: anytype) @TypeOf(__WIFEXITED(status)) {
    _ = &status;
    return __WIFEXITED(status);
}
pub inline fn WIFSIGNALED(status: anytype) @TypeOf(__WIFSIGNALED(status)) {
    _ = &status;
    return __WIFSIGNALED(status);
}
pub inline fn WIFSTOPPED(status: anytype) @TypeOf(__WIFSTOPPED(status)) {
    _ = &status;
    return __WIFSTOPPED(status);
}
pub inline fn WIFCONTINUED(status: anytype) @TypeOf(__WIFCONTINUED(status)) {
    _ = &status;
    return __WIFCONTINUED(status);
}
pub const __ldiv_t_defined = @as(c_int, 1);
pub const __lldiv_t_defined = @as(c_int, 1);
pub const RAND_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const EXIT_FAILURE = @as(c_int, 1);
pub const EXIT_SUCCESS = @as(c_int, 0);
pub const MB_CUR_MAX = __ctype_get_mb_cur_max();
pub const _SYS_TYPES_H = @as(c_int, 1);
pub const __u_char_defined = "";
pub const __ino_t_defined = "";
pub const __dev_t_defined = "";
pub const __gid_t_defined = "";
pub const __mode_t_defined = "";
pub const __nlink_t_defined = "";
pub const __uid_t_defined = "";
pub const __pid_t_defined = "";
pub const __id_t_defined = "";
pub const __daddr_t_defined = "";
pub const __key_t_defined = "";
pub const __clock_t_defined = @as(c_int, 1);
pub const __clockid_t_defined = @as(c_int, 1);
pub const __time_t_defined = @as(c_int, 1);
pub const __timer_t_defined = @as(c_int, 1);
pub const __BIT_TYPES_DEFINED__ = @as(c_int, 1);
pub const _ENDIAN_H = @as(c_int, 1);
pub const _BITS_ENDIAN_H = @as(c_int, 1);
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __PDP_ENDIAN = @as(c_int, 3412);
pub const _BITS_ENDIANNESS_H = @as(c_int, 1);
pub const __BYTE_ORDER = __LITTLE_ENDIAN;
pub const __FLOAT_WORD_ORDER = __BYTE_ORDER;
pub inline fn __LONG_LONG_PAIR(HI: anytype, LO: anytype) @TypeOf(HI) {
    _ = &HI;
    _ = &LO;
    return blk: {
        _ = &LO;
        break :blk HI;
    };
}
pub const LITTLE_ENDIAN = __LITTLE_ENDIAN;
pub const BIG_ENDIAN = __BIG_ENDIAN;
pub const PDP_ENDIAN = __PDP_ENDIAN;
pub const BYTE_ORDER = __BYTE_ORDER;
pub const _BITS_BYTESWAP_H = @as(c_int, 1);
pub inline fn __bswap_constant_16(x: anytype) __uint16_t {
    _ = &x;
    return __helpers.cast(__uint16_t, ((x >> @as(c_int, 8)) & @as(c_int, 0xff)) | ((x & @as(c_int, 0xff)) << @as(c_int, 8)));
}
pub inline fn __bswap_constant_32(x: anytype) @TypeOf(((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24))) {
    _ = &x;
    return ((((x & __helpers.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & __helpers.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24));
}
pub inline fn __bswap_constant_64(x: anytype) @TypeOf(((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56))) {
    _ = &x;
    return ((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56));
}
pub const _BITS_UINTN_IDENTITY_H = @as(c_int, 1);
pub inline fn htobe16(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn htole16(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn be16toh(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn le16toh(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn htobe32(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn htole32(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn be32toh(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn le32toh(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn htobe64(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn htole64(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub inline fn be64toh(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn le64toh(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub const _SYS_SELECT_H = @as(c_int, 1);
pub const __FD_ZERO = @compileError("unable to translate macro: undefined identifier `__i`"); // /usr/include/bits/select.h:25:9
pub const __FD_SET = @compileError("unable to translate C expr: expected ')' instead got '|='"); // /usr/include/bits/select.h:32:9
pub const __FD_CLR = @compileError("unable to translate C expr: expected ')' instead got '&='"); // /usr/include/bits/select.h:34:9
pub inline fn __FD_ISSET(d: anytype, s: anytype) @TypeOf((__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0)) {
    _ = &d;
    _ = &s;
    return (__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0);
}
pub const __sigset_t_defined = @as(c_int, 1);
pub const ____sigset_t_defined = "";
pub const _SIGSET_NWORDS = __helpers.div(@as(c_int, 1024), @as(c_int, 8) * __helpers.sizeof(c_ulong));
pub const __timeval_defined = @as(c_int, 1);
pub const _STRUCT_TIMESPEC = @as(c_int, 1);
pub const __suseconds_t_defined = "";
pub const __NFDBITS = @as(c_int, 8) * __helpers.cast(c_int, __helpers.sizeof(__fd_mask));
pub inline fn __FD_ELT(d: anytype) @TypeOf(__helpers.div(d, __NFDBITS)) {
    _ = &d;
    return __helpers.div(d, __NFDBITS);
}
pub inline fn __FD_MASK(d: anytype) __fd_mask {
    _ = &d;
    return __helpers.cast(__fd_mask, @as(c_ulong, 1) << __helpers.rem(d, __NFDBITS));
}
pub inline fn __FDS_BITS(set: anytype) @TypeOf(set.*.__fds_bits) {
    _ = &set;
    return set.*.__fds_bits;
}
pub const FD_SETSIZE = __FD_SETSIZE;
pub const NFDBITS = __NFDBITS;
pub inline fn FD_SET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_SET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_SET(fd, fdsetp);
}
pub inline fn FD_CLR(fd: anytype, fdsetp: anytype) @TypeOf(__FD_CLR(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_CLR(fd, fdsetp);
}
pub inline fn FD_ISSET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_ISSET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_ISSET(fd, fdsetp);
}
pub inline fn FD_ZERO(fdsetp: anytype) @TypeOf(__FD_ZERO(fdsetp)) {
    _ = &fdsetp;
    return __FD_ZERO(fdsetp);
}
pub const __blksize_t_defined = "";
pub const __blkcnt_t_defined = "";
pub const __fsblkcnt_t_defined = "";
pub const __fsfilcnt_t_defined = "";
pub const _BITS_PTHREADTYPES_COMMON_H = @as(c_int, 1);
pub const _THREAD_SHARED_TYPES_H = @as(c_int, 1);
pub const _BITS_PTHREADTYPES_ARCH_H = @as(c_int, 1);
pub const __SIZEOF_PTHREAD_MUTEX_T = @as(c_int, 40);
pub const __SIZEOF_PTHREAD_ATTR_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_RWLOCK_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_BARRIER_T = @as(c_int, 32);
pub const __SIZEOF_PTHREAD_MUTEXATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_COND_T = @as(c_int, 48);
pub const __SIZEOF_PTHREAD_CONDATTR_T = @as(c_int, 4);
pub const __SIZEOF_PTHREAD_RWLOCKATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_BARRIERATTR_T = @as(c_int, 4);
pub const __LOCK_ALIGNMENT = "";
pub const __ONCE_ALIGNMENT = "";
pub const _BITS_ATOMIC_WIDE_COUNTER_H = "";
pub const _THREAD_MUTEX_INTERNAL_H = @as(c_int, 1);
pub const __PTHREAD_MUTEX_HAVE_PREV = @as(c_int, 1);
pub const __PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/struct_mutex.h:56:10
pub const _RWLOCK_INTERNAL_H = "";
pub const __PTHREAD_RWLOCK_ELISION_EXTRA = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/struct_rwlock.h:40:11
pub inline fn __PTHREAD_RWLOCK_INITIALIZER(__flags: anytype) @TypeOf(__flags) {
    _ = &__flags;
    return blk: {
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = &__PTHREAD_RWLOCK_ELISION_EXTRA;
        _ = @as(c_int, 0);
        break :blk __flags;
    };
}
pub const __ONCE_FLAG_INIT = @compileError("unable to translate C expr: unexpected token '{'"); // /usr/include/bits/thread-shared-types.h:114:9
pub const __have_pthread_attr_t = @as(c_int, 1);
pub const _ALLOCA_H = @as(c_int, 1);
pub const __COMPAR_FN_T = "";
pub const _STRING_H = @as(c_int, 1);
pub const _BITS_TYPES_LOCALE_T_H = @as(c_int, 1);
pub const _BITS_TYPES___LOCALE_T_H = @as(c_int, 1);
pub const _STRINGS_H = @as(c_int, 1);
pub const _ERRNO_H = @as(c_int, 1);
pub const _BITS_ERRNO_H = @as(c_int, 1);
pub const _ASM_GENERIC_ERRNO_H = "";
pub const _ASM_GENERIC_ERRNO_BASE_H = "";
pub const EPERM = @as(c_int, 1);
pub const ENOENT = @as(c_int, 2);
pub const ESRCH = @as(c_int, 3);
pub const EINTR = @as(c_int, 4);
pub const EIO = @as(c_int, 5);
pub const ENXIO = @as(c_int, 6);
pub const E2BIG = @as(c_int, 7);
pub const ENOEXEC = @as(c_int, 8);
pub const EBADF = @as(c_int, 9);
pub const ECHILD = @as(c_int, 10);
pub const EAGAIN = @as(c_int, 11);
pub const ENOMEM = @as(c_int, 12);
pub const EACCES = @as(c_int, 13);
pub const EFAULT = @as(c_int, 14);
pub const ENOTBLK = @as(c_int, 15);
pub const EBUSY = @as(c_int, 16);
pub const EEXIST = @as(c_int, 17);
pub const EXDEV = @as(c_int, 18);
pub const ENODEV = @as(c_int, 19);
pub const ENOTDIR = @as(c_int, 20);
pub const EISDIR = @as(c_int, 21);
pub const EINVAL = @as(c_int, 22);
pub const ENFILE = @as(c_int, 23);
pub const EMFILE = @as(c_int, 24);
pub const ENOTTY = @as(c_int, 25);
pub const ETXTBSY = @as(c_int, 26);
pub const EFBIG = @as(c_int, 27);
pub const ENOSPC = @as(c_int, 28);
pub const ESPIPE = @as(c_int, 29);
pub const EROFS = @as(c_int, 30);
pub const EMLINK = @as(c_int, 31);
pub const EPIPE = @as(c_int, 32);
pub const EDOM = @as(c_int, 33);
pub const ERANGE = @as(c_int, 34);
pub const EDEADLK = @as(c_int, 35);
pub const ENAMETOOLONG = @as(c_int, 36);
pub const ENOLCK = @as(c_int, 37);
pub const ENOSYS = @as(c_int, 38);
pub const ENOTEMPTY = @as(c_int, 39);
pub const ELOOP = @as(c_int, 40);
pub const EWOULDBLOCK = EAGAIN;
pub const ENOMSG = @as(c_int, 42);
pub const EIDRM = @as(c_int, 43);
pub const ECHRNG = @as(c_int, 44);
pub const EL2NSYNC = @as(c_int, 45);
pub const EL3HLT = @as(c_int, 46);
pub const EL3RST = @as(c_int, 47);
pub const ELNRNG = @as(c_int, 48);
pub const EUNATCH = @as(c_int, 49);
pub const ENOCSI = @as(c_int, 50);
pub const EL2HLT = @as(c_int, 51);
pub const EBADE = @as(c_int, 52);
pub const EBADR = @as(c_int, 53);
pub const EXFULL = @as(c_int, 54);
pub const ENOANO = @as(c_int, 55);
pub const EBADRQC = @as(c_int, 56);
pub const EBADSLT = @as(c_int, 57);
pub const EDEADLOCK = EDEADLK;
pub const EBFONT = @as(c_int, 59);
pub const ENOSTR = @as(c_int, 60);
pub const ENODATA = @as(c_int, 61);
pub const ETIME = @as(c_int, 62);
pub const ENOSR = @as(c_int, 63);
pub const ENONET = @as(c_int, 64);
pub const ENOPKG = @as(c_int, 65);
pub const EREMOTE = @as(c_int, 66);
pub const ENOLINK = @as(c_int, 67);
pub const EADV = @as(c_int, 68);
pub const ESRMNT = @as(c_int, 69);
pub const ECOMM = @as(c_int, 70);
pub const EPROTO = @as(c_int, 71);
pub const EMULTIHOP = @as(c_int, 72);
pub const EDOTDOT = @as(c_int, 73);
pub const EBADMSG = @as(c_int, 74);
pub const EOVERFLOW = @as(c_int, 75);
pub const ENOTUNIQ = @as(c_int, 76);
pub const EBADFD = @as(c_int, 77);
pub const EREMCHG = @as(c_int, 78);
pub const ELIBACC = @as(c_int, 79);
pub const ELIBBAD = @as(c_int, 80);
pub const ELIBSCN = @as(c_int, 81);
pub const ELIBMAX = @as(c_int, 82);
pub const ELIBEXEC = @as(c_int, 83);
pub const EILSEQ = @as(c_int, 84);
pub const ERESTART = @as(c_int, 85);
pub const ESTRPIPE = @as(c_int, 86);
pub const EUSERS = @as(c_int, 87);
pub const ENOTSOCK = @as(c_int, 88);
pub const EDESTADDRREQ = @as(c_int, 89);
pub const EMSGSIZE = @as(c_int, 90);
pub const EPROTOTYPE = @as(c_int, 91);
pub const ENOPROTOOPT = @as(c_int, 92);
pub const EPROTONOSUPPORT = @as(c_int, 93);
pub const ESOCKTNOSUPPORT = @as(c_int, 94);
pub const EOPNOTSUPP = @as(c_int, 95);
pub const EPFNOSUPPORT = @as(c_int, 96);
pub const EAFNOSUPPORT = @as(c_int, 97);
pub const EADDRINUSE = @as(c_int, 98);
pub const EADDRNOTAVAIL = @as(c_int, 99);
pub const ENETDOWN = @as(c_int, 100);
pub const ENETUNREACH = @as(c_int, 101);
pub const ENETRESET = @as(c_int, 102);
pub const ECONNABORTED = @as(c_int, 103);
pub const ECONNRESET = @as(c_int, 104);
pub const ENOBUFS = @as(c_int, 105);
pub const EISCONN = @as(c_int, 106);
pub const ENOTCONN = @as(c_int, 107);
pub const ESHUTDOWN = @as(c_int, 108);
pub const ETOOMANYREFS = @as(c_int, 109);
pub const ETIMEDOUT = @as(c_int, 110);
pub const ECONNREFUSED = @as(c_int, 111);
pub const EHOSTDOWN = @as(c_int, 112);
pub const EHOSTUNREACH = @as(c_int, 113);
pub const EALREADY = @as(c_int, 114);
pub const EINPROGRESS = @as(c_int, 115);
pub const ESTALE = @as(c_int, 116);
pub const EUCLEAN = @as(c_int, 117);
pub const ENOTNAM = @as(c_int, 118);
pub const ENAVAIL = @as(c_int, 119);
pub const EISNAM = @as(c_int, 120);
pub const EREMOTEIO = @as(c_int, 121);
pub const EDQUOT = @as(c_int, 122);
pub const ENOMEDIUM = @as(c_int, 123);
pub const EMEDIUMTYPE = @as(c_int, 124);
pub const ECANCELED = @as(c_int, 125);
pub const ENOKEY = @as(c_int, 126);
pub const EKEYEXPIRED = @as(c_int, 127);
pub const EKEYREVOKED = @as(c_int, 128);
pub const EKEYREJECTED = @as(c_int, 129);
pub const EOWNERDEAD = @as(c_int, 130);
pub const ENOTRECOVERABLE = @as(c_int, 131);
pub const ERFKILL = @as(c_int, 132);
pub const EHWPOISON = @as(c_int, 133);
pub const ENOTSUP = EOPNOTSUPP;
pub const errno = __errno_location().*;
pub const @"bool" = bool;
pub const @"true" = @as(c_int, 1);
pub const @"false" = @as(c_int, 0);
pub const __bool_true_false_are_defined = @as(c_int, 1);
pub const _UNISTD_H = @as(c_int, 1);
pub const _POSIX_VERSION = @as(c_long, 200809);
pub const __POSIX2_THIS_VERSION = @as(c_long, 200809);
pub const _POSIX2_VERSION = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_VERSION = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_BIND = __POSIX2_THIS_VERSION;
pub const _POSIX2_C_DEV = __POSIX2_THIS_VERSION;
pub const _POSIX2_SW_DEV = __POSIX2_THIS_VERSION;
pub const _POSIX2_LOCALEDEF = __POSIX2_THIS_VERSION;
pub const _XOPEN_VERSION = @as(c_int, 700);
pub const _XOPEN_XCU_VERSION = @as(c_int, 4);
pub const _XOPEN_XPG2 = @as(c_int, 1);
pub const _XOPEN_XPG3 = @as(c_int, 1);
pub const _XOPEN_XPG4 = @as(c_int, 1);
pub const _XOPEN_UNIX = @as(c_int, 1);
pub const _XOPEN_ENH_I18N = @as(c_int, 1);
pub const _XOPEN_LEGACY = @as(c_int, 1);
pub const _BITS_POSIX_OPT_H = @as(c_int, 1);
pub const _POSIX_JOB_CONTROL = @as(c_int, 1);
pub const _POSIX_SAVED_IDS = @as(c_int, 1);
pub const _POSIX_PRIORITY_SCHEDULING = @as(c_long, 200809);
pub const _POSIX_SYNCHRONIZED_IO = @as(c_long, 200809);
pub const _POSIX_FSYNC = @as(c_long, 200809);
pub const _POSIX_MAPPED_FILES = @as(c_long, 200809);
pub const _POSIX_MEMLOCK = @as(c_long, 200809);
pub const _POSIX_MEMLOCK_RANGE = @as(c_long, 200809);
pub const _POSIX_MEMORY_PROTECTION = @as(c_long, 200809);
pub const _POSIX_CHOWN_RESTRICTED = @as(c_int, 0);
pub const _POSIX_VDISABLE = '\x00';
pub const _POSIX_NO_TRUNC = @as(c_int, 1);
pub const _XOPEN_REALTIME = @as(c_int, 1);
pub const _XOPEN_REALTIME_THREADS = @as(c_int, 1);
pub const _XOPEN_SHM = @as(c_int, 1);
pub const _POSIX_THREADS = @as(c_long, 200809);
pub const _POSIX_REENTRANT_FUNCTIONS = @as(c_int, 1);
pub const _POSIX_THREAD_SAFE_FUNCTIONS = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIORITY_SCHEDULING = @as(c_long, 200809);
pub const _POSIX_THREAD_ATTR_STACKSIZE = @as(c_long, 200809);
pub const _POSIX_THREAD_ATTR_STACKADDR = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIO_INHERIT = @as(c_long, 200809);
pub const _POSIX_THREAD_PRIO_PROTECT = @as(c_long, 200809);
pub const _POSIX_THREAD_ROBUST_PRIO_INHERIT = @as(c_long, 200809);
pub const _POSIX_THREAD_ROBUST_PRIO_PROTECT = -@as(c_int, 1);
pub const _POSIX_SEMAPHORES = @as(c_long, 200809);
pub const _POSIX_REALTIME_SIGNALS = @as(c_long, 200809);
pub const _POSIX_ASYNCHRONOUS_IO = @as(c_long, 200809);
pub const _POSIX_ASYNC_IO = @as(c_int, 1);
pub const _LFS_ASYNCHRONOUS_IO = @as(c_int, 1);
pub const _POSIX_PRIORITIZED_IO = @as(c_long, 200809);
pub const _LFS64_ASYNCHRONOUS_IO = @as(c_int, 1);
pub const _LFS_LARGEFILE = @as(c_int, 1);
pub const _LFS64_LARGEFILE = @as(c_int, 1);
pub const _LFS64_STDIO = @as(c_int, 1);
pub const _POSIX_SHARED_MEMORY_OBJECTS = @as(c_long, 200809);
pub const _POSIX_CPUTIME = @as(c_int, 0);
pub const _POSIX_THREAD_CPUTIME = @as(c_int, 0);
pub const _POSIX_REGEXP = @as(c_int, 1);
pub const _POSIX_READER_WRITER_LOCKS = @as(c_long, 200809);
pub const _POSIX_SHELL = @as(c_int, 1);
pub const _POSIX_TIMEOUTS = @as(c_long, 200809);
pub const _POSIX_SPIN_LOCKS = @as(c_long, 200809);
pub const _POSIX_SPAWN = @as(c_long, 200809);
pub const _POSIX_TIMERS = @as(c_long, 200809);
pub const _POSIX_BARRIERS = @as(c_long, 200809);
pub const _POSIX_MESSAGE_PASSING = @as(c_long, 200809);
pub const _POSIX_THREAD_PROCESS_SHARED = @as(c_long, 200809);
pub const _POSIX_MONOTONIC_CLOCK = @as(c_int, 0);
pub const _POSIX_CLOCK_SELECTION = @as(c_long, 200809);
pub const _POSIX_ADVISORY_INFO = @as(c_long, 200809);
pub const _POSIX_IPV6 = @as(c_long, 200809);
pub const _POSIX_RAW_SOCKETS = @as(c_long, 200809);
pub const _POSIX2_CHAR_TERM = @as(c_long, 200809);
pub const _POSIX_SPORADIC_SERVER = -@as(c_int, 1);
pub const _POSIX_THREAD_SPORADIC_SERVER = -@as(c_int, 1);
pub const _POSIX_TRACE = -@as(c_int, 1);
pub const _POSIX_TRACE_EVENT_FILTER = -@as(c_int, 1);
pub const _POSIX_TRACE_INHERIT = -@as(c_int, 1);
pub const _POSIX_TRACE_LOG = -@as(c_int, 1);
pub const _POSIX_TYPED_MEMORY_OBJECTS = -@as(c_int, 1);
pub const _POSIX_V7_LPBIG_OFFBIG = -@as(c_int, 1);
pub const _POSIX_V6_LPBIG_OFFBIG = -@as(c_int, 1);
pub const _XBS5_LPBIG_OFFBIG = -@as(c_int, 1);
pub const _POSIX_V7_LP64_OFF64 = @as(c_int, 1);
pub const _POSIX_V6_LP64_OFF64 = @as(c_int, 1);
pub const _XBS5_LP64_OFF64 = @as(c_int, 1);
pub const __ILP32_OFF32_CFLAGS = "-m32";
pub const __ILP32_OFF32_LDFLAGS = "-m32";
pub const __ILP32_OFFBIG_CFLAGS = "-m32 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64";
pub const __ILP32_OFFBIG_LDFLAGS = "-m32";
pub const __LP64_OFF64_CFLAGS = "-m64";
pub const __LP64_OFF64_LDFLAGS = "-m64";
pub const STDIN_FILENO = @as(c_int, 0);
pub const STDOUT_FILENO = @as(c_int, 1);
pub const STDERR_FILENO = @as(c_int, 2);
pub const __useconds_t_defined = "";
pub const __socklen_t_defined = "";
pub const R_OK = @as(c_int, 4);
pub const W_OK = @as(c_int, 2);
pub const X_OK = @as(c_int, 1);
pub const F_OK = @as(c_int, 0);
pub const L_SET = SEEK_SET;
pub const L_INCR = SEEK_CUR;
pub const L_XTND = SEEK_END;
pub const _SC_PAGE_SIZE = _SC_PAGESIZE;
pub const _CS_POSIX_V6_WIDTH_RESTRICTED_ENVS = _CS_V6_WIDTH_RESTRICTED_ENVS;
pub const _CS_POSIX_V5_WIDTH_RESTRICTED_ENVS = _CS_V5_WIDTH_RESTRICTED_ENVS;
pub const _CS_POSIX_V7_WIDTH_RESTRICTED_ENVS = _CS_V7_WIDTH_RESTRICTED_ENVS;
pub const _GETOPT_POSIX_H = @as(c_int, 1);
pub const _GETOPT_CORE_H = @as(c_int, 1);
pub const F_ULOCK = @as(c_int, 0);
pub const F_LOCK = @as(c_int, 1);
pub const F_TLOCK = @as(c_int, 2);
pub const F_TEST = @as(c_int, 3);
pub const _FCNTL_H = @as(c_int, 1);
pub const __O_LARGEFILE = @as(c_int, 0);
pub const F_GETLK64 = @as(c_int, 5);
pub const F_SETLK64 = @as(c_int, 6);
pub const F_SETLKW64 = @as(c_int, 7);
pub const O_ACCMODE = @as(c_int, 0o003);
pub const O_RDONLY = @as(c_int, 0o0);
pub const O_WRONLY = @as(c_int, 0o1);
pub const O_RDWR = @as(c_int, 0o2);
pub const O_CREAT = @as(c_int, 0o100);
pub const O_EXCL = @as(c_int, 0o200);
pub const O_NOCTTY = @as(c_int, 0o400);
pub const O_TRUNC = @as(c_int, 0o1000);
pub const O_APPEND = @as(c_int, 0o2000);
pub const O_NONBLOCK = @as(c_int, 0o4000);
pub const O_NDELAY = O_NONBLOCK;
pub const O_SYNC = __helpers.promoteIntLiteral(c_int, 0o4010000, .octal);
pub const O_FSYNC = O_SYNC;
pub const O_ASYNC = @as(c_int, 0o20000);
pub const __O_DIRECTORY = __helpers.promoteIntLiteral(c_int, 0o200000, .octal);
pub const __O_NOFOLLOW = __helpers.promoteIntLiteral(c_int, 0o400000, .octal);
pub const __O_CLOEXEC = __helpers.promoteIntLiteral(c_int, 0o2000000, .octal);
pub const __O_DIRECT = @as(c_int, 0o40000);
pub const __O_NOATIME = __helpers.promoteIntLiteral(c_int, 0o1000000, .octal);
pub const __O_PATH = __helpers.promoteIntLiteral(c_int, 0o10000000, .octal);
pub const __O_DSYNC = @as(c_int, 0o10000);
pub const __O_TMPFILE = __helpers.promoteIntLiteral(c_int, 0o20000000, .octal) | __O_DIRECTORY;
pub const F_GETLK = F_GETLK64;
pub const F_SETLK = F_SETLK64;
pub const F_SETLKW = F_SETLKW64;
pub const O_DIRECTORY = __O_DIRECTORY;
pub const O_NOFOLLOW = __O_NOFOLLOW;
pub const O_CLOEXEC = __O_CLOEXEC;
pub const O_DSYNC = __O_DSYNC;
pub const O_RSYNC = O_SYNC;
pub const F_DUPFD = @as(c_int, 0);
pub const F_GETFD = @as(c_int, 1);
pub const F_SETFD = @as(c_int, 2);
pub const F_GETFL = @as(c_int, 3);
pub const F_SETFL = @as(c_int, 4);
pub const __F_SETOWN = @as(c_int, 8);
pub const __F_GETOWN = @as(c_int, 9);
pub const F_SETOWN = __F_SETOWN;
pub const F_GETOWN = __F_GETOWN;
pub const __F_SETSIG = @as(c_int, 10);
pub const __F_GETSIG = @as(c_int, 11);
pub const __F_SETOWN_EX = @as(c_int, 15);
pub const __F_GETOWN_EX = @as(c_int, 16);
pub const F_DUPFD_CLOEXEC = @as(c_int, 1030);
pub const FD_CLOEXEC = @as(c_int, 1);
pub const F_RDLCK = @as(c_int, 0);
pub const F_WRLCK = @as(c_int, 1);
pub const F_UNLCK = @as(c_int, 2);
pub const F_EXLCK = @as(c_int, 4);
pub const F_SHLCK = @as(c_int, 8);
pub const LOCK_SH = @as(c_int, 1);
pub const LOCK_EX = @as(c_int, 2);
pub const LOCK_NB = @as(c_int, 4);
pub const LOCK_UN = @as(c_int, 8);
pub const FAPPEND = O_APPEND;
pub const FFSYNC = O_FSYNC;
pub const FASYNC = O_ASYNC;
pub const FNONBLOCK = O_NONBLOCK;
pub const FNDELAY = O_NDELAY;
pub const __POSIX_FADV_DONTNEED = @as(c_int, 4);
pub const __POSIX_FADV_NOREUSE = @as(c_int, 5);
pub const POSIX_FADV_NORMAL = @as(c_int, 0);
pub const POSIX_FADV_RANDOM = @as(c_int, 1);
pub const POSIX_FADV_SEQUENTIAL = @as(c_int, 2);
pub const POSIX_FADV_WILLNEED = @as(c_int, 3);
pub const POSIX_FADV_DONTNEED = __POSIX_FADV_DONTNEED;
pub const POSIX_FADV_NOREUSE = __POSIX_FADV_NOREUSE;
pub inline fn __OPEN_NEEDS_MODE(oflag: anytype) @TypeOf(((oflag & O_CREAT) != @as(c_int, 0)) or ((oflag & __O_TMPFILE) == __O_TMPFILE)) {
    _ = &oflag;
    return ((oflag & O_CREAT) != @as(c_int, 0)) or ((oflag & __O_TMPFILE) == __O_TMPFILE);
}
pub const _BITS_STAT_H = @as(c_int, 1);
pub const _BITS_STRUCT_STAT_H = @as(c_int, 1);
pub const st_atime = @compileError("unable to translate macro: undefined identifier `st_atim`"); // /usr/include/bits/struct_stat.h:77:11
pub const st_mtime = @compileError("unable to translate macro: undefined identifier `st_mtim`"); // /usr/include/bits/struct_stat.h:78:11
pub const st_ctime = @compileError("unable to translate macro: undefined identifier `st_ctim`"); // /usr/include/bits/struct_stat.h:79:11
pub const _STATBUF_ST_BLKSIZE = "";
pub const _STATBUF_ST_RDEV = "";
pub const _STATBUF_ST_NSEC = "";
pub const __S_IFMT = __helpers.promoteIntLiteral(c_int, 0o170000, .octal);
pub const __S_IFDIR = @as(c_int, 0o040000);
pub const __S_IFCHR = @as(c_int, 0o020000);
pub const __S_IFBLK = @as(c_int, 0o060000);
pub const __S_IFREG = __helpers.promoteIntLiteral(c_int, 0o100000, .octal);
pub const __S_IFIFO = @as(c_int, 0o010000);
pub const __S_IFLNK = __helpers.promoteIntLiteral(c_int, 0o120000, .octal);
pub const __S_IFSOCK = __helpers.promoteIntLiteral(c_int, 0o140000, .octal);
pub inline fn __S_TYPEISMQ(buf: anytype) @TypeOf(buf.*.st_mode - buf.*.st_mode) {
    _ = &buf;
    return buf.*.st_mode - buf.*.st_mode;
}
pub inline fn __S_TYPEISSEM(buf: anytype) @TypeOf(buf.*.st_mode - buf.*.st_mode) {
    _ = &buf;
    return buf.*.st_mode - buf.*.st_mode;
}
pub inline fn __S_TYPEISSHM(buf: anytype) @TypeOf(buf.*.st_mode - buf.*.st_mode) {
    _ = &buf;
    return buf.*.st_mode - buf.*.st_mode;
}
pub const __S_ISUID = @as(c_int, 0o4000);
pub const __S_ISGID = @as(c_int, 0o2000);
pub const __S_ISVTX = @as(c_int, 0o1000);
pub const __S_IREAD = @as(c_int, 0o400);
pub const __S_IWRITE = @as(c_int, 0o200);
pub const __S_IEXEC = @as(c_int, 0o100);
pub const UTIME_NOW = (@as(c_long, 1) << @as(c_int, 30)) - @as(c_long, 1);
pub const UTIME_OMIT = (@as(c_long, 1) << @as(c_int, 30)) - @as(c_long, 2);
pub const S_IFMT = __S_IFMT;
pub const S_IFDIR = __S_IFDIR;
pub const S_IFCHR = __S_IFCHR;
pub const S_IFBLK = __S_IFBLK;
pub const S_IFREG = __S_IFREG;
pub const S_IFIFO = __S_IFIFO;
pub const S_IFLNK = __S_IFLNK;
pub const S_IFSOCK = __S_IFSOCK;
pub const S_ISUID = __S_ISUID;
pub const S_ISGID = __S_ISGID;
pub const S_ISVTX = __S_ISVTX;
pub const S_IRUSR = __S_IREAD;
pub const S_IWUSR = __S_IWRITE;
pub const S_IXUSR = __S_IEXEC;
pub const S_IRWXU = (__S_IREAD | __S_IWRITE) | __S_IEXEC;
pub const S_IRGRP = S_IRUSR >> @as(c_int, 3);
pub const S_IWGRP = S_IWUSR >> @as(c_int, 3);
pub const S_IXGRP = S_IXUSR >> @as(c_int, 3);
pub const S_IRWXG = S_IRWXU >> @as(c_int, 3);
pub const S_IROTH = S_IRGRP >> @as(c_int, 3);
pub const S_IWOTH = S_IWGRP >> @as(c_int, 3);
pub const S_IXOTH = S_IXGRP >> @as(c_int, 3);
pub const S_IRWXO = S_IRWXG >> @as(c_int, 3);
pub const AT_FDCWD = -@as(c_int, 100);
pub const AT_SYMLINK_NOFOLLOW = @as(c_int, 0x100);
pub const AT_REMOVEDIR = @as(c_int, 0x200);
pub const AT_SYMLINK_FOLLOW = @as(c_int, 0x400);
pub const AT_EACCESS = @as(c_int, 0x200);
pub const _FTW_H = @as(c_int, 1);
pub const _SYS_STAT_H = @as(c_int, 1);
pub inline fn __S_ISTYPE(mode: anytype, mask: anytype) @TypeOf((mode & __S_IFMT) == mask) {
    _ = &mode;
    _ = &mask;
    return (mode & __S_IFMT) == mask;
}
pub inline fn S_ISDIR(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFDIR)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFDIR);
}
pub inline fn S_ISCHR(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFCHR)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFCHR);
}
pub inline fn S_ISBLK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFBLK)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFBLK);
}
pub inline fn S_ISREG(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFREG)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFREG);
}
pub inline fn S_ISFIFO(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFIFO)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFIFO);
}
pub inline fn S_ISLNK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFLNK)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFLNK);
}
pub inline fn S_ISSOCK(mode: anytype) @TypeOf(__S_ISTYPE(mode, __S_IFSOCK)) {
    _ = &mode;
    return __S_ISTYPE(mode, __S_IFSOCK);
}
pub inline fn S_TYPEISMQ(buf: anytype) @TypeOf(__S_TYPEISMQ(buf)) {
    _ = &buf;
    return __S_TYPEISMQ(buf);
}
pub inline fn S_TYPEISSEM(buf: anytype) @TypeOf(__S_TYPEISSEM(buf)) {
    _ = &buf;
    return __S_TYPEISSEM(buf);
}
pub inline fn S_TYPEISSHM(buf: anytype) @TypeOf(__S_TYPEISSHM(buf)) {
    _ = &buf;
    return __S_TYPEISSHM(buf);
}
pub const S_IREAD = S_IRUSR;
pub const S_IWRITE = S_IWUSR;
pub const S_IEXEC = S_IXUSR;
pub const ACCESSPERMS = (S_IRWXU | S_IRWXG) | S_IRWXO;
pub const ALLPERMS = ((((S_ISUID | S_ISGID) | S_ISVTX) | S_IRWXU) | S_IRWXG) | S_IRWXO;
pub const DEFFILEMODE = ((((S_IRUSR | S_IWUSR) | S_IRGRP) | S_IWGRP) | S_IROTH) | S_IWOTH;
pub const S_BLKSIZE = @as(c_int, 512);
pub const _TIME_H = @as(c_int, 1);
pub const _BITS_TIME_H = @as(c_int, 1);
pub const CLOCKS_PER_SEC = __helpers.cast(__clock_t, __helpers.promoteIntLiteral(c_int, 1000000, .decimal));
pub const CLOCK_REALTIME = @as(c_int, 0);
pub const CLOCK_MONOTONIC = @as(c_int, 1);
pub const CLOCK_PROCESS_CPUTIME_ID = @as(c_int, 2);
pub const CLOCK_THREAD_CPUTIME_ID = @as(c_int, 3);
pub const CLOCK_MONOTONIC_RAW = @as(c_int, 4);
pub const CLOCK_REALTIME_COARSE = @as(c_int, 5);
pub const CLOCK_MONOTONIC_COARSE = @as(c_int, 6);
pub const CLOCK_BOOTTIME = @as(c_int, 7);
pub const CLOCK_REALTIME_ALARM = @as(c_int, 8);
pub const CLOCK_BOOTTIME_ALARM = @as(c_int, 9);
pub const CLOCK_TAI = @as(c_int, 11);
pub const TIMER_ABSTIME = @as(c_int, 1);
pub const __struct_tm_defined = @as(c_int, 1);
pub const __itimerspec_defined = @as(c_int, 1);
pub const TIME_UTC = @as(c_int, 1);
pub inline fn __isleap(year: anytype) @TypeOf((__helpers.rem(year, @as(c_int, 4)) == @as(c_int, 0)) and ((__helpers.rem(year, @as(c_int, 100)) != @as(c_int, 0)) or (__helpers.rem(year, @as(c_int, 400)) == @as(c_int, 0)))) {
    _ = &year;
    return (__helpers.rem(year, @as(c_int, 4)) == @as(c_int, 0)) and ((__helpers.rem(year, @as(c_int, 100)) != @as(c_int, 0)) or (__helpers.rem(year, @as(c_int, 400)) == @as(c_int, 0)));
}
pub const _UTIME_H = @as(c_int, 1);
pub const _FNMATCH_H = @as(c_int, 1);
pub const FNM_PATHNAME = @as(c_int, 1) << @as(c_int, 0);
pub const FNM_NOESCAPE = @as(c_int, 1) << @as(c_int, 1);
pub const FNM_PERIOD = @as(c_int, 1) << @as(c_int, 2);
pub const FNM_NOMATCH = @as(c_int, 1);
pub const _LIBGEN_H = @as(c_int, 1);
pub const basename = __xpg_basename;
pub const _CTYPE_H = @as(c_int, 1);
pub inline fn _ISbit(bit: anytype) @TypeOf(if (__helpers.cast(bool, bit < @as(c_int, 8))) (@as(c_int, 1) << bit) << @as(c_int, 8) else (@as(c_int, 1) << bit) >> @as(c_int, 8)) {
    _ = &bit;
    return if (__helpers.cast(bool, bit < @as(c_int, 8))) (@as(c_int, 1) << bit) << @as(c_int, 8) else (@as(c_int, 1) << bit) >> @as(c_int, 8);
}
pub inline fn __isctype(c: anytype, @"type": anytype) @TypeOf(__ctype_b_loc().*[@as(usize, @intCast(__helpers.cast(c_int, c)))] & __helpers.cast(c_ushort, @"type")) {
    _ = &c;
    _ = &@"type";
    return __ctype_b_loc().*[@as(usize, @intCast(__helpers.cast(c_int, c)))] & __helpers.cast(c_ushort, @"type");
}
pub inline fn __isascii(c: anytype) @TypeOf((c & ~@as(c_int, 0x7f)) == @as(c_int, 0)) {
    _ = &c;
    return (c & ~@as(c_int, 0x7f)) == @as(c_int, 0);
}
pub inline fn __toascii(c: anytype) @TypeOf(c & @as(c_int, 0x7f)) {
    _ = &c;
    return c & @as(c_int, 0x7f);
}
pub const __exctype = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/ctype.h:102:9
pub const __tobody = @compileError("unable to translate macro: undefined identifier `__res`"); // /usr/include/ctype.h:155:9
pub inline fn __isctype_l(c: anytype, @"type": anytype, locale: anytype) @TypeOf(locale.*.__ctype_b[@as(usize, @intCast(__helpers.cast(c_int, c)))] & __helpers.cast(c_ushort, @"type")) {
    _ = &c;
    _ = &@"type";
    _ = &locale;
    return locale.*.__ctype_b[@as(usize, @intCast(__helpers.cast(c_int, c)))] & __helpers.cast(c_ushort, @"type");
}
pub const __exctype_l = @compileError("unable to translate C expr: unexpected token 'extern'"); // /usr/include/ctype.h:244:10
pub inline fn __isalnum_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISalnum, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISalnum, l);
}
pub inline fn __isalpha_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISalpha, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISalpha, l);
}
pub inline fn __iscntrl_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _IScntrl, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _IScntrl, l);
}
pub inline fn __isdigit_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISdigit, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISdigit, l);
}
pub inline fn __islower_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISlower, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISlower, l);
}
pub inline fn __isgraph_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISgraph, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISgraph, l);
}
pub inline fn __isprint_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISprint, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISprint, l);
}
pub inline fn __ispunct_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISpunct, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISpunct, l);
}
pub inline fn __isspace_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISspace, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISspace, l);
}
pub inline fn __isupper_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISupper, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISupper, l);
}
pub inline fn __isxdigit_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISxdigit, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISxdigit, l);
}
pub inline fn __isblank_l(c: anytype, l: anytype) @TypeOf(__isctype_l(c, _ISblank, l)) {
    _ = &c;
    _ = &l;
    return __isctype_l(c, _ISblank, l);
}
pub inline fn __isascii_l(c: anytype, l: anytype) @TypeOf(__isascii(c)) {
    _ = &c;
    _ = &l;
    return blk_1: {
        _ = &l;
        break :blk_1 __isascii(c);
    };
}
pub inline fn __toascii_l(c: anytype, l: anytype) @TypeOf(__toascii(c)) {
    _ = &c;
    _ = &l;
    return blk_1: {
        _ = &l;
        break :blk_1 __toascii(c);
    };
}
pub inline fn isascii_l(c: anytype, l: anytype) @TypeOf(__isascii_l(c, l)) {
    _ = &c;
    _ = &l;
    return __isascii_l(c, l);
}
pub inline fn toascii_l(c: anytype, l: anytype) @TypeOf(__toascii_l(c, l)) {
    _ = &c;
    _ = &l;
    return __toascii_l(c, l);
}
pub const _LIBC_LIMITS_H_ = @as(c_int, 1);
pub const __GLIBC_USE_LIB_EXT2 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT_C2X = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT_C2X = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_TYPES_EXT = @as(c_int, 0);
pub const MB_LEN_MAX = @as(c_int, 16);
pub const _GCC_LIMITS_H_ = "";
pub const __CLANG_LIMITS_H = "";
pub const SCHAR_MAX = __SCHAR_MAX__;
pub const SHRT_MAX = __SHRT_MAX__;
pub const INT_MAX = __INT_MAX__;
pub const LONG_MAX = __LONG_MAX__;
pub const SCHAR_MIN = -__SCHAR_MAX__ - @as(c_int, 1);
pub const SHRT_MIN = -__SHRT_MAX__ - @as(c_int, 1);
pub const INT_MIN = -__INT_MAX__ - @as(c_int, 1);
pub const LONG_MIN = -__LONG_MAX__ - @as(c_long, 1);
pub const UCHAR_MAX = (__SCHAR_MAX__ * @as(c_int, 2)) + @as(c_int, 1);
pub const USHRT_MAX = (__SHRT_MAX__ * @as(c_int, 2)) + @as(c_int, 1);
pub const UINT_MAX = (__INT_MAX__ * @as(c_uint, 2)) + @as(c_uint, 1);
pub const ULONG_MAX = (__LONG_MAX__ * @as(c_ulong, 2)) + @as(c_ulong, 1);
pub const CHAR_BIT = __CHAR_BIT__;
pub const CHAR_MIN = SCHAR_MIN;
pub const CHAR_MAX = __SCHAR_MAX__;
pub const LLONG_MIN = -__LONG_LONG_MAX__ - @as(c_longlong, 1);
pub const LLONG_MAX = __LONG_LONG_MAX__;
pub const ULLONG_MAX = (__LONG_LONG_MAX__ * @as(c_ulonglong, 2)) + @as(c_ulonglong, 1);
pub const _BITS_POSIX1_LIM_H = @as(c_int, 1);
pub const _POSIX_AIO_LISTIO_MAX = @as(c_int, 2);
pub const _POSIX_AIO_MAX = @as(c_int, 1);
pub const _POSIX_ARG_MAX = @as(c_int, 4096);
pub const _POSIX_CHILD_MAX = @as(c_int, 25);
pub const _POSIX_DELAYTIMER_MAX = @as(c_int, 32);
pub const _POSIX_HOST_NAME_MAX = @as(c_int, 255);
pub const _POSIX_LINK_MAX = @as(c_int, 8);
pub const _POSIX_LOGIN_NAME_MAX = @as(c_int, 9);
pub const _POSIX_MAX_CANON = @as(c_int, 255);
pub const _POSIX_MAX_INPUT = @as(c_int, 255);
pub const _POSIX_MQ_OPEN_MAX = @as(c_int, 8);
pub const _POSIX_MQ_PRIO_MAX = @as(c_int, 32);
pub const _POSIX_NAME_MAX = @as(c_int, 14);
pub const _POSIX_NGROUPS_MAX = @as(c_int, 8);
pub const _POSIX_OPEN_MAX = @as(c_int, 20);
pub const _POSIX_PATH_MAX = @as(c_int, 256);
pub const _POSIX_PIPE_BUF = @as(c_int, 512);
pub const _POSIX_RE_DUP_MAX = @as(c_int, 255);
pub const _POSIX_RTSIG_MAX = @as(c_int, 8);
pub const _POSIX_SEM_NSEMS_MAX = @as(c_int, 256);
pub const _POSIX_SEM_VALUE_MAX = @as(c_int, 32767);
pub const _POSIX_SIGQUEUE_MAX = @as(c_int, 32);
pub const _POSIX_SSIZE_MAX = @as(c_int, 32767);
pub const _POSIX_STREAM_MAX = @as(c_int, 8);
pub const _POSIX_SYMLINK_MAX = @as(c_int, 255);
pub const _POSIX_SYMLOOP_MAX = @as(c_int, 8);
pub const _POSIX_TIMER_MAX = @as(c_int, 32);
pub const _POSIX_TTY_NAME_MAX = @as(c_int, 9);
pub const _POSIX_TZNAME_MAX = @as(c_int, 6);
pub const _POSIX_CLOCKRES_MIN = __helpers.promoteIntLiteral(c_int, 20000000, .decimal);
pub const _LINUX_LIMITS_H = "";
pub const NGROUPS_MAX = __helpers.promoteIntLiteral(c_int, 65536, .decimal);
pub const MAX_CANON = @as(c_int, 255);
pub const MAX_INPUT = @as(c_int, 255);
pub const NAME_MAX = @as(c_int, 255);
pub const PATH_MAX = @as(c_int, 4096);
pub const PIPE_BUF = @as(c_int, 4096);
pub const XATTR_NAME_MAX = @as(c_int, 255);
pub const XATTR_SIZE_MAX = __helpers.promoteIntLiteral(c_int, 65536, .decimal);
pub const XATTR_LIST_MAX = __helpers.promoteIntLiteral(c_int, 65536, .decimal);
pub const RTSIG_MAX = @as(c_int, 32);
pub const _POSIX_THREAD_KEYS_MAX = @as(c_int, 128);
pub const PTHREAD_KEYS_MAX = @as(c_int, 1024);
pub const _POSIX_THREAD_DESTRUCTOR_ITERATIONS = @as(c_int, 4);
pub const PTHREAD_DESTRUCTOR_ITERATIONS = _POSIX_THREAD_DESTRUCTOR_ITERATIONS;
pub const _POSIX_THREAD_THREADS_MAX = @as(c_int, 64);
pub const AIO_PRIO_DELTA_MAX = @as(c_int, 20);
pub const PTHREAD_STACK_MIN = @as(c_int, 16384);
pub const DELAYTIMER_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const TTY_NAME_MAX = @as(c_int, 32);
pub const LOGIN_NAME_MAX = @as(c_int, 256);
pub const HOST_NAME_MAX = @as(c_int, 64);
pub const MQ_PRIO_MAX = __helpers.promoteIntLiteral(c_int, 32768, .decimal);
pub const SEM_VALUE_MAX = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const SSIZE_MAX = LONG_MAX;
pub const _BITS_POSIX2_LIM_H = @as(c_int, 1);
pub const _POSIX2_BC_BASE_MAX = @as(c_int, 99);
pub const _POSIX2_BC_DIM_MAX = @as(c_int, 2048);
pub const _POSIX2_BC_SCALE_MAX = @as(c_int, 99);
pub const _POSIX2_BC_STRING_MAX = @as(c_int, 1000);
pub const _POSIX2_COLL_WEIGHTS_MAX = @as(c_int, 2);
pub const _POSIX2_EXPR_NEST_MAX = @as(c_int, 32);
pub const _POSIX2_LINE_MAX = @as(c_int, 2048);
pub const _POSIX2_RE_DUP_MAX = @as(c_int, 255);
pub const _POSIX2_CHARCLASS_NAME_MAX = @as(c_int, 14);
pub const BC_BASE_MAX = _POSIX2_BC_BASE_MAX;
pub const BC_DIM_MAX = _POSIX2_BC_DIM_MAX;
pub const BC_SCALE_MAX = _POSIX2_BC_SCALE_MAX;
pub const BC_STRING_MAX = _POSIX2_BC_STRING_MAX;
pub const COLL_WEIGHTS_MAX = @as(c_int, 255);
pub const EXPR_NEST_MAX = _POSIX2_EXPR_NEST_MAX;
pub const LINE_MAX = _POSIX2_LINE_MAX;
pub const CHARCLASS_NAME_MAX = @as(c_int, 2048);
pub const RE_DUP_MAX = @as(c_int, 0x7fff);
pub const _SYS_FILE_H = @as(c_int, 1);
pub const _SYS_UTSNAME_H = @as(c_int, 1);
pub const _UTSNAME_LENGTH = @as(c_int, 65);
pub const _UTSNAME_DOMAIN_LENGTH = _UTSNAME_LENGTH;
pub const _UTSNAME_SYSNAME_LENGTH = _UTSNAME_LENGTH;
pub const _UTSNAME_NODENAME_LENGTH = _UTSNAME_LENGTH;
pub const _UTSNAME_RELEASE_LENGTH = _UTSNAME_LENGTH;
pub const _UTSNAME_VERSION_LENGTH = _UTSNAME_LENGTH;
pub const _UTSNAME_MACHINE_LENGTH = _UTSNAME_LENGTH;
pub const SYS_NMLN = _UTSNAME_LENGTH;
pub const _SYS_STATFS_H = @as(c_int, 1);
pub const _STATFS_F_NAMELEN = "";
pub const _STATFS_F_FRSIZE = "";
pub const _STATFS_F_FLAGS = "";
pub const _DIRENT_H = @as(c_int, 1);
pub const d_fileno = @compileError("unable to translate macro: undefined identifier `d_ino`"); // /usr/include/bits/dirent.h:47:9
pub const _DIRENT_HAVE_D_RECLEN = "";
pub const _DIRENT_HAVE_D_OFF = "";
pub const _DIRENT_HAVE_D_TYPE = "";
pub const _DIRENT_MATCHES_DIRENT64 = @as(c_int, 1);
pub inline fn _D_EXACT_NAMLEN(d: anytype) @TypeOf(strlen(d.*.d_name)) {
    _ = &d;
    return strlen(d.*.d_name);
}
pub inline fn _D_ALLOC_NAMLEN(d: anytype) @TypeOf((__helpers.cast([*c]u8, d) + d.*.d_reclen) - (&d.*.d_name[@as(usize, @intCast(@as(c_int, 0)))])) {
    _ = &d;
    return (__helpers.cast([*c]u8, d) + d.*.d_reclen) - (&d.*.d_name[@as(usize, @intCast(@as(c_int, 0)))]);
}
pub inline fn IFTODT(mode: anytype) @TypeOf((mode & __helpers.promoteIntLiteral(c_int, 0o170000, .octal)) >> @as(c_int, 12)) {
    _ = &mode;
    return (mode & __helpers.promoteIntLiteral(c_int, 0o170000, .octal)) >> @as(c_int, 12);
}
pub inline fn DTTOIF(dirtype: anytype) @TypeOf(dirtype << @as(c_int, 12)) {
    _ = &dirtype;
    return dirtype << @as(c_int, 12);
}
pub const MAXNAMLEN = NAME_MAX;
pub const _TDNF_H_ = "";
pub const TDNF_RPMTRANS_FLAG_NONE = UINT32_C(@as(c_int, 0x00000000));
pub const TDNF_RPMTRANS_FLAG_TEST = UINT32_C(@as(c_int, 0x00000001));
pub const TDNF_RPMTRANS_FLAG_NOSCRIPTS = UINT32_C(@as(c_int, 0x00000004));
pub const TDNF_RPMTRANS_FLAG_JUSTDB = UINT32_C(@as(c_int, 0x00000008));
pub const TDNF_RPMTRANS_FLAG_NOTRIGGERS = UINT32_C(@as(c_int, 0x00000010));
pub const TDNF_RPMTRANS_FLAG_NODOCS = UINT32_C(@as(c_int, 0x00000020));
pub const TDNF_RPMTRANS_FLAG_ALLFILES = UINT32_C(@as(c_int, 0x00000040));
pub const TDNF_RPMTRANS_FLAG_NOPLUGINS = UINT32_C(@as(c_int, 0x00000080));
pub const TDNF_RPMTRANS_FLAG_NOCONTEXTS = UINT32_C(@as(c_int, 0x00000100));
pub const TDNF_RPMTRANS_FLAG_NOCAPS = UINT32_C(@as(c_int, 0x00000200));
pub const TDNF_RPMTRANS_FLAG_NODB = UINT32_C(@as(c_int, 0x00000400));
pub const TDNF_RPMTRANS_FLAG_NOTRIGGERPREIN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00010000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPRE = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00020000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPOST = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00040000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOTRIGGERIN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00080000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOTRIGGERUN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00100000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPREUN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00200000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPOSTUN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00400000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOTRIGGERPOSTUN = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x00800000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPRETRANS = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x01000000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOPOSTTRANS = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x02000000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOMD5 = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x08000000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOFILEDIGEST = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x08000000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOARTIFACTS = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x20000000, .hex));
pub const TDNF_RPMTRANS_FLAG_NOCONFIGS = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x40000000, .hex));
pub const TDNF_RPMTRANS_FLAG_DEPLOOPS = UINT32_C(__helpers.promoteIntLiteral(c_int, 0x80000000, .hex));
pub const CLEANTYPE_NONE = @as(c_int, 0x00);
pub const CLEANTYPE_PACKAGES = @as(c_int, 0x01);
pub const CLEANTYPE_METADATA = @as(c_int, 0x02);
pub const CLEANTYPE_DBCACHE = @as(c_int, 0x04);
pub const CLEANTYPE_PLUGINS = @as(c_int, 0x08);
pub const CLEANTYPE_EXPIRE_CACHE = @as(c_int, 0x10);
pub const CLEANTYPE_KEYS = @as(c_int, 0x20);
pub const CLEANTYPE_ALL = @as(c_int, 0xff);
pub const TDNF_REPOSYNC_MAXARCHS = @as(c_int, 10);
pub const TDNF_REPOQUERY_MAXARCHS = @as(c_int, 10);
pub const __TDNFDEFINES_H__ = "";
pub const ERROR_TDNF_BASE = @as(c_int, 1000);
pub const ERROR_TDNF_PACKAGE_REQUIRED = @as(c_int, 1001);
pub const ERROR_TDNF_CONF_FILE_LOAD = @as(c_int, 1002);
pub const ERROR_TDNF_REPO_FILE_LOAD = @as(c_int, 1003);
pub const ERROR_TDNF_INVALID_REPO_FILE = @as(c_int, 1004);
pub const ERROR_TDNF_REPO_DIR_OPEN = @as(c_int, 1005);
pub const ERROR_TDNF_REPO_PERFORM = @as(c_int, 1006);
pub const ERROR_TDNF_REPO_GETINFO = @as(c_int, 1007);
pub const ERROR_TDNF_NO_REPOS = @as(c_int, 1008);
pub const ERROR_TDNF_REPO_NOT_FOUND = @as(c_int, 1009);
pub const ERROR_TDNF_INVALID_CONF = @as(c_int, 1010);
pub const ERROR_TDNF_NO_MATCH = @as(c_int, 1011);
pub const ERROR_TDNF_NO_ENABLED_REPOS = @as(c_int, 1012);
pub const ERROR_TDNF_PACKAGELIST_EMPTY = @as(c_int, 1013);
pub const ERROR_TDNF_GOAL_CREATE = @as(c_int, 1014);
pub const ERROR_TDNF_INVALID_RESOLVE_ARG = @as(c_int, 1015);
pub const ERROR_TDNF_CLEAN_UNSUPPORTED = @as(c_int, 1016);
pub const ERROR_TDNF_NO_DOWNGRADES = @as(c_int, 1017);
pub const ERROR_TDNF_AUTOERASE_UNSUPPORTED = @as(c_int, 1018);
pub const ERROR_TDNF_SET_PROXY = @as(c_int, 1020);
pub const ERROR_TDNF_SET_PROXY_USERPASS = @as(c_int, 1021);
pub const ERROR_TDNF_NO_DISTROVERPKG = @as(c_int, 1022);
pub const ERROR_TDNF_DISTROVERPKG_READ = @as(c_int, 1023);
pub const ERROR_TDNF_INVALID_ALLOCSIZE = @as(c_int, 1024);
pub const ERROR_TDNF_STRING_TOO_LONG = @as(c_int, 1025);
pub const ERROR_TDNF_ALREADY_INSTALLED = @as(c_int, 1026);
pub const ERROR_TDNF_NO_UPGRADE_PATH = @as(c_int, 1027);
pub const ERROR_TDNF_NO_DOWNGRADE_PATH = @as(c_int, 1028);
pub const ERROR_TDNF_METADATA_EXPIRE_PARSE = @as(c_int, 1029);
pub const ERROR_TDNF_PROTECTED = @as(c_int, 1030);
pub const ERROR_TDNF_SELF_ERASE = @as(c_int, 1030);
pub const ERROR_TDNF_ERASE_NEEDS_INSTALL = @as(c_int, 1031);
pub const ERROR_TDNF_OPERATION_ABORTED = @as(c_int, 1032);
pub const ERROR_TDNF_INVALID_INPUT = @as(c_int, 1033);
pub const ERROR_TDNF_CACHE_DISABLED = @as(c_int, 1034);
pub const ERROR_TDNF_DOWNGRADE_NOT_ALLOWED = @as(c_int, 1035);
pub const ERROR_TDNF_CACHE_DIR_OUT_OF_DISK_SPACE = @as(c_int, 1036);
pub const ERROR_TDNF_DUPLICATE_REPO_ID = @as(c_int, 1037);
pub const ERROR_TDNF_INVALID_REPO_NAME = @as(c_int, 1038);
pub const ERROR_TDNF_CURL_INIT = @as(c_int, 1200);
pub const ERROR_TDNF_CURL_BASE = @as(c_int, 1201);
pub const ERROR_TDNF_CURLE_UNSUPPORTED_PROTOCOL = @as(c_int, 1202);
pub const ERROR_TDNF_CURLE_FAILED_INIT = @as(c_int, 1203);
pub const ERROR_TDNF_CURLE_URL_MALFORMAT = @as(c_int, 1204);
pub const ERROR_TDNF_CURL_END = @as(c_int, 1299);
pub const ERROR_TDNF_SOLV_BASE = @as(c_int, 1300);
pub const ERROR_TDNF_SOLV_FAILED = ERROR_TDNF_SOLV_BASE + @as(c_int, 1);
pub const ERROR_TDNF_SOLV_OP = ERROR_TDNF_SOLV_BASE + @as(c_int, 2);
pub const ERROR_TDNF_SOLV_LIBSOLV = ERROR_TDNF_SOLV_BASE + @as(c_int, 3);
pub const ERROR_TDNF_SOLV_IO = ERROR_TDNF_SOLV_BASE + @as(c_int, 4);
pub const ERROR_TDNF_SOLV_CACHE_WRITE = ERROR_TDNF_SOLV_BASE + @as(c_int, 5);
pub const ERROR_TDNF_SOLV_QUERY = ERROR_TDNF_SOLV_BASE + @as(c_int, 6);
pub const ERROR_TDNF_SOLV_ARCH = ERROR_TDNF_SOLV_BASE + @as(c_int, 7);
pub const ERROR_TDNF_SOLV_VALIDATION = ERROR_TDNF_SOLV_BASE + @as(c_int, 8);
pub const ERROR_TDNF_SOLV_SELECTOR = ERROR_TDNF_SOLV_BASE + @as(c_int, 9);
pub const ERROR_TDNF_SOLV_NO_SOLUTION = ERROR_TDNF_SOLV_BASE + @as(c_int, 10);
pub const ERROR_TDNF_SOLV_NO_CAPABILITY = ERROR_TDNF_SOLV_BASE + @as(c_int, 11);
pub const ERROR_TDNF_SOLV_CHKSUM = ERROR_TDNF_SOLV_BASE + @as(c_int, 12);
pub const ERROR_TDNF_REPO_WRITE = ERROR_TDNF_SOLV_BASE + @as(c_int, 13);
pub const ERROR_TDNF_SOLV_CACHE_NOT_CREATED = ERROR_TDNF_SOLV_BASE + @as(c_int, 14);
pub const ERROR_TDNF_ADD_SOLV = ERROR_TDNF_SOLV_BASE + @as(c_int, 15);
pub const ERROR_TDNF_REPO_BASE = @as(c_int, 1400);
pub const ERROR_TDNF_SET_SSL_SETTINGS = @as(c_int, 1401);
pub const ERROR_TDNF_RPM_BASE = @as(c_int, 1470);
pub const ERROR_TDNF_RPMRC_NOTFOUND = @as(c_int, 1471);
pub const ERROR_TDNF_RPMRC_FAIL = @as(c_int, 1472);
pub const ERROR_TDNF_RPMRC_NOTTRUSTED = @as(c_int, 1473);
pub const ERROR_TDNF_RPMRC_NOKEY = @as(c_int, 1474);
pub const ERROR_TDNF_RPMTS_CREATE_FAILED = @as(c_int, 1501);
pub const ERROR_TDNF_RPMTS_BAD_ROOT_DIR = @as(c_int, 1502);
pub const ERROR_TDNF_RPMTS_SET_CB_FAILED = @as(c_int, 1503);
pub const ERROR_TDNF_RPMTS_KEYRING_FAILED = @as(c_int, 1504);
pub const ERROR_TDNF_INVALID_PUBKEY_FILE = @as(c_int, 1505);
pub const ERROR_TDNF_CREATE_PUBKEY_FAILED = @as(c_int, 1506);
pub const ERROR_TDNF_KEYURL_INVALID = @as(c_int, 1507);
pub const ERROR_TDNF_KEYURL_UNSUPPORTED = @as(c_int, 1508);
pub const ERROR_TDNF_RPM_HEADER_CONVERT_FAILED = @as(c_int, 1509);
pub const ERROR_TDNF_RPM_NOT_SIGNED = @as(c_int, 1510);
pub const ERROR_TDNF_RPMTD_CREATE_FAILED = @as(c_int, 1511);
pub const ERROR_TDNF_RPM_GET_RSAHEADER_FAILED = @as(c_int, 1512);
pub const ERROR_TDNF_RPM_GPG_PARSE_FAILED = @as(c_int, 1513);
pub const ERROR_TDNF_RPM_GPG_NO_MATCH = @as(c_int, 1514);
pub const ERROR_TDNF_RPM_CHECK = @as(c_int, 1515);
pub const ERROR_TDNF_SETOPT_NO_EQUALS = @as(c_int, 1516);
pub const ERROR_TDNF_PLUGINS_DISABLED = @as(c_int, 1517);
pub const ERROR_TDNF_NO_PLUGIN_CONF_DIR = @as(c_int, 1518);
pub const ERROR_TDNF_PLUGIN_LOAD_ERROR = @as(c_int, 1519);
pub const ERROR_TDNF_OPT_NOT_FOUND = @as(c_int, 1520);
pub const ERROR_TDNF_PLUGIN_NO_MORE_EVENTS = @as(c_int, 1521);
pub const ERROR_TDNF_NO_PLUGIN_ERROR = @as(c_int, 1522);
pub const ERROR_TDNF_NO_GPGKEY_CONF_ENTRY = @as(c_int, 1523);
pub const ERROR_TDNF_URL_INVALID = @as(c_int, 1524);
pub const ERROR_TDNF_TRANSACTION_FAILED = @as(c_int, 1525);
pub const ERROR_TDNF_RPMTS_OPENDB_FAILED = @as(c_int, 1526);
pub const ERROR_TDNF_SIZE_MISMATCH = @as(c_int, 1527);
pub const ERROR_TDNF_CHECKSUM_MISMATCH = @as(c_int, 1528);
pub const ERROR_TDNF_RPMTS_FDDUP_FAILED = @as(c_int, 1529);
pub const ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED = @as(c_int, 1530);
pub const ERROR_TDNF_RPM_UNSIGNED = @as(c_int, 1531);
pub const ERROR_TDNF_NATIVE_SOLVER_MISMATCH = @as(c_int, 1532);
pub const ERROR_TDNF_EVENT_CTXT_ITEM_NOT_FOUND = @as(c_int, 1551);
pub const ERROR_TDNF_EVENT_CTXT_ITEM_INVALID_TYPE = @as(c_int, 1552);
pub const ERROR_TDNF_NO_SEARCH_RESULTS = @as(c_int, 1599);
pub const ERROR_TDNF_SYSTEM_BASE = @as(c_int, 1600);
pub const ERROR_TDNF_PERM = ERROR_TDNF_SYSTEM_BASE + EPERM;
pub const ERROR_TDNF_INVALID_PARAMETER = ERROR_TDNF_SYSTEM_BASE + EINVAL;
pub const ERROR_TDNF_OUT_OF_MEMORY = ERROR_TDNF_SYSTEM_BASE + ENOMEM;
pub const ERROR_TDNF_NO_DATA = ERROR_TDNF_SYSTEM_BASE + ENODATA;
pub const ERROR_TDNF_FILE_NOT_FOUND = ERROR_TDNF_SYSTEM_BASE + ENOENT;
pub const ERROR_TDNF_ACCESS_DENIED = ERROR_TDNF_SYSTEM_BASE + EACCES;
pub const ERROR_TDNF_ALREADY_EXISTS = ERROR_TDNF_SYSTEM_BASE + EEXIST;
pub const ERROR_TDNF_INVALID_ADDRESS = ERROR_TDNF_SYSTEM_BASE + EFAULT;
pub const ERROR_TDNF_CALL_INTERRUPTED = ERROR_TDNF_SYSTEM_BASE + EINTR;
pub const ERROR_TDNF_FILESYS_IO = ERROR_TDNF_SYSTEM_BASE + EIO;
pub const ERROR_TDNF_SYM_LOOP = ERROR_TDNF_SYSTEM_BASE + ELOOP;
pub const ERROR_TDNF_NAME_TOO_LONG = ERROR_TDNF_SYSTEM_BASE + ENAMETOOLONG;
pub const ERROR_TDNF_CALL_NOT_SUPPORTED = ERROR_TDNF_SYSTEM_BASE + ENOSYS;
pub const ERROR_TDNF_INVALID_DIR = ERROR_TDNF_SYSTEM_BASE + ENOTDIR;
pub const ERROR_TDNF_OVERFLOW = ERROR_TDNF_SYSTEM_BASE + EOVERFLOW;
pub const ERROR_TDNF_JSONDUMP = @as(c_int, 1700);
pub const ERROR_TDNF_HISTORY_ERROR = @as(c_int, 1801);
pub const ERROR_TDNF_HISTORY_NODB = @as(c_int, 1802);
pub const ERROR_TDNF_PLUGIN_BASE = @as(c_int, 2000);
pub const ERROR_TDNF_BASEURL_DOES_NOT_EXISTS = @as(c_int, 2500);
pub const ERROR_TDNF_CHECKSUM_VALIDATION_FAILED = @as(c_int, 2501);
pub const ERROR_TDNF_METALINK_RESOURCE_VALIDATION_FAILED = @as(c_int, 2502);
pub const ERROR_TDNF_FIPS_MODE_FORBIDDEN = @as(c_int, 2600);
pub const CMD_INSTALL = "install";
pub const TDNF_TRANSACTION_PLAN_SCHEMA_VERSION = UINT32_C(@as(c_int, 1));
pub const TDNF_TRANSACTION_PLAN_SCHEMA = "tdnf.transaction-plan/v1";
pub const TDNF_TRANSACTION_PLAN_DIGEST_SIZE = UINT32_C(@as(c_int, 32));
pub const TDNF_TRANSACTION_PLAN_DIGEST_HEX_LENGTH = UINT32_C(@as(c_int, 64));
pub const _TDNF_REPOMD_H_ = "";
pub const RPMDB_REPORT_PROGRESS = @as(c_int, 1) << @as(c_int, 8);
pub const RPM_ADD_WITH_PKGID = @as(c_int, 1) << @as(c_int, 9);
pub const RPM_ADD_NO_FILELIST = @as(c_int, 1) << @as(c_int, 10);
pub const RPM_ADD_NO_RPMLIBREQS = @as(c_int, 1) << @as(c_int, 11);
pub const RPM_ADD_WITH_SHA1SUM = @as(c_int, 1) << @as(c_int, 12);
pub const RPM_ADD_WITH_SHA256SUM = @as(c_int, 1) << @as(c_int, 13);
pub const RPM_ADD_TRIGGERS = @as(c_int, 1) << @as(c_int, 14);
pub const RPM_ADD_WITH_HDRID = @as(c_int, 1) << @as(c_int, 15);
pub const RPM_ADD_WITH_LEADSIGID = @as(c_int, 1) << @as(c_int, 16);
pub const RPM_ADD_WITH_CHANGELOG = @as(c_int, 1) << @as(c_int, 17);
pub const RPM_ADD_FILTERED_FILELIST = @as(c_int, 1) << @as(c_int, 18);
pub const RPMDB_KEEP_GPG_PUBKEY = @as(c_int, 1) << @as(c_int, 19);
pub const RPM_ADD_WITH_ORDERWITHREQUIRES = @as(c_int, 1) << @as(c_int, 20);
pub const RPMDB_EMPTY_REFREPO = @as(c_int, 1) << @as(c_int, 30);
pub const TDNF_REPO_REUSE_REPODATA = @as(c_int, 1) << @as(c_int, 0);
pub const __INC_TDNF_COMMON_DEFINES_H__ = "";
pub const UNUSED = __helpers.DISCARD;
pub inline fn ARRAY_SIZE(arr: anytype) @TypeOf(__helpers.div(__helpers.sizeof(arr), __helpers.sizeof(arr[@as(usize, @intCast(@as(c_int, 0)))]))) {
    _ = &arr;
    return __helpers.div(__helpers.sizeof(arr), __helpers.sizeof(arr[@as(usize, @intCast(@as(c_int, 0)))]));
}
pub inline fn IsNullOrEmptyString(str: anytype) @TypeOf(!(str != 0) or !(str.* != 0)) {
    _ = &str;
    return !(str != 0) or !(str.* != 0);
}
pub const BAIL_ON_TDNF_SYSTEM_ERROR = @compileError("unable to translate macro: undefined identifier `error`");
pub const BAIL_ON_TDNF_SYSTEM_ERROR_UNCOND = @compileError("unable to translate macro: undefined identifier `error`");
pub const CHECK_JD_RC = @compileError("unable to translate macro: undefined identifier `dwError`");
pub const CHECK_JD_NULL = @compileError("unable to translate macro: undefined identifier `dwError`");
pub const JD_SAFE_DESTROY = @compileError("unable to translate macro: undefined identifier `jd_destroy`");
pub const TDNF_SAFE_FREE_MEMORY = @compileError("unable to translate C expr: unexpected token 'do'");
pub const TDNF_SAFE_FREE_STRINGARRAY = @compileError("unable to translate C expr: unexpected token 'do'");
pub const LOG_INFO = @as(c_int, 0);
pub const LOG_ERR = @as(c_int, 1);
pub const LOG_CRIT = @as(c_int, 2);
pub const LOG_NOTICE = @as(c_int, 3);
pub const pr_info = @compileError("unable to translate C expr: unexpected token '##'");
pub const pr_err = @compileError("unable to translate C expr: unexpected token '##'");
pub const pr_notice = @compileError("unable to translate C expr: unexpected token '##'");
pub inline fn pr_json(str: anytype) @TypeOf(fputs(str, stdout)) {
    _ = &str;
    return fputs(str, stdout);
}
pub const pr_jsonf = @compileError("unable to translate C expr: unexpected token '##'");
pub const pr_crit = @compileError("unable to translate C expr: unexpected token '##'");
pub const _TDNF_RPMZIG_RPMDB_H_ = "";
pub const TDNF_JOB_SOLVABLE = @as(c_int, 0x01);
pub const TDNF_JOB_SOLVABLE_NAME = @as(c_int, 0x02);
pub const TDNF_JOB_SOLVABLE_ALL = @as(c_int, 0x06);
pub const TDNF_JOB_INSTALL = @as(c_int, 0x0100);
pub const TDNF_JOB_ERASE = @as(c_int, 0x0200);
pub const TDNF_JOB_UPDATE = @as(c_int, 0x0300);
pub const TDNF_JOB_MULTIVERSION = @as(c_int, 0x0500);
pub const TDNF_JOB_LOCK = @as(c_int, 0x0600);
pub const TDNF_JOB_DISTUPGRADE = @as(c_int, 0x0700);
pub const TDNF_JOB_USERINSTALLED = @as(c_int, 0x0a00);
pub const TDNF_JOB_ALLOWUNINSTALL = @as(c_int, 0x0b00);
pub const TDNF_JOB_JOBMASK = __helpers.promoteIntLiteral(c_int, 0xff00, .hex);
pub const TDNF_JOB_CLEANDEPS = __helpers.promoteIntLiteral(c_int, 0x040000, .hex);
pub const TDNF_JOB_FORCEBEST = __helpers.promoteIntLiteral(c_int, 0x100000, .hex);
pub const SYSTEM_REPO_NAME = "@System";
pub const CMDLINE_REPO_NAME = "@cmdline";
pub const TDNF_METADATA_COOKIE_LEN = @as(c_int, 32);
pub const TDNF_NEVRA_UNINSTALLED = @as(c_int, 0);
pub const TDNF_NEVRA_INSTALLED = @as(c_int, 1);
pub const _TDNF_CLIENT_TRANSACTION_PLAN_CAPTURE_ABI_INC_ = "";
pub const __LLCONF_NODES_H_INCLUDED = "";
pub inline fn find_child(cn_parent: anytype, name: anytype) @TypeOf(find_node(cn_parent.*.first_child, name)) {
    _ = &cn_parent;
    _ = &name;
    return find_node(cn_parent.*.first_child, name);
}
pub const MAX_CONFIG_LINE_LENGTH = @as(c_int, 1024);
pub const TDNF_DEFAULT_MAX_STRING_LEN = __helpers.promoteIntLiteral(c_int, 16384000, .decimal);
pub const TDNF_MD5_DIGEST_LEN = @as(c_int, 16);
pub const TDNF_SHA1_DIGEST_LEN = @as(c_int, 20);
pub const TDNF_SHA256_DIGEST_LEN = @as(c_int, 32);
pub const TDNF_SHA512_DIGEST_LEN = @as(c_int, 64);
pub const TDNF_MAX_DIGEST_LEN = TDNF_SHA512_DIGEST_LEN;
pub const TDNF_INSTANCE_LOCK_FILE = "/var/run/.tdnf-instance-lockfile";
pub inline fn STR_IS_TRUE(s: anytype) @TypeOf((s != 0) and (!(strcmp(s, "1") != 0) or !(strcasecmp(s, "true") != 0))) {
    _ = &s;
    return (s != 0) and (!(strcmp(s, "1") != 0) or !(strcasecmp(s, "true") != 0));
}
pub const TDNF_RPM_EXT = ".rpm";
pub const TDNF_NAME = "tdnf";
pub const DIR_SEPARATOR = '/';
pub const SOLV_PATCH_MARKER = "patch:";
pub const TDNF_REPOMD_TYPE_PRIMARY = "primary";
pub const TDNF_REPOMD_TYPE_FILELISTS = "filelists";
pub const TDNF_REPOMD_TYPE_UPDATEINFO = "updateinfo";
pub const TDNF_REPOMD_TYPE_OTHER = "other";
pub const TDNF_REPO_EXT = ".repo";
pub const TDNF_CONF_FILE = "/etc/tdnf/tdnf.conf";
pub const TDNF_CONF_GROUP = "main";
pub const TDNF_CONF_KEY_GPGCHECK = "gpgcheck";
pub const TDNF_CONF_KEY_CMDLINEGPGCHECK = "cligpgcheck";
pub const TDNF_CONF_KEY_INSTALLONLY_LIMIT = "installonly_limit";
pub const TDNF_CONF_KEY_INSTALLONLYPKGS = "installonlypkgs";
pub const TDNF_CONF_KEY_CLEAN_REQ_ON_REMOVE = "clean_requirements_on_remove";
pub const TDNF_CONF_KEY_REPODIR = "repodir";
pub const TDNF_CONF_KEY_REPOSDIR = "reposdir";
pub const TDNF_CONF_KEY_CACHEDIR = "cachedir";
pub const TDNF_CONF_KEY_PERSISTDIR = "persistdir";
pub const TDNF_CONF_KEY_PROXY = "proxy";
pub const TDNF_CONF_KEY_PROXY_USER = "proxy_username";
pub const TDNF_CONF_KEY_PROXY_PASS = "proxy_password";
pub const TDNF_CONF_KEY_KEEP_CACHE = "keepcache";
pub const TDNF_CONF_KEY_DISTROVERPKGS = "distroverpkg";
pub const TDNF_CONF_KEY_DISTROARCHPKG = "distroarchpkg";
pub const TDNF_CONF_KEY_MAX_STRING_LEN = "maxstringlen";
pub const TDNF_CONF_KEY_PLUGINS = "plugins";
pub const TDNF_CONF_KEY_NO_PLUGINS = "noplugins";
pub const TDNF_CONF_KEY_PLUGIN_PATH = "pluginpath";
pub const TDNF_CONF_KEY_PLUGIN_CONF_PATH = "pluginconfpath";
pub const TDNF_CONF_KEY_SSL_VERIFY = "sslverify";
pub const TDNF_PLUGIN_CONF_KEY_ENABLED = "enabled";
pub const TDNF_CONF_KEY_TSFLAGS = "tsflags";
pub const TDNF_CONF_KEY_EXCLUDE = "excludepkgs";
pub const TDNF_CONF_KEY_MINVERSIONS = "minversions";
pub const TDNF_CONF_KEY_OPENMAX = "openmax";
pub const TDNF_CONF_KEY_VARS_DIRS = "varsdir";
pub const TDNF_CONF_KEY_CHECK_UPDATE_COMPAT = "dnf_check_update_compat";
pub const TDNF_CONF_KEY_DISTROSYNC_REINSTALL_CHANGED = "distrosync_reinstall_changed";
pub const TDNF_CONF_KEY_CONNECT_TIMEOUT = "connect_timeout";
pub const TDNF_REPO_KEY_BASEURL = "baseurl";
pub const TDNF_REPO_KEY_ENABLED = "enabled";
pub const TDNF_REPO_KEY_METALINK = "metalink";
pub const TDNF_REPO_KEY_MIRRORLIST = "mirrorlist";
pub const TDNF_REPO_KEY_NAME = "name";
pub const TDNF_REPO_KEY_SKIP = "skip_if_unavailable";
pub const TDNF_REPO_KEY_GPGCHECK = "gpgcheck";
pub const TDNF_REPO_KEY_GPGKEY = "gpgkey";
pub const TDNF_REPO_KEY_USERNAME = "username";
pub const TDNF_REPO_KEY_PASSWORD = "password";
pub const TDNF_REPO_KEY_PRIORITY = "priority";
pub const TDNF_REPO_KEY_METADATA_EXPIRE = "metadata_expire";
pub const TDNF_REPO_KEY_TIMEOUT = "timeout";
pub const TDNF_REPO_KEY_RETRIES = "retries";
pub const TDNF_REPO_KEY_MINRATE = "minrate";
pub const TDNF_REPO_KEY_THROTTLE = "throttle";
pub const TDNF_REPO_KEY_SSL_VERIFY = TDNF_CONF_KEY_SSL_VERIFY;
pub const TDNF_REPO_KEY_SSL_CA_CERT = "sslcacert";
pub const TDNF_REPO_KEY_SSL_CLI_CERT = "sslclientcert";
pub const TDNF_REPO_KEY_SSL_CLI_KEY = "sslclientkey";
pub const TDNF_REPO_KEY_SKIP_MD_FILELISTS = "skip_md_filelists";
pub const TDNF_REPO_KEY_SKIP_MD_UPDATEINFO = "skip_md_updateinfo";
pub const TDNF_REPO_KEY_SKIP_MD_OTHER = "skip_md_other";
pub const TDNF_REPO_KEY_SNAPSHOT_URL = "snapshot";
pub const TDNF_REPO_METADATA_MARKER = "lastrefresh";
pub const TDNF_REPO_METADATA_MIRRORLIST = "mirrorlist";
pub const TDNF_REPO_METADATA_SNAPSHOT = "snapshot";
pub const TDNF_REPO_METADATA_FILE_PATH = "repodata/repomd.xml";
pub const TDNF_REPO_METADATA_FILE_NAME = "repomd.xml";
pub const TDNF_REPO_METALINK_FILE_NAME = "metalink";
pub const TDNF_REPO_BASEURL_FILE_NAME = "baseurl";
pub const TDNF_AUTOINSTALLED_FILE = "autoinstalled";
pub const TDNF_HISTORY_DB_FILE = "history.db";
pub const TDNF_DEFAULT_DATA_LOCATION = "/var/lib/tdnf";
pub const TDNF_DEFAULT_REPO_LOCATION = "/etc/yum.repos.d";
pub const TDNF_DEFAULT_CACHE_LOCATION = "/var/cache/tdnf";
pub const TDNF_DEFAULT_VARS_DIRS = "/etc/tdnf/vars /etc/dnf/vars /etc/yum/vars";
pub const TDNF_DEFAULT_DB_LOCATION = HISTORY_DB_DIR;
pub const TDNF_DEFAULT_DISTROVERPKGS = "system-release(releasever) system-release redhat-release";
pub const TDNF_DEFAULT_DISTROARCHPKG = "x86_64";
pub const TDNF_RPM_CACHE_DIR_NAME = "rpms";
pub const TDNF_REPODATA_DIR_NAME = "repodata";
pub const TDNF_SOLVCACHE_DIR_NAME = "solvcache";
pub const TDNF_REPO_METADATA_EXPIRE_NEVER = "never";
pub const TDNF_CONF_DEFAULT_OPENMAX = @as(c_int, 1024);
pub const TDNF_CONF_DEFAULT_INSTALLONLY_LIMIT = @as(c_int, 2);
pub const TDNF_CONF_DEFAULT_SSLVERIFY = @as(c_int, 1);
pub const TDNF_CONF_DEFAULT_CONNECT_TIMEOUT = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_ENABLED = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_SKIP = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_MINRATE = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_THROTTLE = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_TIMEOUT = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_RETRIES = @as(c_int, 10);
pub const TDNF_REPO_DEFAULT_PRIORITY = @as(c_int, 50);
pub const TDNF_REPO_DEFAULT_METADATA_EXPIRE = __helpers.promoteIntLiteral(c_int, 172800, .decimal);
pub const TDNF_REPO_DEFAULT_SKIP_MD_FILELISTS = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_SKIP_MD_UPDATEINFO = @as(c_int, 0);
pub const TDNF_REPO_DEFAULT_SKIP_MD_OTHER = @as(c_int, 0);
pub const TDNF_VAR_RELEASEVER = "releasever";
pub const TDNF_VAR_BASEARCH = "basearch";
pub const TDNF_SETOPT_NAME_DUMMY = "opt.dummy.name";
pub const TDNF_SETOPT_VALUE_DUMMY = "opt.dummy.value";
pub const TDNF_DEFAULT_PLUGINS_ENABLED = @as(c_int, 0);
pub const TDNF_DEFAULT_PLUGIN_PATH = SYSTEM_LIBDIR ++ "/tdnf-plugins";
pub const TDNF_DEFAULT_PLUGIN_CONF_PATH = "/etc/tdnf/pluginconf.d";
pub const TDNF_PLUGIN_CONF_EXT = ".conf";
pub const TDNF_PLUGIN_CONF_EXT_LEN = @as(c_int, 5);
pub const TDNF_PLUGIN_CONF_MAIN_SECTION = "main";
pub const __COMMON_PROTOTYPES_H__ = "";
pub const HISTORY_DB_FILE = "history.db";
pub const HISTORY_DB_DIR = "/var/lib/tdnf";
pub const HISTORY_TRANS_TYPE_BASE = @as(c_int, 0);
pub const HISTORY_TRANS_TYPE_DELTA = @as(c_int, 1);
pub const HISTORY_ITEM_TYPE_SET = @as(c_int, 0);
pub const HISTORY_ITEM_TYPE_ADD = @as(c_int, 1);
pub const HISTORY_ITEM_TYPE_REMOVE = @as(c_int, 2);
pub const PACKAGE_NAME = "tdnf";
pub const PACKAGE_VERSION = "4.0.0";
pub const SYSTEM_LIBDIR = "/usr/local/lib";
pub const BAIL_ON_TDNF_RPM_ERROR = @compileError("unable to translate macro: undefined identifier `error`"); // client/defines.h:23:9
pub const TDNF_UNKNOWN_ERROR_STRING = "Unknown error";
pub const TDNF_ERROR_TABLE = @compileError("unable to translate C expr: unexpected token '{'"); // client/defines.h:35:9
pub const TAG_NAME_FILE = "file";
pub const TAG_NAME_SIZE = "size";
pub const TAG_NAME_HASH = "hash";
pub const TAG_NAME_URL = "url";
pub inline fn TDNF_REPO_RPM_DIRECTORY(pRepo: anytype) @TypeOf(if (__helpers.cast(bool, (!(pRepo.*.nHasMetaData != 0) and (pRepo.*.ppszBaseUrls != 0)) and !(IsNullOrEmptyString(pRepo.*.ppszBaseUrls[@as(usize, @intCast(@as(c_int, 0)))]) != 0))) pRepo.*.ppszBaseUrls[@as(usize, @intCast(@as(c_int, 0)))] else NULL) {
    _ = &pRepo;
    return if (__helpers.cast(bool, (!(pRepo.*.nHasMetaData != 0) and (pRepo.*.ppszBaseUrls != 0)) and !(IsNullOrEmptyString(pRepo.*.ppszBaseUrls[@as(usize, @intCast(@as(c_int, 0)))]) != 0))) pRepo.*.ppszBaseUrls[@as(usize, @intCast(@as(c_int, 0)))] else NULL;
}
pub inline fn TDNF_REPO_IS_QUERYABLE(pRepo: anytype) @TypeOf(((pRepo.*.nEnabled != 0) and !(IsNullOrEmptyString(pRepo.*.pszId) != 0)) and ((pRepo.*.nHasMetaData != 0) or (TDNF_REPO_RPM_DIRECTORY(pRepo) != NULL))) {
    _ = &pRepo;
    return ((pRepo.*.nEnabled != 0) and !(IsNullOrEmptyString(pRepo.*.pszId) != 0)) and ((pRepo.*.nHasMetaData != 0) or (TDNF_REPO_RPM_DIRECTORY(pRepo) != NULL));
}
pub const __TDNF_BUILTIN_PLUGINS_H__ = "";
pub const __CLIENT_PROTOTYPES_H__ = "";
pub const _G_fpos_t = struct__G_fpos_t;
pub const _G_fpos64_t = struct__G_fpos64_t;
pub const _IO_marker = struct__IO_marker;
pub const _IO_codecvt = struct__IO_codecvt;
pub const _IO_wide_data = struct__IO_wide_data;
pub const _IO_FILE = struct__IO_FILE;
pub const _IO_cookie_io_functions_t = struct__IO_cookie_io_functions_t;
pub const timeval = struct_timeval;
pub const timespec = struct_timespec;
pub const __pthread_internal_list = struct___pthread_internal_list;
pub const __pthread_internal_slist = struct___pthread_internal_slist;
pub const __pthread_mutex_s = struct___pthread_mutex_s;
pub const __pthread_rwlock_arch_t = struct___pthread_rwlock_arch_t;
pub const __pthread_cond_s = struct___pthread_cond_s;
pub const random_data = struct_random_data;
pub const drand48_data = struct_drand48_data;
pub const __locale_struct = struct___locale_struct;
pub const tm = struct_tm;
pub const itimerspec = struct_itimerspec;
pub const sigevent = struct_sigevent;
pub const utimbuf = struct_utimbuf;
pub const utsname = struct_utsname;
pub const dirent = struct_dirent;
pub const __dirstream = struct___dirstream;
pub const _TDNF_PACKAGE_CONTEXT = struct__TDNF_PACKAGE_CONTEXT;
pub const cnfnode = struct_cnfnode;
pub const _TDNF_CMD_ARGS = struct__TDNF_CMD_ARGS;
pub const _TDNF_CONF = struct__TDNF_CONF;
pub const s_Repo = struct_s_Repo;
pub const _TDNF_REPO_DATA = struct__TDNF_REPO_DATA;
pub const _TDNF_PLUGIN_ = struct__TDNF_PLUGIN_;
pub const _TDNF_ = struct__TDNF_;
pub const _TDNF_PKG_CHANGELOG_ENTRY = struct__TDNF_PKG_CHANGELOG_ENTRY;
pub const _TDNF_PKG_INFO = struct__TDNF_PKG_INFO;
pub const _TDNF_SOLVED_PKG_INFO = struct__TDNF_SOLVED_PKG_INFO;
pub const _TDNF_CMD_OPT = struct__TDNF_CMD_OPT;
pub const _TDNF_ERROR_DESC = struct__TDNF_ERROR_DESC;
pub const _TDNF_UPDATEINFO_REF = struct__TDNF_UPDATEINFO_REF;
pub const _TDNF_UPDATEINFO_PKG = struct__TDNF_UPDATEINFO_PKG;
pub const _TDNF_UPDATEINFO = struct__TDNF_UPDATEINFO;
pub const _TDNF_UPDATEINFO_SUMMARY = struct__TDNF_UPDATEINFO_SUMMARY;
pub const _TDNF_REPOSYNC_ARGS = struct__TDNF_REPOSYNC_ARGS;
pub const _TDNF_REPOQUERY_ARGS = struct__TDNF_REPOQUERY_ARGS;
pub const _TDNF_HISTORY_ARGS = struct__TDNF_HISTORY_ARGS;
pub const _TDNF_HISTORY_INFO_ITEM = struct__TDNF_HISTORY_INFO_ITEM;
pub const _TDNF_HISTORY_INFO = struct__TDNF_HISTORY_INFO;
pub const _TDNF_ZIG_DOWNLOAD_REQUEST = struct__TDNF_ZIG_DOWNLOAD_REQUEST;
pub const tdnf_repomd_doc = struct_tdnf_repomd_doc;
pub const _TDNF_REPOMD_CHECKSUM = struct__TDNF_REPOMD_CHECKSUM;
pub const _TDNF_REPOMD_RECORD = struct__TDNF_REPOMD_RECORD;
pub const _TDNF_REPOMD_NATIVE_REPO_INPUT = struct__TDNF_REPOMD_NATIVE_REPO_INPUT;
pub const _TDNF_REPOMD_NATIVE_TRANSACTION_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM;
pub const _TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2;
pub const _TDNF_REPOMD_NATIVE_PROBLEM_TYPE = enum__TDNF_REPOMD_NATIVE_PROBLEM_TYPE;
pub const _TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM;
pub const _TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM;
pub const _TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN;
pub const _TDNF_REPOMD_NATIVE_SOLVER_ACTION_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_KIND;
pub const _TDNF_REPOMD_NATIVE_SOLVER_ACTION_REASON = enum__TDNF_REPOMD_NATIVE_SOLVER_ACTION_REASON;
pub const _TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM_KIND;
pub const _TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_KIND = enum__TDNF_REPOMD_NATIVE_SOLVER_REPOSITORY_KIND;
pub const _TDNF_REPOMD_NATIVE_SOLVER_COMPARISON = enum__TDNF_REPOMD_NATIVE_SOLVER_COMPARISON;
pub const _TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = struct__TDNF_REPOMD_NATIVE_SOLVER_PACKAGE;
pub const _TDNF_REPOMD_NATIVE_SOLVER_ACTION = struct__TDNF_REPOMD_NATIVE_SOLVER_ACTION;
pub const _TDNF_REPOMD_NATIVE_SOLVER_RELATION = struct__TDNF_REPOMD_NATIVE_SOLVER_RELATION;
pub const _TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = struct__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM;
pub const _TDNF_REPOMD_NATIVE_SOLVER_RESULT = struct__TDNF_REPOMD_NATIVE_SOLVER_RESULT;
pub const _TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16;
pub const _TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB;
pub const _TDNF_ID_LIST = struct__TDNF_ID_LIST;
pub const _TDNF_PKG_FIELDS = struct__TDNF_PKG_FIELDS;
pub const _TDNF_REPO_METADATA = struct__TDNF_REPO_METADATA;
pub const _TDNF_CACHED_RPM_ENTRY = struct__TDNF_CACHED_RPM_ENTRY;
pub const _TDNF_CACHED_RPM_LIST = struct__TDNF_CACHED_RPM_LIST;
pub const _TDNF_RPM_TS_ITEM = struct__TDNF_RPM_TS_ITEM;
pub const _TDNF_RPM_TS_ = struct__TDNF_RPM_TS_;
pub const progress_cb_data = struct_progress_cb_data;
pub const history_ctx = struct_history_ctx;
pub const _KEYVALUE_ = struct__KEYVALUE_;
pub const _CONF_SECTION_ = struct__CONF_SECTION_;
pub const _CONF_DATA_ = struct__CONF_DATA_;
pub const _hash_op = struct__hash_op;
pub const _hash_type = struct__hash_type;
pub const history_delta = struct_history_delta;
pub const history_flags_delta = struct_history_flags_delta;
pub const history_transaction = struct_history_transaction;

comptime {
    if (@sizeOf(struct__TDNF_) != @sizeOf(canonical_abi.Tdnf) or
        @sizeOf(struct__TDNF_ID_LIST) != @sizeOf(canonical_abi.IdList) or
        @sizeOf(TDNF_CMD_ARGS) != @sizeOf(canonical_abi.CmdArgs) or
        @sizeOf(TDNF_CONF) != @sizeOf(canonical_abi.Conf) or
        @sizeOf(TDNF_REPO_DATA) != @sizeOf(canonical_abi.RepoData))
    {
        @compileError("resolver ABI declarations differ from client/abi.zig");
    }
}
