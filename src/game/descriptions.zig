//! A full set of descriptions for all entities in the game.
//!
//! It also used as a tricky system of meta types.
//! Because of all entities must have a description, the easies way
//! to get a type for some entity is match its description `preset`
//! to a more precise enum that represents a type of the entity.
//!
//! NOTE: **All descriptions for potions MUST be declared here!**
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Archetypes = struct {
    pub const Enum = std.meta.FieldEnum(Archetypes);

    adventurer: g.Description = .{
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
    archeologist: g.Description = .{
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
    vandal: g.Description = .{
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
    rogue: g.Description = .{
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
    weapon_mastery: g.Description = .{
        .name = "Weapon Mastery",
        .description = &.{
            "Possessing this skill  allows  you",
            "to use any weapon more effectively",
            "and miss less often.",
        },
    },
    mechanics: g.Description = .{
        .name = "Mechanics",
        .description = &.{
            "Knowledge in the field of mechanics",
            "helps  you  pick  locks  and disarm",
            "traps.",
        },
    },
    stealth: g.Description = .{
        .name = "Stealth",
        .description = &.{
            "Stealth  is the ability  to  remain",
            "unseen — to stay out  of sight  and",
            "avoid    waking    the   slumbering",
            "inhabitants of the dungeons.",
        },
    },
    echo_of_knowledge: g.Description = .{
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

    rat: g.Description = .{
        .name = "Rat",
        .description = &.{
            "A big, nasty rat with vicious eyes",
            "that thrives in dark corners and",
            "forgotten cellars.",
        },
    },
    snake: g.Description = .{
        .name = "Snake",
        .description = &.{
            "A silent reptile with a venomous",
            "bite. Inflicts poison at close",
            "range.",
        },
    },
    wolf: g.Description = .{
        .name = "Wolf",
        .description = &.{
            "Wild predator. Its fur is smeared",
            "with blood, eyes glinting with",
            "hunger.",
        },
    },
};

pub const Weapon = struct {
    arrows: g.Description = .{
        .name = "Arrows",
        .description = &.{
            "Wooden arrows with metal tips.",
            "Standard ammunition for bows.",
        },
    },
    bolts: g.Description = .{
        .name = "Bolts",
        .description = &.{
            "Wooden arrows with metal tips.",
            "Standard ammunition for bows.",
        },
    },
    bullets: g.Description = .{
        .name = "Bullets",
        .description = &.{
            "Cartridges  with  tarnished",
            "casings  and  the  smell of",
            "gunpowder.  Even  untouched,",
            "they look dangerous.",
        },
    },
    club: g.Description = .{
        .name = "Club",
        .description = &.{
            "A gnarled piece of wood, scarred",
            "from use.  Deals  blunt  damage.",
            "Cheap and easy to use.",
        },
    },
    dagger: g.Description = .{
        .name = "Dagger",
        .description = &.{
            "A light,  sharp  blade.  Fast,",
            "concealable, and effective up",
            "close.",
        },
    },
    light_crossbow: g.Description = .{
        .name = "Light crossbow",
        .description = &.{
            "Compact crossbow for steady and",
            "accurate targeting.",
        },
    },
    pickaxe: g.Description = .{
        .name = "Pickaxe",
        .description = &.{
            "Heavy tool for mining stone and",
            "ore. Can double as a weapon.",
        },
    },
    torch: g.Description = .{
        .name = "Torch",
        .description = &.{
            "Wooden handle, cloth wrap, burning",
            "flame. Lasts until the  fire dies.",
            "It can be  used as a weapon out of",
            "despair.",
        },
    },
    short_bow: g.Description = .{
        .name = "Short bow",
        .description = &.{
            "A compact bow. Quick to draw,",
            "quiet, and effective at short",
            "range.",
        },
    },
};

pub const Potions = struct {
    ancient_preserved_supplies: g.Description = .{
        .name = "Ancient Preserved Supplies",
        .description = &.{
            "These  supplies outlived the people",
            "who  hid  them and nearly outlasted",
            "their  own  expiration  date. Their",
            "strange  taste  seems a small price",
            "for such an unlikely discovery.",
        },
    },

    apple: g.Description = .{
        .name = "Apple",
        .description = &.{
            "The  crisp  skin gives way to sweet",
            "flesh  and a burst of freshness. It",
            "will  not end a journey, but it can",
            "quiet  hunger  long  enough to keep",
            "walking.",
        },
    },

    armadillo_roast: g.Description = .{
        .name = "Armadillo Roast",
        .description = &.{
            "Fatty  armadillo  meat needs a long",
            "roast, but it is deeply satisfying.",
            "The   thick   shell  protected  its",
            "former  owner from danger, not from",
            "a hungry explorer.",
        },
    },

    cheese: g.Description = .{
        .name = "Cheese",
        .description = &.{
            "A firm piece of aged cheese wears a",
            "dry  rind  and  smells  faintly  of",
            "smoke.   Its   sharp  flavor  feels",
            "almost  luxurious after a long walk",
            "through stone corridors.",
        },
    },

    cooked_meat: g.Description = .{
        .name = "Cooked Meat",
        .description = &.{
            "A  juicy  portion  of meat has been",
            "browned  over  a  fire and seasoned",
            "with nothing but salt. Simple food,",
            "but   more   reliable   than   many",
            "expensive promises.",
        },
    },

    dried_fruits: g.Description = .{
        .name = "Dried Fruits",
        .description = &.{
            "Sticky   slices   of   fruit   have",
            "darkened  with  age and sugar. They",
            "cling  to  the teeth, but keep well",
            "and  preserve  a  bright  sweetness",
            "through many hungry days.",
        },
    },

    insect_paste: g.Description = .{
        .name = "Insect Paste",
        .description = &.{
            "A  thick  paste  made  from crushed",
            "insects looks unpleasant, but it is",
            "rich in nourishment. It is best not",
            "to  study  it  too  closely  before",
            "taking the first bite.",
        },
    },

    jerky: g.Description = .{
        .name = "Jerky",
        .description = &.{
            "Tough  strips  of  salted meat keep",
            "for   a   long   time   and  demand",
            "patience.  Every  minute of chewing",
            "feels   worthwhile  when  dangerous",
            "roads still lie ahead.",
        },
    },

    miners_rations: g.Description = .{
        .name = "Miner’s Rations",
        .description = &.{
            "Heavy  rations  made for people who",
            "spend  their days underground. They",
            "are   rough,   filling,  and  dense",
            "enough  to  survive  being  crushed",
            "inside a pack.",
        },
    },

    rat_skewer: g.Description = .{
        .name = "Rat Skewer",
        .description = &.{
            "A  roasted  rat  turns  on  a rough",
            "wooden   skewer,  its  smoky  smell",
            "overpowering     every     sensible",
            "objection.  Hunger  soon makes sure",
            "you    stop    asking   unnecessary",
            "questions.",
        },
    },

    salted_meat_pack: g.Description = .{
        .name = "Salted Meat Pack",
        .description = &.{
            "Dense  cuts of meat are salted to a",
            "powerful  flavor  and  can  survive",
            "months  in  storage.  They  must be",
            "chewed  slowly,  but  hunger  stays",
            "away for a long while.",
        },
    },

    sandwich: g.Description = .{
        .name = "Sandwich",
        .description = &.{
            "Two  slices  of bread hold a simple",
            "filling   assembled   without  much",
            "concern  for taste. Still, the meal",
            "is  easy  to  carry  and  eat while",
            "moving through the dark.",
        },
    },

    stale_bread: g.Description = .{
        .name = "Stale Bread",
        .description = &.{
            "The  loaf  lost  its freshness long",
            "ago  and hardened almost like wood.",
            "It  is  difficult  to  chew, but it",
            "still   gives   an   empty  stomach",
            "something   to   do  and  a  little",
            "strength.",
        },
    },

    stew: g.Description = .{
        .name = "Stew",
        .description = &.{
            "Thick  stew  smells of meat, roots,",
            "and  campfire  smoke.  It warms the",
            "body  from  within  and gives tired",
            "legs  enough confidence to face the",
            "next stretch of darkness.",
        },
    },

    tins: g.Description = .{
        .name = "Tins",
        .description = &.{
            "Heavy  tins  are  sealed as if they",
            "were  meant  to  survive the end of",
            "the   world.   Inside  waits  plain",
            "prepared food, lacking elegance but",
            "built to last.",
        },
    },

    traveler_ration: g.Description = .{
        .name = "Traveler Ration",
        .description = &.{
            "A  dependable  bundle  for  a  long",
            "journey,   packed  with  dry  food,",
            "salt,  and  nothing unnecessary. It",
            "will  not  bring joy, but it rarely",
            "lets a traveler down.",
        },
    },
};

pub const Food = struct {
    acid: g.Description = .{
        .name = "Acid",
        .description = &.{
            "The  caustic liquid burns the mouth",
            "and  stomach  before eating through",
            "the  body  from  within.  The  pain",
            "arrives quickly and leaves no doubt",
            "about the drink's true nature.",
        },
    },

    antidote: g.Description = .{
        .name = "Antidote",
        .description = &.{
            "The   bitter   medicine  burns  the",
            "tongue and stomach. Its ingredients",
            "bind  the poison and slowly cleanse",
            "the  blood,  giving  the  body back",
            "control of its own strength.",
        },
    },

    bouillon: g.Description = .{
        .name = "Bouillon",
        .description = &.{
            "Hot  broth  with  salt  and  humble",
            "vegetables offers no luxury, but it",
            "quickly   warms   the  stomach  and",
            "restores   enough  strength  for  a",
            "tired explorer to continue.",
        },
    },

    healing: g.Description = .{
        .name = "Healing",
        .description = &.{
            "The  warm  medicinal brew smells of",
            "herbs  and  honey.  A  few  careful",
            "swallows restore strength, dull the",
            "pain,  and help the body endure its",
            "deepest wounds.",
        },
    },

    liquid_fire: g.Description = .{
        .name = "Liquid Fire",
        .description = &.{
            "Liquid fire ignites in the stomach,",
            "scorching  the throat and entrails.",
            "A   few   moments   are  enough  to",
            "understand that this is no metaphor",
            "and certainly no ordinary drink.",
        },
    },

    machine_oil: g.Description = .{
        .name = "Machine Oil",
        .description = &.{
            "Heavy  machine oil fills cracks and",
            "frees  jammed  mechanisms.  It  was",
            "never  meant  for  a  living  body,",
            "where  it burns through the stomach",
            "and leaves a metallic ache.",
        },
    },

    oil: g.Description = .{
        .name = "Oil",
        .description = &.{
            "Thick  lamp oil burns steadily in a",
            "proper  vessel, but inside a living",
            "body  it  spreads through the blood",
            "and leaves behind a slow, lingering",
            "weakness.",
        },
    },

    poison: g.Description = .{
        .name = "Poison",
        .description = &.{
            "The  clear  liquid  has  almost  no",
            "smell   and  looks  harmless.  That",
            "illusion   ends   with   the  first",
            "swallow,  as  the poison begins its",
            "slow work of draining strength.",
        },
    },

    spoiled_bouillon: g.Description = .{
        .name = "Spoiled Bouillon",
        .description = &.{
            "A  sour  sludge  hides  beneath the",
            "film  on  its surface. The smell is",
            "warning  enough,  but  it comes too",
            "late  once  the  first mouthful has",
            "already been swallowed.",
        },
    },

    water: g.Description = .{
        .name = "Water",
        .description = &.{
            "Clean, cold water with no taste and",
            "no  hidden  property.  It offers no",
            "miracle,  but  a  plain  drink  can",
            "still  save a traveler whose throat",
            "has gone dry.",
        },
    },
};

closed_door: g.Description = .{
    .name = "Closed door",
    .description = &.{
        "The  door  stands shut, silent  and",
        "uninviting,  hidding  whatever lies",
        "beyond.",
    },
},
coctail_molotov: g.Description = .{
    .name = "Molotov cocktail",
    .description = &.{
        "A dark glass bottle sealed with a",
        "cloth wad soaked in fuel. When it",
        "shatters the dark liquid spatters",
        "and flames leap up",
    },
},
jacket: g.Description = .{
    .name = "Jacket",
    .description = &.{
        "A sturdy, time-worn leather jacket.",
        "Despite its worn  look, the  jacket",
        "offers     surprising    resilience",
        "against  scrapes   and  gives minor",
        "resistance to fire and heat.",
    },
},
ladder_down: g.Description = .{ .name = "Ladder down" },
ladder_to_caves: g.Description = .{ .name = "Entrance to caves" },
ladder_up: g.Description = .{ .name = "Ladder up" },
oil_lamp: g.Description = .{
    .name = "Oil lamp",
    .description = &.{
        "A simple metal lamp filled with",
        "oil, its flickering flame casts",
        "light into the darkest corners.",
    },
},
opened_door: g.Description = .{
    .name = "Opened door",
    .description = &.{
        "A  doorway  stands open, offering a",
        "glimpse  intothe  space  that  lies",
        "ahead.",
    },
},
pile: g.Description = .{
    .name = "Pile of items",
    .description = &.{
        "A heap of miscellaneous gear.",
        "Search it to see what’s useful.",
    },
},
gold_pile: g.Description = .{
    .name = "Gold",
    .description = &.{
        "A  pile  of  dimly  glinting",
        "coins, carelessly swept into",
        "one place.",
    },
},
player: g.Description = .{ .name = "You" },
scientist: g.Description = .{ .name = "Scientist" },
teleport: g.Description = .{ .name = "Teleport" },
traider: g.Description = .{ .name = "Traider" },
trap: g.Description = .{
    .name = "Trap",
    .description = &.{
        "Hidden spikes burst from the ground",
        "impaling anything standing above.",
    },
},
unknown_key: g.Description = .{ .name = "Unknown" },
wharf: g.Description = .{ .name = "Wharf" },

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
