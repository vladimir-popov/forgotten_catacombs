const std = @import("std");

/// The representation of the mutable string in utf-8 encoding,
/// which can be dynamically extended by another utf-8 string.
/// Instead of the standard string representation, this one isn't
/// ended by the '\0' symbol.
pub const Symbol = struct {
    index: usize,
    len: u8,
};

pub const Error = std.mem.Allocator.Error || error{ Utf8CannotEncodeSurrogateHalf, CodepointTooLarge };

const String = @This();

bytes: std.ArrayList(u8),

pub fn init(alloc: std.mem.Allocator) String {
    return .{ .bytes = std.ArrayList(u8).init(alloc) };
}

/// Allocates the byte arrays with allocator `alloc`,
/// and copies all symbols from the string `str`.
pub fn initParse(alloc: std.mem.Allocator, str: []const u8) Error!String {
    var bytes = try std.ArrayList(u8).initCapacity(alloc, str.len);
    try bytes.insertSlice(0, str);
    return .{ .bytes = bytes };
}

/// Allocates `capacity_in_bytes` bytes  with allocator `alloc`,
pub fn initWithCapacity(alloc: std.mem.Allocator, capacity_in_bytes: usize) Error!String {
    return .{ .bytes = try std.ArrayList(u8).initCapacity(alloc, capacity_in_bytes) };
}

pub fn initFill(alloc: std.mem.Allocator, char: u8, count: usize) Error!String {
    var res = String{ .bytes = try std.ArrayList(u8).initCapacity(alloc, count) };
    for (0..count) |_| {
        try res.bytes.append(char);
    }
    return res;
}

pub fn fromOneSymbol(alloc: std.mem.Allocator, symbol: u21) Error!String {
    var bytes: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(symbol, &bytes);
    var str = String{ .bytes = try std.ArrayList(u8).initCapacity(alloc, len) };
    try str.bytes.insertSlice(0, bytes[0..len]);
    return str;
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
    return findStartOfSymbol(self.bytes.items, b_idx);
}

fn findStartOfSymbol(bytes: []u8, b_idx: usize) ?Symbol {
    var idx: usize = b_idx;

    // move to the nearest symbol beginning
    // 0xC0 == 1100 0000; 0x80 == 1000 0000
    while (idx < bytes.len and (bytes[idx] & 0xC0) == 0x80) {
        idx += 1;
    }

    // looks like no one full symbol till the end
    if (idx >= bytes.len)
        return null;

    // skip control sequence
    if (bytes[idx] == '\x1b') {
        idx += 1;

        if (bytes[idx] == '[') {
            idx += 1;
            while (idx < bytes.len) {
                const c = bytes[idx];
                idx += 1;
                // TODO skip CS more generally
                if (c == 'B' or c == 'C' or c == 'J' or c == 'H' or c == 'h' or c == 'm' or c == 'l' or c == 'n')
                    break;
            }
        }
    }

    // count symbol's bytes
    var n: u8 = 1;
    while (idx + n < bytes.len and (bytes[idx + n] & 0xC0) == 0x80)
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

/// Replaces s_idx (0 based) symbol by the passed symbol.
/// If the s_idx more than length of the string, appropriate count of spaces
/// will be added.
pub fn set(self: *String, s_idx: usize, symbol: u21) Error!void {
    const str = try fromOneSymbol(self.bytes.allocator, symbol);
    defer str.deinit();
    try self.merge(str, s_idx);
}

// 0xE2 == 1110 0010
// 0x92 == 1001 0010
// 0xB6 == 1011 0110
//
// Ⓐ    0xE2 0x92 0xB6   1110 0010 1001 0010 1011 0110    226 146 182
// Ⓑ    0xE2 0x92 0xB7
// Ⓒ    0xE2 0x92 0xB8
// Ⓓ    0xE2 0x92 0xB9
// ☺    0xE2 0x98 0xBA
// █	0xE2 0x96 0x88
// ░	0xE2 0x96 0x91

test "should treat uint as a utf8 symbol" {
    const str = try String.fromOneSymbol(std.testing.allocator, 'Ⓐ');
    defer str.deinit();
    try std.testing.expectEqualStrings("Ⓐ", str.bytes.items);
}

test "should return expected symbol at specified index" {
    const alloc = std.testing.allocator;
    const u8str = try String.initParse(alloc, "ⒶⒷ");
    defer u8str.deinit();
    try std.testing.expectEqual(Symbol{ .index = 0, .len = 3 }, u8str.symbolAfter(0));
}

test "should return the next symbol after the index" {
    const alloc = std.testing.allocator;
    const u8str = try String.initParse(alloc, "ⒶⒷ");
    defer u8str.deinit();
    try std.testing.expectEqual(Symbol{ .index = 3, .len = 3 }, u8str.symbolAfter(1));
}

test "symbols count" {
    const alloc = std.testing.allocator;
    const u8str = try String.initParse(alloc, "ⒶⒷⒸ");
    defer u8str.deinit();
    try std.testing.expectEqual(3, u8str.symbolsCount());
}

test "should not count escape symbols" {
    const alloc = std.testing.allocator;
    const u8str = try String.initParse(alloc, "ⒶⒷⒸ\x1bⒹ");
    defer u8str.deinit();
    try std.testing.expectEqual(4, u8str.symbolsCount());
}

test "the 3 symbol should have index 10" {
    const alloc = std.testing.allocator;
    const u8str = try String.initParse(alloc, "ⒶⒷⒸ\x1bⒹ");
    defer u8str.deinit();
    try std.testing.expectEqual(10, u8str.indexOfSymbol(3));
}

test "merge in the middle" {
    // given:
    var str1 = try String.initParse(std.testing.allocator, ".......");
    defer str1.deinit();
    var str2 = try String.initParse(std.testing.allocator, "***");
    defer str2.deinit();

    // when:
    try str1.merge(str2, 2);

    // then:
    try std.testing.expectEqualStrings("..***..", str1.bytes.items);
}

test "merge to short string" {
    // given:
    var str1 = try String.initParse(std.testing.allocator, "");
    defer str1.deinit();
    var str2 = try String.initParse(std.testing.allocator, "***");
    defer str2.deinit();

    // when:
    try str1.merge(str2, 2);

    // then:
    try std.testing.expectEqualStrings("  ***", str1.bytes.items);
}

test "set symbol at existed char" {
    // given:
    const alloc = std.testing.allocator;
    var u8str = try String.initParse(alloc, "123");
    defer u8str.deinit();
    // when:
    try u8str.set(1, 'Ⓐ');
    // then:
    try std.testing.expectEqualStrings("1Ⓐ3", u8str.bytes.items);
}

test "set symbol at existed utf8 symbol" {
    // given:
    const alloc = std.testing.allocator;
    var u8str = try String.initParse(alloc, "1Ⓑ3");
    defer u8str.deinit();
    // when:
    try u8str.set(1, 'Ⓐ');
    // then:
    try std.testing.expectEqualStrings("1Ⓐ3", u8str.bytes.items);
}

test "set symbol at the end of the string" {
    // given:
    const alloc = std.testing.allocator;
    var u8str = try String.initParse(alloc, "123");
    defer u8str.deinit();
    // when:
    try u8str.set(5, 'Ⓐ');
    // then:
    try std.testing.expectEqualStrings("123  Ⓐ", u8str.bytes.items);
}
