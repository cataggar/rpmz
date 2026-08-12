//! Direct package-integrity API used by the client's GPG policy layer.

const std = @import("std");
const pkgfile = @import("rpm_pkgfile");
const integrity = @import("integrity.zig");
const file_handle = @import("rpm_file_handle");

pub const FileHandle = file_handle.FileHandle;
pub const SignatureReport = integrity.SignatureReport;

pub const Outcome = enum(i32) {
    ok = 0,
    missing = 1,
    bad = 2,
    unsupported = 3,
    malformed = 4,
    internal = 5,
};

pub fn openFile(path: [:0]const u8) pkgfile.Error!*FileHandle {
    var file = try pkgfile.RpmFile.open(std.heap.c_allocator, path);
    errdefer file.close(std.heap.c_allocator);
    const handle = try std.heap.c_allocator.create(FileHandle);
    handle.* = .{ .file = file };
    return handle;
}

pub fn closeFile(handle_opt: ?*FileHandle) void {
    const handle = handle_opt orelse return;
    handle.file.close(std.heap.c_allocator);
    std.heap.c_allocator.destroy(handle);
}

pub fn verifyDigests(
    allocator: std.mem.Allocator,
    handle: *const FileHandle,
) integrity.Error!Outcome {
    var report = try integrity.verifyPackage(allocator, &handle.file, .{});
    defer report.deinit(allocator);
    if (integrity.rpm6SuppressesLegacySignatureHeader(&handle.file))
        report.suppressLegacySignatureHeader();
    return classifyDigests(&report);
}

pub fn verifySignatures(
    allocator: std.mem.Allocator,
    handle: *const FileHandle,
    key_blobs: []const []const u8,
) integrity.Error!Outcome {
    var report = try integrity.verifySignatures(
        allocator,
        &handle.file,
        .{},
        key_blobs,
    );
    defer report.deinit(allocator);
    return classifySignatures(&report);
}

/// Detailed form used by bundle replay to bind a successful verification to
/// the exact bundled key fingerprint recorded in the manifest.
pub fn verifySignatureReport(
    allocator: std.mem.Allocator,
    handle: *const FileHandle,
    key_blobs: []const []const u8,
) integrity.Error!SignatureReport {
    return integrity.verifySignatures(
        allocator,
        &handle.file,
        .{},
        key_blobs,
    );
}

fn classifyDigests(report: *const integrity.Report) Outcome {
    var saw_bad = false;
    var saw_unsupported = false;
    var saw_malformed = false;

    for (report.candidates, 0..) |candidate, index| {
        if (candidate.suppressed_legacy) continue;
        switch (candidate.outcome) {
            .bad_digest => {
                if (!report.failureSuppressedByAlternative(index))
                    saw_bad = true;
            },
            .malformed_tag => {
                if (!report.failureSuppressedByAlternative(index))
                    saw_malformed = true;
            },
            .unsupported_digest => {
                if (!report.failureSuppressedByAlternative(index))
                    saw_unsupported = true;
            },
            else => {},
        }
    }

    if (saw_malformed) return .malformed;
    if (saw_bad) return .bad;
    if (saw_unsupported) return .unsupported;
    if (!report.coverage.header_verified or !report.coverage.payload_verified)
        return .missing;
    return .ok;
}

fn classifySignatures(report: *const integrity.SignatureReport) Outcome {
    var saw_missing_key = false;
    var saw_bad = false;
    var saw_unsupported = false;
    var saw_malformed = false;
    var saw_internal = false;

    for (report.candidates) |candidate| {
        switch (candidate.outcome) {
            .no_key => saw_missing_key = true,
            .bad_signature => saw_bad = true,
            .unsupported_openpgp => saw_unsupported = true,
            .malformed_tag, .malformed_base64, .malformed_openpgp => saw_malformed = true,
            .unchecked => saw_internal = true,
            else => {},
        }
    }

    if (saw_malformed) return .malformed;
    if (saw_bad) return .bad;
    if (saw_unsupported) return .unsupported;
    if (saw_internal) return .internal;
    if (report.coverage.no_signature_candidates or saw_missing_key)
        return .missing;
    if (report.coverage.any_enabled_unsuppressed_failure or
        !report.coverage.fully_verified)
        return .internal;
    return .ok;
}
