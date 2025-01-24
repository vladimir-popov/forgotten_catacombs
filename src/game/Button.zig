const g = @import("game_pkg.zig");
const p = g.primitives;

const Button = @This();

pub const GameButton = enum(u8) {
    left = (1 << 0),
    right = (1 << 1),
    up = (1 << 2),
    down = (1 << 3),
    b = (1 << 4),
    a = (1 << 5),

    pub fn fromCode(code: c_int) ?GameButton {
        return switch (code) {
            1 => .left,
            2 => .right,
            4 => .up,
            8 => .down,
            16 => .b,
            32 => .a,
            else => null,
        };
    }

    pub inline fn isMove(self: GameButton) bool {
        return switch (self) {
            .left, .up, .right, .down => true,
            else => false,
        };
    }
};
pub const State = enum {
    /// For the playdate it means that the button was released;
    /// For terminal it means that some keyboard button code was read.
    released,
    /// For the playdate it means that the button is hold right now;
    /// For terminal it means that some keyboard button was pressed with Shift.
    hold,
};

game_button: GameButton,
state: State,

pub inline fn isMove(self: Button) bool {
    return self.game_button.isMove();
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
