//! This is metadata which is used to generate the dungeon
//! and its map.
const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

pub const Passage = @import("Passage.zig");

pub const Room = p.Region;

/// The list of the dungeon's rooms. Usually, the first room in the list has entrance to the dungeon,
/// and the last has exit.
rooms: std.ArrayList(Room),
/// Passages connect rooms and other passages.
/// The first tunnel begins from the door, and the last one doesn't have the end.
passages: std.ArrayList(Passage),
/// The set of places where doors are inside the dungeon.
doors: std.AutoHashMap(p.Point, void),
