const std = @import("std");
const g = @import("game");
const p = g.primitives;
const w = g.windows;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,
compositor: *w.WindowCompositor,

pub fn options(self: Self, comptime Item: type) Options {
    return .{
        .options_area = self.compositor.topModalWindowArea(w.OptionsArea(Item)).?,
        .test_session = self.test_session,
    };
}
