//! Its implementation depends on the Level.
//! The strategy of visibility also affects the strategy of marking visited places on the LevelMap.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;

pub const Visibility = enum { visible, known, invisible };

const VisibilityStrategy = @This();

context: *anyopaque,
/// Custom function to decide should the place be drawn or not.
isVisibleFn: *const fn (context: *anyopaque, level: *const g.Level, place: p.Point) Visibility,
/// Should mark the visited places with same logic that used for isVisibleFn
markVisitedPlacesFn: *const fn (
    context: *anyopaque,
    level: *g.Level,
    point_of_view: p.Point,
    placement: *const d.Placement,
) anyerror!void,

pub inline fn isVisible(self: VisibilityStrategy, level: *const g.Level, place: p.Point) Visibility {
    return self.isVisibleFn(self.context, level, place);
}

pub inline fn markVisitedPlaces(
    self: VisibilityStrategy,
    level: *g.Level,
    point_of_view: p.Point,
    placement: *const d.Placement,
) !void {
    try self.markVisitedPlacesFn(self.context, level, point_of_view, placement);
}

//
// Different strategies
//

// Used by the DungeonGenerator program
pub fn showAll() VisibilityStrategy {
    return .{ .context = undefined, .isVisibleFn = visibleAll, .markVisitedPlacesFn = markNothing };
}

fn visibleAll(_: *anyopaque, _: *const g.Level, _: p.Point) g.Visibility {
    return .visible;
}
fn markNothing(_: *anyopaque, _: *g.Level, _: p.Point, _: *const d.Placement) anyerror!void {}

/// This is strategy for the Render only
pub fn delegateToLevel() g.VisibilityStrategy {
    return .{ .context = undefined, .isVisibleFn = isVisibleFromLevel, .markVisitedPlacesFn = markVisibleOnLevel };
}

fn isVisibleFromLevel(_: *anyopaque, level: *const g.Level, place: p.Point) g.Visibility {
    return level.visibility_strategy.isVisible(level, place);
}

fn markVisibleOnLevel(_: *anyopaque, level: *g.Level, place: p.Point, placement: *const d.Placement) anyerror!void {
    try level.visibility_strategy.markVisitedPlaces(level, place, placement);
}

/// Marks as visible the whole placement and optionally its nearest neighbors
pub fn visibleWholePlacements() VisibilityStrategy {
    return .{ .context = undefined, .isVisibleFn = isVisibleInPlacements, .markVisitedPlacesFn = markVisitedPlacements };
}

fn isVisibleInPlacements(_: *anyopaque, level: *const g.Level, place: p.Point) Visibility {
    if (level.player_placement.contains(place))
        return .visible;

    var doorways = level.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
            // skip the neighbor if the door between is closed
            if (level.components.getForEntity(doorway.door_id, c.Door)) |door| {
                if (door.state == .closed) continue;
            } else {
                std.debug.panic(
                    \\Error on checking visibility of the {any}: 
                    \\Component Door was not found for the doorway.door_id {d} on the level {d}
                ,
                    .{ place, doorway.door_id, level.depth },
                );
            }

            if (doorway.oppositePlacement(level.player_placement)) |placement| {
                if (placement.contains(place))
                    return .visible;
            }
        }
    }
    if (level.map.isVisited(place))
        return .known;

    return .invisible;
}

fn markVisitedPlacements(
    _: *anyopaque,
    level: *g.Level,
    _: p.Point,
    placement: *const d.Placement,
) anyerror!void {
    try level.map.addVisitedPlacement(placement);
    var doorways = level.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (level.dungeon.doorwayAt(door_place.*)) |doorway| {
            if (level.components.getForEntity(doorway.door_id, c.Door)) |door| if (door.state == .opened)
                if (doorway.oppositePlacement(level.player_placement)) |pl| try level.map.addVisitedPlacement(pl);
        }
    }
}
