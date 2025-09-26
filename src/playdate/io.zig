const std = @import("std");
const api = @import("api.zig");
const PlaydateRuntime = @import("PlaydateRuntime.zig");

const log = std.log.scoped(.playdate_io);

pub const FileWrapper = union(enum) {
    reader: FileReader,
    writer: FileWriter,

    pub fn sdfile(self: FileWrapper) *api.SDFile {
        return switch (self) {
            .reader => self.reader.file,
            .writer => self.writer.file,
        };
    }
};

pub const FileReader = struct {
    playdate: *api.PlaydateAPI,
    file: *api.SDFile,
    interface: std.Io.Reader,

    pub fn init(playdate: *api.PlaydateAPI, file: *api.SDFile, buffer: []u8) FileReader {
        return .{
            .playdate = playdate,
            .file = file,
            .interface = .{
                .buffer = buffer,
                .seek = 0,
                .end = 0,
                .vtable = &.{ .stream = FileReader.stream },
            },
        };
    }

    pub fn stream(io_r: *std.Io.Reader, io_w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *FileReader = @fieldParentPtr("interface", io_r);
        const buffer = limit.slice(try io_w.writableSliceGreedy(1));
        const len = self.playdate.file.read(self.file, buffer.ptr, @intCast(buffer.len));
        if (len < 0) {
            log.err("Error on reading from the file {any}: {s}", .{ self.file, self.playdate.file.geterr() });
            return error.ReadFailed;
        }
        io_w.advance(@intCast(len));
        return @intCast(len);
    }
};

pub const FileWriter = struct {
    playdate: *api.PlaydateAPI,
    file: *api.SDFile,
    interface: std.Io.Writer,

    pub fn init(playdate: *api.PlaydateAPI, file: *api.SDFile, buffer: []u8) FileWriter {
        return .{
            .playdate = playdate,
            .file = file,
            .interface = .{ .buffer = buffer, .vtable = &.{ .drain = drain } },
        };
    }

    pub fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *FileWriter = @fieldParentPtr("interface", io_w);
        defer {
            if (self.playdate.file.flush(self.file) < 0) {
                std.debug.panic("Error on flushing file {any}: {s}", .{ self.file, self.playdate.file.geterr() });
            }
        }

        // copied from:
        // https://github.com/ziglang/zig/blob/bc7955306e3480fc065277d0b6c5abb6797a27ae/lib/std/fs/File.zig#L1609
        const buffered = io_w.buffered();
        if (buffered.len != 0) {
            const len = self.playdate.file.write(self.file, buffered.ptr, @intCast(buffered.len));
            if (len < 0) {
                log.err("Error on writing to the file {any}: {s}", .{ self.file, self.playdate.file.geterr() });
                return error.WriteFailed;
            }
            return io_w.consume(@intCast(len));
        }
        for (data[0 .. data.len - 1]) |buf| {
            if (buf.len == 0) continue;
            const len = self.playdate.file.write(self.file, buf.ptr, @intCast(buf.len));
            if (len < 0) {
                log.err("Error on writing to the file {any}: {s}", .{ self.file, self.playdate.file.geterr() });
                return error.WriteFailed;
            }
            return io_w.consume(@intCast(len));
        }
        const pattern = data[data.len - 1];
        if (pattern.len == 0 or splat == 0) return 0;
        const len = self.playdate.file.write(self.file, pattern.ptr, @intCast(pattern.len));
        if (len < 0) {
            log.err("Error on writing to the file {any}: {s}", .{ self.file, self.playdate.file.geterr() });
            return error.WriteFailed;
        }
        return io_w.consume(@intCast(len));
    }
};
