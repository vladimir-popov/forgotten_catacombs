const std = @import("std");
const g = @import("game");
const w = g.windows;
const Options = @import("Options.zig");
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,
modal_windows: *w.ModalWindows,

pub fn asOptions(self: Self) !Options {
    return if (self.modal_windows.topWindow()) |window|
        .{
            .test_session = self.test_session,
            .options_area = @ptrCast(@alignCast(window.scrollable_area.content.underlying)),
        }
    else
        error.NoModalWindow;
}
