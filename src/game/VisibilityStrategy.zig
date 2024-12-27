//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;

pub const Visibility = enum { visible, known, invisible };

const VisibilityStrategy = @This();

context: *const anyopaque,
/// Custom function to decide should the place be drawn or not.
checkVisibilityFn: *const fn (context: *const anyopaque, level: *const g.Level, place: p.Point) Visibility,

pub inline fn checkVisibility(self: VisibilityStrategy, level: *const g.Level, place: p.Point) Visibility {
    return self.checkVisibilityFn(self.context, level, place);
}

//
// Different strategies
//

// Used by the DungeonGenerator program
pub fn showWholeDungeon() VisibilityStrategy {
    return .{ .context = undefined, .checkVisibilityFn = visibleWholeDungeon };
}

fn visibleWholeDungeon(_: *const anyopaque, level: *const g.Level, place: p.Point) g.Visibility {
    return if (level.dungeon.rows < place.row or level.dungeon.cols < place.col) .invisible else .visible;
}

/// This is strategy for the Render only
pub fn delegateToLevel() g.VisibilityStrategy {
    return .{ .context = undefined, .checkVisibilityFn = checkVisibilityOnLevel };
}

fn checkVisibilityOnLevel(_: *const anyopaque, level: *const g.Level, place: p.Point) g.Visibility {
    return level.visibility_strategy.checkVisibility(level, place);
}

/// Marks as visible the whole placement and optionally its nearest neighbors
pub fn visibleWholePlacements() VisibilityStrategy {
    return .{ .context = undefined, .checkVisibilityFn = checkVisibilityInPlacement };
}

fn checkVisibilityInPlacement(_: *const anyopaque, level: *const g.Level, place: p.Point) Visibility {
    if (level.player_placement.contains(place)) return .visible;

    // check visibility of the nearest placement if the player is in the doorway:
    const player_position = level.playerPosition().point;
    var doorways = level.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (!door_place.eql(player_position)) continue;
        if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
            if (doorway.oppositePlacement(level.player_placement)) |placement| {
                if (placement.contains(place)) return .visible;
            }
        }
    }

    return chechKnownPlaces(level, place);
}

/// This strategy checks the distance between player and checked visible place
/// additionally to the underlying strategy. If the visible place far away from
/// the player, it marks as invisible (or known).
pub const VisibleCirle = struct {
    underlying: VisibilityStrategy,
    radius: f16,

    pub fn strategy(self: *const VisibleCirle) VisibilityStrategy {
        return .{ .context = self, .checkVisibilityFn = checkVisibilityInCircle };
    }

    fn checkVisibilityInCircle(ptr: *const anyopaque, level: *const g.Level, place: p.Point) Visibility {
        const self: *const VisibleCirle = @ptrCast(@alignCast(ptr));
        const underlying_result = self.underlying.checkVisibility(level, place);
        if (level.playerPosition().point.distanceTo(place) > self.radius) {
            return chechKnownPlaces(level, place);
        } else {
            return underlying_result;
        }
    }
};

/// Checks known places, to mark invisible, but previously visited places as known.
fn chechKnownPlaces(level: *const g.Level, place: p.Point) Visibility {
    if (level.map.isVisited(place)) {
        switch (level.player_placement) {
            // mark invisible everything inside the inner rooms
            .area => |area| if (area.isInsideInnerRoom(place)) return .invisible,
            .room => |room| if (room.host_area) |area| if (area.isInsideInnerRoom(place)) return .invisible,
            else => {},
        }
        return .known;
    }
    return .invisible;
}
