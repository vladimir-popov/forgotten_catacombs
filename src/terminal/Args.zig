const std = @import("std");

pub fn key(comptime name: []const u8) ?[]const u8 {
    var args = std.process.args();
    while (args.next()) |arg| {
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-' and std.mem.eql(u8, arg[2..], name)) {
            return name;
        }
    }
    return null;
}

/// Iterates over args, and looking for '--{name}'. If the arg with the {name} is found,
/// takes the string after the '=' as the value, parse it as a number, and returns result.
pub fn int(comptime T: type, name: []const u8) !?T {
    var args = std.process.args();
    while (args.next()) |arg| {
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            var itr = std.mem.splitScalar(u8, arg[2..], '=');
            if (itr.next()) |arg_name| if (std.mem.eql(u8, arg_name, name)) if (itr.next()) |arg_value|
                return try std.fmt.parseInt(T, arg_value, 10);
        }
    }
    return null;
}
