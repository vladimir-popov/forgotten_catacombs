/// The mutable list of utf-8 string,
/// where every string is a single line.
/// It's used as buffer to render graphic in the terminal.
const std = @import("std");
const String = @import("String.zig");

const Buffer = @This();

const Error = std.mem.Allocator.Error;

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

pub fn parse(str: []const u8, alloc: std.mem.Allocator) Error!Buffer {
    var self: Buffer = Buffer.init(alloc);
    var t = std.mem.tokenizeAny(u8, str, "\r\n");
    while (t.next()) |line| {
        try self.addLine(line);
    }
    return self;
}

pub inline fn linesCount(self: Buffer) usize {
    return self.lines.items.len;
}

pub inline fn get(self: Buffer, idx: usize) ?String {
    return if (self.lines.items.len > idx) self.lines.items[idx] else null;
}

pub fn addLine(self: *Buffer, line: []const u8) Error!void {
    const s_ptr = try self.lines.addOne();
    s_ptr.* = try String.init(line, self.lines.allocator);
}

pub fn addEmptyLine(self: *Buffer, capacity_in_bytes: usize) Error!void {
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

pub fn merge(self: *Buffer, other: Buffer, lines_pad: usize, left_symbols_pad: usize) Error!void {
    // add lines till pad
    if (lines_pad > self.lines.items.len) {
        const max_len = @max(self.getLengthOfLine(0) orelse 0, other.getLengthOfLine(0) orelse 0);
        for (0..(lines_pad - self.lines.items.len + 1)) |_| {
            try self.addEmptyLine(max_len + left_symbols_pad);
        }
    }
    // merge intersection
    const min_len = @min(self.lines.items.len - lines_pad, other.lines.items.len);
    for (0..min_len) |i| {
        try self.lines.items[i + lines_pad].merge(other.lines.items[i], left_symbols_pad);
    }
}

test "parse string" {
    const data =
        \\12345
        \\67890
    ;
    const buffer = try Buffer.parse(data, std.testing.allocator);
    defer buffer.deinit();

    try std.testing.expectEqual(2, buffer.linesCount());
}

test "should crop \r and \n symbols" {
    const data = "12345\n";
    const buffer = try Buffer.parse(data, std.testing.allocator);
    defer buffer.deinit();

    try std.testing.expectEqual(1, buffer.linesCount());
}

test "should recover to the same string" {
    const data =
        \\12345
        \\67890
    ;
    const buffer = try Buffer.parse(data, std.testing.allocator);
    defer buffer.deinit();

    const str = try buffer.toCString(std.testing.allocator);
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings(data, str);
}

test "merge middle buffer" {
    // given:
    const str =
        \\.........
        \\.........
        \\.........
    ;
    var first = try Buffer.parse(str, std.testing.allocator);
    defer first.deinit();
    var second = try Buffer.parse("###", std.testing.allocator);
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
    var first = try Buffer.parse(str1, std.testing.allocator);
    defer first.deinit();
    var second = try Buffer.parse(str2, std.testing.allocator);
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
    var first = try Buffer.parse(str, std.testing.allocator);
    defer first.deinit();
    var second = try Buffer.parse("☺", std.testing.allocator);
    defer second.deinit();

    // when:
    try first.merge(second, 1, 1);
    const actual = try first.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    // then:
    try std.testing.expectEqualStrings(expected, actual);
}
