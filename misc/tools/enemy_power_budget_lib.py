"""Infrastructure for the enemy power-budget notebook.

The notebook intentionally keeps configuration and experiments visible. CSV
parsing, report calculations, HTML rendering, and persistence live here so
they do not obscure the balance model.
"""

from __future__ import annotations

import csv
import json
import re
from dataclasses import asdict, dataclass
from decimal import Decimal, ROUND_HALF_UP
from html import escape
from pathlib import Path
from typing import Any, Iterable, Sequence

from IPython.display import HTML, display


@dataclass(frozen=True)
class Enemy:
    """Normalized source data for one enemy from Enemies.csv."""

    symbol: str
    name: str
    tier: int
    traits: tuple[str, ...]
    minimum_damage: float
    maximum_damage: float
    armor: float
    hp: float

    @property
    def average_damage(self) -> float:
        return (self.minimum_damage + self.maximum_damage) / 2


@dataclass(frozen=True)
class BalanceRules:
    """All adjustable coefficients used by the enemy balance model.

    Power is split between traits and base stats. Enemy TTK measures player
    hits needed to kill an enemy. Player TTK measures enemy hits needed to
    kill the reference player.
    """

    base_tier_power: float
    power_gained_per_tier: float
    power_unit: float
    hp_per_power_unit: float
    damage_per_power_unit: float
    damage_range_fraction: float
    characteristic_weights: dict[str, float]
    enemy_ttk_range: tuple[float, float]
    armored_enemy_ttk_range: tuple[float, float]
    player_hp_base: float
    player_hp_per_level: float
    player_health_coefficient: float
    player_health_reference: float
    player_ttk_range: tuple[float, float]


def find_project_root(start: Path = Path.cwd()) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "misc/entities/Enemies.csv").exists():
            return candidate
    raise FileNotFoundError("Could not find misc/entities/Enemies.csv")


def _format_value(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{value:.2f}" if isinstance(value, float) else str(value)


def show_table(rows: Sequence[dict[str, Any]], columns: Sequence[str]) -> None:
    header = "".join(f"<th>{escape(column)}</th>" for column in columns)
    body = "".join(
        "<tr>" + "".join(
            f"<td>{escape(_format_value(row.get(column)))}</td>" for column in columns
        ) + "</tr>"
        for row in rows
    )
    display(HTML(
        "<style>table.balance{border-collapse:collapse;font-family:sans-serif;font-size:13px}"
        "table.balance th{background:#244a64;color:white;text-align:left}"
        "table.balance th,table.balance td{border:1px solid #ccd5dc;padding:5px 8px}"
        "table.balance tbody tr:nth-child(even){background:#f5f7f8}</style>"
        f"<table class='balance'><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table>"
    ))


def _parse_range(raw: str) -> tuple[float, float]:
    bounds = [float(value) for value in re.split(r"[–-]", raw)]
    if len(bounds) != 2:
        raise ValueError(f"Invalid numeric range: {raw}")
    return bounds[0], bounds[1]


def _parse_traits(raw: str) -> tuple[str, ...]:
    value = raw.strip()
    if not value or value == "—":
        return ()
    return tuple(token.strip() for token in value.replace("\n", ",").split(",") if token.strip())


def load_enemies(path: Path) -> list[Enemy]:
    result = []
    with path.open(encoding="utf-8", newline="") as source_file:
        for row in csv.DictReader(source_file, delimiter=";"):
            minimum, maximum = _parse_range(row["Урон"])
            result.append(Enemy(
                symbol=row["Symbol"],
                name=row["English Name"],
                tier=int(row["Tier"]),
                traits=_parse_traits(row["Особенности"]),
                minimum_damage=minimum,
                maximum_damage=maximum,
                armor=float(row["Броня"]) if row["Броня"].strip() else 0.0,
                hp=float(row["HP"]),
            ))
    return result


def load_player_armor_references(path: Path) -> dict[int, float]:
    """Return mean armor midpoint for every tier represented in Armor.csv."""
    values: dict[int, list[float]] = {}
    with path.open(encoding="utf-8", newline="") as source_file:
        for row in csv.DictReader(source_file, delimiter=";"):
            minimum, maximum = _parse_range(row["Armor"])
            values.setdefault(int(row["Peak"]), []).append((minimum + maximum) / 2)
    return {tier: sum(items) / len(items) for tier, items in values.items()}


def trait_category(trait: str) -> str | None:
    if trait.startswith("RNG("):
        return "range"
    if trait in {"ATK+", "ATK-"}:
        return "attack_speed"
    if trait in {"DEX+", "DEX-"}:
        return "dodge"
    if trait in {"SPD+", "SPD-"}:
        return "movement_speed"
    if trait == "ARM":
        return "armor"
    if trait in {"PER+", "PER-"}:
        return "accuracy"
    if trait in {"FIRE", "ACID", "POISON"}:
        return "elemental_effect"
    if trait in {"F+", "F-", "A+", "A-", "P+", "P-"}:
        return "resistance_or_vulnerability"
    return None


def tier_power(tier: int, model: BalanceRules) -> float:
    return model.base_tier_power + model.power_gained_per_tier * (tier - 1)


def trait_power_breakdown(
    traits: Iterable[str], tier: int, model: BalanceRules
) -> list[dict[str, Any]]:
    result = []
    for trait in traits:
        category = trait_category(trait)
        weight = model.characteristic_weights.get(category, 0.0)
        result.append({
            "trait": trait,
            "category": category or "unpriced",
            "weight_percent": weight * 100,
            "power_cost": tier_power(tier, model) * weight,
        })
    return result


def trait_power_cost(traits: Iterable[str], tier: int, model: BalanceRules) -> float:
    return sum(item["power_cost"] for item in trait_power_breakdown(traits, tier, model))


def _allocate_remaining_power(power: float, model: BalanceRules) -> tuple[float, float]:
    hp_weight = model.characteristic_weights["hp"]
    damage_weight = model.characteristic_weights["damage"]
    total = hp_weight + damage_weight
    return (
        power * hp_weight / total / model.power_unit * model.hp_per_power_unit,
        power * damage_weight / total / model.power_unit * model.damage_per_power_unit,
    )


def round_half_up(value: float) -> int:
    """Round to the nearest integer, resolving exact halves away from zero."""
    return int(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _damage_range(average_damage: float, model: BalanceRules) -> tuple[int, int]:
    center = max(1, round_half_up(average_damage))
    half_width = max(1, round_half_up(center * model.damage_range_fraction))
    return max(1, center - half_width), center + half_width


def _stat_power_cost(hp: float, damage: float, model: BalanceRules) -> float:
    return (
        hp / model.hp_per_power_unit * model.power_unit
        + damage / model.damage_per_power_unit * model.power_unit
    )


def _ttk_in_hits(hp: float, incoming_damage: float, armor: float) -> float | None:
    effective_damage = incoming_damage - armor
    return hp / effective_damage if effective_damage > 0 else None


def _ttk_status(ttk: float | None, target: tuple[float, float]) -> str:
    if ttk is None:
        return "damage blocked by armor"
    if ttk < target[0]:
        return "below target"
    if ttk > target[1]:
        return "above target"
    return "within target"


def player_hp_at_level(level: int, model: BalanceRules) -> float:
    """Calculate reference HP with the progression formula from game_mechanics.md."""
    health_multiplier = 1 + model.player_health_coefficient * model.player_health_reference
    return model.player_hp_base + level * model.player_hp_per_level * health_multiplier


def build_tier_report(
    tier: int,
    all_enemies: Sequence[Enemy],
    player_armor_by_tier: dict[int, float],
    model: BalanceRules,
) -> list[dict[str, Any]]:
    tier_enemies = [enemy for enemy in all_enemies if enemy.tier == tier]
    if not tier_enemies:
        raise ValueError(f"No enemies found for tier {tier}")
    if tier not in player_armor_by_tier:
        raise ValueError(f"No player armor reference found for tier {tier}")

    available = tier_power(tier, model)
    allocations = []
    for enemy in tier_enemies:
        trait_cost = trait_power_cost(enemy.traits, tier, model)
        remaining = available - trait_cost
        raw_hp, raw_damage = _allocate_remaining_power(remaining, model)
        target_hp = max(1, round_half_up(raw_hp))
        minimum_damage, maximum_damage = _damage_range(raw_damage, model)
        target_damage = (minimum_damage + maximum_damage) // 2
        allocations.append((
            enemy, trait_cost, remaining, target_hp, target_damage,
            minimum_damage, maximum_damage,
        ))

    player_damage = sum(item[4] for item in allocations) / len(allocations)
    player_armor = player_armor_by_tier[tier]
    player_level = tier
    player_hp = player_hp_at_level(player_level, model)
    report = []
    for (
        enemy, trait_cost, remaining, target_hp, target_damage,
        minimum_damage, maximum_damage,
    ) in allocations:
        enemy_ttk_target = (
            model.armored_enemy_ttk_range if "ARM" in enemy.traits else model.enemy_ttk_range
        )
        if "ARM" in enemy.traits:
            target_ttk_midpoint = sum(model.armored_enemy_ttk_range) / 2
            raw_armor = player_damage - target_hp / target_ttk_midpoint
            target_armor = max(0, min(round_half_up(raw_armor), max(0, round_half_up(player_damage) - 1)))
        else:
            target_armor = 0
        enemy_ttk = _ttk_in_hits(target_hp, player_damage, target_armor)
        player_ttk = _ttk_in_hits(player_hp, target_damage, player_armor)
        report.append({
            "enemy": enemy.name,
            "traits": ", ".join(enemy.traits) if enemy.traits else "—",
            "available_power": available,
            "trait_power": trait_cost,
            "remaining_power": remaining,
            "target_hp": target_hp,
            "target_minimum_damage": minimum_damage,
            "target_maximum_damage": maximum_damage,
            "target_average_damage": target_damage,
            "target_armor": target_armor,
            "player_damage_reference": player_damage,
            "enemy_ttk_hits": enemy_ttk,
            "enemy_ttk_target": f"{enemy_ttk_target[0]:g}–{enemy_ttk_target[1]:g}",
            "enemy_ttk_status": _ttk_status(enemy_ttk, enemy_ttk_target),
            "player_level_reference": player_level,
            "player_hp_reference": player_hp,
            "player_armor_reference": player_armor,
            "player_ttk_hits": player_ttk,
            "player_ttk_target": f"{model.player_ttk_range[0]:g}–{model.player_ttk_range[1]:g}",
            "player_ttk_status": _ttk_status(player_ttk, model.player_ttk_range),
            "csv_hp": enemy.hp,
            "csv_average_damage": enemy.average_damage,
            "csv_armor": enemy.armor,
            "csv_total_power": _stat_power_cost(enemy.hp, enemy.average_damage, model) + trait_cost,
        })
    return report


REPORT_COLUMNS = (
    "enemy",
    "enemy_ttk_hits", "enemy_ttk_target", "enemy_ttk_status",
    "player_ttk_hits", "player_ttk_target", "player_ttk_status",
    "traits", "available_power", "trait_power", "remaining_power",
    "target_hp", "target_minimum_damage", "target_maximum_damage",
    "target_average_damage", "target_armor", "player_damage_reference",
    "player_level_reference", "player_hp_reference", "player_armor_reference",
    "csv_hp", "csv_average_damage", "csv_armor", "csv_total_power",
)


RULES_START = "# RULES_START: managed by the synchronization cell at the end of this notebook."
RULES_END = "# RULES_END"
MARKDOWN_START = "<!-- ENEMY_POWER_RULES_START -->"
MARKDOWN_END = "<!-- ENEMY_POWER_RULES_END -->"

_CHARACTERISTIC_LABELS = {
    "hp": "HP",
    "damage": "Damage",
    "range": "Range",
    "attack_speed": "Attack speed",
    "dodge": "Dodge",
    "movement_speed": "Movement speed",
    "armor": "Armor",
    "accuracy": "Accuracy",
    "elemental_effect": "Elemental effect",
    "resistance_or_vulnerability": "Resistance or vulnerability",
}


def _compact_number(value: float) -> str:
    return f"{value:g}"


def _replace_managed_block(text: str, start: str, end: str, replacement: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError(f"Expected exactly one block delimited by {start!r} and {end!r}")
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    return before + replacement + after


def _write_atomically(path: Path, text: str) -> None:
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(text, encoding="utf-8")
    temporary_path.replace(path)


def _render_enemy_csv(
    path: Path,
    armor_path: Path,
    model: BalanceRules,
) -> str:
    """Render Enemies.csv with calculated integer HP, damage, and armor."""
    enemies = load_enemies(path)
    armor_by_tier = load_player_armor_references(armor_path)
    tiers = sorted({enemy.tier for enemy in enemies})
    reports = {
        row["enemy"]: row
        for tier in tiers
        for row in build_tier_report(tier, enemies, armor_by_tier, model)
    }

    with path.open(encoding="utf-8", newline="") as source_file:
        reader = csv.DictReader(source_file, delimiter=";")
        fieldnames = reader.fieldnames
        if fieldnames is None:
            raise ValueError(f"Missing CSV header: {path}")
        rows = list(reader)

    from io import StringIO

    output = StringIO(newline="")
    writer = csv.DictWriter(
        output,
        fieldnames=fieldnames,
        delimiter=";",
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    writer.writeheader()
    for row in rows:
        calculated = reports[row["English Name"]]
        row["Урон"] = (
            f"{calculated['target_minimum_damage']}–{calculated['target_maximum_damage']}"
        )
        row["Броня"] = str(calculated["target_armor"]) if calculated["target_armor"] else ""
        row["HP"] = str(calculated["target_hp"])
        writer.writerow(row)
    return output.getvalue()


def _render_rules_source(model: BalanceRules) -> str:
    lines = [RULES_START, "RULES = BalanceRules("]
    for name in (
        "base_tier_power", "power_gained_per_tier", "power_unit",
        "hp_per_power_unit", "damage_per_power_unit", "damage_range_fraction",
    ):
        lines.append(f"    {name}={_compact_number(getattr(model, name))},")
    lines.append("    characteristic_weights={")
    for name, value in model.characteristic_weights.items():
        lines.append(f'        "{name}": {value:.2f},')
    lines.extend([
        "    },",
        f"    enemy_ttk_range=({_compact_number(model.enemy_ttk_range[0])}, {_compact_number(model.enemy_ttk_range[1])}),",
        f"    armored_enemy_ttk_range=({_compact_number(model.armored_enemy_ttk_range[0])}, {_compact_number(model.armored_enemy_ttk_range[1])}),",
        f"    player_hp_base={_compact_number(model.player_hp_base)},",
        f"    player_hp_per_level={_compact_number(model.player_hp_per_level)},",
        f"    player_health_coefficient={_compact_number(model.player_health_coefficient)},",
        f"    player_health_reference={_compact_number(model.player_health_reference)},",
        f"    player_ttk_range=({_compact_number(model.player_ttk_range[0])}, {_compact_number(model.player_ttk_range[1])}),",
        ")",
        RULES_END,
    ])
    return "\n".join(lines)


def _render_markdown_rules(model: BalanceRules) -> str:
    lines = [
        MARKDOWN_START,
        "### Enemy Power Model Parameters",
        "",
        "This block is generated by `misc/tools/enemy_power_budget_python.ipynb`.",
        "",
        "Tier power:",
        "",
        "```text",
        f"tier_power = {_compact_number(model.base_tier_power)} + {_compact_number(model.power_gained_per_tier)} x (tier - 1)",
        "```",
        "",
        "Stat conversions:",
        "",
        "| Conversion | Result |",
        "| ---------- | ------ |",
        f"| `{_compact_number(model.power_unit)} power` | `{_compact_number(model.hp_per_power_unit)} HP` |",
        f"| `{_compact_number(model.power_unit)} power` | `{_compact_number(model.damage_per_power_unit)} average damage` |",
        f"| Damage half-width | `{model.damage_range_fraction:.0%}` of rounded average damage |",
        "",
        "Calculated HP, damage bounds, and armor use round-half-up integer rounding.",
        "Armor is calculated only for the `ARM` trait from the midpoint of the armored enemy TTK target.",
        "",
        "Characteristic weights:",
        "",
        "| Characteristic | Weight |",
        "| -------------- | ------ |",
    ]
    for name, value in model.characteristic_weights.items():
        lines.append(f"| {_CHARACTERISTIC_LABELS.get(name, name)} | `{value:.0%}` |")
    lines.extend([
        "",
        "TTK references and targets:",
        "",
        "| Measurement | Value |",
        "| ----------- | ----- |",
        f"| Enemy without armor | `{_compact_number(model.enemy_ttk_range[0])} .. {_compact_number(model.enemy_ttk_range[1])}` player hits |",
        f"| Armored enemy | `{_compact_number(model.armored_enemy_ttk_range[0])} .. {_compact_number(model.armored_enemy_ttk_range[1])}` player hits |",
        "| Reference player level | Same as enemy tier |",
        f"| Player HP formula | `{_compact_number(model.player_hp_base)} + level x {_compact_number(model.player_hp_per_level)} x (1 + {_compact_number(model.player_health_coefficient)} x health)` |",
        f"| Reference player health | `{_compact_number(model.player_health_reference)}` |",
        f"| Player survivability | `{_compact_number(model.player_ttk_range[0])} .. {_compact_number(model.player_ttk_range[1])}` enemy hits |",
        MARKDOWN_END,
    ])
    return "\n".join(lines)


def synchronize_rules(
    model: BalanceRules,
    notebook_path: Path,
    markdown_targets: tuple[Path, ...],
    enemy_csv_path: Path,
    armor_csv_path: Path,
) -> None:
    """Promote an experiment to defaults, documentation, and enemy stats."""
    notebook = json.loads(notebook_path.read_text(encoding="utf-8"))
    matching_cells = []
    for cell in notebook["cells"]:
        source_lines = {line.strip() for line in cell.get("source", [])}
        if RULES_START in source_lines and RULES_END in source_lines:
            matching_cells.append(cell)
    if len(matching_cells) != 1:
        raise ValueError(f"Expected one managed RULES cell, found {len(matching_cells)}")

    cell = matching_cells[0]
    source = "".join(cell["source"])
    updated = _replace_managed_block(source, RULES_START, RULES_END, _render_rules_source(model))
    cell["source"] = updated.splitlines(keepends=True)
    notebook_text = json.dumps(notebook, ensure_ascii=False, indent=1) + "\n"

    markdown_updates = []
    for path in markdown_targets:
        original = path.read_text(encoding="utf-8")
        markdown_updates.append((path, _replace_managed_block(
            original, MARKDOWN_START, MARKDOWN_END, _render_markdown_rules(model)
        )))
    enemy_csv_text = _render_enemy_csv(enemy_csv_path, armor_csv_path, model)

    _write_atomically(notebook_path, notebook_text)
    for path, text in markdown_updates:
        _write_atomically(path, text)
    _write_atomically(enemy_csv_path, enemy_csv_text)

    print("Updated:")
    print(f"  {notebook_path}")
    for path, _ in markdown_updates:
        print(f"  {path}")
    print(f"  {enemy_csv_path}")
    print("Reload this notebook from disk now, then review git diff before committing.")
