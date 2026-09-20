# Game Balance

## 1. Purpose and Source of Truth

This document stores balancing targets, tunable constants, progression
curves, economy weights, generation weights, and TTK expectations.

Source of truth split:

- `misc/game_mechanics.md`: qualitative mechanical rules and terminology.
- `misc/game_balance.md`: formulas, numeric tuning values, and design targets.
- `misc/entities/**.csv`: item/content tables and editable content data.

When a balancing value changes, update this file first, then update code and
dependent content.

## 2. Global Balance Targets

Dungeon-level tuning:

| Rule                   | Value                                                       |
| ------------------     | -----------------------------------                         |
| Total dungeon size     | `36 x 120`                                                  |
| Max inventory capacity | `30`                                                        |
| Actual cells           | `30 .. 40%`, roughly `1296 .. 1728`                         |
| Enemies per level      | `7 .. 15`                                                   |
| Two biomes             | Caves on floors `1 .. 4`, Catacombs on floors `5 .. 8`      |
| Two extra levels       | Zero level where the game begins, 9th level with final Boss |
| Max depth              | `9`, the first level has number 0                           |

The main dungeon progression uses 8 tiers for the 8 regular dungeon floors.
The zero level is the starting location, and the 9th level is reserved for the
final boss. Each regular tier has its own enemies, weapons, and armor.

Biome distribution:

| Floors    | Biome     | Role |
| --------- | --------- | ---- |
| `0`       | Start     | safe starting location |
| `1 .. 4`  | Caves     | natural threats, beasts, insects, burrow creatures |
| `5 .. 8`  | Catacombs | ancient shelter, machines, old security systems |
| `9`       | Final     | final boss depth |

Entity generation should be tied to dungeon depth. Dungeon depth defines the
current biome, and the biome defines which tier range and entity families are
expected on that floor.

Neighboring tiers may appear on the same floor, but enemy generation must not
cross biome boundaries. For example, floor `4` may use cave enemies from tiers
`3 .. 4`, but should not preview catacomb enemies from tier `5`.

## 3. Player Progression

Progression bounds:

| Rule                  | Value      |
| --------------------- | ---------- |
| Max player level      | `10`       |
| Characteristics range | `-2 .. +5` |
| Skills range          | `0 .. 10`  |

Characteristics:

- Start: `+1` point, or `+2` points for Adventurer.
- During the game: `+3` total, at levels `3`, `6`, and `9`.

Skills:

- Each level grants `+1` skill point.

Player HP constants:

| Constant | Value  |
| -------- | -----  |
| `Base`   | `20`   |
| `Growth` | `6`    |
| `k`      | `0.15` |

Player HP progression:

```text
HP(level, health) = Base + level x Growth x (1 + k x health)
```

`health` is the character's health characteristic. For tier-based reference
calculations, expected player level is equal to the current floor tier.

Player XP constants:

| Constant      | Value |
| ------------- | ----- |
| `XP_base`     | `20`  |
| `XP_exponent` | `1.5` |

XP progression:

```text
XP_to_next(level) = XP_base x level^XP_exponent
```

## 4. Player TTK

TTK means "time to kill". In this document it is measured in successful hits,
not in real seconds. For player survivability, TTK answers the question:
how many successful same-tier enemy attacks the player can survive before
dying.

Player TTK is the number of successful hits the player survives from an
average same-tier enemy. Enemy damage is tuned against the expected armor
from the previous tier, so current-tier armor remains an advantage.

The target accounts for two common scenarios.

The first scenario is contact with several weak enemies in early/mid gear
or in a narrow corridor. The player must have enough time to react by
retreating, repositioning, sealing a lane, or spending a resource.
The player must have enough survivability to respond before the encounter is
decided.

The second scenario is a chain of ordinary 1v1 fights on one level.
Typical encounters should gradually drain HP, but should not force healing
after every single enemy. Health potion usage should stay moderate:
frequent enough to keep the resource meaningful, but not so frequent that
fighting without a potion feels like a default mistake.
Together these scenarios require a long attrition window without making
ordinary enemies harmless.

The exact TTK range, average target, approximation, and executable examples
are defined in [combat_balance_manual.ipynb](tools/combat_balance_manual.ipynb).
The model assumes successful hits; real combat can differ because of misses,
movement, effects, consumables, and tactical positioning.

Primary layers explain which knobs move player survivability:

- `HP` increases the number of hits the player can take.
- `incoming damage` decreases survivability by making each enemy hit matter
  more.
- `armor` increases survivability by reducing effective incoming damage.
- `attack speed` changes pressure over time: faster enemies apply their damage
  more often, even if their per-hit damage is unchanged.

## 5. Enemy Tiers and TTK

Enemy TTK is built around one question:
how many hits the player should need with typical weaponry from the
current dungeon, against enemies typical for the same dungeon.

TTK targets do not depend on tier and count only successful hits. Individual
profiles vary around the average to keep encounters diverse.

Enemies are balanced primarily by tier. Damage roles such as weak, medium,
strong, very weak, or very strong are not separate balance categories.
Enemies of the same tier should present comparable overall danger through
different combinations of HP, damage, armor, movement, and evasion.

The authoritative values, formulas, examples, and CSV update steps are stored
in [combat_balance_manual.ipynb](tools/combat_balance_manual.ipynb).

Each tier should support at least two encounter metas. For example, Cave Rat
and Cave Snake should not differ because one is simply weak and the other is
strong. They should both fit tier 1, while the rat relies on HP and direct
damage, and the snake relies on speed, dexterity, evasion, and poison pressure.

Target values should be assigned per tier and checked against the same-tier
weapon tier. Within a tier, low-HP/high-speed enemies and high-HP/low-speed
enemies are both valid as long as their overall threat is comparable.

Enemy armor is tied to same-tier weapon damage. The numeric armor value and
the `ARM` trait must agree.

Enemy tier distribution:

| Floor | Biome     | Floor tier | Allowed enemy tiers |
| ----- | --------- | ---------- | ------------------- |
| `0`   | Start     | `-`        | `-`                 |
| `1`   | Caves     | `1`        | `1`                 |
| `2`   | Caves     | `2`        | `1 .. 2`            |
| `3`   | Caves     | `3`        | `2 .. 3`            |
| `4`   | Caves     | `4`        | `3 .. 4`            |
| `5`   | Catacombs | `5`        | `5`                 |
| `6`   | Catacombs | `6`        | `5 .. 6`            |
| `7`   | Catacombs | `7`        | `6 .. 7`            |
| `8`   | Catacombs | `8`        | `7 .. 8`            |
| `9`   | Final     | `9`        | `9`                 |

The floor tier defines expected difficulty, not a hard spawn lock. Allowed
enemy tiers describe local overlap inside the same biome, so earlier enemies
can remain familiar low-pressure encounters and later enemies can start
appearing before they become the main threat of their own tier.

Enemy XP constants:

| Constant | Value    |
| -------- | -----    |
| `tier`   | `1 .. 9` |
| `A`      | `2.15`   |
| `p`      | `1.53`   |

These coefficients are calibrated against tier averages in `Enemies.csv` and
keep expected player level close to floor tier at about 11 enemies per floor.

Enemy XP progression:

```text
XP_enemy(tier) = A x tier^p
```

Enemy HP is derived from same-tier weapon damage, armor, dexterity, and
movement. Armor is only partially compensated during HP generation so it
remains a real survivability advantage. Enemy damage is derived from player
HP, attack speed, range, and expected player armor from the previous tier.
Elemental effects and resistances do not modify these base values. Exact
coefficients and the disabled-by-default `Enemies.csv` update step live in the
notebook.

## 6. Combat Tuning

Hit chance:

```text
hit_chance_percent =
    hit_base
    + perception_hit_weight x ACTOR_PER
    + skill_hit_weight x ACTOR_skill
    - dexterity_evasion_weight x TARGET_DEX
```

Hit chance constants:

| Constant                   | Value |
| -------------------------- | ----- |
| `hit_base`                 | `60`  |
| `perception_hit_weight`    | `2`   |
| `skill_hit_weight`         | `2`   |
| `dexterity_evasion_weight` | `3`   |

Player physical damage and attack-speed adjustments are defined in
[combat_balance_manual.ipynb](tools/combat_balance_manual.ipynb). Elemental
effects are applied to that physical damage as follows:

```text
damage = max(
    poison_floor,
    physical_damage x fire_multiplier - enemy_armor x acid_factor
)

poison_floor =
    poison_floor_weight x base_damage x poison_resistance_multiplier
```

`base_damage` is a random value from the weapon damage range.

Effect multipliers:

| Target relation | `fire_multiplier` | `acid_factor` | `poison_resistance_multiplier`  |
| --------------- | ----------------- | ------------- | ------------------------------- |
| Weak            | `1.25`            | `0.60`        | `1.5`                           |
| Normal          | `1.10`            | `0.85`        | `1.0`                           |
| Resistant       | `1.00`            | `1.00`        | `0.0`                           |

Poisoned attack minimum damage:

```text
poison_floor_weight = 0.2
```

Speed tuning:

| Speed                 | Move points |
| --------------------- | ----------- |
| Normal movement speed | `10 mp`     |
| High movement speed   | `8 mp`      |
| Low movement speed    | `12 mp`     |

## 7. Character Identity

Player characteristics are intentionally asymmetric. Each characteristic
provides a distinct gameplay advantage rather than equal mathematical
value.

| Characteristic | Design role                                                                                     |
| -------------- | -----------                                                                                     |
| **STR**        | Access to the widest selection of weapons and gives bonus damage regardless of the weapon type. |
| **DEX**        | Access to agile weapons, improves survivability, and helps disarm traps.                        |
| **PER**        | Improves hit chance and exploration by detecting traps and secrets.                             |
| **INT**        | Access to the rarest and most powerful weapons, and enables advanced item modification.         |

Weapon distribution and supporting mechanics should be balanced to
reinforce these identities.

## 8. Weapon Damage Balance

Weapon tier is stored explicitly in `Weapon.csv`. Each tier defines a
reference average damage for a melee weapon with normal attack speed. Adjacent
tier ranges overlap so a strong roll from a lower tier can compete with a weak
roll from the next tier.

DEX weapons trade damage per hit for attack frequency. Ranged weapons trade
damage for positional advantage and also require ammunition. Fire, acid, and
poison remain bonuses and do not reduce base damage. The separate `VAR` trait
marks weapons with a wider damage range, while `Effect` remains reserved for
elemental effects. Exceptional weapons may use explicit individual factors.

The authoritative progression table, coefficients, exceptions, formulas, and
the disabled-by-default `Weapon.csv` update step are defined in
[combat_balance_manual.ipynb](tools/combat_balance_manual.ipynb).

Class identity:

| Class     | Stat  | Combat identity                                                                                                                       |
| -----     | ----  | ---------------                                                                                                                       |
| Primitive | `STR` | Highest common raw melee damage. Supports the strong, tough vandal meta.                                                             |
| Tricky    | `DEX` | Lower raw damage, more ranged options, and lighter-feeling weapons. Supports the agile rogue meta.                                   |
| Ancient   | `INT` | Highest ceiling and rarest late-game power. Supports the archaeologist meta through intelligence and access to forgotten technology. |

Ancient weapon drawbacks and their compensation through intelligence and
`echo_of_knowledge` are applied outside the base-damage calculation.

## 9. Economy

Starting player gold:

```text
starting_gold = 35 .. 70
```

Shop category weights:

| Category         | Weight |
| --------         | ------ |
| Weapons          | `14`   |
| Modified Weapons | `10`   |
| Broken Weapons   | `8`    |
| Armor            | `10`   |
| Modified Armor   | `8`    |
| Broken Armor     | `6`    |
| Food             | `18`   |
| Potions          | `12`   |
| Ammo             | `24`   |
| Torches          | `10`   |
| Oil              | `5`    |

Sell multipliers:

| Category                      | Multiplier |
| --------------------          | ---------- |
| Food                          | `0.25`     |
| Potions                       | `0.20`     |
| Unidentified Potions          | `0.10`     |
| Ammo                          | `0.30`     |
| Torches                       | `0.15`     |
| Oil                           | `0.20`     |
| Weapons                       | `0.35`     |
| Improved Weapons              | `0.55`     |
| Broken Weapons                | `0.05`     |
| Unidentified Weapons          | `0.20`     |
| Unidentified Modified Weapons | `0.40`     |
| Armor                         | `0.30`     |
| Improved Armor                | `0.45`     |
| Broken Armor                  | `0.05`     |
| Unidentified Armor            | `0.20`     |
| Unidentified Modified Armor   | `0.35`     |

Modify/recognize services:

```text
identify_cost = round(item_price x 0.45)

repair_break_cost = round(item_price x 0.50)

crude_mod_cost = round(item_price x 0.35)

careful_mod_cost = round(item_price x 1.05)

manual_mod_cost = round(item_price x 2.80)
```

## 10. Generation

Shared spawn weight formula:

```text
distance = abs(depth - peak)

weight =
    if distance > radius:
        0
    else:
        max(tail_weight, base_weight - step_weight x distance)
```

Weapon peak:

```text
weapon_peak = weapon_tier
```

Item category generation:

| Category         | Weight | Comment                     |
| ---------------- | ------ | --------------------------- |
| Gold             | `28`   | main neutral loot           |
| Weapons          | `10`   | regular weapons             |
| Modified Weapons | `6`    | weapons with modifications  |
| Broken Weapons   | `8`    | broken weapons, vendor loot |
| Armor            | `8`    | regular armor               |
| Modified Armor   | `4`    | armor with modifications    |
| Broken Armor     | `8`    | broken armor, vendor loot   |
| Food             | `10`   | hunger remains a threat     |
| Potions          | `12`   | rare utility resources      |
| Ammo             | `14`   | ranged build support        |
| Torches          | `10`   | critical light source       |
| Oil              | `6`    | rare lamp resource          |

Gold piles:

| Floor | Range        |
| ----- | ------------ |
| `1`   | `6 .. 15`    |
| `2`   | `14 .. 36`   |
| `3`   | `24 .. 64`   |
| `4`   | `36 .. 94`   |
| `5`   | `48 .. 128`  |
| `6`   | `62 .. 162`  |
| `7`   | `76 .. 200`  |
| `8`   | `91 .. 239`  |
| `9`   | `107 .. 281` |

Weapon spawn parameters:

| Parameter     | Value | Meaning                        |
| ------------- | ----- | ------------------------------ |
| `base_weight` | `100` | weight on peak floor           |
| `step_weight` | `45`  | weight decrease per floor away |
| `tail_weight` | `3`   | minimum rare spawn chance      |
| `radius`      | `3`   | max distance from peak         |

Weapon generation starts from the explicit tier in `Weapon.csv`. Spawn
overlap and biome boundaries can be tuned independently without changing the
weapon's tier.

Armor spawn parameters:

| Parameter     | Value | Meaning                             |
| ------------- | ----- | ----------------------------------- |
| `base_weight` | `100` | weight on peak floor                |
| `step_weight` | `50`  | weight decrease per floor away      |
| `tail_weight` | `5`   | minimum rare spawn chance           |
| `radius`      | `2`   | max distance from peak              |

Armor distribution:

| Distance | Weight |
| -------- | ------ |
| `0`      | `100`  |
| `1`      | `50`   |
| `2`      | `5`    |
| `3`      | `0`    |

## 11. Modifications and Breakage

Feature and trait stat values:

| Source        | Value |
| ------------- | ----- |
| Modification  | `+2`  |
| Trait         | `+4`  |

Modification function:

| Modification         | Value                    | Weight |
| -------------------- | ------------------------ | ------ |
| Stat bonus           | `+1`                     | `5`    |
| Extra effect         | `FIRE`, `ACID`, `POISON` | `10`   |
| Movement speed bonus | `2`                      | `3`    |
| Attack speed bonus   | `2`                      | `3`    |

Breakage function:

| Breakage               | Value                    | Weight |
| ---------------------- | ------------------------ | ------ |
| Stat penalty           | `-1`                     | `5`    |
| Effect vulnerability   | `FIRE`, `ACID`, `POISON` | `10`   |
| Movement speed penalty | `2`                      | `7`    |
| Attack speed penalty   | `2`                      | `7`    |

## 12. Poisoning

Poison damage sequence:

```text
poison_damage(0) = initial_poison_damage
poison_damage(n) = floor(poison_damage(n - 1) / 2)
```

The effect ends when the next damage value reaches zero. Applying Poison again
keeps the greater of the current and newly applied damage values.

Initial poison damage:

| Source | Initial damage |
| ------ | -------------- |
| Poison potion | `0.40 x max_HP` |
| Oil | `0.10 x max_HP` |

The halving sequence deals total damage close to twice its initial value.

## 13. Hunger

Hunger levels:

| Turns          | Level                 |
| -------------- | --------------------- |
| `0 .. 800`     | `well_fed`            |
| `800 .. 1500`  | `hunger`              |
| `1500 .. 2100` | `severe_hunger`       |
| `2100 ..`      | `critical_starvation` |

Hunger damage:

| Level    | Length | Interval    | Ticks | Damage   | Damage at HP 100 | Total    |
| -------- | ------ | ----------- | ----- | -------- | ---------------- | -------- |
| hunger   | `700`  | `~50 turns` | `~14` | `1 + 1%` | `2`              | `~28 HP` |
| severe   | `600`  | `~25 turns` | `~24` | `1 + 2%` | `3`              | `~72 HP` |
| critical | `-`    | `~12 turns` | `-`   | `2 + 4%` | `6`              | `-`      |

## 14. Traps

Trap model uses 4 power tiers.

| Power | Damage         | Feeling           |
| ----- | -------------- | ----------------- |
| `0`   | `5 .. 8% HP`   | background threat |
| `1`   | `10 .. 15% HP` | noticeable        |
| `2`   | `18 .. 25% HP` | dangerous         |
| `3`   | `30 .. 45% HP` | critical          |

Detection chance clamp:

```text
0.05 .. 0.85
```

Detection constants:

| Constant               | Value  |
| ---------------------- | ------ |
| `notice_base_chance`   | `0.42` |
| `notice_power_penalty` | `0.08` |

Detection:

```text
effective_distance = max(1, distance - perception)
base_chance = notice_base_chance - notice_power_penalty x trap_power

notice_chance = clamp(
    base_chance / effective_distance,
    min_notice_chance,
    max_notice_chance
)
```

Disarm chance clamp:

```text
0.05 .. 0.90
```

Disarm constants:

| Constant                  | Value  |
| ------------------------- | ------ |
| `disarm_base_chance`      | `0.30` |
| `dexterity_disarm_weight` | `0.06` |
| `mechanic_disarm_weight`  | `0.07` |
| `power_disarm_penalty`    | `0.10` |

Disarm:

```text
raw_disarm_chance =
    disarm_base_chance
    + dexterity_disarm_weight x dexterity
    + mechanic_disarm_weight x mechanic
    - power_disarm_penalty x power

disarm_chance = clamp(
    raw_disarm_chance,
    min_disarm_chance,
    max_disarm_chance
)
```

Disarm tiers:

| Tier           | Chance         |
| -------------- | -------------- |
| easy to disarm | `>= 0.65`      |
| have to tinker | `0.45 .. 0.65` |
| risky to touch | `0.25 .. 0.45` |
| God help me    | `<= 0.25`      |
