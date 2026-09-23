const std = @import("std");

const armor = @import("generate_armor.zig");
const descriptions = @import("generate_descriptions.zig");
const food = @import("generate_food.zig");
const names_enum = @import("generate_names_enum.zig");
const potions = @import("generate_potions.zig");
const weapons = @import("generate_weapons.zig");
const weights = @import("generate_weights.zig");

const max_csv_size = 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    defer stdout.interface.flush() catch {};

    const command = args.next() orelse {
        try writeUsage(&stdout.interface);
        return;
    };
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try writeUsage(&stdout.interface);
        return;
    }

    const csv_path = args.next() orelse return error.MissingCsvPath;
    const csv = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        csv_path,
        init.gpa,
        .limited(max_csv_size),
    );
    defer init.gpa.free(csv);

    if (args.next() != null)
        return error.UnexpectedArgument;

    if (std.mem.eql(u8, command, "armor")) {
        try armor.generate(csv, &stdout.interface, init.gpa);
    } else if (std.mem.eql(u8, command, "descriptions")) {
        try descriptions.generate(csv, &stdout.interface, init.gpa);
    } else if (std.mem.eql(u8, command, "food")) {
        try food.generate(csv, &stdout.interface, init.gpa);
    } else if (std.mem.eql(u8, command, "names-enum")) {
        try names_enum.generate(csv, &stdout.interface);
    } else if (std.mem.eql(u8, command, "potions")) {
        try potions.generate(csv, &stdout.interface, init.gpa);
    } else if (std.mem.eql(u8, command, "weapons")) {
        try weapons.generate(csv, &stdout.interface, init.gpa);
    } else if (std.mem.eql(u8, command, "weights")) {
        try weights.generate(csv, &stdout.interface);
    } else {
        return error.UnknownCommand;
    }
}

fn writeUsage(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "Usage: zig run misc/tools/main.zig -- <command> <csv-path>\n\n" ++
            "Commands:\n" ++
            "  armor         Generate armor entities\n" ++
            "  descriptions  Generate description presets\n" ++
            "  food          Generate food entities\n" ++
            "  names-enum    Generate enum values from names\n" ++
            "  potions       Generate potion entities\n" ++
            "  weapons       Generate weapon entities\n" ++
            "  weights       Generate random weight fields\n",
    );
}
