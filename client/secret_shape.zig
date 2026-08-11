//! Credential-shaped text detection shared by every versioned tdnf artifact.
//!
//! These predicates are the last line of defence against a secret reaching a
//! plan, a bundle manifest, a digest, or a filename. They are deliberately
//! conservative: a false positive rejects an input, while a false negative
//! publishes a credential.

const std = @import("std");

pub fn isHex(byte: u8) bool {
    return std.ascii.isDigit(byte) or (byte >= 'a' and byte <= 'f') or (byte >= 'A' and byte <= 'F');
}

pub fn hexByte(high: u8, low: u8) u8 {
    return hexValue(high) * 16 + hexValue(low);
}

fn hexValue(byte: u8) u8 {
    return if (std.ascii.isDigit(byte))
        byte - '0'
    else if (byte >= 'a' and byte <= 'f')
        byte - 'a' + 10
    else
        byte - 'A' + 10;
}

pub const markers = [_][]const u8{
    "-----begin ",
    "private key",
    "api_key=",
    "apikey=",
    "access_token=",
    "client_secret=",
    "passwd=",
    "password=",
    "proxy://",
    "proxy=",
    "proxy_password=",
    "proxy_pass=",
    "proxy_user=",
    "******proxy=",
    "************proxy=",
    "******secret=",
    "secret=",
    "token=",
};

pub fn containsSecretShape(value: []const u8) bool {
    for (markers) |marker| {
        if (indexOfIgnoreCase(value, marker) != null) return true;
    }
    return false;
}

fn decodedUriByte(value: []const u8, index: *usize) u8 {
    const byte = value[index.*];
    index.* += 1;
    if (byte == '%') {
        const decoded = hexByte(value[index.*], value[index.* + 1]);
        index.* += 2;
        return decoded;
    }
    return byte;
}

/// Scans an absolute URI's authority and path once after percent-decoding.
/// Callers exclude the outer HTTP(S) scheme so a safe scheme is not a marker.
pub fn decodedUriHasSecretShape(
    value: []const u8,
    authority_length: ?usize,
) bool {
    var history: [64]u8 = undefined;
    var history_len: usize = 0;
    var next_slot: usize = 0;
    var value_index: usize = 0;
    while (value_index < value.len) {
        const raw_index = value_index;
        const byte = decodedUriByte(value, &value_index);
        if (authority_length) |length| {
            if (raw_index < length and
                (byte == '@' or byte == '/' or byte == '\\' or
                    byte == '?' or byte == '#'))
            {
                return true;
            }
        }

        history[next_slot] = std.ascii.toLower(byte);
        next_slot = (next_slot + 1) % history.len;
        if (history_len < history.len) history_len += 1;
        for (markers) |marker| {
            if (decodedRingEndsWith(history[0..], next_slot, history_len, marker)) {
                return true;
            }
        }
        if (decodedRingEndsWith(history[0..], next_slot, history_len, "://")) {
            return true;
        }
    }
    return false;
}

pub fn decodedRingEndsWith(
    history: []const u8,
    next_slot: usize,
    history_len: usize,
    marker: []const u8,
) bool {
    if (marker.len > history_len) return false;
    const first_slot = (next_slot + history.len - marker.len) % history.len;
    for (marker, 0..) |byte, index| {
        if (history[(first_slot + index) % history.len] != byte) return false;
    }
    return true;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    for (0..haystack.len - needle.len + 1) |index| if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    return null;
}
