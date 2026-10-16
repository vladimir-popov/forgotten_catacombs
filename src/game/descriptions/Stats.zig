const std = @import("std");
const Description = @import("../Description.zig");

strength: Description = .{
    .name = "Strength",
    .description = &.{
        "A measure of a character's physical",
        "power.  It determines how hard they",
        "can  strike  and  how much they can",
        "lift, hold, or break. High strength",
        "helps deliver devastating blows and",
        "carry heavy equipment.",
    },
},

dexterity: Description = .{
    .name = "Dexterity",
    .description = &.{
        "A  measure of a character's agility",
        "and coordination. It reflects their",
        "ability to move precisely, quickly,",
        "and  reliably. Dexterity determines",
        "how   well  they  avoid  traps  and",
        "blows,   handle   tools,   and  mix",
        "potions without spilling a drop.",
    },
},

perception: Description = .{
    .name = "Perception",
    .description = &.{
        "A  measure of a character's ability",
        "to  notice  details and dangers. It",
        "determines  the  chance of spotting",
        "traps,  hidden items, or an enemy's",
        "incoming attack.",
    },
},

intelligence: Description = .{
    .name = "Intelligence",
    .description = &.{
        "A  measure  of a character's mental",
        "abilities. It determines how easily",
        "they   uncover   the   secrets   of",
        "unfamiliar     items,    understand",
        "mechanisms,  and  show  an aptitude",
        "for alchemy.",
    },
},

constitution: Description = .{
    .name = "Constitution",
    .description = &.{
        "A measure of a character's physical",
        "endurance.  It  determines how much",
        "hardship   and   injury   they  can",
        "withstand.   Constitution   affects",
        "maximum  health  and how quickly it",
        "increases when leveling up.",
    },
},
