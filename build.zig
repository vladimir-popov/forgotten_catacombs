// This build file uses code from the:
// https://github.com/DanB91/Zig-Playdate-Template

const std = @import("std");

const os_tag = @import("builtin").os.tag;
const name = "ForgottenCatacomb";
const pdx_file_name = name ++ ".pdx";

pub fn build(b: *std.Build) !void {
    const playdate_sdk_path = try std.process.getEnvVarOwned(b.allocator, "PLAYDATE_SDK_PATH");

    const writer = b.addWriteFiles();
    const source_dir = writer.getDirectory();
    writer.step.name = "write source directory";

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const desktop_target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================
    //                    Modules:
    // ============================================================

    const game_module = b.createModule(.{
        .root_source_file = b.path("src/game/game_pkg.zig"),
    });

    // ============================================================
    //                   Desktop files:
    // ============================================================

    // ------------------------------------------------------------
    //                  Forgotten Catacomb Game
    // ------------------------------------------------------------
    const terminal_game_exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/terminal/main.zig"),
        .target = desktop_target,
        .optimize = optimize,
    });
    terminal_game_exe.root_module.addImport("game", game_module);
    b.installArtifact(terminal_game_exe);

    // Step to build and run the game in terminal
    const run_game_cmd = b.addRunArtifact(terminal_game_exe);
    if (b.args) |args| {
        run_game_cmd.addArgs(args);
    }
    const run_game_step = b.step("run", "Run the Forgotten Catacomb in the terminal");
    run_game_step.dependOn(&run_game_cmd.step);

    // ------------------------------------------------------------
    //                   Dungeons generator
    // ------------------------------------------------------------
    const dungeons_exe = b.addExecutable(.{
        .name = "Dungeons generator",
        .root_source_file = b.path("src/terminal/DungeonsGenerator.zig"),
        .target = desktop_target,
        .optimize = optimize,
    });
    dungeons_exe.root_module.addImport("game", game_module);
    b.installArtifact(dungeons_exe);

    // Step to build and run the game in terminal
    const run_generator_cmd = b.addRunArtifact(dungeons_exe);
    if (b.args) |args| {
        run_generator_cmd.addArgs(args);
    }
    const run_generator_step = b.step("generate", "Run the dungeons generator in the terminal");
    run_generator_step.dependOn(&run_generator_cmd.step);

    // ============================================================
    //                   Playdate files:
    // ============================================================

    const lib = b.addSharedLibrary(.{
        .name = "pdex",
        .root_source_file = b.path("src/playdate/main.zig"),
        .optimize = optimize,
        .target = b.host,
    });
    lib.root_module.addImport("game", game_module);
    _ = writer.addCopyFile(lib.getEmittedBin(), "pdex" ++ switch (os_tag) {
        .windows => ".dll",
        .macos => ".dylib",
        .linux => ".so",
        else => @panic("Unsupported OS"),
    });

    const elf = b.addExecutable(.{
        .name = "pdex.elf",
        .root_source_file = b.path("src/playdate/main.zig"),
        .target = b.resolveTargetQuery(try std.Target.Query.parse(.{
            .arch_os_abi = "thumb-freestanding-eabihf",
            .cpu_features = "cortex_m7+vfp4d16sp",
        })),
        .optimize = optimize,
        .pic = true,
    });
    elf.root_module.addImport("game", game_module);
    elf.link_emit_relocs = true;
    elf.entry = .{ .symbol_name = "eventHandler" };

    elf.setLinkerScriptPath(b.path("link_map.ld"));
    if (optimize == .ReleaseFast) {
        elf.root_module.omit_frame_pointer = true;
    }
    _ = writer.addCopyFile(elf.getEmittedBin(), "pdex.elf");

    // copy resources:
    try addCopyDirectory(writer, "assets", ".");

    // ------------------------------------------------------------
    //                Step to run in emulator
    // ------------------------------------------------------------

    const pdc_path = b.pathJoin(&.{ playdate_sdk_path, "bin", if (os_tag == .windows) "pdc.exe" else "pdc" });
    const pd_simulator_path = switch (os_tag) {
        .linux => b.pathJoin(&.{ playdate_sdk_path, "bin", "PlaydateSimulator" }),
        .macos => "open", // `open` focuses the window, while running the simulator directry doesn't.
        .windows => b.pathJoin(&.{ playdate_sdk_path, "bin", "PlaydateSimulator.exe" }),
        else => @panic("Unsupported OS"),
    };

    const pdc = b.addSystemCommand(&.{pdc_path});
    pdc.addDirectorySourceArg(source_dir);
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
    emulate_cmd.addDirectorySourceArg(pdx_path);
    emulate_cmd.setName("PlaydateSimulator");

    const emulate_step = b.step("emulate", "Run the Forgotten Catacomb in the Playdate Simulator");
    emulate_step.dependOn(&emulate_cmd.step);
    emulate_step.dependOn(b.getInstallStep());

    // ------------------------------------------------------------
    //                Step to run tests
    // ------------------------------------------------------------

    const test_filter = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};

    const ut_game = b.addTest(.{
        .root_source_file = b.path("src/game/game_pkg.zig"),
        .test_runner = b.path("src/test_runner.zig"),
        .target = desktop_target,
        .optimize = optimize,
        .filters = test_filter,
    });
    const run_ut_game = b.addRunArtifact(ut_game);

    const ut_terminal = b.addTest(.{
        .root_source_file = b.path("src/terminal/main.zig"),
        .test_runner = b.path("src/test_runner.zig"),
        .target = desktop_target,
        .optimize = optimize,
        .filters = test_filter,
    });
    ut_terminal.root_module.addImport("game", game_module);

    b.installArtifact(ut_terminal);
    const run_ut_terminal = b.addRunArtifact(ut_terminal);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    if (b.args) |args| {
        run_ut_game.addArgs(args);
        run_ut_terminal.addArgs(args);
    }
    run_ut_game.has_side_effects = true;
    run_ut_terminal.has_side_effects = true;

    test_step.dependOn(&run_ut_game.step);
    test_step.dependOn(&run_ut_terminal.step);
}

pub fn addCopyDirectory(
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
