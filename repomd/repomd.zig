const std = @import("std");
const shared_xml = @import("xml");
const sax = shared_xml.sax;
const model = @import("model.zig");

const REPO_NS = "http://linux.duke.edu/metadata/repo";

pub const Error = error{
    InvalidRepoMd,
    OutOfMemory,
};

const ElementKind = enum {
    other,
    root,
    revision,
    data,
    checksum,
    open_checksum,
    location,
    timestamp,
    size,
    open_size,
    database_version,
};

const Frame = struct {
    kind: ElementKind,
    record_index: ?usize = null,
    collect_text: bool = false,
    text: std.array_list.Managed(u8),
    pszType: ?[:0]const u8 = null,

    fn init(allocator: std.mem.Allocator, kind: ElementKind) Frame {
        return .{
            .kind = kind,
            .text = std.array_list.Managed(u8).init(allocator),
        };
    }

    fn deinit(self: *Frame) void {
        self.text.deinit();
    }
};

const Parser = struct {
    allocator: std.mem.Allocator,
    frames: std.array_list.Managed(Frame),
    records: std.array_list.Managed(model.Record),
    record_xml_bases: std.array_list.Managed(?[]const u8),
    pszRevision: ?[*:0]const u8 = null,
    saw_root: bool = false,

    fn init(allocator: std.mem.Allocator) Parser {
        return .{
            .allocator = allocator,
            .frames = std.array_list.Managed(Frame).init(allocator),
            .records = std.array_list.Managed(model.Record).init(allocator),
            .record_xml_bases = std.array_list.Managed(?[]const u8).init(
                allocator,
            ),
        };
    }

    fn deinit(self: *Parser) void {
        for (self.frames.items) |*frame| {
            frame.deinit();
        }
        self.frames.deinit();
        self.record_xml_bases.deinit();
        self.records.deinit();
    }

    fn parse(self: *Parser, input: []const u8) Error!model.ParsedRepoMd {
        var walker = sax.Walker.init(std.heap.c_allocator, input);
        defer walker.deinit();

        while (true) {
            const maybe_event = walker.next() catch |err| return switch (err) {
                error.InvalidXml => error.InvalidRepoMd,
                error.OutOfMemory => error.OutOfMemory,
            };

            const event = maybe_event orelse break;
            switch (event) {
                .start => |start| try self.onStartElement(start),
                .text => |text| try self.onText(text),
                .end => |end| try self.onEndElement(end),
            }
        }

        if (!self.saw_root or self.frames.items.len != 0) {
            return error.InvalidRepoMd;
        }

        const records = try self.records.toOwnedSlice();
        errdefer self.allocator.free(records);
        const record_xml_bases = try self.record_xml_bases.toOwnedSlice();
        if (record_xml_bases.len != records.len) {
            self.allocator.free(record_xml_bases);
            return error.InvalidRepoMd;
        }
        return .{
            .pszRevision = self.pszRevision,
            .pRecords = records,
            .pRecordXmlBases = record_xml_bases,
        };
    }

    fn onStartElement(self: *Parser, element: sax.StartElement) Error!void {
        if (!self.saw_root) {
            if (!isRepoElement(element.name.ns_uri, element.name.local, "repomd")) {
                return error.InvalidRepoMd;
            }
            self.saw_root = true;
            try self.frames.append(Frame.init(self.allocator, .root));
            return;
        }

        if (self.frames.items.len == 0) {
            return error.InvalidRepoMd;
        }

        const parent = self.frames.items[self.frames.items.len - 1];
        var frame = Frame.init(self.allocator, .other);

        if (isRepoNs(element.name.ns_uri)) {
            switch (parent.kind) {
                .root => {
                    if (std.mem.eql(u8, element.name.local, "revision")) {
                        frame.kind = .revision;
                        frame.collect_text = true;
                    } else if (std.mem.eql(u8, element.name.local, "data")) {
                        const raw_type = lookupAttr(element.attrs, "type") orelse return error.InvalidRepoMd;
                        const type_z = try model.dupZ(self.allocator, raw_type);
                        try self.records.append(.{
                            .pszType = type_z.ptr,
                            .dwKind = @intFromEnum(model.kindFromRawType(raw_type)),
                        });
                        try self.record_xml_bases.append(null);
                        frame.kind = .data;
                        frame.record_index = self.records.items.len - 1;
                    }
                },
                .data => {
                    const record_index = parent.record_index orelse return error.InvalidRepoMd;
                    if (std.mem.eql(u8, element.name.local, "checksum")) {
                        frame.kind = .checksum;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                        if (lookupAttr(element.attrs, "type")) |checksum_type| {
                            frame.pszType = try model.dupZ(self.allocator, checksum_type);
                        }
                    } else if (std.mem.eql(u8, element.name.local, "open-checksum")) {
                        frame.kind = .open_checksum;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                        if (lookupAttr(element.attrs, "type")) |checksum_type| {
                            frame.pszType = try model.dupZ(self.allocator, checksum_type);
                        }
                    } else if (std.mem.eql(u8, element.name.local, "location")) {
                        const href = lookupAttr(element.attrs, "href") orelse return error.InvalidRepoMd;
                        if (href.len == 0) return error.InvalidRepoMd;
                        const href_z = try model.dupZ(self.allocator, href);
                        self.records.items[record_index].pszLocationHref = href_z.ptr;
                        self.record_xml_bases.items[record_index] =
                            if (element.xml_base) |xml_base|
                                try model.dup(self.allocator, xml_base)
                            else
                                null;
                        frame.kind = .location;
                        frame.record_index = record_index;
                    } else if (std.mem.eql(u8, element.name.local, "timestamp")) {
                        frame.kind = .timestamp;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                    } else if (std.mem.eql(u8, element.name.local, "size")) {
                        frame.kind = .size;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                    } else if (std.mem.eql(u8, element.name.local, "open-size")) {
                        frame.kind = .open_size;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                    } else if (std.mem.eql(u8, element.name.local, "database_version")) {
                        frame.kind = .database_version;
                        frame.record_index = record_index;
                        frame.collect_text = true;
                    }
                },
                else => {},
            }
        }

        try self.frames.append(frame);
    }

    fn onText(self: *Parser, text: []const u8) Error!void {
        if (self.frames.items.len == 0) {
            return error.InvalidRepoMd;
        }

        const top = &self.frames.items[self.frames.items.len - 1];
        if (!top.collect_text) return;
        try top.text.appendSlice(text);
    }

    fn onEndElement(self: *Parser, element: sax.EndElement) Error!void {
        _ = element;
        if (self.frames.items.len == 0) {
            return error.InvalidRepoMd;
        }

        try self.finishTopFrame();
        var frame = self.frames.pop() orelse return error.InvalidRepoMd;
        frame.deinit();
    }

    fn finishTopFrame(self: *Parser) Error!void {
        const top = &self.frames.items[self.frames.items.len - 1];
        switch (top.kind) {
            .revision => {
                const text = trimText(top.text.items);
                if (text.len != 0) {
                    const value_z = try model.dupZ(self.allocator, text);
                    self.pszRevision = value_z.ptr;
                }
            },
            .data => {
                const record_index = top.record_index orelse return error.InvalidRepoMd;
                if (self.records.items[record_index].pszLocationHref == null) {
                    return error.InvalidRepoMd;
                }
            },
            .checksum => try self.finishChecksum(top, false),
            .open_checksum => try self.finishChecksum(top, true),
            .timestamp => {
                const record = try self.currentRecord(top);
                record.nTimestamp = try parseTimestamp(top.text.items);
                record.nHasTimestamp = 1;
            },
            .size => {
                const record = try self.currentRecord(top);
                record.nSize = try parseRequiredUnsigned(top.text.items);
                record.nHasSize = 1;
            },
            .open_size => {
                const record = try self.currentRecord(top);
                record.nOpenSize = try parseRequiredUnsigned(top.text.items);
                record.nHasOpenSize = 1;
            },
            .database_version => {
                const record = try self.currentRecord(top);
                record.nDatabaseVersion = try parseRequiredUnsigned(top.text.items);
                record.nHasDatabaseVersion = 1;
            },
            else => {},
        }
    }

    fn finishChecksum(self: *Parser, top: *const Frame, open: bool) Error!void {
        const record = try self.currentRecord(top);
        const text = trimText(top.text.items);
        if (text.len == 0) {
            return error.InvalidRepoMd;
        }

        const value_z = try model.dupZ(self.allocator, text);
        const checksum = model.Checksum{
            .pszType = if (top.pszType) |value| value.ptr else null,
            .pszValue = value_z.ptr,
        };
        if (open) {
            record.openChecksum = checksum;
        } else {
            record.checksum = checksum;
        }
    }

    fn currentRecord(self: *Parser, top: *const Frame) Error!*model.Record {
        const record_index = top.record_index orelse return error.InvalidRepoMd;
        return &self.records.items[record_index];
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) Error!model.ParsedRepoMd {
    var parser = Parser.init(allocator);
    defer parser.deinit();
    return parser.parse(input);
}

fn isRepoNs(ns_uri: ?[]const u8) bool {
    const uri = ns_uri orelse return false;
    return std.mem.eql(u8, uri, REPO_NS);
}

fn isRepoElement(ns_uri: ?[]const u8, local: []const u8, wanted: []const u8) bool {
    return isRepoNs(ns_uri) and std.mem.eql(u8, local, wanted);
}

fn lookupAttr(attrs: []const sax.Attribute, local: []const u8) ?[]const u8 {
    var index = attrs.len;
    while (index > 0) {
        index -= 1;
        const attr = attrs[index];
        if (attr.prefix.len == 0 and std.mem.eql(u8, attr.local, local)) {
            return attr.value;
        }
    }
    return null;
}

fn trimText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn parseRequiredUnsigned(text: []const u8) Error!u64 {
    const trimmed = trimText(text);
    if (trimmed.len == 0) {
        return error.InvalidRepoMd;
    }
    return parseUnsignedDigits(trimmed) catch error.InvalidRepoMd;
}

fn parseTimestamp(text: []const u8) Error!u64 {
    const trimmed = trimText(text);
    if (trimmed.len == 0 or trimmed[0] == '-') {
        return error.InvalidRepoMd;
    }

    var integer_end = trimmed.len;
    if (std.mem.indexOfScalar(u8, trimmed, '.')) |dot| {
        integer_end = dot;
        if (dot + 1 == trimmed.len) {
            return error.InvalidRepoMd;
        }
        for (trimmed[dot + 1 ..]) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidRepoMd;
        }
    }
    if (integer_end == 0) return error.InvalidRepoMd;
    return parseUnsignedDigits(trimmed[0..integer_end]) catch
        error.InvalidRepoMd;
}

fn parseUnsignedDigits(text: []const u8) !u64 {
    var start: usize = 0;
    if (text[0] == '+') {
        start = 1;
        if (start == text.len) return error.InvalidNumber;
    }
    for (text[start..]) |byte| {
        if (!std.ascii.isDigit(byte)) return error.InvalidNumber;
    }
    return std.fmt.parseInt(u64, text[start..], 10);
}

test "repomd timestamps retain integer seconds from fractional values" {
    const xml =
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><location href="repodata/primary.xml"/><timestamp>42.875</timestamp></data></repomd>
    ;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try parse(arena_state.allocator(), xml);
    try std.testing.expectEqual(@as(usize, 1), parsed.pRecords.len);
    try std.testing.expectEqual(@as(u64, 42), parsed.pRecords[0].nTimestamp);
    try std.testing.expectEqual(@as(c_int, 1), parsed.pRecords[0].nHasTimestamp);
}

test "repomd timestamps reject malformed, negative, and overflowing values" {
    for ([_][]const u8{
        "42.",
        "42.seconds",
        "-1",
        "18446744073709551616",
        "18446744073709551616.5",
    }) |timestamp| {
        const xml = try std.fmt.allocPrint(
            std.testing.allocator,
            "<repomd xmlns=\"http://linux.duke.edu/metadata/repo\"><data type=\"primary\"><location href=\"repodata/primary.xml\"/><timestamp>{s}</timestamp></data></repomd>",
            .{timestamp},
        );
        defer std.testing.allocator.free(xml);
        var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena_state.deinit();
        try std.testing.expectError(
            error.InvalidRepoMd,
            parse(arena_state.allocator(), xml),
        );
    }
}

test "repomd locations retain inherited effective XML Base" {
    const xml =
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo" xml:base="https://example.test/repo/">
        \\  <data type="primary" xml:base="../metadata/">
        \\    <location xml:base="nested/" href="repodata/primary.xml"/>
        \\  </data>
        \\</repomd>
    ;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try parse(arena_state.allocator(), xml);
    try std.testing.expectEqual(@as(usize, 1), parsed.pRecords.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.pRecordXmlBases.len);
    try std.testing.expectEqualStrings(
        "https://example.test/metadata/nested/",
        parsed.pRecordXmlBases[0].?,
    );
}

test "repomd omits current-directory XML Bases" {
    const xml =
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo" xml:base=".">
        \\  <data type="primary" xml:base="./">
        \\    <location xml:base="" href="repodata/primary.xml"/>
        \\  </data>
        \\</repomd>
    ;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try parse(arena_state.allocator(), xml);
    try std.testing.expectEqual(@as(usize, 1), parsed.pRecordXmlBases.len);
    try std.testing.expect(parsed.pRecordXmlBases[0] == null);
    try std.testing.expectEqualStrings(
        "repodata/primary.xml",
        std.mem.span(parsed.pRecords[0].pszLocationHref.?),
    );
}

test "repomd rejects empty required location href" {
    const xml =
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><location href=""/></data></repomd>
    ;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectError(
        error.InvalidRepoMd,
        parse(arena_state.allocator(), xml),
    );
}
