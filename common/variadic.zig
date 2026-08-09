// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux) {
        @compileError(
            "common's C variadic ABI bridge supports Linux targets only",
        );
    }
    switch (builtin.cpu.arch) {
        .x86_64, .aarch64 => {},
        else => @compileError(
            "common's C variadic ABI bridge supports only x86_64 and aarch64",
        ),
    }
}

pub const VaList = switch (builtin.cpu.arch) {
    .x86_64 => std.builtin.VaListX86_64,
    .aarch64 => std.builtin.VaListAarch64,
    else => unreachable,
};

pub const needs_manual_start =
    builtin.cpu.arch == .aarch64 and
    builtin.zig_backend == .stage2_llvm;

// Zig 0.16 disables std.builtin.VaList on AArch64 under the LLVM backend
// because @cVaArg lowers to LLVM's va_arg instruction, which is not ABI-correct
// there. Clang uses these intrinsics for va_start/copy/end, while pointer
// extraction follows AAPCS64 explicitly below. Other supported combinations
// use Zig's builtins, including native Debug builds on the self-hosted backend.
extern fn @"llvm.va_start.p0"(list: *anyopaque) callconv(.c) void;
extern fn @"llvm.va_copy.p0"(
    destination: *anyopaque,
    source: *anyopaque,
) callconv(.c) void;
extern fn @"llvm.va_end.p0"(list: *anyopaque) callconv(.c) void;

pub inline fn startManual(list: *VaList) void {
    if (!needs_manual_start) {
        @compileError("manual va_start is only for AArch64's LLVM backend");
    }
    @"llvm.va_start.p0"(@ptrCast(list));
}

pub inline fn copy(destination: *VaList, source: *VaList) void {
    if (comptime needs_manual_start) {
        @"llvm.va_copy.p0"(
            @ptrCast(destination),
            @ptrCast(source),
        );
    } else {
        destination.* = @cVaCopy(source);
    }
}

pub inline fn end(list: *VaList) void {
    if (comptime needs_manual_start) {
        @"llvm.va_end.p0"(@ptrCast(list));
    } else {
        @cVaEnd(list);
    }
}

pub fn cArgument(comptime T: type, list: *VaList) T {
    return switch (builtin.cpu.arch) {
        .x86_64 => blk: {
            const info = @typeInfo(T);
            if (info != .pointer or
                @sizeOf(info.pointer.child) != @sizeOf(VaList))
            {
                @compileError("unexpected x86_64 C va_list parameter type");
            }
            break :blk @ptrCast(list);
        },
        .aarch64 => blk: {
            if (@sizeOf(T) != @sizeOf(VaList) or
                @alignOf(T) != @alignOf(VaList))
            {
                @compileError("unexpected AArch64 C va_list parameter type");
            }
            break :blk @bitCast(list.*);
        },
        else => unreachable,
    };
}

fn pointerAt(address: usize) ?*anyopaque {
    const slot: *align(@alignOf(usize)) const usize = @ptrFromInt(address);
    return if (slot.* == 0) null else @ptrFromInt(slot.*);
}

fn nextAarch64Pointer(list: *std.builtin.VaListAarch64) ?*anyopaque {
    const slot_size = @sizeOf(usize);
    const offset = list.__gr_offs;

    if (offset < 0) {
        const next_offset = offset + slot_size;
        list.__gr_offs = next_offset;
        if (next_offset <= 0) {
            const address =
                @intFromPtr(list.__gr_top) -
                @as(usize, @intCast(-offset));
            return pointerAt(address);
        }
    }

    const address = std.mem.alignForward(
        usize,
        @intFromPtr(list.__stack),
        @alignOf(usize),
    );
    list.__stack = @ptrFromInt(address + slot_size);
    return pointerAt(address);
}

pub fn nextPointer(list: *VaList) callconv(.c) ?*anyopaque {
    if (comptime needs_manual_start) {
        return nextAarch64Pointer(list);
    }
    return @cVaArg(list, ?*anyopaque);
}
