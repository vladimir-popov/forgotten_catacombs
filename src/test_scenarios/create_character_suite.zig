const std = @import("std");
const g = @import("game");
const TestGame = @import("utils/TestGame.zig");

test "Create a new character" {
    var test_game: TestGame = undefined;
    try test_game.initNewCharacter(std.testing.allocator, std.testing.io);
    defer test_game.deinit();

    try test_game.runtime.display.expectLooksLike(
        \\         Choose your archetype:        ¶
        \\                                       ¶
        \\                                       ¶
        \\              Adventurer               ¶
        \\             Archeologist              ¶
        \\                Vandal                 ¶
        \\                Rogue                  ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\                     Describe   Choose¶¶
    , .whole_display);

    // Check a description:
    try test_game.pressButton(.b);
    try test_game.runtime.display.expectLooksLike(
        \\┌──────────────Adventurer──────────────┐
        \\│ You are  forever  in  search of new ▒│
        \\│ sensations. Your  main desire is to ░│
        \\│ test  your strength  and  feel  the ░│
        \\│ taste  of adventure.  You  have  no ░│
        \\│ pronounced talents,  but no serious ░│
        \\│ flaws   either.   Flexibility   and ░│
        \\│ curiosity  make   you  a  versatile ░│
        \\│ explorer     of     the   forgotten ░│
        \\└──────────────────────────────────────┘
        \\                                       ¶
        \\                                Close¶¶¶
    , .whole_display);
    // close description:
    try test_game.pressButton(.a);

    // Make a choice:
    try test_game.pressButton(.a);
    try test_game.runtime.display.expectLooksLike(
        \\      Distribute the stats points:     ¶
        \\                                       ¶
        \\                                       ¶
        \\ Strength                           0  ¶
        \\ Dexterity                          0  ¶
        \\ Perception                         0  ¶
        \\ Intelligence                       0  ¶
        \\ Constitution                       0  ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\  2 points remain      Back    Describe¶
    , .whole_display);

    // Check a description:
    try test_game.pressButton(.a);
    try test_game.runtime.display.expectLooksLike(
        \\┌───────────────Strength───────────────┐
        \\│ A measure of a character's physical  │
        \\│ power.  It determines how hard they  │
        \\│ can  strike  and  how much they can  │
        \\│ lift, hold, or break. High strength  │
        \\│ helps deliver devastating blows and  │
        \\│ carry heavy equipment.               │
        \\│                                      │
        \\│                                      │
        \\└──────────────────────────────────────┘
        \\                                       ¶
        \\  2 points remain      Back     Close  ¶
    , .whole_display);
    // close the window
    try test_game.pressButton(.a);

    // Distribute the stats points:
    try test_game.pressButton(.right);
    try test_game.pressButton(.down);
    try test_game.pressButton(.right);
    try test_game.runtime.display.expectLooksLike(
        \\      Distribute the stats points:     ¶
        \\                                       ¶
        \\                                       ¶
        \\ Strength                           1  ¶
        \\ Dexterity                          1  ¶
        \\ Perception                         0  ¶
        \\ Intelligence                       0  ¶
        \\ Constitution                       0  ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\  0 points remain      Back      Next  ¶
    , .whole_display);

    // Go to the skills step:
    try test_game.pressButton(.a);
    try test_game.runtime.display.expectLooksLike(
        \\      Distribute the skill points:     ¶
        \\                                       ¶
        \\                                       ¶
        \\ Echo of knowledge                  0  ¶
        \\ Mechanics                          0  ¶
        \\ Stealth                            0  ¶
        \\ Weapon Mastery                     0  ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\  2 points remain      Back    Describe¶
    , .whole_display);

    // Check a description:
    try test_game.pressButton(.a);
    try test_game.runtime.display.expectLooksLike(
        \\┌──────────Echo of knowledge───────────┐
        \\│ This  is  more of an innate ability  │
        \\│ than an acquired skill. A character  │
        \\│ with  this  skill  has an intuitive  │
        \\│ understanding  of  the sciences and  │
        \\│ technologies of past civilizations,  │
        \\│ allowing them to understand and use  │
        \\│ their devices and artifacts.         │
        \\│                                      │
        \\└──────────────────────────────────────┘
        \\                                       ¶
        \\  2 points remain      Back     Close  ¶
    , .whole_display);
    // close the window
    try test_game.pressButton(.a);

    // Distribute the skills points:
    try test_game.pressButton(.right);
    try test_game.pressButton(.right);
    try test_game.runtime.display.expectLooksLike(
        \\      Distribute the skill points:     ¶
        \\                                       ¶
        \\                                       ¶
        \\ Echo of knowledge                  2  ¶
        \\ Mechanics                          0  ¶
        \\ Stealth                            0  ¶
        \\ Weapon Mastery                     0  ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\                                       ¶
        \\  0 points remain      Back      Next  ¶
    , .whole_display);

    // Check characteristics:
    try test_game.pressButton(.a);
    try test_game.runtime.display.expectLooksLike(
        \\      Start with this character?       ¶
        \\                                       ¶
        \\  Level: 1                             ▒
        \\  Experience: 0/200                    ░
        \\                                       ░
        \\  Health: 33/33                        ░
        \\                                       ░
        \\  Skills:                              ░
        \\    Weapon Mastery:     0              ░
        \\    Mechanics:          0              ░
        \\                                       ¶
        \\                       Back      Play  ¶
    , .whole_display);
    for (0..8) |_| {
        try test_game.pressButton(.down);
    }
    try test_game.runtime.display.expectLooksLike(
        \\      Start with this character?       ¶
        \\                                       ¶
        \\    Stealth:            0              ░
        \\    Echo of knowledge:  2              ░
        \\                                       ░
        \\  Stats:                               ░
        \\    Strength:           1              ░
        \\    Dexterity:          1              ░
        \\    Perception:         0              ▒
        \\    Intelligence:       0              ░
        \\                                       ¶
        \\                       Back      Play  ¶
    , .whole_display);

    // Start the game:
    try test_game.pressButton(.a);
    // one extra tick to move the viewpoint
    try test_game.tick(.{});
    try test_game.runtime.display.expectLooksLike(
        \\######################################33
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘••••••••••••••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\                    ⇧Explore     Wait  ⇧
    , .whole_display);
}

test "A choice of the archetype should be persisted" {
    var test_game: TestGame = undefined;
    try test_game.initNewCharacter(std.testing.allocator, std.testing.io);
    defer test_game.deinit();

    // let's choose a predefined archetype to have non zero values
    try test_game.pressButton(.down);
    // next
    try test_game.pressButton(.a);
    // back
    try test_game.pressButton(.b);

    try std.testing.expectEqual(.archeologist, test_game.game.state.create_character.archetype);
}
