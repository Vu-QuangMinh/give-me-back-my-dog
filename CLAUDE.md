# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Give Me Back My Dog" is a Godot 4.6 grid-based tactical roguelike game. There is no build system — open `project.godot` in the Godot 4.6 editor and press F5 (or the Play button) to run.

## Architecture

All scripts and scenes live flat in the project root. `main.tscn` is the entry scene, driven by `main.gd`. See `DESIGN.md` (v1.6) for the authoritative game design spec.

**main.gd** (~3500 lines) — Central controller and authoritative source of all game state. Owns the grid, all entities, turn phases, projectile system, UI labels, and input handling. All state mutations flow through here.

**Player.gd** — Stats (HP, armor, perfection/cockiness meter), weapon, passives, and action economy. Defines two character presets — **Sonny** (melee, pan, Boong charge bar; Q=charge attack, W=bomb placement) and **Mike** (ranged, slingshot, Draw Shot; Q=aim+timing, W=grapple gun 2 uses/map).

**enemy.gd** — All enemy types in one file via presets (`"grunt"`, `"archer"`, `"assassin"`, `"bomb"`, `"dummy"`). Defines stats, attack dicts, and AI behavior (`plan_action()`). Grunt uses AGGRESSIVE, Archer uses RANGER (keep 2–5 hex distance), Assassin uses AGGRESSIVE with dual_bar flag.

**hextile.gd** — Hex tile types (`NORMAL`, `COLUMN`, `FIRE_PIT`), passability, and visual state.

**dodge_bar.gd** — Enemy melee dodge minigame. Ball travels left-to-right; SPACE freezes it. Perfect ±4%, dodge ±8%, else hit. Emits `bar_finished(result)`.

**sonny_charge_bar.gd** — Boong (Sonny Q) charge mechanic. Hold LMB to push ball forward; release resolves: perfect ≥0.85, normal 0.65–0.84, miss <0.65. Emits `charge_resolved(result)`.

**mike_timing_bar.gd** — Draw Shot timing (3 steps: aim mode → lock direction → drag+release). Ball oscillates sinusoidally; drag shifts center. Perfect ±0.04, hit ±0.08. Emits `timing_resolved(result)`.

**bounce.gd** (`BounceTracer` RefCounted class) — Stateless pixel-space ray tracer. Pre-computes projectile paths with wall/column bounces. Returns `{segs, hit_hexes}`. Used by both live projectile launch and Mike's aim preview.

**projectile.gd** — Visual only (circle scales with `redirect_count`, blinks red when supercharged). All collision/physics logic is in main.gd.

**world_map.gd** — World map node graph. Generates 2 nodes per floor clear using weighted angular distribution (70% forward, 15% diagonal, 15% wide). Persists state across scene changes via `Engine.meta`. Tracks time and km distance toward 100 km goal.

**aim_overlay.gd** — Draws Mike's trajectory preview (blue line segments with arrowheads). Updated each mouse-move during aim mode.

**bomb.gd** — Visual only for Sonny's W bomb. Actual bomb entity is an Enemy with `type="bomb"`.

## Key constants

- Grid: 12 columns × 8 rows, `HEX_SIZE = 38.0` px
- `ACTION_DELAY = 0.5s` between sequential enemy actions
- `TWEEN_SPEED = 0.18s` for movement animation
- Enemy attack reaction windows: `perfect_window = 0.20s`, `ok_window = 0.40s`
- Character spawns (Player.gd presets): Sonny at col=5 row=1, Mike at col=6 row=1, both `move_range = 2`
- World map: 100 km total, 10–15 km per node, 10 floors

## Input reference

| Key | Action |
|-----|--------|
| Q | Primary attack (Sonny: start charge bar; Mike: enter aim mode) |
| W | Secondary action (Sonny: place bomb; Mike: grapple gun) |
| SPACE | End player turn / dodge bar freeze / projectile reaction |
| Tab | Switch active character |
| LMB | Move to tile / confirm attack / hold to charge / drag timing bar |
| D | Debug toggle |

## Turn phases and data flow

```
PLAYER_TURN → (Q attack or move click) → DODGE_PHASE or PLAYER_TURN
PLAYER_TURN → (SPACE) → ENEMY_TURN
ENEMY_TURN  → (action queue, sequential) → DODGE_PHASE or ENEMY_TURN
ENEMY_TURN  → (queue empty) → PLAYER_TURN
DODGE_PHASE → (bar/projectile resolved) → previous phase
DEAD        → (ENTER) → restart
```

1. Grid builds → Sonny spawns (5,1), Mike spawns (6,1) → enemies spawn per floor
2. Player selects move (BFS reachability) or attack (crescent/single/area/charge\_bar/draw\_shot)
3. Attack triggers a timing minigame; result determines damage multiplier
4. Enemy attacks trigger DodgeBar (melee, range==1) or projectile (Archer, range>1); SPACE reacts
5. Clearing all enemies → floor clear → world map transition

## Combat mechanics

**Damage formula:** `base_dmg × (1.0 + perfection × 0.10) × hit_mult` where hit\_mult = 1.5 (perfect), 1.0 (hit), 0.5 (miss).

**Perfection (cockiness):** 0–10 (doubled to 0–20 with `too_easy` passive). Increases on perfect timing/dodge; resets to 0 on missed attack or taking real damage.

**Enemy attack dicts** (routed by main.gd): `{ range, damage, aoe, hits, speed, perfect_window, ok_window, dual_bar, speed_mults, hit_details }`. Range==1 → dodge bar, range>1 → projectile.

**Projectile system:** `_launch_projectile()` uses BounceTracer to pre-compute the full path, then detects which players intersect which segments and at what time. `live_proj_states[]` tracks in-flight projectiles per-frame. SPACE during a contact window triggers `_proj_resolve_reaction()` — Sonny redirects (up to 3 times; 3rd = supercharge AoE), Mike dodges/counters. Supercharged projectile cannot be dodged.

**Status effects:** Bleed (stacks, ticks each player turn) and Disarm (turns remaining, blocks attack) are defined. Armor mitigation exists in `take_damage()` but armor is never inflicted in current code.

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

## What is scaffolded but not yet wired

- **Floor enemy compositions** — Arrays defined in main.gd but currently empty; enemies must be populated per floor
- **Archer RANGER distance AI** — `plan_action()` has RANGER behavior defined but `range_min`/`range_max` not fully wired to turn logic
- **Assassin dual_bar** — Attack dict has `dual_bar: true` but main.gd doesn't spawn two sequential bars
- **Passives** — Rage, Executioner, Momentum, Too Easy, Insane Reflexes, Bloodthirsty defined in Player.gd but not wired into damage calc
- **Projectile velocity decay** — DESIGN.md v1.6 specifies exponential decay (`exp(-PROJ_DECAY_RATE*delta)`); current code uses constant speed
- **World map → combat loop** — World map generates nodes and persists state, but combat-to-world-map-to-combat transition is partially wired
- **Reward cards, chests, forging** — Not started
