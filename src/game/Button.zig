const g = @import("game_pkg.zig");
const p = g.primitives;

const Button = @This();

pub const GameButton = enum(u8) {
    cheat = 0,
    left = (1 << 0),
    right = (1 << 1),
    up = (1 << 2),
    down = (1 << 3),
    b = (1 << 4),
    a = (1 << 5),

    pub fn fromCode(code: c_int) ?GameButton {
        return switch (code) {
            0 => .cheat,
            1 => .left,
            2 => .right,
            4 => .up,
            8 => .down,
            16 => .b,
            32 => .a,
            else => null,
        };
    }
};
pub const State = enum { pressed, double_pressed, hold, released };

game_button: GameButton,
state: State,

pub inline fn isMove(btn: Button) bool {
    return switch (btn.game_button) {
        .cheat, .a, .b => false,
        else => true,
    };
}

pub inline fn toDirection(btn: Button) ?p.Direction {
    return switch (btn.game_button) {
        .up => p.Direction.up,
        .down => p.Direction.down,
        .left => p.Direction.left,
        .right => p.Direction.right,
        else => null,
    };
}
