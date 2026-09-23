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
`src/game/descriptions.zig` separately.
Generated food entities are sorted alphabetically by `Name`.

## Generate Description Presets

The `descriptions` command generates description declarations from
the `Name` and `Description` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/main.zig -- descriptions misc/entities/Food.csv
```

The output is a fragment for `src/game/descriptions.zig`. Insert it inside the
corresponding description group, such as `pub const Food = struct`.

Description text is split into lines no longer than 35 characters. Additional
spaces are distributed between words to justify every line except the last.
Generated description presets are sorted alphabetically by `Name`.

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
