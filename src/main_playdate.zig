const std = @import("std");
const pdapi = @import("playdate/pd_api.zig");

const GlobalState = struct {
    playdate: *pdapi.PlaydateAPI,
};

pub export fn eventHandler(playdate: *pdapi.PlaydateAPI, event: pdapi.PDSystemEvent, arg: u32) callconv(.C) c_int {
    _ = arg;
    switch (event) {
        .EventInit => {
            const global_state: *GlobalState =
                @ptrCast(
                @alignCast(
                    playdate.system.realloc(
                        null,
                        @sizeOf(GlobalState),
                    ),
                ),
            );
            global_state.* = .{
                .playdate = playdate,
            };

            const font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", null).?;
            playdate.graphics.setFont(font);

            const to_draw =
                \\123456789012345678901234567890   
                \\2   #########
                \\3   #.......#
                \\4   #....^..#
                \\5   #..@....#
                \\6   ###'#####
                \\7     # #
                \\8     # ######
                \\9     %      #
                \\0     ###### #
                \\1          # #
                \\2          # #
                \\3          # #
                \\4          # #
                \\5          # #
                \\6          # #
                \\7          # #
                \\8          # #
            ;

            playdate.graphics.clear(@intFromEnum(pdapi.LCDSolidColor.ColorBlack));
            playdate.graphics.setDrawMode(pdapi.LCDBitmapDrawMode.DrawModeFillWhite);
            const pixel_width = playdate.graphics.drawText(to_draw, to_draw.len, .UTF8Encoding, 0, 0);
            _ = pixel_width;

            playdate.system.setUpdateCallback(update_and_render, global_state);
        },
        else => {},
    }
    return 0;
}

fn update_and_render(userdata: ?*anyopaque) callconv(.C) c_int {
    const global_state: *GlobalState = @ptrCast(@alignCast(userdata.?));
    _ = global_state;

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
