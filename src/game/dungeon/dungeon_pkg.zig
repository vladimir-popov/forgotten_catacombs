const placements = @import("placements.zig");

pub const Placement = placements.Placement;
pub const Doorway = placements.Doorway;
pub const Area = placements.Area;
pub const Room = placements.Room;
pub const Passage = placements.Passage;

pub const Dungeon = @import("Dungeon.zig");
pub const FirstLocation = @import("FirstLocation.zig");
pub const Cave = @import("Cave.zig").Cave;
pub const Catacomb = @import("Catacomb.zig");

pub const CatacombGenerator = @import("CatacombGenerator.zig");
pub const CavesGenerator = @import("CavesGenerator.zig").CavesGenerator;

pub const DungeonType = enum {
    first_location,
    cave,
    catacomb,

    pub fn accordingToDepth(depth: u8) DungeonType {
        return switch (depth) {
            0 => .first_location,
            1 => .cave,
            else => .catacomb,
        };
    }
};
