const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Saving a game session and go back to the main menu" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();

    test_session.session.switchModeToSavingSession();

    try std.testing.expectEqual(.inited, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.display.expectLooksLike(
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\             Saving   0%
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\                                        
    , .whole_display);
    try std.testing.expectEqual(.session_saved, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                     20%                
    , .{ .line = 6 });
    try std.testing.expectEqual(.level_seed_saved, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                     30%                
    , .{ .line = 6 });
    try std.testing.expectEqual(.entities_saved, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                     70%                
    , .{ .line = 6 });
    try std.testing.expectEqual(.visited_places_saved, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                     80%                
    , .{ .line = 6 });
    try std.testing.expectEqual(.remembered_objects_saved, test_session.session.mode.save_load.process.saving.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                     95%                
    , .{ .line = 6 });
    try std.testing.expectEqual(.completed, test_session.session.mode.save_load.process.saving.progress);
    // the error.GoToMainMenu is used to break the game session loop and go back to the main screen
    try std.testing.expectError(error.GoToMainMenu, test_session.tick());
}

test "Loading a game session" {
    const tmp_dir = std.testing.tmpDir(.{});
    const session_file = try tmp_dir.dir.createFile(g.persistance.SESSION_FILE_NAME, .{});
    _ = try session_file.write(@embedFile("resources/new_session.json"));

    var buf: [64]u8 = undefined;
    const level0_file = try tmp_dir.dir.createFile(try g.persistance.pathToLevelFile(&buf, 0), .{});
    _ = try level0_file.write(@embedFile("resources/level_0.json"));

    var test_session: TestSession = undefined;
    try test_session.load(std.testing.allocator, tmp_dir);
    defer test_session.deinit();

    try std.testing.expectEqual(.load_session, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.display.expectLooksLike(
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\             Loading   0%
        \\                                        
        \\                                        
        \\                                        
        \\                                        
        \\
        \\
    , .whole_display);
    try std.testing.expectEqual(.session_loaded, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                      10% 
    , .{ .line = 6 });
    try std.testing.expectEqual(.level_inited, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                      20% 
    , .{ .line = 6 });
    try std.testing.expectEqual(.entities_loaded, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                      70% 
    , .{ .line = 6 });
    try std.testing.expectEqual(.visited_places_loaded, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                      80% 
    , .{ .line = 6 });
    try std.testing.expectEqual(.remembered_objects_loaded, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try test_session.runtime.last_frame.expectLooksLike(
        \\                      90% 
    , .{ .line = 6 });
    try std.testing.expectEqual(.completed, test_session.session.mode.save_load.process.loading.progress);
    try test_session.tick();
    try std.testing.expect(test_session.session.mode == .play);
}
