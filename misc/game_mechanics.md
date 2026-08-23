# Game Mechanics

## 1. Purpose and Source of Truth

This document stores all gameplay formulas and mechanic constants.

Source of truth split:

- `misc/game_mechanics.md`: formulas, balancing rules, and
  table-driven mechanic functions.
- `misc/entities/**.csv`: item/content tables and editable content data.

When a formula or mechanic changes, update this file first, then update
code and dependent content.

## 2. Global Constants

Dungeon-level constants used across multiple systems:

| Rule                   | Value                                                       |
| ------------------     | -----------------------------------                         |
| Total dungeon size     | `36 x 120`                                                  |
| Actual cells           | `30 .. 40%`, roughly `1296 .. 1728`                         |
| Enemies per level      | `7 .. 15`                                                   |
| Two biomes             | 4 levels of Caves, 4 levels of Catacombs                    |
| Two extra levels       | Zero level where the game begins, 9th level with final Boss |
| Max depth              | `9`, the first level has number 0                           |
| Max inventory capacity | 30                                                          |

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

_stat +2 for modifications, and +4 for traits_

## 4. Player Progression Model

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

Player HP:

```text
HP(level, health) = Base + level x Growth x (1 + k x health)
```
Where:
- `Base`   = 20
- `Growth` = 6
- `k`      = 0.15
- `health` is a characteristic in [-2 .. +5]

XP progression:

```text
XP_to_next(level) = 20 x level^1.5
```

## 5. Player BASE_TTK

`BASE_TTK` is the number of hits the player can survive from a same-tier
enemy while wearing same-tier armor.

Two baseline scenarios define the target:

The first scenario is contact with several weak enemies in early/mid gear
or in a narrow corridor. The player must have enough time to react by
retreating, repositioning, sealing a lane, or spending a resource.
This sets the lower survivability bound.

The second scenario is a chain of ordinary 1v1 fights on one level.
Typical encounters should gradually drain HP, but should not force healing
after every single enemy. Health potion usage should stay moderate:
frequent enough to keep the resource meaningful, but not so frequent that
fighting without a potion feels like a default mistake.
This sets the working survivability target.

Baseline target:

```text
BASE_TTK ~= 12 .. 30
avg(BASE_TTK) ~= 20
```

Approximation:

```text
BASE_TTK = HP / (enemy_damage - armor)
```

Primary layers:

```text
HP
incoming damage
armor
attack speed
```

## 6. Enemy Model

### Enemy TTK

Enemy TTK is built around one question:
how many hits the player should need with typical weaponry from the
current dungeon, against enemies typical for the same dungeon.

Target values:

| Enemy type | TTK        |
| ---------- | ---------- |
| weak       | `1 .. 3`   |
| medium     | `2 .. 5`   |
| strong     | `3 .. 6`   |

Floor distribution:

| Floor | Biome               | Main enemies                                     | Rare / dangerous                |
| ----- | ------------------- | ------------------------------------------------ | ------------------------------- |
| `1`   | Upper caves         | Rat, Snake                                       | Bat                             |
| `2`   | Upper caves         | Rat, Snake, Bat                                  | Cave Hound                      |
| `3`   | Deep burrows        | Carrion Feeder, Worm, Venom Centipede            | Acid Centipede                  |
| `4`   | Deep burrows        | Carrion Feeder, Armadillo Beast, Giant Venom Ant | Fire Centipede, Giant Acid Ant  |
| `5`   | Abandoned catacombs | Repair Drone, Cave Spider, Mechatron             | Robot                           |
| `6`   | Abandoned catacombs | Repair Drone, Cave Spider, Mechatron, Robot      | Turret                          |
| `7`   | Tech depths         | Robot, Turret, Mechatron                         | Cyborg                          |
| `8`   | Tech depths         | Cyborg, Robot, Turret                            | Terminator                      |


## 7. Enemy Scaling Formulas

Enemy XP:

```text
XP_enemy = A x tier^p
```

```text
tier in [1 .. 9]
A = 6
p = 1.3
```

Enemy HP:

```text
enemy_HP = (0.8 .. 1.2) x base_HP x tier^1.25
base_HP = 12
```

## 8. Combat Model

Hit chance:

```text
hit_chance_percent = 60 + 2 x ACTOR PER + 2 x ACTOR skill - 3 x TARGET DEX
```

Damage:

```text
physical_damage = base_damage x (1 + 0.05 x STR + 0.1 x stat)

damage = max(
    poison_floor,
    physical_damage x fire_multiplier - enemy_armor x acid_factor
)

poison_floor = K x base_damage x poison_resistance_multiplier

K = 0.2
```

Where:

```text
base_damage = random weapon damage
stat        = matching stat: STR, DEX, or INT
enemy_armor = target armor
poison_floor = minimum damage dealt by a poisoned attack
```

Effect multipliers:

| Target relation | `fire_multiplier` | `acid_factor` | `poison_resistance_multiplier` |
| --------------- | ----------------- | ------------- | ------------------- |
| Weak            | `1.25`            | `0.60`        | `1.5`               |
| Normal          | `1.10`            | `0.85`        | `1.0`               |
| Resistant       | `1.00`            | `1.00`        | `0.0`               |


Enemy damage roles:

| Type        | Modifier | Damage    |
| ----------- | -------- | --------- |
| Very weak   | `-0.30`  | `4 .. 6`  |
| Weak        | `-0.20`  | `5 .. 7`  |
| Base        | `0`      | `6 .. 8`  |
| Strong      | `+0.20`  | `7 .. 10` |
| Very strong | `+0.35`  | `8 .. 11` |

## Character Identity

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

## 9. Speed Model

The game uses two independent speed channels:

- attack speed
- movement speed

Usually each action costs `10` move points. Slower actions cost more,
faster actions cost less.

| Speed                   | Move points |
| ----------------------- | ----------- |
| Normal attack speed     | `10 mp`     |
| DEX weapon attack speed | `8 mp`      |
| Normal movement speed   | `10 mp`     |
| High movement speed     | `8 mp`      |
| Low movement speed      | `12 mp`     |

## 10. Economy Model

Item base prices are defined in item/content tables in
`misc/entities/**.csv`.

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

## 11. Generation Model

Key weighted random selector:

`https://ziglang.org/documentation/master/std/#std.Random.weightedIndex`

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

Spawn weight function:

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
power = (min_damage + max_damage) / 2
peak = 1 + floor(power / 7)
```

Weapon parameters:

| Parameter     | Value | Meaning                        |
| ------------- | ----- | ------------------------------ |
| `base_weight` | `100` | weight on peak floor           |
| `step_weight` | `45`  | weight decrease per floor away |
| `tail_weight` | `3`   | minimum rare spawn chance      |
| `radius`      | `3`   | max distance from peak         |

Armor parameters:

| Parameter     | Value  | Meaning                             |
| ------------- | ------ | ----------------------------------- |
| `base_weight` | `100`  | weight on peak floor                |
| `step_weight` | `50`   | weight decrease per floor away      |
| `tail_weight` | `5`    | minimum rare spawn chance           |
| `radius`      | `2`    | max distance from peak              |

Armor distribution:

| Distance | Weight |
| -------- | ------ |
| `0`      | `100`  |
| `1`      | `50`   |
| `2`      | `5`    |
| `3`      | `0`    |

## Modifications

Weapons and armors can have few modifications. Every type of modification can be
applied only once.

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

## 12. Hunger

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

## 13. Traps

Trap model uses 4 power tiers.

| Power | Damage         | Feeling           |
| ----- | -------------- | ----------------- |
| `0`   | `5 .. 8% HP`   | background threat |
| `1`   | `10 .. 15% HP` | noticeable        |
| `2`   | `18 .. 25% HP` | dangerous         |
| `3`   | `30 .. 45% HP` | critical          |

Detection:

`D` chance to notice:

```text
effective_distance = max(1, distance - perception)

base_chance = 0.42 - 0.08 x trap_power

notice_chance = clamp(
    base_chance / effective_distance,
    0.05,
    0.85
)
```

Disarm:

`S` chance to disarm:

```text
disarm_chance = clamp(
    0.30 + 0.06 x dexterity + 0.07 x mechanic - 0.10 x power,
    0.05,
    0.90
)
```

Disarm tiers:

| Tier           | Chance         |
| -------------- | -------------- |
| easy to disarm | `>= 0.65`      |
| have to tinker | `0.45 .. 0.65` |
| risky to touch | `0.25 .. 0.45` |
| God help me    | `<= 0.25`      |
