const std = @import("std");
const api = @import("api.zig");
const g = @import("game");

const log = std.log.scoped(.last_button);

const HOLD_DELAY_MS = 400;
const REPEATE_DELAY_MS = 200;

const State = enum { pressed, released };

const LastButton = @This();

buttons: c_int = 0,
pressed_at: u64 = 0,
was_repeated: bool = false,
// dirty hack: playdate sends button events happened when the menu was opened
// right after closing menu. But we have to ignore that events.
is_menu_shown: bool = false,

pub const reset = LastButton{};

inline fn isReleased(self: LastButton) bool {
    return self.pressed_at == 0;
}

pub fn pop(self: *LastButton, now_ms: u64) ?g.Button {
    var button: ?g.Button = null;
    if (g.Button.GameButton.fromCode(self.buttons)) |game_button| {
        log.debug("Poping {any} at {d}", .{ self, now_ms });
        if (self.isReleased()) {
            // ignore release for repeated button
            if (self.was_repeated) {
                self.* = .reset;
                button = null;
            } else {
                self.* = .reset;
                button = .{ .game_button = game_button, .state = .released };
            }
        }
        // repeat for pressed arrows only
        else if (game_button.isMove() and now_ms - self.pressed_at > REPEATE_DELAY_MS) {
            self.pressed_at = now_ms;
            self.was_repeated = true;
            button = .{ .game_button = game_button, .state = .hold };
        }
        // the button is held
        else if (now_ms - self.pressed_at > HOLD_DELAY_MS) {
            self.* = .reset;
            button = .{ .game_button = game_button, .state = .hold };
        }
    }
    if (button) |btn| log.debug("Pop {any}", .{btn});
    return button;
}

/// The ButtonCallback handler.
///
/// This function is called for each button up/down event
/// (possibly multiple events on the same button) that occurred during
/// the previous update cycle. At the default 30 FPS, a queue size of 5
/// should be adequate. At lower frame rates/longer frame times, the
/// queue size should be extended until all button presses are caught.
///
/// See: https://sdk.play.date/2.6.2/Inside%20Playdate%20with%20C.html#f-system.setButtonCallback
///
pub fn handleEvent(
    buttons: api.PDButtons,
    down: c_int,
    when: u32,
    ptr: ?*anyopaque,
) callconv(.c) c_int {
    log.debug("Handle {d} buttons at {d} down {d}", .{ buttons, when, down });
    const self: *LastButton = @ptrCast(@alignCast(ptr));
    if (self.is_menu_shown) {
        self.* = .reset;
        return 0;
    }
    if (down > 0) {
        self.buttons = buttons;
        self.pressed_at = when;
        log.debug("Pressed {d} buttons at {d}. Last buttons {any}", .{ buttons, when, self.buttons });
    } else {
        self.pressed_at = 0;
    }
    return 0;
}
