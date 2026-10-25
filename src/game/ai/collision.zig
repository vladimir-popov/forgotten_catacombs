const g = @import("../game_pkg.zig");
const c = g.components;

pub const Collision = union(enum) {
    /// The target cell can be entered normally.
    nothing,
    /// A closed door occupies the target cell.
    door: struct { g.Entity, *const c.Door },
    /// Another enemy occupies the target cell.
    enemy: struct { g.Entity, g.Enemy },
    /// A trap occupies the target cell.
    trap: struct { g.Entity, *const c.Trap },
    /// The player occupies the target cell.
    player,
    /// The target cell cannot be entered.
    obstacle,
};
