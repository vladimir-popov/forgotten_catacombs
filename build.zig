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
    //                The main Game Module:
    // ============================================================

    const game_module = b.createModule(.{
        .root_source_file = b.path("src/game/game_pkg.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ============================================================
    //                     Terminal
    // ============================================================

    const terminal_module = b.createModule(.{
        .root_source_file = b.path("src/terminal/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_module.addImport("game", game_module);

    const terminal_game_exe = b.addExecutable(.{
        .name = target_name,
        .root_module = terminal_module,
    });
    terminal_game_exe.root_module.link_libc = true;
    b.installArtifact(terminal_game_exe);

    const run_game_step = b.step("run", "Run the Forgotten Catacombs in the terminal");
    const run_game_cmd = b.addRunArtifact(terminal_game_exe);
    if (b.args) |args| {
        run_game_cmd.addArgs(args);
    }
    run_game_step.dependOn(&run_game_cmd.step);

    // ============================================================
    //                      Playdate
    // ============================================================

    const playdate_target = b.resolveTargetQuery(try std.Target.Query.parse(.{
        .arch_os_abi = "thumb-freestanding-eabihf",
        .cpu_features = "cortex_m7+vfp4d16sp",
    }));

    const playdate_module = b.createModule(.{
        .root_source_file = b.path("src/playdate/main.zig"),
        .target = playdate_target,
        .optimize = .ReleaseFast,
        .pic = true,
        .single_threaded = true,
    });
    playdate_module.addImport("game", game_module);

    const writer = b.addWriteFiles();
    const source_dir = writer.getDirectory();
    writer.step.name = "write source directory";

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
    try addCopyDirectory(writer, b.graph.io, "assets", ".");

    // ------------------------------------------------------------
    //                Build pdex lib for emulator
    // ------------------------------------------------------------

    // TODO: build the lib for all possible host OS

    const playdate_em_module = b.createModule(.{
        .root_source_file = b.path("src/playdate/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "pdex",
        .linkage = .dynamic,
        .root_module = playdate_em_module,
    });
    lib.root_module.addImport("game", game_module);

    _ = writer.addCopyFile(lib.getEmittedBin(), "pdex" ++ switch (native_os_tag) {
        .windows => ".dll",
        .macos => ".dylib",
        .linux => ".so",
        else => @panic("Unsupported OS"),
    });

    // ------------------------------------------------------------
    //                Step to run on emulator
    // ------------------------------------------------------------
    if (std.process.hasEnvVarConstant(PLAYDATE_SDK_PATH)) {
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

    // ============================================================
    //                     Tests
    // ============================================================

    // ------------------------------------------------------------
    //                  Test scenarios
    // ------------------------------------------------------------

    const test_scenarios_module = b.createModule(.{
        .root_source_file = b.path("src/test_scenarios/test_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_scenarios_module.addImport("game", game_module);
    test_scenarios_module.addImport("terminal", terminal_module);
    // a library created to take part in the `check` step later
    const test_scenarios_lib = b.addLibrary(.{
        .name = target_name,
        .root_module = test_scenarios_module,
    });
    // ------------------------------------------------------------

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&terminal_game_exe.step);

    const test_filter = b.option(
        []const []const u8,
        "only",
        "Skip tests that do not match the filter:\n" ++
            "                               `-Donly=<part of the test name>`",
    ) orelse &[0][]const u8{};

    const test_runner = std.Build.Step.Compile.TestRunner{
        .path = b.path("zrunner.zig"),
        .mode = .simple,
    };

    const modules_with_tests = [_]struct { []const u8, *std.Build.Module }{
        .{ "game_tests", game_module },
        .{ "terminal_tests", terminal_module },
        // playdate_module, <- do not compiled with host OS as a target
        .{ "test_scenarios", test_scenarios_module },
    };
    for (modules_with_tests) |module| {
        const tests = b.addTest(.{
            .name = module[0],
            .root_module = module[1],
            .test_runner = test_runner,
            .filters = test_filter,
        });
        b.installArtifact(tests);

        const tests_exe = b.addRunArtifact(tests);
        tests_exe.has_side_effects = true;
        test_step.dependOn(&tests_exe.step);
        if (b.args) |args| {
            tests_exe.addArgs(args);
        }
    }

    // ============================================================
    //                Step to check by zls
    // ============================================================
    const check = b.step("check", "Verify code by zls on save");
    check.dependOn(&terminal_game_exe.step);
    check.dependOn(&test_scenarios_lib.step);
    check.dependOn(&elf.step);
}

fn addCopyDirectory(
    wf: *std.Build.Step.WriteFile,
    io: std.Io,
    src_path: []const u8,
    dest_path: []const u8,
) !void {
    const b = wf.step.owner;
    var dir = try b.build_root.handle.openDir(io, src_path, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        const new_src_path = b.pathJoin(&.{ src_path, entry.name });
        const new_dest_path = b.pathJoin(&.{ dest_path, entry.name });
        const new_src = b.path(new_src_path);
        switch (entry.kind) {
            .file => {
                _ = wf.addCopyFile(new_src, new_dest_path);
            },
            .directory => {
                try addCopyDirectory(wf, io, new_src_path, new_dest_path);
            },
            //TODO: possible support for sym links?
            else => {},
        }
    }
}
