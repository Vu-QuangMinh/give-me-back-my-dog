# Project Architecture: Give Me Back My Dog

## Overview
"Give Me Back My Dog" is a Godot 4.6 grid-based tactical roguelike. The game features turn-based combat on a hexagonal grid, a world map for progression, and unique mechanics for player actions and enemy behaviors. The project uses a flat file structure, with all scripts and scenes located in the project root.

## Key Components

### 1. **Main Controller**
- **File:** `main.gd`
- **Role:** Central controller for the game state, including grid management, turn phases, floor progression, and entity spawning.
- **Responsibilities:**
  - Handles player and enemy turns.
  - Manages the action queue and animations.
  - Coordinates combat mechanics, such as attacks and dodging.
  - Preloads and initializes key resources (e.g., `Player.gd`, `Enemy.gd`, `HexTile.gd`).

### 2. **Player System**
- **File:** `Player.gd`
- **Role:** Defines player stats, weapons, abilities, and action economy.
- **Details:**
  - Two characters: Sonny (melee-focused) and Mike (ranged-focused).
  - Each character has unique abilities (e.g., Sonny's charge bar, Mike's timing bar).
  - Weapons and abilities are defined in dictionaries for easy tuning.

### 3. **Enemy System**
- **File:** `enemy.gd`
- **Role:** Defines enemy types, stats, and AI behaviors.
- **Details:**
  - Enemy presets include Grunt, Archer, and others.
  - AI behaviors include aggressive melee, ranged attacks, and dummy behavior.
  - Supports complex attack patterns, such as AoE and multi-hit attacks.

### 4. **Grid and Tiles**
- **File:** `hextile.gd`
- **Role:** Manages hexagonal grid tiles.
- **Details:**
  - Tile types: Normal, Column (impassable), Fire Pit (damaging).
  - Handles tile passability and visual states.

### 5. **Minigames**
- **Dodge Bar:**
  - **File:** `dodge_bar.gd`
  - **Mechanic:** Timing-based minigame for dodging enemy attacks.
  - **Details:** Ball travels across a bar; player presses SPACE to stop it in the dodge zone.
- **Sonny's Charge Bar:**
  - **File:** `sonny_charge_bar.gd`
  - **Mechanic:** Hold and release to push a ball toward the target zone.
- **Mike's Timing Bar:**
  - **File:** `mike_timing_bar.gd`
  - **Mechanic:** Drag and release to align a ball with the target zone.

### 6. **Projectile System**
- **File:** `projectile.gd`
- **Role:** Visual representation of projectiles.
- **Details:**
  - Handles projectile appearance and animations.
  - Logic for trajectory and collisions is managed in `main.gd`.

### 7. **World Map**
- **File:** `world_map.gd`
- **Role:** Manages the overworld progression system.
- **Details:**
  - Generates nodes for each floor.
  - Tracks player progress toward the final goal (100 km).

### 8. **Utility Systems**
- **Bounce Tracer:**
  - **File:** `bounce.gd`
  - **Role:** Simulates projectile paths for Mike's aim preview.
- **Aim Overlay:**
  - **File:** `aim_overlay.gd`
  - **Role:** Visualizes Mike's trajectory during aim mode.

## Data Flow
1. **World Map:** Player selects a node to enter.
2. **Combat:**
   - Grid initializes with player and enemy spawns.
   - Player and enemies take turns performing actions.
   - Minigames resolve attacks and dodges.
3. **Progression:** Clearing all enemies advances the floor and updates the world map.

## Constants
- **Grid Size:** 12 columns × 8 rows.
- **Tile Size:** `HEX_SIZE = 38.0`.
- **Turn Timing:**
  - `ACTION_DELAY = 0.5s`
  - `TWEEN_SPEED = 0.18s`

## Notes
- The project is modular, with each system encapsulated in its own script.
- Minigames and mechanics are highly customizable via constants and dictionaries.
- The architecture supports easy addition of new characters, enemies, and mechanics.