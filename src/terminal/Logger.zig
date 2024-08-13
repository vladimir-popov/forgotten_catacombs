const std = @import("std");

pub var log_file: ?std.fs.File = null;

pub fn writeLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (log_file) |file| {
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        var wr = file.writer();
        wr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch {
            @panic("Error on write log");
        };
    } else {
        log_file = std.fs.cwd().createFile("game.log", .{ .read = false, .truncate = true }) catch {
            @panic("Error on open log file.");
        };
        writeLog(message_level, scope, format, args);
    }
}
