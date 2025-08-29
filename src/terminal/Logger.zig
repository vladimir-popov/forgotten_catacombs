const std = @import("std");

var buffer: [128]u8 = undefined;
var log_writer: ?std.fs.File.Writer = null;

pub fn writeLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (log_writer) |*writer| {
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        writer.interface.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch {
            @panic("Error on write log");
        };
        writer.interface.flush() catch {
            @panic("Error on flushing log buffer");
        };
    } else {
        const file = std.fs.cwd().createFile("game.log", .{ .read = false, .truncate = true }) catch {
            @panic("Error on open log file.");
        };
        log_writer = file.writer(&buffer);
        writeLog(message_level, scope, format, args);
    }
}
