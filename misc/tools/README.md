# Tools

All generators are available through one CLI application:

```sh
zig run misc/tools/main.zig -- <command> <csv-path>
```

Use `--help` to list the available commands:

```sh
zig run misc/tools/main.zig -- --help
```

## Generate Food Entities

The `food` command generates Zig entity definitions from
`misc/entities/Food.csv`.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- food misc/entities/Food.csv \
  > src/game/entities/food.zig
```

The script reads the `Name`, `Calories`, `Price`, and `Description` columns.
The description text is not copied to the generated file. Instead, the
`Name` value is converted to `snake_case` and used as the description preset.

For example, `Traveler Ration` becomes `traveler_ration`.

The description presets referenced by the generated code must be declared in
the corresponding module under `src/game/descriptions/` separately.
Generated food entities are sorted alphabetically by `Name`.

## Generate Enemy Entities

The `enemies` command generates enemy entity definitions from
`misc/entities/Enemies.csv`.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- enemies misc/entities/Enemies.csv \
  > /tmp/enemies.zig
```

The CSV must contain the `Symbol`, `Name`, `Trait`, `Damage`, `Armor`, `HP`,
and `XP` columns. `Damage` accepts a range such as `1–2`; a numeric `Armor`
value is emitted as a fixed protection range. `Name` is converted to
`snake_case` for the entity and description preset names.

The output is a Zig source fragment with a file documentation comment and the
required imports. Immediately before the entity definitions, it includes an
alphabetized reference listing every distinct Trait found in the input and its
current component mapping. The generated definitions use `.bullets` for
`RNG(n)` weapons.
`SPD+`, `ATK+`, `SPD-`, `ATK-`, and `STATIC` are mapped to the corresponding
`Speed` presets where available. `F+`, `A+`, and `P+` are combined into one
`.improvements` component. `POISON`, `FIRE`, and `ACID` are weapon effects;
`ARM` uses the `Armor` value. Stat traits and any mapping still marked `TODO`
need review before replacing the hand-maintained `src/game/entities/enemies.zig`.
An unrecognized Trait stops generation and prints a diagnostic to standard
error explaining that support must be added both to the game code and to
`misc/tools/generate_enemies.zig`.

The generator does not sort enemy definitions; it preserves CSV row order.

## Generate Description Presets

The `descriptions` command generates description declarations from the `Name`
and `Description` columns of a CSV file. If the CSV also contains an
`Alt Description` column, its text is emitted as the `.alt_description` field.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- descriptions misc/entities/Food.csv
```

The output is a fragment for `src/game/descriptions.zig`. Insert it inside the
corresponding description group, such as `pub const Food = struct`.

Description and alternate description text are split into lines no longer than
35 characters. Additional spaces are distributed between words to justify
every line except the last. Generated description presets are sorted
alphabetically by `Name`.

## Generate Random Weights

The `weights` command generates `EnumMap` fields from the `Name`
and `RND Weight` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- weights misc/entities/Food.csv
```

The output can be inserted into the initializer passed to
`std.enums.EnumMap.init`.

## Generate Potion Entities

The `potions` command generates potion entity definitions from the
`Name`, `Price (known)`, and `Действие` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- potions misc/entities/Potions.csv \
  > src/game/entities/potions.zig
```

The entity, description preset, and `Potion` component names use the same
`snake_case` value. For example, `Bouillon` generates `bouillon` and
`.bouillon`.
An action in the form `Утоляет голод (N)` also generates a `Consumable`
component with `N` calories.
Generated potion entities are sorted alphabetically by `Name`.

## Generate Weapon Entities

The `weapons` command generates weapon entity definitions from
the `Name`, `Stat`, `Damage`, `Ammo`, `Range`, `Effect`, and `Price` columns of
a CSV file. The optional `Trait` column stores balance metadata such as `VAR`
and is not emitted into the runtime weapon definition.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- weapons misc/entities/Weapon.csv \
  > src/game/entities/weapons.zig
```

The `Damage` column must contain a range such as `3-5`. The `Stat` values
`STR`, `DEX`, and `INT` are mapped to the corresponding weapon classes.
An empty `Ammo` field generates a melee weapon. Otherwise, `Ammo` selects the
ranged weapon ammunition type. A non-empty `Effect` field adds the matching
elemental effect.
Generated weapon entities are sorted alphabetically by `Name`.

## Generate Armor Entities

The `armor` command generates armor entity definitions from the
`Name`, `Armor`, and `Price` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- armor misc/entities/Armor.csv \
  > src/game/entities/armor.zig
```

The `Armor` column must contain an integer range such as `1-3` or `1–3`.
The `Name` value is converted to `snake_case` and used both as the entity name
and as its description preset. Generated armor entities are sorted
alphabetically by `Name`.

## Generate Names as Enum Values

The `names-enum` command generates enum values from the `Name` column of
a CSV file.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- names-enum misc/entities/Potions.csv
```

The output uses lowercase `snake_case` values:

```zig
    healing,
    poison,
    oil,
```
