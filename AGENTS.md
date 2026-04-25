# AGENTS.md

## Project Overview

**Give Me Back My Dog** is a Godot 4.6 grid-based tactical roguelike. Open `project.godot` in Godot 4.6 and press F5 to run.

## Key Architecture & Conventions
- **Flat file structure:** All scripts and scenes are in the project root.
- **Main.gd:** Central controller for grid, turn phases, floor progression, and entity spawning. Authoritative game state.
- **Player.gd:** Player stats, weapons, passives, and action economy. Q/W for combat actions.
- **Item.gd:** Weapon types, ranks, prefixes, and gem sockets (data only).
- **Grunt.gd:** Enemy entity, HP, status effects, dodge bar integration.
- **HexTile.gd:** Tile types and visual state.
- **DodgeBar.gd:** Dodge minigame (timing bar, perfect/normal zones).

## Development & Testing
- **No build/test scripts:** Run directly in Godot editor.
- **Key constants:**
  - Grid: 9×10, `HEX_SIZE = 38.0`
  - `MOVE_RANGE = 2`, `ACTION_DELAY = 0.5s`, `TWEEN_SPEED = 0.18s`
- **Floor enemy compositions:** Deterministic arrays in Main.gd (floors 1–10).

## Data Flow
1. Grid builds → Player spawns at (4,5) → Enemies spawn per floor
2. Player selects move (BFS) or attack (AoE pattern)
3. Enemies act sequentially with delay
4. On hit, DodgeBar minigame resolves
5. Clearing all enemies advances floor, scales difficulty, offers loot

## Documentation
- [DESIGN.md](DESIGN.md): Full game design, mechanics, controls, file structure, and implementation status.
- [CLAUDE.md](CLAUDE.md): Additional agent guidance (Claude-specific).

## Agent Guidance
- **Link, don’t duplicate:** Reference DESIGN.md for mechanics, controls, and file structure.
- **Minimal by default:** Only include what’s not easily discoverable; link to docs for details.
- **Concise and actionable:** Every line should guide agent behavior.

---

For details on mechanics, controls, or file structure, see [DESIGN.md](DESIGN.md).
For Claude-specific instructions, see [CLAUDE.md](CLAUDE.md).
