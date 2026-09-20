# Game Mechanics

## 1. Purpose and Source of Truth

This document describes gameplay rules and terminology without duplicating
their tunable formulas or numeric parameters.

Source of truth split:

- `misc/game_mechanics.md`: qualitative mechanical rules and terminology.
- `misc/game_balance.md`: formulas, numeric tuning values, design targets, and
  balancing rules.
- `misc/entities/**.csv`: item/content tables and editable content data.

When a mechanic changes, update this file. When a formula or balancing value
changes, update `misc/game_balance.md` first, then update code and dependent
content.

## 2. Global Rules

Dungeon dimensions, inventory capacity, dungeon density, depth, and enemy
count are stored in `misc/game_balance.md`.

## 3. Feature Codes

| Code     | Meaning                                |
| -------- | -------------------------------------- |
| `ARM`    | armor, reduces incoming damage         |
| `F-`     | fire vulnerability                     |
| `A-`     | acid vulnerability                     |
| `P-`     | poison vulnerability                   |
| `F+`     | fire resistance                        |
| `A+`     | acid resistance                        |
| `P+`     | poison resistance                      |
| `SPD-`   | low movement speed                     |
| `SPD+`   | high movement speed                    |
| `ATK-`   | low attack speed                       |
| `ATK+`   | high attack speed                      |
| `DEX+`   | increased dexterity, hits more often   |
| `DEX-`   | decreased dexterity, misses more often |
| `PER+`   | increased perception                   |
| `PER-`   | decreased perception                   |
| `FIRE`   | attacks apply fire effect              |
| `ACID`   | attacks reduce armor effectiveness     |
| `POISON` | attacks guarantee minimum damage       |
| `RNG(N)` | ranged attack with range `N`           |

Stat modification values are stored in `misc/game_balance.md`.

## 4. Player Progression Model

Player maximum HP grows with level and the health characteristic. Defeating
enemies grants XP toward the next player level. HP and XP formulas,
coefficients, progression bounds, level caps, and point awards are stored in
sections 3 and 5 of `misc/game_balance.md`.

## 5. Enemy Scaling Formulas

Enemy XP and expected HP scale with enemy tier. Their formulas, coefficients,
floor distribution, combat profiles, and TTK targets are stored in section 5
of `misc/game_balance.md`.

## 6. Combat Model

Hit chance depends on actor perception and weapon skill, opposed by target
dexterity. Physical damage starts with a random value from the weapon range,
then applies strength, the weapon's matching characteristic, elemental
relations, armor, and the poisoned-attack damage floor.

Combat formulas, coefficients, effect multipliers, and TTK targets are stored
in sections 4 and 6 of `misc/game_balance.md`.

## 7. Speed Model

The game uses two independent speed channels:

- attack speed
- movement speed

Usually each action costs move points. Slower actions cost more, faster
actions cost less.

Move-point values for normal, high, and low speed are stored in
`misc/game_balance.md`.

## 8. Economy Model

Item base prices are defined in item/content tables in
`misc/entities/**.csv`.

Starting gold, shop category weights, sell multipliers, and service prices are
stored in `misc/game_balance.md`.

## 9. Generation Model

Key weighted random selector:

`https://ziglang.org/documentation/master/std/#std.Random.weightedIndex`

Item probability decreases as dungeon depth moves away from the item's peak
floor and reaches zero outside its spawn radius. Weapon peak is derived from
average weapon damage.

Generation formulas, weights, gold pile ranges, weapon spawn parameters, and
armor spawn parameters are stored in sections 8 and 10 of
`misc/game_balance.md`.

## 10. Modifications

Weapons and armors can have few modifications. Every type of modification can
be applied only once.

Modification and breakage weights are stored in `misc/game_balance.md`.

## 11. Poisoning

Drinking a poison potion or oil applies the Poison effect to the actor.
The effect deals damage once per cycle. Each subsequent damage value is half
of the previous one, rounded down, and the effect ends when the value reaches
zero.

Applying Poison again sets the current poison damage to the greater of the
current and new values.

The poison sequence formula and initial damage values are stored in section 12
of `misc/game_balance.md`.

## 12. Hunger

Hunger levels, starvation damage values, intervals, and total damage targets
are stored in `misc/game_balance.md`.

## 13. Traps

Detection improves with perception and proximity and becomes harder with trap
power. Disarming improves with dexterity and mechanics skill and becomes
harder with trap power.

Detection and disarm formulas, trap power tiers, damage values, chance clamps,
and disarm tiers are stored in section 14 of `misc/game_balance.md`.
