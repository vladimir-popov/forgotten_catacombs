# Tools

## Generate Food Entities

The `generate_food.zig` script generates Zig entity definitions from
`misc/entities/Food.csv`.

Run it from the project root:

```sh
zig run misc/tools/generate_food.zig -- misc/entities/Food.csv \
  > src/game/entities/food.zig
```

The script reads the `Name`, `Calories`, `Price`, and `Description` columns.
The description text is not copied to the generated file. Instead, the
`Name` value is converted to `snake_case` and used as the description preset.

For example, `Traveler Ration` becomes `traveler_ration`.

The description presets referenced by the generated code must be declared in
`src/game/descriptions.zig` separately.

## Generate Description Presets

The `generate_descriptions.zig` script generates description declarations from
the `Name` and `Description` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/generate_descriptions.zig -- misc/entities/Food.csv
```

The output is a fragment for `src/game/descriptions.zig`. Insert it inside the
corresponding description group, such as `pub const Food = struct`.

Description text is split into lines no longer than 35 characters. Additional
spaces are distributed between words to justify every line except the last.

## Generate Random Weights

The `generate_weights.zig` script generates `EnumMap` fields from the `Name`
and `RND Weight` columns of a CSV file.

Run it from the project root:

```sh
zig run misc/tools/generate_weights.zig -- misc/entities/Food.csv
```

The output can be inserted into the initializer passed to
`std.enums.EnumMap.init`.
