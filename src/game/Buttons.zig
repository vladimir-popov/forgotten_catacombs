const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const Buttons = @This();

pub const Code = c_int;

// a button is pushed on release only
pub const State = enum { pushed, hold, double_pushed };

code: Code,
state: State,

pub const Left: Code = (1 << 0);
pub const Right: Code = (1 << 1);
pub const Up: Code = (1 << 2);
pub const Down: Code = (1 << 3);
pub const B: Code = (1 << 4);
pub const A: Code = (1 << 5);

pub inline fn isMove(btn: Code) bool {
    return (Up | Down | Left | Right) & btn > 0;
}

pub inline fn toDirection(btn: Buttons) ?p.Direction {
    return if (btn.code & Buttons.Up > 0)
        p.Direction.up
    else if (btn.code & Buttons.Down > 0)
        p.Direction.down
    else if (btn.code & Buttons.Left > 0)
        p.Direction.left
    else if (btn.code & Buttons.Right > 0)
        p.Direction.right
    else
        null;
}
