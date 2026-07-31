// Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

//! A growable list of 32-bit ids, replacing libsolv's `Queue` as the way
//! `client/` carries package selections and solver jobs around.
//!
//! Two shapes share this one container, exactly as they shared `Queue`:
//! a *selection* is a flat list of package ids, and a *job list* is a list of
//! `(how, id)` pairs, which is why `push2` exists. The pair layout is what the
//! transaction-plan request trace already consumes -- it takes a plain
//! `const int32_t *` -- so nothing about the on-the-wire job numbering moves.
//!
//! Deliberately not generic and deliberately not an `ArrayList`: the C callers
//! own the struct by value, embed it in their own locals, and hand
//! `.pnElements` to code that wants a bare pointer, so the layout has to stay
//! exactly this and the allocator has to be the project's own, which is why
//! this calls `TDNFAllocateMemory` and friends rather than a Zig allocator.

const std = @import("std");

const errors = @import("tdnf_error");

/// Mirrors `TDNF_ID_LIST` in `common/structs.h`.
pub const IdList = extern struct {
    pnElements: ?[*]i32,
    dwCount: u32,
    dwCapacity: u32,
};

extern fn TDNFAllocateMemory(
    nNumElements: usize,
    nSize: usize,
    ppMemory: *?*anyopaque,
) callconv(.c) u32;

extern fn TDNFReAllocateMemory(
    nSize: usize,
    ppMemory: *?*anyopaque,
) callconv(.c) u32;

extern fn TDNFFreeMemory(pMemory: ?*anyopaque) callconv(.c) void;

/// Chosen so the common cases -- a handful of goal ids, or a few job pairs --
/// never realloc, while an all-packages job list still only grows a few times.
const minimum_capacity: u32 = 16;

fn reserve(list: *IdList, additional: u32) u32 {
    const needed = std.math.add(u32, list.dwCount, additional) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    if (needed <= list.dwCapacity) return 0;

    var capacity = if (list.dwCapacity < minimum_capacity)
        minimum_capacity
    else
        list.dwCapacity;
    while (capacity < needed) {
        capacity = std.math.mul(u32, capacity, 2) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }

    const bytes = std.math.mul(usize, capacity, @sizeOf(i32)) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;

    var memory: ?*anyopaque = @ptrCast(list.pnElements);
    if (memory == null) {
        const rc = TDNFAllocateMemory(capacity, @sizeOf(i32), &memory);
        if (rc != 0) return rc;
    } else {
        const rc = TDNFReAllocateMemory(bytes, &memory);
        if (rc != 0) return rc;
        // `TDNFReAllocateMemory` does not zero what it grows into, and callers
        // read `pnElements[0..dwCount]` only, but the trace helpers are handed
        // the raw pointer, so leaving stale bytes past the count would be a
        // trap waiting for the first caller that trusts the capacity.
        const raw: [*]i32 = @ptrCast(@alignCast(memory.?));
        @memset(raw[list.dwCount..capacity], 0);
    }

    list.pnElements = @ptrCast(@alignCast(memory.?));
    list.dwCapacity = capacity;
    return 0;
}

/// Resets a list to empty without freeing. Safe on a zeroed struct, which is
/// how C callers declare theirs (`TDNF_ID_LIST list = {0};`).
export fn TDNFIdListInit(pList: ?*IdList) callconv(.c) void {
    const list = pList orelse return;
    list.* = .{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
}

export fn TDNFIdListFree(pList: ?*IdList) callconv(.c) void {
    const list = pList orelse return;
    TDNFFreeMemory(@ptrCast(list.pnElements));
    list.* = .{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
}

/// Drops every element but keeps the allocation, matching `queue_empty()`.
export fn TDNFIdListEmpty(pList: ?*IdList) callconv(.c) void {
    const list = pList orelse return;
    list.dwCount = 0;
}

export fn TDNFIdListPush(pList: ?*IdList, nValue: i32) callconv(.c) u32 {
    const list = pList orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const rc = reserve(list, 1);
    if (rc != 0) return rc;
    list.pnElements.?[list.dwCount] = nValue;
    list.dwCount += 1;
    return 0;
}

/// Appends a `(how, id)` job pair. Both elements land or neither does, so a
/// failed push can never leave a job list with an odd count -- every consumer
/// indexes it two at a time.
export fn TDNFIdListPush2(
    pList: ?*IdList,
    nFirst: i32,
    nSecond: i32,
) callconv(.c) u32 {
    const list = pList orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const rc = reserve(list, 2);
    if (rc != 0) return rc;
    list.pnElements.?[list.dwCount] = nFirst;
    list.pnElements.?[list.dwCount + 1] = nSecond;
    list.dwCount += 2;
    return 0;
}

/// `queue_pushunique()`: appends only when the value is not already present.
export fn TDNFIdListPushUnique(pList: ?*IdList, nValue: i32) callconv(.c) u32 {
    const list = pList orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (list.pnElements) |elements| {
        for (elements[0..list.dwCount]) |existing| {
            if (existing == nValue) return 0;
        }
    }
    return TDNFIdListPush(pList, nValue);
}

test "push grows and preserves order" {
    var list = IdList{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
    defer TDNFIdListFree(&list);

    var index: i32 = 0;
    while (index < 100) : (index += 1) {
        try std.testing.expectEqual(@as(u32, 0), TDNFIdListPush(&list, index));
    }
    try std.testing.expectEqual(@as(u32, 100), list.dwCount);
    try std.testing.expect(list.dwCapacity >= 100);
    index = 0;
    while (index < 100) : (index += 1) {
        try std.testing.expectEqual(index, list.pnElements.?[@intCast(index)]);
    }
}

test "push2 keeps pairs adjacent and the count even" {
    var list = IdList{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
    defer TDNFIdListFree(&list);

    var index: i32 = 0;
    while (index < 50) : (index += 1) {
        try std.testing.expectEqual(
            @as(u32, 0),
            TDNFIdListPush2(&list, index, index + 1000),
        );
        try std.testing.expectEqual(@as(u32, 0), list.dwCount % 2);
    }
    try std.testing.expectEqual(@as(u32, 100), list.dwCount);
    index = 0;
    while (index < 50) : (index += 1) {
        const at: usize = @intCast(index * 2);
        try std.testing.expectEqual(index, list.pnElements.?[at]);
        try std.testing.expectEqual(index + 1000, list.pnElements.?[at + 1]);
    }
}

test "pushunique skips values already present" {
    var list = IdList{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
    defer TDNFIdListFree(&list);

    try std.testing.expectEqual(@as(u32, 0), TDNFIdListPushUnique(&list, 7));
    try std.testing.expectEqual(@as(u32, 0), TDNFIdListPushUnique(&list, 9));
    try std.testing.expectEqual(@as(u32, 0), TDNFIdListPushUnique(&list, 7));
    try std.testing.expectEqual(@as(u32, 2), list.dwCount);
    try std.testing.expectEqual(@as(i32, 7), list.pnElements.?[0]);
    try std.testing.expectEqual(@as(i32, 9), list.pnElements.?[1]);
}

test "empty keeps the allocation and free resets the struct" {
    var list = IdList{ .pnElements = null, .dwCount = 0, .dwCapacity = 0 };
    defer TDNFIdListFree(&list);

    try std.testing.expectEqual(@as(u32, 0), TDNFIdListPush(&list, 1));
    const capacity = list.dwCapacity;
    TDNFIdListEmpty(&list);
    try std.testing.expectEqual(@as(u32, 0), list.dwCount);
    try std.testing.expectEqual(capacity, list.dwCapacity);
    try std.testing.expect(list.pnElements != null);

    TDNFIdListFree(&list);
    try std.testing.expectEqual(@as(u32, 0), list.dwCount);
    try std.testing.expectEqual(@as(u32, 0), list.dwCapacity);
    try std.testing.expect(list.pnElements == null);
}

test "null list arguments are rejected rather than crashing" {
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFIdListPush(null, 1),
    );
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFIdListPush2(null, 1, 2),
    );
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFIdListPushUnique(null, 1),
    );
    TDNFIdListInit(null);
    TDNFIdListFree(null);
    TDNFIdListEmpty(null);
}
