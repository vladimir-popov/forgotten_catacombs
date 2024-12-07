const std = @import("std");

/// Iterates over args, and looking for the '--{name}' argument. If the arg with the {name} is found,
/// returns true, or false otherwise.
pub fn key(comptime name: []const u8) bool {
    var args = std.process.args();
    while (args.next()) |arg| {
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-' and std.mem.eql(u8, arg[2..], name)) {
            return true;
        }
    }
    return false;
}

/// Iterates over args, and looking for the '--{name}=<value>' argument. If the arg with the {name} is found,
/// it takes the string after the '=' as the value.
/// Note, that spaces around the '=' are not expected.
pub fn str(name: []const u8) ?[]const u8 {
    var args = std.process.args();
    while (args.next()) |arg| {
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            var itr = std.mem.splitScalar(u8, arg[2..], '=');
            if (itr.next()) |arg_name| if (std.mem.eql(u8, arg_name, name)) if (itr.next()) |arg_value|
                return arg_value;
        }
    }
    return null;
}

/// Iterates over args, and looking for the '--{name}=<value>' argument. If the arg with the {name} is found,
/// it takes the string after the '=' as the value, parse it as a number, and returns result (including error).
/// Note, that spaces around the '=' are not expected.
pub fn int(comptime T: type, name: []const u8) !?T {
    if (str(name)) |arg_value| {
        return try std.fmt.parseInt(T, arg_value, 10);
    }
    return null;
}
