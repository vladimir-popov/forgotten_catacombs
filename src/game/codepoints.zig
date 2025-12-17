//! Codepoints for the special
const std = @import("std");

pub const armor = ']';
pub const armor_unknown = '[';
pub const container_opened = '=';
pub const container_locked = '≠';
pub const door_closed = '+';
pub const door_locked = '±';
pub const door_opened = '\'';
pub const floor_known = '·';
pub const floor_visible = '•';
pub const food = '%';
pub const human = '@';
pub const ladder_down = '>';
pub const ladder_up = '<';
pub const nothing = ' ';
pub const noise = '♪';
pub const pile = '=';
pub const potion = '¿';
pub const ranged_weapon = '}';
pub const ranged_weapon_unknown = '{';
pub const rock = '#';
pub const source_of_light = '¡';
pub const teleport = '_';
pub const unknown = '�';
pub const variants = '⇧';
pub const wall_known = '░';
pub const wall_visible = '▒';
pub const walls = [_]u21{ '│', '┐', '┌', '─', '┘', '└', '├', '┤', '┬', '┴', '┼' };
pub const water = '~';
pub const weapon_melee = '/';
pub const weapon_melee_unknown = '\\';

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
