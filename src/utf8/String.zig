const std = @import("std");

/// The representation of the mutable string in utf-8 encoding,
/// which can be dynamically extended by another utf-8 string.
/// Instead of the standard string representation, this one isn't
/// ended by the '\0' symbol.
pub const Symbol = struct {
    index: usize,
    len: u8,
};

pub const Error = std.mem.Allocator.Error;

const String = @This();

bytes: std.ArrayList(u8),

/// Allocates the byte arrays with allocator `alloc`,
/// and copies all symbols from the string `str`.
pub fn init(str: []const u8, alloc: std.mem.Allocator) Error!String {
    var bytes = try std.ArrayList(u8).initCapacity(alloc, str.len);
    try bytes.insertSlice(0, str);
    return .{ .bytes = bytes };
}

/// Allocates `capacity_in_bytes` bytes  with allocator `alloc`,
pub fn initWithCapacity(capacity_in_bytes: usize, alloc: std.mem.Allocator) Error!String {
    return .{ .bytes = try std.ArrayList(u8).initCapacity(alloc, capacity_in_bytes) };
}

/// Frees memory allocated for this sting.
pub fn deinit(self: String) void {
    self.bytes.deinit();
}

/// Finds the index of the first byte of the utf-8 symbol on or next after `b_idx`.
/// Control sequences are not counted.
///
/// @b_idx the index of the byte near which the symbol will be looking for.
pub fn symbolAfter(self: String, b_idx: usize) ?Symbol {
    var idx: usize = b_idx;

    // move to the nearest symbol beginning
    // 0xC0 == 1100 0000; 0x80 == 1000 0000
    while (idx < self.bytes.items.len and (self.bytes.items[idx] & 0xC0) == 0x80) {
        idx += 1;
    }

    // looks like no one full symbol till the end
    if (idx >= self.bytes.items.len)
        return null;

    // skip control sequence
    if (self.bytes.items[idx] == '\x1b') {
        idx += 1;

        if (self.bytes.items[idx] == '[') {
            idx += 1;
            while (idx < self.bytes.items.len) {
                const c = self.bytes.items[idx];
                idx += 1;
                // TODO skip CS more generally
                if (c == 'B' or c == 'C' or c == 'J' or c == 'H' or c == 'h' or c == 'm' or c == 'l' or c == 'n')
                    break;
            }
        }
    }

    // count symbol's bytes
    var n: u8 = 1;
    while (idx + n < self.bytes.items.len and (self.bytes.items[idx + n] & 0xC0) == 0x80)
        n += 1;

    return .{ .index = idx, .len = n };
}

/// Returns the count of bytes in this string.
pub fn bytesCount(self: String) usize {
    return self.bytes.items.len;
}

/// Returns the count of symbols in utf-8 encoding in the string.
/// Control sequences are not counted.
pub fn symbolsCount(self: String) usize {
    var i: usize = 0;
    var count: usize = 0;
    while (self.symbolAfter(i)) |s| {
        count += 1;
        i = s.index + s.len;
    }
    return count;
}

/// Returns the index of the first byte of the `s_idx` symbol (0-based)
/// in this string or null, if the string has less symbols.
/// Control sequences do not count.
pub fn indexOfSymbol(self: String, s_idx: usize) ?usize {
    var found: usize = 0;
    var i: usize = 0;
    while (self.symbolAfter(i)) |s| {
        if (found == s_idx)
            return s.index;
        i = s.index + s.len;
        found += 1;
    }
    return null;
}

/// Adds the prefix to the end of this string.
pub fn append(self: *String, prefix: []const u8) Error!void {
    try self.bytes.insertSlice(self.bytes.items.len, prefix);
}

/// Appends the string `str` `count` times to the end of this string.
///
/// If the inner buffer is not enough to store the whole new string,
/// it will be recreated.
pub fn appendRepeate(self: *String, str: []const u8, count: usize) Error!void {
    for (0..count) |_| {
        try self.append(str);
    }
}

/// Replaces `source.symbolsCount()` symbols of this string by the symbols
/// of the source string. Begins from the `left_pad_symbols` symbol.
/// If the length of this string less than `left_pad_symbols`, then
/// appropriate count of spaces will be appended.
///
/// Example:
/// "abcdefg".merge("123", 2) == "ab123fg"
/// or:
/// "abc".merge("123", 5) == "abc  123"
///
pub fn merge(self: *String, source: String, left_pad_symbols: usize) Error!void {
    // find an start index of the left_pad_symbols + 1 symbol
    // from which replacement should become
    var left_pad_index: ?usize = self.indexOfSymbol(left_pad_symbols);

    // This string is shorter than left_pad_symbols.
    // Let's fill it by appropriate count of spaces
    if (left_pad_index == null) {
        const scount = self.symbolsCount();
        try self.appendRepeate(" ", left_pad_symbols - scount);
        left_pad_index = self.bytes.items.len;
    }
    // Now, let's find an index of the last byte of the symbol till which
    // replacement should happened
    const source_symbols = source.symbolsCount();

    var appendix: ?[]u8 = null;
    if (self.indexOfSymbol(source_symbols + left_pad_symbols)) |app_idx| {
        appendix = try self.bytes.allocator.alloc(u8, self.bytes.items.len - app_idx);
        @memcpy(appendix.?.ptr, self.bytes.items[app_idx..]);
    }
    defer if (appendix) |app| self.bytes.allocator.free(app);

    try self.bytes.resize(left_pad_index orelse 0);
    try self.append(source.bytes.items);
    if (appendix) |app| {
        try self.append(app);
    }
}

// 0xE2 == 1110 0010
// 0x92 == 1001 0010
// 0xB6 == 1011 0110
//
// Ⓐ    0xE2 0x92 0xB6
// Ⓑ    0xE2 0x92 0xB7
// Ⓒ    0xE2 0x92 0xB8
// Ⓓ    0xE2 0x92 0xB9
// ☺    0xE2 0x98 0xBA
// █	0xE2 0x96 0x88
// ░	0xE2 0x96 0x91

test "should return expected symbol at specified index" {
    const alloc = std.testing.allocator;
    const u8str = try String.init("ⒶⒷ", alloc);
    defer u8str.deinit();
    try std.testing.expectEqual(Symbol{ .index = 0, .len = 3 }, u8str.symbolAfter(0));
}

test "should return the next symbol after the index" {
    const alloc = std.testing.allocator;
    const u8str = try String.init("ⒶⒷ", alloc);
    defer u8str.deinit();
    try std.testing.expectEqual(Symbol{ .index = 3, .len = 3 }, u8str.symbolAfter(1));
}

test "symbols count" {
    const alloc = std.testing.allocator;
    const u8str = try String.init("ⒶⒷⒸ", alloc);
    defer u8str.deinit();
    try std.testing.expectEqual(3, u8str.symbolsCount());
}

test "should not count escape symbols" {
    const alloc = std.testing.allocator;
    const u8str = try String.init("ⒶⒷⒸ\x1bⒹ", alloc);
    defer u8str.deinit();
    try std.testing.expectEqual(4, u8str.symbolsCount());
}

test "the 3 symbol should have index 10" {
    const alloc = std.testing.allocator;
    const u8str = try String.init("ⒶⒷⒸ\x1bⒹ", alloc);
    defer u8str.deinit();
    try std.testing.expectEqual(10, u8str.indexOfSymbol(3));
}

test "merge in the middle" {
    // given:
    var str1 = try String.init(".......", std.testing.allocator);
    defer str1.deinit();
    var str2 = try String.init("***", std.testing.allocator);
    defer str2.deinit();

    // when:
    try str1.merge(str2, 2);
    
    // then:
    try std.testing.expectEqualStrings("..***..", str1.bytes.items);
}

test "merge to short string" {
    // given:
    var str1 = try String.init("", std.testing.allocator);
    defer str1.deinit();
    var str2 = try String.init("***", std.testing.allocator);
    defer str2.deinit();

    // when:
    try str1.merge(str2, 2);
    
    // then:
    try std.testing.expectEqualStrings("  ***", str1.bytes.items);
}
