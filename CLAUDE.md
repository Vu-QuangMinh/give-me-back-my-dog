# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Give Me Back My Dog" is a Godot 4.6 grid-based tactical roguelike game. There is no build system — open `project.godot` in the Godot 4.6 editor and press F5 (or the Play button) to run.

The game is a **3D port** (`extends Node3D`). The hex grid lives in the XZ plane; entities are capsule meshes with `.glb` model children swapped by visibility.

## Architecture

All scripts and scenes live flat in the project root. `main.tscn` is the entry scene, driven by `main.gd`. See `DESIGN.md` for the authoritative game design spec.

**main.gd** (~3500 lines, `extends Node3D`) — Central controller and authoritative source of all game state. Owns the 3D hex grid, all entities, turn phases, projectile system, floor progression, modals, and input handling. All state mutations flow through here.

**Player.gd** — Stats (HP, armor, perfection/cockiness meter), weapon, passives, and action economy. Defines two character presets — **Sonny** (melee, pan, Boong charge bar; Q=charge attack, W=bomb placement) and **Mike** (ranged, slingshot, Draw Shot; Q=aim+timing, W=grapple gun 2 uses/map). Models are loaded from `MODEL_PATHS_BY_CHAR`; idle/run/attack swap by toggling `visible` on pre-instantiated children (not Godot AnimationPlayer injection — each .glb has its own library).

**enemy.gd** — All enemy types in one file via presets (`"grunt"`, `"archer"`, `"assassin"`, `"bomb"`, `"dummy"`). Defines stats, attack dicts, and AI behavior (`plan_action()`). Grunt uses AGGRESSIVE, Archer uses RANGER (keep 2–5 hex distance), Assassin uses AGGRESSIVE with dual_bar flag. Each instance calls `material_override.duplicate()` in `_ready()` to avoid shared material tinting.

**hextile.gd** — Hex tile types (`NORMAL`, `COLUMN`, `FIRE_PIT`), passability, and visual state. Tiles are flat-top 3D meshes in the XZ plane at `y=0`.

**hud.gd** (`GameHUD`, `CanvasLayer`) — Full HUD: player panel (avatar + slot column + HP head/mid/end gem bar), HYPE smooth-fill bar (gradient clip-rect), enemy panel (dynamic blocks with type-letter placeholder), 4 buttons (BACKPACK/UNDO/RESET/END_TURN), dialogue scroll. Public API called from `main.gd` via `_init_hud()` / `_refresh_hud()`. Signals: `backpack_pressed`, `undo_pressed`, `reset_pressed`, `end_turn_pressed`, `player_avatar_clicked(char_name)`.

**dodge_bar.gd** — Enemy melee dodge minigame. Ball travels left-to-right; SPACE freezes it. Perfect ±4%, dodge ±8%, else hit. Emits `bar_finished(result)`. Attached to `Camera3D` at local `(0, -0.18, -1.2)` — always in view.

**sonny_charge_bar.gd** — Boong (Sonny Q) charge mechanic. Hold LMB to push ball forward; release resolves: perfect ≥0.955, normal 0.895–0.954, miss <0.895. Emits `charge_resolved(result)`.

**mike_timing_bar.gd** — Draw Shot timing (3 steps: aim mode → lock direction → drag+release). Ball oscillates sinusoidally; drag shifts center. Perfect ±0.04, hit ±0.08. Emits `timing_resolved(result)`.

**bounce.gd** (`BounceTracer` RefCounted class) — Stateless 3D ray tracer on the XZ plane. Pre-computes projectile paths with exponential speed decay + wall/column/entity reflection. `stop_on_hit=false` so bounced projectiles can hit multiple enemies. Returns `{segs, hit_hexes}`. Used by both live projectile launch and Mike's aim preview.

**projectile.gd** — `Node3D` sphere mesh with emission + CPUParticles3D trail. Animates along pre-computed segments from `BounceTracer`. Emits `projectile_finished(hit_hexes)` when done. Visual only — all collision logic is in main.gd.

**aim_overlay.gd** — Draws Mike's 3D trajectory preview (BoxMesh segments stretched + rotated via `atan2`). First segment darker blue, bounces lighter + lower alpha. Updated each mouse-move during aim mode.

**world_map.gd** — World map node graph (not yet wired into combat-to-world-map-to-combat loop). Generates 2 nodes per floor clear using weighted angular distribution (70% forward, 15% diagonal, 15% wide). Persists state across scene changes via `Engine.meta`.

## Key constants

- Grid: 12 columns × 8 rows, `HEX_SIZE = 1.0` (world units, flat-top hex in XZ plane)
- `GROUND_Y = 0.2` — top surface of hex tile where entities stand
- `ACTION_DELAY = 0.5s` between sequential enemy actions
- `TWEEN_SPEED = 0.18s` for movement animation
- Enemy attack reaction windows: `perfect_window = 0.20s`, `ok_window = 0.40s`
- Projectile: `LAUNCH_SPEED = 18.0`, `DECAY_RATE = 0.85` (exponential), `MIN_SPEED = 1.0`
- Bomb: `BOMB_FUSE_TURNS = 2`, `BOMB_AOE_DAMAGE = 2`, `SONNY_BOMBS_PER_FLOOR = 1`
- Grapple: `MIKE_GRAPPLES_PER_FLOOR = 2`
- Floor progression: 5 floors, `FLOOR_SCENARIOS` array in main.gd (data-driven)

## Input reference

| Key | Action |
|-----|--------|
| Q | Primary attack (Sonny: start charge bar; Mike: enter aim mode) |
| W | Secondary action (Sonny: place bomb; Mike: grapple gun) |
| SPACE | End player turn / dodge bar freeze / projectile reaction |
| Tab | Switch active character |
| LMB | Move to tile / confirm attack / hold to charge / drag timing bar |
| D | Debug toggle |
| R | Camera orbit (right-mouse-drag) |
| `[` / `]` | Camera pitch |

## Turn phases and data flow

```
PLAYER_TURN → (Q attack or move click) → DODGE_PHASE or PLAYER_TURN
PLAYER_TURN → (SPACE or END TURN button) → ENEMY_TURN
ENEMY_TURN  → (action queue, sequential) → DODGE_PHASE or ENEMY_TURN
ENEMY_TURN  → (queue empty) → PLAYER_TURN
DODGE_PHASE → (bar/projectile resolved) → previous phase
FLOOR_CLEAR → (modal click/ENTER) → next floor or VICTORY
DEAD        → (modal click/ENTER) → restart from floor 0
```

1. Grid builds from `_current_scenario()` → players spawn → enemies spawn per `FLOOR_SCENARIOS[floor]`
2. Player selects move (BFS reachability) or attack (crescent/single/area/charge_bar/draw_shot)
3. Attack triggers a timing minigame; result determines damage multiplier
4. Enemy attacks trigger DodgeBar (all ranges currently; Mốc 9+ splits to projectile for ranged)
5. Clearing all enemies → `FLOOR_CLEAR` phase → modal → `_next_floor()` or VICTORY

## Combat mechanics

**Damage formula:** `base_dmg × (1.0 + perfection × 0.10) × hit_mult` where hit_mult = 1.5 (perfect), 1.0 (hit), 0.5 (miss).

**Perfection (cockiness):** 0–10 (doubled to 0–20 with `too_easy` passive). Increases on perfect timing/dodge; resets to 0 on missed attack or taking real damage. Drives the HYPE bar in HUD.

**Enemy attack dicts** (routed by main.gd): `{ range, damage, aoe, hits, speed, perfect_window, ok_window, dual_bar, speed_mults, hit_details }`. All attacks currently trigger DodgeBar regardless of range.

**Projectile system (Mike Draw Shot):** `_fire_bouncing_projectile()` uses BounceTracer to pre-compute the full 3D path (XZ plane), spawns `Projectile3D` to animate it, then resolves damage via `projectile_finished` signal. SPACE during a contact window triggers reaction — Sonny redirects (up to 3 times; 3rd = supercharge AoE), Mike dodges/counters. Supercharged projectile cannot be dodged.

**Status effects:** Bleed (stacks, ticks each player turn) and Disarm (turns remaining, blocks attack) are defined. Armor mitigation exists in `take_damage()` but armor is never inflicted in current code.

**Floor progression:** `_current_scenario()` reads from `FLOOR_SCENARIOS`. Boss floor (`is_boss=true`) shows VICTORY on clear; otherwise shows "Floor X CLEARED" and calls `_next_floor()`. State persists via `Engine.has_meta("current_floor")`.

## Hex math

Cube-coordinate conversion (used for distance and neighbors):
```gdscript
func to_cube(c, r):
    var x = c
    var z = r - (c - (c & 1)) / 2
    return Vector3i(x, -x - z, z)

func hex_dist(c1, r1, c2, r2):
    var a = to_cube(c1, r1); var b = to_cube(c2, r2)
    return maxi(maxi(abs(a.x-b.x), abs(a.y-b.y)), abs(a.z-b.z))
```

Neighbor offsets use parity (even vs odd column). This math is duplicated in enemy.gd and main.gd — not extracted to a shared utility.

**Line-of-sight** uses cube-coord interpolation + cube_round with ε-nudge. Columns block LOS; fire pits and entities do not.

## Test harness

`main_test.tscn` / `main_test.gd` were removed during the 3D port (they extended the 2D `main.gd`). There is currently no automated test scene. Use the in-game debug toggle (D key) and floor scenarios in `FLOOR_SCENARIOS` to configure specific combat setups.

## Workflow notes

- **After editing `main.gd`**: append a short summary of the changes to `temporary.md`.
- `problem.md` — notes on known bugs and design problems.
- `ideas.md` — feature brainstorming and future direction.
- `CHANGELOG.md` — per-milestone history; update when completing a milestone.

## Post-edit validation rule

After every edit to `main.gd`, run the project headlessly in Godot to check for GDScript errors. This is automated via the PostToolUse hook in `.claude/settings.json`, which runs `.claude/hooks/check_godot.sh`.

The hook filters output for lines referencing `.gd` files (actual GDScript parse/type errors). Engine-internal shutdown messages (`BUG: Unreferenced static string`, RID leak warnings) are noise — ignore them. If GDScript errors are reported, fix them before marking the task complete.

## What is scaffolded but not yet wired

- **Archer RANGER distance AI** — `plan_action()` has RANGER behavior defined but all enemy attacks still route through DodgeBar; ranged projectile path is planned for Mốc 9+
- **Assassin dual_bar** — Attack dict has `dual_bar: true` but main.gd doesn't spawn two sequential bars
- **Passives** — Rage, Executioner, Momentum, Too Easy, Insane Reflexes, Bloodthirsty defined in Player.gd but not wired into damage calc
- **World map → combat loop** — `world_map.gd` generates nodes and persists state, but combat-to-world-map-to-combat transition is not wired; floor progression uses hardcoded `FLOOR_SCENARIOS` instead
- **Reward cards, chests, forging** — Not started; HUD item slot assets exist (`pan_lv2-5`, `bomb_lv2-5`, etc.) but logic not wired
- **3D models for enemies/bomb** — Still capsule placeholders; `.glb` only exists for Sonny and Mike
- **Save/load** — `Engine.meta` persists floor only within session; no file-backed save
- **Audio** — No SFX or BGM wired
