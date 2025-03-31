// This build file uses code from the:
// https://github.com/DanB91/Zig-Playdate-Template

const std = @import("std");

const builtin = @import("builtin");
const native_os_tag = builtin.os.tag;
const native_cpu_arch = builtin.cpu.arch;
const name = "forgotten_catacombs";
const pdx_file_name = name ++ ".pdx";
const PLAYDATE_SDK_PATH = "PLAYDATE_SDK_PATH";

pub fn build(b: *std.Build) !void {

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const target_name = if (target.query.cpu_arch) |target_cpu|
        if (target.query.os_tag) |target_os|
            try std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}", .{
                name,
                @tagName(target_os),
                @tagName(target_cpu),
            })
        else
            try std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}", .{
                name,
                @tagName(native_os_tag),
                @tagName(target_cpu),
            })
    else
        try std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}", .{
            name,
            @tagName(native_os_tag),
            @tagName(native_cpu_arch),
        });

    // ============================================================
    //                    Modules:
    // ============================================================

    const game_module = b.createModule(.{
        .root_source_file = b.path("src/game/game_pkg.zig"),
        .target = target,
        .optimize = optimize,
    });

    const terminal_module = b.createModule(.{
        .root_source_file = b.path("src/terminal/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_module.addImport("game", game_module);

    const dungeon_generator_module = b.createModule(.{
        .root_source_file = b.path("src/terminal/DungeonsGenerator.zig"),
        .target = target,
        .optimize = optimize,
    });
    dungeon_generator_module.addImport("game", game_module);

    const playdate_module = b.createModule(.{
        .root_source_file = b.path("src/playdate/main.zig"),
        .target = b.resolveTargetQuery(try std.Target.Query.parse(.{
            .arch_os_abi = "thumb-freestanding-eabihf",
            .cpu_features = "cortex_m7+vfp4d16sp",
        })),
        .optimize = .ReleaseFast,
        .pic = true,
    });
    playdate_module.addImport("game", game_module);

    // ============================================================
    //                   Desktop files
    // ============================================================

    // ------------------------------------------------------------
    //                  Forgotten Catacomb Game
    // ------------------------------------------------------------

    const terminal_game_exe = b.addExecutable(.{
        .name = target_name,
        .root_module = terminal_module,
        .link_libc = true,
    });
    b.installArtifact(terminal_game_exe);

    const run_game_step = b.step("run", "Run the Forgotten Catacombs in the terminal");
    const run_game_cmd = b.addRunArtifact(terminal_game_exe);
    if (b.args) |args| {
        run_game_cmd.addArgs(args);
    }
    run_game_step.dependOn(&run_game_cmd.step);

    // ------------------------------------------------------------
    //                   Dungeons generator
    // ------------------------------------------------------------
    const dungeons_exe = b.addExecutable(.{
        .name = "dungeons-generator",
        .root_module = dungeon_generator_module,
        .link_libc = true,
    });
    b.installArtifact(dungeons_exe);

    // Step to build and run the game in terminal
    const run_generator_cmd = b.addRunArtifact(dungeons_exe);
    if (b.args) |args| {
        run_generator_cmd.addArgs(args);
    }
    const run_generator_step = b.step("generate", "Run the dungeons generator in the terminal");
    run_generator_step.dependOn(&run_generator_cmd.step);

    // ============================================================
    //                Step to run tests
    // ============================================================

    const test_filter = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};

    const test_runner = std.Build.Step.Compile.TestRunner{
        .path = b.path("src/test_runner.zig"),
        .mode = .simple,
    };

    const game_tests = b.addTest(.{
        .root_module = game_module,
        .test_runner = test_runner,
        .filters = test_filter,
    });
    b.installArtifact(game_tests);
    const run_game_tests = b.addRunArtifact(game_tests);

    const terminal_tests = b.addTest(.{
        .root_module = terminal_module,
        .test_runner = test_runner,
        .filters = test_filter,
    });
    b.installArtifact(terminal_tests);
    const run_terminal_tests = b.addRunArtifact(terminal_tests);

    const generator_tests = b.addTest(.{
        .root_module = dungeon_generator_module,
        .test_runner = test_runner,
        .filters = test_filter,
    });
    b.installArtifact(generator_tests);
    const run_generator_tests = b.addRunArtifact(generator_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    if (b.args) |args| {
        run_game_tests.addArgs(args);
        run_terminal_tests.addArgs(args);
        run_generator_tests.addArgs(args);
    }
    // run_terminal_tests.has_side_effects = true;
    // run_generator_tests.has_side_effects = true;

    test_step.dependOn(&run_game_tests.step);
    test_step.dependOn(&run_terminal_tests.step);
    test_step.dependOn(&run_generator_tests.step);

    // ============================================================
    //                Step to check by zls
    // ============================================================
    const check_game = b.addSharedLibrary(.{
        .name = "check game",
        .root_module = game_module,
    });
    const check_terminal = b.addExecutable(.{
        .name = "check terminal",
        .root_module = terminal_module,
    });
    const check_generator = b.addExecutable(.{
        .name = "check generator",
        .root_module = dungeon_generator_module,
    });
    const check_playdate = b.addExecutable(.{
        .name = "check playdate",
        .root_module = playdate_module,
    });
    const check = b.step("check", "Verify code by zls on save");
    check.dependOn(&check_game.step);
    check.dependOn(&check_terminal.step);
    check.dependOn(&check_generator.step);
    check.dependOn(&check_playdate.step);

    // ============================================================
    //                   Playdate files
    // ============================================================

    const writer = b.addWriteFiles();
    const source_dir = writer.getDirectory();
    writer.step.name = "write source directory";

    const lib = b.addSharedLibrary(.{
        .name = "pdex",
        .root_source_file = b.path("src/playdate/main.zig"),
        .optimize = .ReleaseFast,
        .target = b.graph.host,
    });
    lib.root_module.addImport("game", game_module);
    _ = writer.addCopyFile(lib.getEmittedBin(), "pdex" ++ switch (native_os_tag) {
        .windows => ".dll",
        .macos => ".dylib",
        .linux => ".so",
        else => @panic("Unsupported OS"),
    });

    const elf = b.addExecutable(.{
        .name = "pdex.elf",
        .root_module = playdate_module,
    });
    elf.link_emit_relocs = true;
    elf.entry = .{ .symbol_name = "eventHandler" };

    elf.setLinkerScript(b.path("link_map.ld"));
    elf.root_module.omit_frame_pointer = true;
    _ = writer.addCopyFile(elf.getEmittedBin(), "pdex.elf");

    // copy resources:
    try addCopyDirectory(writer, "assets", ".");

    // ------------------------------------------------------------
    //                Step to run in emulator
    // ------------------------------------------------------------
    if (!std.process.hasEnvVarConstant(PLAYDATE_SDK_PATH)) {
        std.debug.print("Playdate SDK was not found. The {s} is absent", .{PLAYDATE_SDK_PATH});
        return;
    }
    const playdate_sdk_path = try std.process.getEnvVarOwned(b.allocator, PLAYDATE_SDK_PATH);

    const pdc_path = b.pathJoin(&.{ playdate_sdk_path, "bin", if (native_os_tag == .windows) "pdc.exe" else "pdc" });
    const pd_simulator_path = switch (native_os_tag) {
        .linux => b.pathJoin(&.{ playdate_sdk_path, "bin", "PlaydateSimulator" }),
        .macos => "open", // `open` focuses the window, while running the simulator directry doesn't.
        .windows => b.pathJoin(&.{ playdate_sdk_path, "bin", "PlaydateSimulator.exe" }),
        else => @panic("Unsupported OS"),
    };

    const pdc = b.addSystemCommand(&.{pdc_path});
    pdc.addDirectoryArg(source_dir);
    pdc.setName("pdc");
    const pdx_path = pdc.addOutputFileArg(pdx_file_name);

    b.installDirectory(.{
        .source_dir = pdx_path,
        .install_dir = .prefix,
        .install_subdir = pdx_file_name,
    });
    b.installDirectory(.{
        .source_dir = source_dir,
        .install_dir = .prefix,
        .install_subdir = "pdx_source_dir",
    });

    const emulate_cmd = b.addSystemCommand(&.{pd_simulator_path});
    emulate_cmd.addDirectoryArg(pdx_path);
    emulate_cmd.setName("PlaydateSimulator");

    const emulate_step = b.step("emulate", "Run the Forgotten Catacomb in the Playdate Simulator");
    emulate_step.dependOn(&emulate_cmd.step);
    emulate_step.dependOn(b.getInstallStep());
}

fn addCopyDirectory(
    wf: *std.Build.Step.WriteFile,
    src_path: []const u8,
    dest_path: []const u8,
) !void {
    const b = wf.step.owner;
    var dir = try b.build_root.handle.openDir(
        src_path,
        .{ .iterate = true },
    );
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const new_src_path = b.pathJoin(&.{ src_path, entry.name });
        const new_dest_path = b.pathJoin(&.{ dest_path, entry.name });
        const new_src = b.path(new_src_path);
        switch (entry.kind) {
            .file => {
                _ = wf.addCopyFile(new_src, new_dest_path);
            },
            .directory => {
                try addCopyDirectory(
                    wf,
                    new_src_path,
                    new_dest_path,
                );
            },
            //TODO: possible support for sym links?
            else => {},
        }
    }
}
