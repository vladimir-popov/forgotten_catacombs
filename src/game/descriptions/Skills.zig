const std = @import("std");
const Description = @import("../Description.zig");

pub const Enum = std.meta.FieldEnum(@This());

echo_of_knowledge: Description = .{
    .name = "Echo of knowledge",
    .description = &.{
        "This  is  more of an innate ability",
        "than an acquired skill. A character",
        "with  this  skill  has an intuitive",
        "understanding  of  the sciences and",
        "technologies of past civilizations,",
        "allowing them to understand and use",
        "their devices and artifacts.",
    },
},

mechanics: Description = .{
    .name = "Mechanics",
    .description = &.{
        "Knowledge   of  mechanics  helps  a",
        "character  pick  locks  and  disarm",
        "traps.",
    },
},

stealth: Description = .{
    .name = "Stealth",
    .description = &.{
        "The  ability  to  remain unnoticed,",
        "stay out of sight, and avoid waking",
        "the  sleeping  inhabitants  of  the",
        "dungeons.",
    },
},

weapon_mastery: Description = .{
    .name = "Weapon Mastery",
    .description = &.{
        "This  skill  helps  a character use",
        "any  weapon  more  effectively  and",
        "miss less often.",
    },
},
