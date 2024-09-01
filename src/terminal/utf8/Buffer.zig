/// The mutable list of utf-8 string,
/// where every string is a single line.
/// It's used as buffer to render graphic in the terminal.
const std = @import("std");
const String = @import("String.zig");

const Buffer = @This();

const Error = String.Error;

lines: std.ArrayList(String),

pub fn init(alloc: std.mem.Allocator) Buffer {
    return .{ .lines = std.ArrayList(String).init(alloc) };
}

pub fn deinit(self: Buffer) void {
    for (self.lines.items) |string| {
        string.deinit();
    }
    self.lines.deinit();
}

pub fn parseInit(alloc: std.mem.Allocator, str: []const u8) Error!Buffer {
    var self: Buffer = Buffer.init(alloc);
    var t = std.mem.tokenizeAny(u8, str, "\r\n");
    while (t.next()) |line| {
        try self.addLine(line);
    }
    return self;
}

pub inline fn get(self: Buffer, idx: usize) ?*String {
    return if (self.lines.items.len > idx) &self.lines.items[idx] else null;
}

pub fn addLine(self: *Buffer, line: []const u8) Error!void {
    const s_ptr = try self.lines.addOne();
    s_ptr.* = try String.initParse(self.lines.allocator, line);
}

pub fn addEmptyLine(self: *Buffer) Error!void {
    const s_ptr = try self.lines.addOne();
    s_ptr.* = String.init(self.lines.allocator);
}

pub fn addEmptyLineWithCapacity(self: *Buffer, capacity_in_bytes: usize) Error!void {
    const s_ptr = try self.lines.addOne();
    s_ptr.* = try String.initWithCapacity(capacity_in_bytes, self.lines.allocator);
}

/// Allocates a memory for the string which will contains the content of this buffer.
/// Every line of the buffer except the last one will be added with additional symbol
/// '\n' at the end. The result doesn't have a sentinel 0 at the end.
///
/// Don't forget to free the returned string!
pub fn toCString(self: Buffer, alloc: std.mem.Allocator) Error![]const u8 {
    var bytes: usize = 0;
    for (self.lines.items) |line| {
        bytes += line.bytesCount() + 1; // +1 for "\n"
    }

    if (bytes < 2) return "" else bytes -= 1;

    var i: usize = 0;
    var str: []u8 = try alloc.alloc(u8, bytes);
    for (self.lines.items) |line| {
        const j = i + line.bytesCount();
        @memcpy(str[i..j], line.bytes.items);
        if (j >= bytes)
            break;
        str[j] = '\n';
        i = j + 1;
    }
    return str;
}

/// Returns the length in bytes of the idx line, or null, if lines is not enough.
inline fn getLengthOfLine(self: Buffer, idx: usize) ?usize {
    if (self.get(idx)) |line| {
        return line.bytesCount();
    } else {
        return null;
    }
}

/// Merges string `str` with line `line` starting from the `pos` symbol (both start from 0).
pub fn mergeLine(self: *Buffer, str: []const u8, line: u8, pos: u8) Error!void {
    try self.addAbsentLines(line + 1);
    const string = try String.initParse(self.lines.allocator, str);
    defer string.deinit();
    try self.lines.items[line].merge(string, pos);
}

fn addAbsentLines(self: *Buffer, expected_lines_count: u8) Error!void {
    if (expected_lines_count > self.lines.items.len) {
        for (0..(expected_lines_count - self.lines.items.len)) |_| {
            try self.addEmptyLine();
        }
    }
}

pub fn merge(self: *Buffer, other: Buffer, lines_pad: u8, left_symbols_pad: u8) Error!void {
    // add lines till pad
    try self.addAbsentLines(lines_pad);
    // merge intersection
    const min_len = @min(self.lines.items.len - lines_pad, other.lines.items.len);
    for (0..min_len) |i| {
        try self.lines.items[i + lines_pad].merge(other.lines.items[i], left_symbols_pad);
    }
}

pub fn set(self: *Buffer, codepoint: u21, lines_pad: u8, left_symbols_pad: u8) Error!void {
    try self.addAbsentLines(lines_pad);
    try self.lines.items[lines_pad].set(left_symbols_pad, codepoint);
}

test "parse string" {
    const data =
        \\12345
        \\67890
    ;
    const buffer = try Buffer.parseInit(std.testing.allocator, data);
    defer buffer.deinit();

    try std.testing.expectEqual(2, buffer.lines.items.len);
}

test "should crop \\\\r and \\\\n symbols" {
    const data = "12345\n";
    const buffer = try Buffer.parseInit(std.testing.allocator, data);
    defer buffer.deinit();

    try std.testing.expectEqual(1, buffer.lines.items.len);
}

test "should recover to the same string" {
    const data =
        \\12345
        \\67890
    ;
    const buffer = try Buffer.parseInit(std.testing.allocator, data);
    defer buffer.deinit();

    const str = try buffer.toCString(std.testing.allocator);
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(data, str);
}

test "merge line" {
    // given:
    const str =
        \\.........
        \\.........
        \\.........
    ;
    const expected =
        \\.........
        \\...###...
        \\.........
    ;
    var buffer = try Buffer.parseInit(std.testing.allocator, str);
    defer buffer.deinit();

    // when:
    try buffer.mergeLine("###", 1, 3);
    const actual = try buffer.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}

test "merge line with empty buffer" {
    const expected =
        \\
        \\   ###
    ;
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    // when:
    try buffer.mergeLine("###", 1, 3);
    const actual = try buffer.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}

test "merge middle buffer" {
    // given:
    const str =
        \\.........
        \\.........
        \\.........
    ;
    var first = try Buffer.parseInit(std.testing.allocator, str);
    defer first.deinit();
    var second = try Buffer.parseInit(std.testing.allocator, "###");
    defer second.deinit();
    const expected =
        \\.........
        \\...###...
        \\.........
    ;

    // when:
    try first.merge(second, 1, 3);
    const actual = try first.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}

test "merge bigger buffer" {
    // given:
    const str1 =
        \\.......
        \\.......
        \\.......
    ;
    const str2 =
        \\###
        \\######
        \\###
    ;
    const expected =
        \\.......
        \\...###.
        \\...######
    ;
    var first = try Buffer.parseInit(std.testing.allocator, str1);
    defer first.deinit();
    var second = try Buffer.parseInit(std.testing.allocator, str2);
    defer second.deinit();

    // when:
    try first.merge(second, 1, 3);
    const actual = try first.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}

test "merge buffers with utf-8 symbols" {
    // given:
    const str =
        \\███
        \\███
        \\███
    ;
    const expected =
        \\███
        \\█☺█
        \\███
    ;
    var first = try Buffer.parseInit(std.testing.allocator, str);
    defer first.deinit();
    var second = try Buffer.parseInit(std.testing.allocator, "☺");
    defer second.deinit();

    // when:
    try first.merge(second, 1, 1);
    const actual = try first.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}
