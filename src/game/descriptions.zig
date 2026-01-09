//! A full set of descriptions for all entities in the game.
//!
//! It also used as a tricky system of meta types.
//! Because of all entities must have a description, the easies way
//! to get a type for some entity is match its description `preset`
//! to a more precise enum that represents a type of the entity.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Description = struct {
    /// A short name of the entity.
    name: []const u8,

    // A line should have no more 36 symbols

    /// A short description of the entity.
    description: []const []const u8 = &.{},
};

pub const Archetypes = struct {
    pub const Enum = std.meta.FieldEnum(Archetypes);

    adventurer: Description = .{
        .name = "Adventurer",
        .description = &.{
            "You are  forever  in  search of new",
            "sensations. Your  main desire is to",
            "test  your strength  and  feel  the",
            "taste  of adventure.  You  have  no",
            "pronounced talents,  but no serious",
            "flaws   either.   Flexibility   and",
            "curiosity  make   you  a  versatile",
            "explorer     of     the   forgotten",
            "catacombs.",
        },
    },
    archeologist: Description = .{
        .name = "Archeologist",
        .description = &.{
            "You live for  discoveries.  Nothing",
            "holds more value for  you than lost",
            "knowledge  and  the  secrets of the",
            "past. Every new find is your reward",
            "and for  it,  you are ready to take",
            "risks others avoid.  Your  physical",
            "condition leaves much to be desired",
            "movements are clumsy, but your mind",
            "is  sharp  and  your heart knows no",
            "fear.  Who  knows  -  perhaps  your",
            "knowledge and curiosity will become",
            "the  key  to  the  secrets  of  the",
            "forgotten catacombs.",
        },
    },
    vandal: Description = .{
        .name = "Vandal",
        .description = &.{
            "You  are  a   straightforward   and",
            "simple    person.   Philosophy   or",
            "science  do  not interest you; only",
            "the thirst  for  profit drives you.",
            "You stop  at  nothing  for wealth -",
            "destruction, fighting, or risk  are",
            "merely tools  to achieve your goal.",
            "Your strength  and  endurance allow",
            "you to  survive where others break,",
            "and your physical power makes you a",
            "dangerous opponent in close combat.",
        },
    },
    rogue: Description = .{
        .name = "Rogue",
        .description = &.{
            "You are agile and cunning.Dexterity",
            "matters more to you than  strength.",
            "Direct  confrontations are not your",
            "way:  why  take  risks when you can",
            "quietly take what you need? Legends",
            "of forgotten artifacts of the  past",
            "lure you with the promise of wealth",
            "Every lock, every trap is merely an",
            "obstacle on your path to your goal:",
            "to  become   the   owner   of  lost",
            "technologies that will sustain  you",
            "for the rest of your life.",
        },
    },
};

pub const Skills = struct {
    pub const Enum = std.meta.FieldEnum(Skills);
    weapon_mastery: Description = .{
        .name = "Weapon Mastery",
        .description = &.{
            "Possessing this skill  allows  you",
            "to use any weapon more effectively",
            "and miss less often.",
        },
    },
    mechanics: Description = .{
        .name = "Mechanics",
        .description = &.{
            "Knowledge in the field of mechanics",
            "helps  you  pick  locks  and disarm",
            "traps.",
        },
    },
    stealth: Description = .{
        .name = "Stealth",
        .description = &.{
            "Stealth  is the ability  to  remain",
            "unseen — to stay out  of sight  and",
            "avoid    waking    the   slumbering",
            "inhabitants of the dungeons.",
        },
    },
    echo_of_knowledge: Description = .{
        .name = "Echo of knowledge",
        .description = &.{
            "The character possesses  an  innate",
            "understanding  of  the sciences and",
            "technologies of past civilizations.",
            "This    ability   allows   you   to",
            "comprehend  devices  and  artifacts",
            "from  the past and to apply them in",
            "practice.",
        },
    },
};

// All descriptions for enemies MUST be declared here
pub const Enemies = struct {
    /// Enum of all enemies types
    pub const Enum = std.meta.FieldEnum(Enemies);

    rat: Description = .{
        .name = "Rat",
        .description = &.{
            "A big, nasty rat with vicious eyes",
            "that thrives in dark corners and",
            "forgotten cellars.",
        },
    },
    snake: Description = .{
        .name = "Snake",
        .description = &.{
            "A silent reptile with a venomous",
            "bite. Inflicts poison at close",
            "range.",
        },
    },
    wolf: Description = .{
        .name = "Wolf",
        .description = &.{
            "Wild predator. Its fur is smeared",
            "with blood, eyes glinting with",
            "hunger.",
        },
    },
};

pub const Weapon = struct {
    arrows: Description = .{
        .name = "Arrows",
        .description = &.{
            "Wooden arrows with metal tips.",
            "Standard ammunition for bows.",
        },
    },
    bolts: Description = .{
        .name = "Bolts",
        .description = &.{
            "Wooden arrows with metal tips.",
            "Standard ammunition for bows.",
        },
    },
    club: Description = .{
        .name = "Club",
        .description = &.{
            "A gnarled piece of wood, scarred",
            "from use.  Deals  blunt  damage.",
            "Cheap and easy to use.",
        },
    },
    dagger: Description = .{
        .name = "Dagger",
        .description = &.{
            "A light,  sharp  blade.  Fast,",
            "concealable, and effective up",
            "close.",
        },
    },
    light_crossbow: Description = .{
        .name = "Light crossbow",
        .description = &.{
            "Compact crossbow for steady and",
            "accurate targeting.",
        },
    },
    pickaxe: Description = .{
        .name = "Pickaxe",
        .description = &.{
            "Heavy tool for mining stone and",
            "ore. Can double as a weapon.",
        },
    },
    torch: Description = .{
        .name = "Torch",
        .description = &.{
            "Wooden handle, cloth wrap, burning",
            "flame. Lasts until the  fire dies.",
            "It can be  used as a weapon out of",
            "despair.",
        },
    },
    short_bow: Description = .{
        .name = "Short bow",
        .description = &.{
            "A compact bow. Quick to draw,",
            "quiet, and effective at short",
            "range.",
        },
    },
};

// All descriptions for potions MUST be declared here
pub const Potions = struct {
    /// Enum of all potion types
    pub const Enum = std.meta.FieldEnum(Potions);

    healing_potion: Description = .{
        .name = "A healing potion",
        .description = &.{
            "A brew that glows faintly, as if",
            "mends alive. It warms your veins",
            "and your wounds instantly.",
        },
    },
    poisoning_potion: Description = .{
        .name = "A poison",
        .description = &.{
            "A vial filled with a thick, bitter",
            "liquid that smells of decay.",
        },
    },
    oil_potion: Description = .{
        .name = "Oil",
        .description = &.{
            "Glass bottle filled with viscous",
            "oil. Useful as lamp fuel.",
        },
    },
};

pub const Food = struct {
    apple: Description = .{
        .name = "Apple",
        .description = &.{
            "A  simple  apple.  Briefly  eases",
            "hunger,   but    offers    little",
            "sustenance.",
        },
    },
};

closed_door: Description = .{ .name = "Closed door" },
food_ration: Description = .{
    .name = "Food ration",
    .description = &.{
        "A compact bundle of preserved food.",
        "Bland and meager, yet  designed to",
        "provide  steady nourishment over a",
        "long period.",
    },
},
coctail_molotov: Description = .{
    .name = "Molotov cocktail",
    .description = &.{
        "A dark glass bottle sealed with a",
        "cloth wad soaked in fuel. When it",
        "shatters the dark liquid spatters",
        "and flames leap up",
    },
},
jacket: Description = .{
    .name = "Jacket",
    .description = &.{
        "A sturdy, time-worn leather jacket.",
        "Despite its worn  look, the  jacket",
        "offers     surprising    resilience",
        "against  scrapes   and  gives minor",
        "resistance to fire and heat.",
    },
},
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
oil_lamp: Description = .{
    .name = "Oil lamp",
    .description = &.{
        "A simple metal lamp filled with",
        "oil, its flickering flame casts",
        "light into the darkest corners.",
    },
},
opened_door: Description = .{ .name = "Opened door" },
pile: Description = .{
    .name = "Pile of items",
    .description = &.{
        "A heap of miscellaneous gear.",
        "Search it to see what’s useful.",
    },
},
player: Description = .{ .name = "You" },
scientist: Description = .{ .name = "Scientist" },
teleport: Description = .{ .name = "Teleport" },
traider: Description = .{ .name = "Traider" },
unknown_key: Description = .{ .name = "Unknown" },
wharf: Description = .{ .name = "Wharf" },

test "All descriptions should have lines with no more than 35 symbols" {
    var itr = g.components.Description.Preset.iterator();
    while (itr.next()) |description| {
        for (description.description) |line| {
            const len = try std.unicode.utf8CountCodepoints(line);
            std.testing.expect(len < 36) catch |err| {
                std.debug.print(
                    "Description {s} has too long line with {d} symbols:\n\"{s}\"\n",
                    .{ description.name, line.len, line },
                );
                return err;
            };
        }
    }
}
