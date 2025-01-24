const std = @import("std");

pub const unknown = '�';
pub const nothing = ' ';
// pub const wall_visible = '#';
// pub const wall_known = '#';
// pub const wall_visible = '▓';
pub const wall_visible = '▒';
pub const wall_known = '░';
// pub const floor_visible = '.';
pub const floor_visible = '•';
pub const floor_known = '·';
pub const door_opened = '\'';
pub const door_closed = '+';
pub const ladder_up = '<';
pub const ladder_down = '>';
pub const rock = '#';
pub const walls = [_]u21{ '│', '┐', '┌', '─', '┘', '└', '├', '┤', '┬', '┴', '┼' };
pub const water = '~';
pub const human = '@';
pub const teleport = '_';
pub const variants = '⇧';

pub fn toArray(comptime codepoint: u21) [utf8CodepointSequenceLength(codepoint)]u8 {
    var buf: [utf8CodepointSequenceLength(codepoint)]u8 = undefined;
    _ = std.unicode.utf8Encode(codepoint, &buf) catch @panic("Wrong codepoint");
    return buf;
}

fn utf8CodepointSequenceLength(c: u21) u3 {
    if (c < 0x80) return @as(u3, 1);
    if (c < 0x800) return @as(u3, 2);
    if (c < 0x10000) return @as(u3, 3);
    if (c < 0x110000) return @as(u3, 4);
    return 0;
}

test toArray {
    try std.testing.expectEqual(variants, try std.unicode.utf8Decode(&toArray(variants)));
}
