//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;

/// This global flag is used for cheating
pub var turn_light_on: bool = false;

/// Marks as visible the whole placement and optionally its nearest neighbors
pub fn showTheCurrentPlacement(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on or level.player_placement.contains(place)) return .visible;

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

/// This strategy checks the distance between the player and the checked place.
/// If the distance more than the radius of the player's source of light,
/// it marks that place as invisible (or known).
pub fn showInRadiusOfSourceOfLight(level: *const g.Level, place: p.Point) g.Render.Visibility {
    if (turn_light_on) return .visible;

    const radius = if (level.components.getForEntity(level.player, c.SourceOfLight)) |sol|
        sol.radius
    else
        2.0;

    if (level.playerPosition().point.distanceTo(place) > radius) {
        return chechKnownPlaces(level, place);
    } else {
        return .visible;
    }
}

/// Checks known places, to mark invisible, but previously visited places as known.
fn chechKnownPlaces(level: *const g.Level, place: p.Point) g.Render.Visibility {
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
