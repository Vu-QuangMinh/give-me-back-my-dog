# GIVE ME BACK MY DOG — Game Design Document
> Version: 1.4
> Engine: Godot 4, GDScript
> Genre: Roguelite, Turn-based tactics, Hex grid dungeon crawler

---

## TABLE OF CONTENTS
1. [Story & Concept](#1-story--concept)
2. [Core Loop](#2-core-loop)
3. [World Map](#3-world-map)
4. [Map & Grid (Combat)](#4-map--grid-combat)
5. [Characters — Sonny & Mike](#5-characters--sonny--mike)
5B. [Projectile System](#5b-projectile-system)
6. [Actions & Turn System](#6-actions--turn-system)
7. [Weapons & Abilities](#7-weapons--abilities)
8. [Combat — Attack Bar](#8-combat--attack-bar)
9. [Combat — Dodge Bar](#9-combat--dodge-bar)
10. [Cockiness](#10-cockiness)
11. [Damage Formula](#11-damage-formula)
12. [Status Effects](#12-status-effects)
13. [Enemies](#13-enemies)
14. [Items & Prefixes](#14-items--prefixes)
15. [Backpack & Equipment](#15-backpack--equipment)
16. [Forging & Smelting](#16-forging--smelting)
17. [Floors & Progression](#17-floors--progression)
18. [Objectives](#18-objectives)
19. [Chests & Rewards](#19-chests--rewards)
20. [Every-3-Floor Menu](#20-every-3-floor-menu)
21. [Skills & Passives](#21-skills--passives)
22. [UI Layout](#22-ui-layout)
23. [File Structure](#23-file-structure)
24. [Implementation Status](#24-implementation-status)

---

## 1. STORY & CONCEPT

### Prologue / Tutorial Hook
Death appears and tells **Sonny** he has **180 minutes** to travel **100 km** to save his dog.

Sonny gets his father's car and declares:
> *"We can travel 120 km/h — we'll be there in 50 minutes!"*

**Mike** counters:
> *"You haven't considered acceleration, deceleration, stop signs, red lights, deer on the road..."*

Sonny replies:
> *"We're in a video game — the laws of physics and travel safety can be ignored."*

> ⚠️ **In-Game Disclaimer:** In real life, children should never drive. Always drive safely in any situation.

---

### Act Structure

| Act | Player Controls | Goal | Final Boss |
|-----|-----------------|------|------------|
| 1 | Sonny + Mike | Chase Death for 100km. Death appears periodically as a tutorial guide. | Death |
| 2 | Sonny + Mike | Fight through Heaven. God reveals the dog's soul went to Hell. | God |
| 3 | Sonny + Mike | Fight through Hell. Retrieve dog's soul. Become trapped. | Cerberus |
| 4 (Reverse) | The Dog | Hell → Heaven → Death to rescue the players. | — |
| Final | Both simultaneously | Defeat Death. | Death |

> **Act 1 only is implemented currently (10 floors).**

---

## 2. CORE LOOP

### Time Constraint
- Each Act: **180 minutes** to travel **100 km** to the end stage.
- **Loss condition:** Timer hits 0 before reaching the end stage → dog is lost forever.
- Timer decrements **1 minute per combat turn** the player takes.
- Timer decrements **1 minute per 2 km** travelled on the world map.

### Combat Loop
```
Enter zone
  → Kill all enemies
Receive rewards (3 cards with different options)
When you pick a card, update the game state and is back in world map. When a new node is selected in world map, enter that zone. Repeat
```

---

## 3. WORLD MAP

### Overview
- A long **horizontal map** with node-based navigation.
- Initially shows only the **start node** (0 km) and **end stage** (100 km).
- After clearing each floor, return to the world map: **2 new nodes revealed**, each connected to the current node by a line.

### Node Spawning Rules

**Axis:** Horizontal line from start (0 km) to end (100 km) = 0°.

**Distance from current node:** 1–10 km (float, 1 decimal place).

**Angular distribution:**

| Zone | Angle Range | Spawn Weight |
|------|-------------|--------------|
| Primary | −45° to +45° | 70% |
| Secondary | −90° to −45° and +45° to +90° | 15% |
| Tertiary | −135° to −90° and +90° to +135° | 15% |

**Anti-collision rules:**
- Minimum distance between any two nodes: **1.5 km** (Euclidean).
- On collision: resample up to **10 times**, then discard the attempt.

**Scattering logic (weighted repulsion):**
- For each candidate position, compute the sum of inverse-squared distances to all existing nodes.
- Accept only if repulsion score is below a configurable threshold.
- Among valid candidates, prefer the one with the **lowest repulsion score** (most isolated).

### End Stage Proximity Rules

| Distance to End Stage | Node Behavior |
|-----------------------|---------------|
| > 10 km | 2 new nodes revealed normally |
| ≤ 10 km | 1 new node revealed; 2nd line always points directly to end stage |
| ≤ 5 km | No new nodes; only option is the end stage |

### World Map Counters

| Counter | Location | Update Trigger |
|---------|----------|----------------|
| Minutes Remaining | Top Left — both world map and battle map | −1 per player combat turn; −1 per 2 km travelled |
| Distance to End Stage | Top Right — world map only (hidden during combat) | Recalculated as Euclidean distance each time a node is chosen |

### Node Types

| Type | Description |
|------|-------------|
| Enemy | Standard combat encounter |
| Mini-Boss | Tougher enemy, better reward |
| Boss | Act-ending encounter |
| Event | Narrative or choice-based event |
| Healing Fountain | Restore HP |
| Shop | Purchase upgrades, weapons, or items |

---

## 4. MAP & GRID (COMBAT)

- **Grid size**: 12 columns × 8 rows, flat-top hexagons
- **HEX_SIZE**: 38.0 pixels (radius)
- **Player spawn**: col 4, row 5 (center)
- **Ladder position**: col 4, row 5 (center, after floor clear)
- **Dummy position**: col 4, row 2 (3 rows north of ladder)
- **Camera**: grid centered on screen, offset right to leave room for backpack

### Tile Types

| Type | Passable | Effect |
|------|----------|--------|
| Normal | ✅ | No effect |
| Column | ❌ | Blocks movement AND line of sight. Push collision = push_value damage |
| Fire Pit | ✅ | 1 burn damage on entry. 1 more each turn you remain on it. Enemies path around but will cross if only route |

### Hazard Placement (random floors)
- Columns: 4–7 per floor
- Fire pits: 2–4 per floor
- Safe zone: no hazards within 1 hexes of player spawn

---

## 5. CHARACTERS — SONNY & MIKE

### Definition: AOE (Area of Effect)

AOE is always centered on the **target tile**.

| AOE Value | Affected Tiles |
|-----------|----------------|
| 1 | Target tile only |
| 2 | Target tile + all tiles directly adjacent to it (7 tiles total on a hex grid) |
| 3 | All tiles in AOE 2 + all tiles directly adjacent to those (extends one more ring outward) |

> AOE expands in rings. AOE N includes everything in AOE N-1, plus one more ring of adjacent tiles.

Both characters are on the field simultaneously. Each takes their own turn with 2 actions.
Click on a character to select them and see their remaining actions. You control 1 character at a time (press Tab to switch character).

When it is the enemies turn and they target a character, your control automatically snaps to that character.

Note: character HP can be 0.5. In which case the heart is half empty (vertical half).

---

### Sonny

| Stat | Value |
|------|-------|
| Max HP | 4 |
| Move | 2 hexes per move action |
| Weapon | Metal Pan ("Boong") |
| Actions per turn | 2 |

---

#### Bonk — Q Attack (Charge Bar)

Sonny's Q attack does **not** use the standard click-a-target flow. It uses a **charge bar** system.

**Input flow:**
1. Press Q to enter attack mode. Select a target tile within range 1.
2. The charge bar appears **between Sonny's tile and the target tile**, parallel to the attack direction. Start point (Sonny end) is closest to Sonny; end point (target end) is closest to the target hex. Bar is positioned to avoid overlapping either sprite.
3. The ball starts at the **Sonny end** and **automatically drifts back toward Sonny** at a constant moderate speed.
4. **Hold left click** to push the ball toward the target end (charging the hit).
5. **Release left click** to sample the ball's current position.

**Zones (same visual style as dodge bar — line, green zone, yellow zone):**

| Zone | Position | Result |
|------|----------|--------|
| Perfect (green) | Ball in green zone near target end | **+1 damage** + push 1 |
| Normal (yellow) | Ball in yellow zone | Normal damage (1) + push 1 |
| Miss | Ball drifted back past all zones | do not attack - still lose action point|

All current weapon modifiers and passives apply to this attack.

---

#### Bomb — Special Ability (once per round)

Sonny places a bomb on an adjacent tile (cast range 1).

**Properties:**
- **HP**: 1. Explodes when it takes any damage.
- **Damage**: 2, AOE 1.
- **Does not** draw enemy aggro.
- **Blocks movement** (treated as an obstacle for pathfinding).
- Can be hit and bounced by projectiles like any other object.

**Interaction with Sonny's attacks:**
Sonny's Q attack (Boong) always resolves in **push-first, damage-second** order. If the push moves the bomb into a wall or column, it takes push_value damage and explodes.

**Explosion logic:**
```gdscript
# When bomb HP reaches 0:
var affected_tiles = get_tiles_in_aoe(bomb_tile, 1)  # AOE 1 = bomb tile only
for tile in affected_tiles:
    for character in tile.occupants:
        character.take_damage(2)
bomb.queue_free()
```

**Upgrades (not yet implemented):**

| Upgrade | Effect |
|---------|--------|
| Sentient Bomb | Bomb can move and self-detonate. Requires more battery. |
| Taunting Bomb | Draws enemy aggro. |
| Poison Bomb | Deals 1 poison damage per turn until target dies. Poison is stackable. |
| Mine | No longer blocks movement. Press E to detonate (free action). |
| Grenade | +2 cast range. Explodes immediately on landing. If Sentient Bomb is also active: becomes homing rocket (+5 cast range instead, +1 AOE). |
| Bomb Bomb | On explosion, spawns an identical bomb on the same tile (without the Bomb Bomb modifier). |
| More Bomb | +1 bomb use per round. |
| Push Bomb | Explosion also pushes affected targets 2 tiles. |
| Acid Bomb | Affected enemies take double damage from all sources until end of player's next round. Does not stack. |

---

#### W Attack — Boom
*(TBD — to be designed)*

---

#### Reactions

Sonny has two reaction types, both triggered by incoming attacks.

---

##### Reaction A — Melee Perfect Dodge → Auto Counter

- Trigger: Sonny **perfectly dodges** (≤0.2s) a **melee attack**.
- Result: Sonny automatically performs his current **Q attack** on the attacker (no extra input). Affected by all current modifiers.
- Normal dodge (0.2–0.4s): avoid damage only, no counter.
- Miss: take full damage.

---

##### Reaction B — Projectile Redirect

- Trigger: **any projectile** is on a collision course with Sonny's tile.
- Input: press **SPACE**. No separate timing bar appears — the reaction is directly tied to the real-time position and moment of collision.

**Prediction (implementation):**
- Each frame, the projectile raycasts its current path forward.
- When the raycast determines the projectile **will hit Sonny's tile**, the reaction window opens.
- The exact moment the projectile reaches Sonny's position = **t = 0.0s** (this moment is predictable from speed + distance).
- No visual warning is shown. The player must watch the ball and react.

**Timing (measured from t = 0.0s — the moment of actual contact):**

| Window | Result |
|--------|--------|
| SPACE pressed within ±0.2s of contact | **Perfect redirect** → projectile redirects toward mouse cursor + **+1 bounce**. Green text **"+1 BOUNCE"** shown. |
| SPACE pressed within ±0.2s–±0.4s of contact | **OK redirect** → projectile phases through Sonny, does not trigger collision, redirection or bounce. |
| SPACE not pressed within ±0.4s | **Miss** → Sonny takes full projectile damage. |

**Redirect rules:**
- Redirected projectile travels from Sonny's position toward **mouse cursor position at moment SPACE is pressed**.
- Projectile **does not gain damage** — deals original damage only.
- Redirect does **not** cost a bounce — `bounce_count` is unchanged (+ bonus if perfect).
- All other projectile properties preserved.
- If Sonny perfectly redirects the **same projectile three times in a row** (`redirect_count == 3`), the projectile becomes **Supercharged** (see Section 5B). Also each time he redirects, the projectile becomes a bit more red (color shifts red depending on redirect_count).
- Sonny can deliberately supercharge by choosing to redirect the same projectile a second time.

---

### Mike

| Stat | Value |
|------|-------|
| Max HP | 3 |
| Move | 2 hexes per move action |
| Weapon | Y-Branch Slingshot |
| Actions per turn | 2 |

---

#### Draw Shot — Q Attack

Mike's Q attack uses a **3-step aim → charge → release flow**, implemented as an extension of the existing `main.gd` + `dodge_bar.gd` framework.

**Step 1 — Enter Aim Mode**
- Press Q while Mike is selected → enter **Draw Shot aim mode**.
- A wide **blue-white trajectory arrow** appears showing shot direction and bounce preview.
- Arrow direction = **opposite of mouse direction relative to Mike** (bow logic: mouse = pull direction, shot = opposite).
- Preview updates continuously with mouse movement.
- Preview shows: current shot direction + current bounce direction. Does not need to show the final endpoint.
- Right-click cancels aim mode.

**Step 2 — Left Click = Commit + Start Timing**
- Press left click while in aim mode:
  - Locks the current shot direction and bounce preview path.
  - Starts the timing bar.
  - Switches game into the existing blocking timing-bar phase.
Once left-clicked, the shot direction is **locked**. Mouse movement only affects the timing ball position, not the shot direction.

**Step 3 — Hold and Drag = Control Timing**
- While left click is held, the player drags the mouse backward (like drawing a bow).
- This drag controls the **center point** of the timing ball on the bar.
- The timing bar is **visually rotated** to be parallel to the shot direction.
- Ball position formula:
  ```
  ball_position = drag_center + oscillation_offset
  ```
  - `drag_center` = controlled by current drag distance while holding.
  - `oscillation_offset` = automatic left-right oscillation (width ±0.1 of bar, speed 1.0s per cycle).
- Timing line position: **0.7**.

**Step 4 — Release = Resolve**
- Release left click → lock shot direction → sample ball position against timing line at 0.7.

| Result | Condition | Effect |
|--------|-----------|--------|
| Perfect | Ball within perfect window | Projectile fires with perfect hit modifiers |
| Hit | Ball within normal window | Projectile fires with normal damage |
| Miss | Ball outside window | **"Oops!"** shown; no projectile fires; **action is consumed** |

---

#### Grapple Gun — Special Ability (2 uses per turn)

Mike fires a hook (silver) attached to a rope (brown line) at any target. Infinite range.

**On hit:**
- Deals **1 damage** to enemies. Does **not** damage Sonny.
- **Pull logic:**
  - If target is **movable**: pull target to the best fitting hex adjacent to Mike.
  - If target is **immovable** (walls, columns, and some enemies flagged as immovable): pull Mike to the best fitting hex adjacent to the target.

**Best fitting hex** = the empty, passable hex adjacent to the destination that minimizes remaining distance.

**Upgrades:** *(not yet implemented)*

---

#### Draw Shot — W Attack
*(TBD — to be designed)*

---

#### Reactions

##### Reaction A — Dodge Any Projectile

- Trigger: **any projectile** is on a collision course with Mike's tile.
- Input: press **SPACE**. No separate timing bar appears — the reaction is directly tied to the real-time collision moment.
- Mike **must** attempt to dodge — there is no option to ignore it.

**Prediction (implementation):**
- Same raycast system as Sonny. The exact moment the projectile reaches Mike's position = **t = 0.0s**.
- No visual warning is shown.

**Timing (measured from t = 0.0s):**

| Window | Source: Own Projectile | Source: Other Character's Projectile |
|--------|----------------------|--------------------------------------|
| ±0.2s (Perfect) | Projectile removed, 0 damage | 0 damage + **instant counter-attack** (see below) |
| ±0.2s–±0.4s (Normal) | Projectile removed, 0 damage + projectile continues past Mike on its original trajectory | 0 damage, no counter. Projectile continues past Mike on its original trajectory. |
| Outside ±0.4s (Miss) | Take full damage | Take full damage |

**On normal dodge — projectile continues:**
- The projectile ignores collision with Mike (as if he stepped aside) and continues traveling in its original direction.
- This applies to both own and other-character projectiles.

**Counter-attack rules (perfect dodge of non-own projectile only):**
- Counter fires **instantly** toward the attacker — no aim/timing input required.
- Shot quality = perfect hit (determined by the quality of the dodge).
- Counter projectile uses base bounce count (default 1).
- Counter projectile is **still counted as Mike's** — if it bounces back, Mike must dodge it.
- Counter projectile can damage Sonny or Mike if they cannot dodge it.
- All current weapon modifiers and passives apply to the counter projectile.
- The original projectile that Mike dodged does not trigger collision as in normal dodge.

---

### Shared Stats

| Stat | Value |
|------|-------|
| Actions per turn | 2 |

Attacking will end the turn. Turns can only be: **move + attack** or **attack only**. No other combination is available since attacking ends the turn immediately.

| Move range | 2 hexes (BFS, blocked by columns and enemies) |

---

## 5B. PROJECTILE SYSTEM

Projectiles are **independent entities** with their own scene and script. This allows fine-tuning per projectile type without touching character or combat code.

```
scenes/combat/projectile.tscn
scenes/combat/projectile.gd
```

### Projectile Properties

```gdscript
class_name Projectile extends Node2D

var damage          : float    # base damage value
var direction       : Vector2  # normalized travel direction (world space)
var speed           : float    # pixels per second (~80ms per hex equivalent)
var bounce_count    : int      # remaining bounces (default: 1 for Draw Shot)
var owner_char      : Node     # character who fired this projectile
var is_supercharged : bool = false
var redirect_count  : int = 0  # how many times Sonny has perfectly redirected this projectile
```

### Visual
- Shape: small white ball, **5 px radius**.
- Travel time: **~160 ms per hex distance**.
- Supercharged state: visual change (color shifts more red each time).

### Movement & Bounce

All movement and bounce computed in **world/pixel space**, not tile space.

```
Each frame:
  1. Move in current direction at current speed
  2. Find first collision along path
  3. If bounceable AND bounce_count > 0:
       direction = direction.bounce(surface_normal)
       bounce_count -= 1
       continue traveling
  4. If collision is an enemy:
       apply damage → stop projectile
  5. If bounce_count == 0 and collision occurs:
       apply damage if applicable → stop projectile
```

**Godot reflection:**
```gdscript
direction = direction.bounce(surface_normal)
```
Standard vector reflection — preserves incoming angle, no tile-snapping.

### Bounceable Surfaces

| Surface | Behavior |
|---------|----------|
| Walls (map edge) | Reflect, decrement bounce |
| Columns | Reflect, decrement bounce |
| Enemies | Reflect, decrement bounce (apply damage on stop) |
| Sonny | Only if they cannot dodge |
| Mike | Only if they cannot dodge |

### Shared Preview / Firing Rule

The **same bounce-path algorithm** must be used for:
- The aim preview arrow (Draw Shot Step 1)
- The final locked trajectory (Draw Shot Step 4 at release)
- The actual fired projectile

Do not use one algorithm for preview and a different one for the real shot.

### Reaction Trigger — Sonny & Mike

**Prediction system (shared by both characters):**
- Every frame, each projectile raycasts its current travel path forward.
- If the raycast intersects a tile occupied by Sonny or Mike, that character is marked as the **incoming target**.
- The exact arrival time is computed from: `time_to_contact = distance_to_character / projectile_speed`.
- `t = 0.0s` is defined as the moment the projectile reaches the character's world position.
- The player presses SPACE at any time; the system measures how far that press is from `t = 0.0s`.

**No visual warning is shown.** The player must watch the projectile and react.

**Reaction window:**
- Perfect: SPACE pressed within ±0.2s of contact.
- OK / Normal: SPACE pressed within ±0.2s–±0.4s of contact.
- Miss: SPACE not pressed within ±0.4s.

**Bounce cost on reaction:**
- Reactions (redirect or dodge) do **not** cost a bounce. `bounce_count` is unchanged.
- Perfect redirect grants **+1 bounce** on top of current `bounce_count`.

**On successful dodge (normal or perfect) — projectile continues:**
- The projectile ignores the dodging character's collision and continues in its current direction.
- It is treated as if the character was not there for that frame.

**Only one reaction attempt per projectile impact.**

### Supercharged State

**Trigger:** Sonny perfectly redirects the **same projectile thrice in a row** (`redirect_count == 3`).
Every time Sonny hits a projectile, it becomes slightly bigger (10%) and its color shifts red slightly.
Sonny can deliberately supercharge by choosing to redirect the same projectile a second time.

**Supercharged behavior:**
- Projectile is blinking red.
- No more bounces.
- No more redirects.
- Mike can still dodge a supercharged projectile.
- On next collision with any tile or character (other than Mike successfully dodging):
  - **Explodes**.
  - Deals `original_damage + 1` to **center tile** (impact tile).
  - Deals `original_damage` to all **adjacent tiles**.
  - Hits everything — enemies, Sonny, Mike included.

```gdscript
var affected_tiles = [impact_tile] + get_adjacent_tiles(impact_tile)
for tile in affected_tiles:
    var dmg = original_damage + (1 if tile == impact_tile else 0)
    for character in tile.occupants:
        character.take_damage(dmg)
```

### Default Values per Weapon

| Weapon | Default bounce_count | Stop on enemy hit |
|--------|---------------------|-------------------|
| Mike's Draw Shot | 1 | Yes (after bounces exhausted) |

> `bounce_count` is tunable from data/upgrades — do not hardcode.

---

## 6. ACTIONS & TURN SYSTEM

### Player Turn
- **2 actions** per turn.
- After floor clear: **infinite actions** until stepping on ladder.
- Attack costs 1 action. Move costs 1 action. Attacking will end the turn immediately even if there are actions left.
- Click a character to select them. Selected character is highlighted.

### Controls

| Input | Action |
|-------|--------|
| Click character | Select that character |
| Tab | Switch selected character |
| Q | Enter attack mode. For Mike's slingshot: enter Draw Shot aim mode. |
| Left click | Confirm target (standard attacks). For Draw Shot aim mode: start timing bar. |
| Left click hold + drag | While Draw Shot timing active: drag to control timing ball center and shot direction. |
| Left click release | While Draw Shot timing active: lock direction and resolve shot. |
| Right-click | Cancel Draw Shot aim mode. |
| SPACE | End turn early / resolve dodge bar / attempt reaction. |

### Enemy Turn
- Enemies sorted by distance to player (closest first).
- Tie-break: row ASC, then col ASC.
- Each enemy gets **2 actions** per turn.
- **0.5 second delay** between each action (`ACTION_DELAY`).
- Enemies cycle through their attacks in order, 1 attack per action.

### Phase States
```
PLAYER_TURN  → actions used or SPACE       → ENEMY_TURN
ENEMY_TURN   → enemy executes attack       → DODGE_PHASE
DODGE_PHASE  → bar resolves                → ENEMY_TURN (continues queue)
PLAYER_TURN  → both characters die         → DEAD (press ENTER to restart)
```

### Turn Reset (start of each player turn)
```gdscript
actions_left             = 2
armor                    = 0
disarmed                 = false
tiles_traveled_this_turn = 0
# bleed ticks on all enemies
```

---

## 7. WEAPONS & ABILITIES

Weapons have **Q** (first) and **W** (second) abilities.
Some item upgrades can open R option with new abilities.

### Sonny — Metal Pan ("Boong")

| Ability | Name | Effect | Mode |
|---------|------|--------|------|
| Q | Boong | 1 dmg + push 1. Uses charge bar flow. See Section 5. | charge_bar |
| W | *(TBD)* | *(to be designed)* | — |

### Mike — Y-Branch Slingshot

| Ability | Name | Effect | Mode |
|---------|------|--------|------|
| Q | Draw Shot | 1 dmg, 1 bounce. Uses Draw Shot aim + timing flow. See Section 5. | draw_shot |
| W | *(TBD)* | *(to be designed)* | — |

---

## 9. COMBAT — DODGE BAR

Appears above the attacking enemy when they attack. Ball moves left → right. Press **SPACE** to resolve.

| Zone | Timing | Result |
|------|--------|--------|
| Perfect (green) | ≤ 0.2s from line | 0 damage + **+1 Cockiness**. See Section 5 for character-specific counter reactions. |
| Dodge (yellow) | 0.2–0.4s from line | 0 damage, no Cockiness |
| Hit (outside) | Beyond yellow | Full damage + **lose all Cockiness** |

- Dodge bar construction follows the L S W timing code.
- Swiftness bonus makes ball slower: `BALL_SPEED / (1.0 + swiftness_bonus)`

### Enemy Timing Code: L S W

| Parameter | Description |
|-----------|-------------|
| `L` | Timing line offset. Bar divided into 10 segments. X=0 → line at 0.75. Positive X → moves left. Negative X → moves right. |
| `S` | Ball speed. Time to cross bar = `1*(1-S)` seconds. Y=0 → 1 second. Higher = faster. |
| `W` | Dodge window modifier. Z=0 → default. Z=1 → +10% to both windows. Z=−5 → −50% to both windows. |

---

## 11. DAMAGE FORMULA

All multipliers stack **multiplicatively**. Round to nearest whole (0.5 rounds up).

```
final_dmg = base_weapon_dmg
          × (1.0 + cockiness_stacks × 0.10)
          × hit_mult                               # 1.0 hit / 0.50 miss
          × (1.0 + missing_hp × 0.20)             # Rage passive
          × 1.50 if target_hp ≤ target_max_hp×0.5 # Executioner passive
          × (1.0 + tiles_moved_this_turn × 0.10)  # Momentum passive
          + flat_bonus                             # after all multipliers
```

### Push Damage
- Hit wall/column: target takes `push_value` damage.
- Hit another enemy: both take 1 damage; push transfers at value −1.

---

## 12. STATUS EFFECTS

*(TBD)*

---

## 13. ENEMIES

### Overview

Enemies are defined by a **data resource** (stats + attack list) and a **behavior type** (movement + targeting logic). The combat manager reads each attack and routes it automatically:

```
attack.range == 1  →  melee  →  spawn dodge bar (timing minigame)
attack.range  > 1  →  ranged →  spawn projectile (reaction minigame, no dodge bar)
```

This routing happens in `combat_manager.gd`. Enemy scripts never touch the dodge bar or projectile directly — they only declare their data and behavior type.

---

### Attack Routing Rules

**Melee (range == 1):**
- Spawns a dodge bar using the attack's `perfect_window` and `ok_window`.
- If `dual_bar == true`: spawns two sequential dodge bars for that single hit, each with their own speed modifier.

**Ranged (range > 1):**
- Spawns a projectile using `speed`.
- `perfect_window` and `ok_window` are **ignored** — the player reacts to the physical projectile (see Section 5B).
- Damage value on the main row (or hits table if present) is the projectile's `damage` property.

---

### Hits

An attack with `hits > 1` fires that many times **sequentially** on the same action. Each hit spawns its own dodge bar (melee) or its own projectile (ranged) independently.

If all hits are identical, the main row is sufficient (`hits: N, identical`).

If hits differ (different damage, speed, or timing windows), a **hits table** is required beneath the attack row. The main row `damage` column is left as `—` and the hits table is the source of truth.

---

### Enemy Template

```markdown
### [Name] — [Letter] ([Color])
**HP**: [X]
**Actions**: [X]
**Move**: [X] hexes
**Behavior**: [description of movement and targeting logic]

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | 1 | — | 0.20s | 0.40s | |
| A2 | ... | ... | ... | ... | ... | ... | ... | |

<!-- Only include hits table if hits > 1 AND hits are not identical -->
**[AX] — Hit Details**
| Hit | Damage | Speed | Perfect Window | OK Window |
|-----|--------|-------|----------------|-----------|
| 1   | ...    | ...   | ...            | ...       |
| 2   | ...    | ...   | ...            | ...       |

**Special flags**: [dual_bar | immovable | none]
**Notes**: [any additional behavior quirks]
```

**Column reference:**
- **Range**: 1 = melee (dodge bar). 2+ = ranged (projectile). Range is in hex distance.
- **Damage**: base damage per hit. Use `—` if a hits table overrides it.
- **AOE**: 1 = target tile only. 2 = target + adjacent ring. 3 = two rings out.
- **Hits**: how many times this attack fires on one action. Each hit is independent.
- **Speed**: `—` for melee. `slow` / `medium` / `fast` for ranged projectiles.
- **Perfect Window / OK Window**: seconds from timing line. Melee only. Use `—` for ranged.
- **Special**: `dual_bar` for attacks with two sequential dodge bars. Notes on that attack only.

---

### Grunt — G (red)

**HP**: 5
**Actions**: 2
**Move**: 2 hexes
**Behavior**: Aggressive. Moves toward the nearest player each turn. Attacks if adjacent to any player. If already adjacent to one player, repositions to remain adjacent to that player while minimizing distance to the second player. Attacking ends turn.

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | 1 | — | 0.20s | 0.40s | |
| A2 | 1 | 2 | 1 | 1 | — | 0.15s | 0.35s | |

**Special flags**: none

---

### Archer — A (blue) — NOT YET IMPLEMENTED

**HP**: 3
**Actions**: 2
**Move**: 1 hex
**Behavior**: Keeps 2–5 hexes distance from the nearest player. If a player moves adjacent, moves away. Attacks if a player is within range 4. Attacking ends turn.

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 4 | 2 | 1 | 1 | medium | — | — | |
| A2 | 4 | — | 1 | 2 | — | — | — | see hits table |

**A2 — Hit Details**

| Hit | Damage | Speed | Perfect Window | OK Window |
|-----|--------|-------|----------------|-----------|
| 1 | 0.5 | medium | — | — |
| 2 | 0.5 | fast | — | — |

**Special flags**: none

---

### Assassin — S (purple) — NOT YET IMPLEMENTED

**HP**: 4
**Actions**: 2
**Move**: 2 hexes
**Behavior**: Aggressive. Moves toward the nearest player. Attacks if adjacent. Attacking ends turn.

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | 1 | — | 0.16s | 0.32s | dual_bar: bar1 ×0.80 speed, bar2 ×1.30 speed |

**Special flags**: dual_bar

**Dual bar behavior**: A1 spawns two sequential dodge bars. Bar 1 runs at 0.80× normal ball speed. Bar 2 runs at 1.30× normal ball speed. Both must be resolved for a full dodge. Damage applies if either bar is missed.

---

### Training Dummy — D (green)

**HP**: 5 (resets to full at the start of its own turn if damaged)
**Actions**: 0
**Move**: 0 hexes
**Behavior**: Never moves. Never attacks. Spawns at col 4, row 2 after floor clear. Used for post-combat weapon testing with infinite actions.

**Special flags**: immovable

---

### Enemy AI Priority (shared logic)

Evaluated each action in order. First matching condition wins.

```
1. Adjacent to a player AND can attack      → attack
2. Behavior == archer AND player adjacent   → move away (maintain 2–5 hex distance)
3. Behavior == archer AND player in range   → attack
4. Otherwise                                → move toward nearest player
```

**Movement constraints (all enemies):**
- Cannot enter column tiles.
- Prefers to path around fire pits. Will cross if no other route exists.

---

## 14. ITEMS & PREFIXES

*(TBD)*

---

## 15. BACKPACK & EQUIPMENT

*(TBD)*

---

## 16. FORGING & SMELTING

*(TBD)*

---

## 17. FLOORS & PROGRESSION

### Act 1 — Enemy Counts

| Floor | Grunts | Archers | Assassins | Notes |
|-------|--------|---------|-----------|-------|
| 1 | 2 | 0 | 0 | |
| 2 | 3 | 1 | 0 | |
| 3 | 3 | 2 | 0 | |
| 4 | 3 | 2 | 1 | |
| 5 | 4 | 2 | 1 | Mini-boss placeholder |
| 6 | 4 | 3 | 1 | |
| 7 | 4 | 3 | 2 | |
| 8 | 5 | 3 | 2 | |
| 9 | 5 | 4 | 2 | |
| 10 | 5 | 4 | 3 | Boss placeholder |

Enemy spawn: minimum **4 hexes** from player spawn, not on hazard tiles.

### Future Acts
- Act 2: Heaven — 10 floors *(not designed)*
- Act 3: Hell — 10 floors *(not designed)*

---

## 18. OBJECTIVES

*(TBD)*

---

## 19. CHESTS & REWARDS

*(TBD)*

---

## 20. EVERY-3-FLOOR MENU

*(TBD)*

---

## 21. SKILLS & PASSIVES

Earned from mini-bosses and bosses. **NOT YET IMPLEMENTED.**

### Active Skills (cost Cockiness, keys 1–6, draggable)

| Skill | Cost | Cooldown | Effect |
|-------|------|----------|--------|
| Heal | 3 | 2 turns | Heal 1 HP |
| Teleport | 4 | 3 turns | Move to any hex within range 4 |
| Leap Strike | 5 | — | Jump to empty hex ≤3 range; 2 dmg to all adjacent enemies. All dmg multipliers apply. |
| Hemorrhage | 6 | 1 turn | Apply 3 bleed +1 per missing HP |
| Telekinesis | 2 | None | Move 1 enemy within range 3 to any empty passable tile |
| Shields | 5 | 3 turns | Gain 1 armor block |
| Showtime | 10 | — | End turn. Next enemy turn: all attacks auto-dodged (no Cockiness). Your next turn: all attacks auto normal hit (no Cockiness). Lose all Cockiness on cast. |
| Shinra Tensei | 6 | 3 turns | Push all enemies within 2 hexes by 3. Further enemies pushed first. Normal collision rules outside push range. |

### Passive Skills

| Skill | Effect |
|-------|--------|
| Rage | +20% dmg per missing HP (multiplicative) |
| Executioner | +50% dmg vs targets below 50% HP (multiplicative) |
| Momentum | +10% dmg per tile traveled this turn (resets each turn; includes teleport/leap) |
| Insane Reflexes | +30% accuracy AND swiftness |
| Too Easy | −30% accuracy AND swiftness. Double Cockiness cap (20) and double Cockiness gain. |
| Bloodthirsty | +10% bleed dmg per bleed stack on target *(not yet in formula)* |

---

## 22. UI LAYOUT

*(TBD)*

### Floating Text
- Damage numbers: red, drift upward, fade over 0.8s
- PERFECT! / DODGED! / HIT!: colored by result, drift upward
- +1 BOUNCE: green, appears on Sonny's tile on perfect redirect
- Objective complete: gold, center screen

---

## 23. FILE STRUCTURE

```
godot/
├── autoloads/
│   ├── game_state.gd
│   ├── combat_manager.gd
│   ├── player_registry.gd
│   ├── enemy_registry.gd
│   ├── prefix_system.gd
│   ├── forge_system.gd
│   └── objective_tracker.gd
│
├── classes/
│   ├── character_data.gd
│   ├── enemy_data.gd
│   ├── enemy_attack.gd
│   ├── hit_code.gd
│   ├── item_data.gd
│   └── prefix_data.gd
│
├── resources/
│   ├── characters/
│   │   ├── sonny.tres
│   │   └── mike.tres
│   └── enemies/
│       ├── grunt.tres
│       ├── archer.tres
│       └── assassin.tres
│
├── systems/
│   ├── damage_calculator.gd
│   ├── bfs_pathfinder.gd
│   └── hex_utils.gd
│
└── scenes/
    ├── combat/
    │   ├── hex_tile.tscn + hex_tile.gd
    │   ├── base_character.tscn + base_character.gd
    │   ├── sonny.tscn + sonny.gd
    │   ├── mike.tscn + mike.gd
    │   ├── base_enemy.tscn + base_enemy.gd
    │   ├── projectile.tscn + projectile.gd
    │   ├── timing_bar.tscn + timing_bar.gd
    │   ├── combat_bar_stack.tscn + combat_bar_stack.gd
    │   └── combat_ui.tscn + combat_ui.gd
    ├── world_map/
    │   ├── world_map.tscn + world_map.gd
    │   └── map_node.tscn + map_node.gd
    ├── backpack/
    │   ├── backpack.tscn + backpack.gd
    │   └── item_slot.tscn + item_slot.gd
    └── menus/
        ├── three_floor_menu.tscn + three_floor_menu.gd
        └── chest_popup.tscn + chest_popup.gd
```

### Key Constants
```gdscript
const HEX_SIZE        := 38.0
const GRID_COLS       := 9
const GRID_ROWS       := 10
const MOVE_RANGE      := 2
const ACTION_DELAY    := 0.5
const TWEEN_SPEED     := 0.18
const BALL_SPEED      := 160.0
const ZONE_PERFECT    := 0.04
const ZONE_DODGE      := 0.08
const ACT_TIME_LIMIT  := 100
const ACT_DISTANCE    := 100
```

### Phase Enum
```gdscript
enum Phase {
    PLAYER_TURN,
    ENEMY_TURN,
    DODGE_PHASE,
    DEAD,
}
```

### Signals
```gdscript
# combat_manager.gd
signal phase_changed(new_phase: Phase)
signal character_moved(character, from_tile, to_tile)
signal enemy_attacked(enemy, target)
signal damage_applied(target, amount, source)
signal damage_blocked(target)
signal enemy_died(enemy, cause: String)   # "attack"|"bleed"|"burn"|"push"
signal floor_cleared()
signal cockiness_changed(character, new_value: int)

# timing_bar.gd
signal bar_resolved(result: String)       # "perfect"|"ok"|"miss"

# combat_bar_stack.gd
signal attack_fully_resolved(results: Array)

# backpack.gd
signal equipment_changed(main_hand: ItemData, off_hand: ItemData)

# world_map.gd
signal node_selected(node_data: Dictionary)
signal timer_updated(minutes_remaining: int)
```

---

## 24. IMPLEMENTATION STATUS

| System | Status | Notes |
|--------|--------|-------|
| Hex grid with hazards | ✅ Done | |
| Player movement — BFS, 2 hexes | ✅ Done | Both Sonny and Mike use same BFS via `Player.gd` presets |
| Grunt enemy (AI, HP bar, dodge bar) | ✅ Done | |
| Turn system (player/enemy phases) | ✅ Done | |
| Dodge bar | ✅ Done | `dodge_bar.gd` — configurable line, speed, windows |
| Damage formula (Cockiness, hit/miss) | ✅ Done | |
| Death screen + restart | ✅ Done | |
| Floor clear → chest popup → ladder | ✅ Done | |
| Training dummy | ✅ Done | |
| Objectives (tracking + display) | ✅ Done | |
| Floor progression (10 floors) | ✅ Done | |
| Item system (prefix rolling) | ✅ Done | |
| **Two-character system (Sonny + Mike)** | ✅ Done | Both characters spawned and active via `PLAYER_ORDER` + `CHARACTER_PRESETS` in `Player.gd`. `current_player_index` tracks who is selected. |
| **Sonny charge bar (Boong Q)** | ✅ Done | `sonny_charge_bar.gd` — full drift/hold/release/resolve flow implemented and wired in `main.gd` |
| **Mike Draw Shot (aim + timing)** | ✅ Done | `mike_timing_bar.gd` — aim mode, locked direction, drag-center oscillation, resolve on release; all wired in `main.gd` |
| **Projectile system** | ✅ Done | `projectile.gd` (visual) + `BounceTracer` in `bounce.gd` (path logic) + full live-projectile tracking loop in `main.gd` |
| **Bounce path preview (aim overlay)** | ✅ Done | `aim_overlay.gd` — same BounceTracer used for preview and real shot |
| **Sonny redirect reaction** | ✅ Done | SPACE reaction window, redirect toward mouse, `redirect_count` tracking, +1 bounce on perfect |
| **Mike dodge reaction + counter** | ✅ Done | SPACE reaction window, own-projectile removal, counter-attack on perfect dodge of enemy projectile |
| **Supercharged projectile** | ✅ Done | Triggers at `redirect_count == 3`, blinking red visual, AoE explosion on contact |
| **Enemy data-driven attack system** | ✅ Done | `enemy.gd` — all attacks defined as dicts with `range`, `damage`, `hits`, `speed`, `dual_bar`, `hit_details`; routing in `main.gd` |
| **Archer enemy data** | ✅ Done | Defined in `enemy.gd` ENEMY_TYPES with correct A1/A2 hit table |
| **Assassin enemy data** | ✅ Done | Defined in `enemy.gd` with `dual_bar: true`, `speed_mults: [0.80, 1.30]` |
| Tab to switch character | ❌ Not started | `current_player_index` exists but no KEY_TAB handler found |
| Auto camera snap to targeted character | ❌ Not started | |
| Sonny Bomb special ability | ❌ Not started | |
| Mike Grapple Gun special ability | ❌ Not started | |
| Archer enemy — combat behavior | ❌ Not started | Data defined; AI behavior (keep distance, move away) not yet in `plan_action` |
| Assassin enemy — combat behavior | ❌ Not started | Data defined; dual bar spawn logic not yet wired in `main.gd` |
| World map (nodes, timer, travel) | ❌ Not started | |
| Every-3-floor menu (Heal/Forge/Smelt) | ❌ Not started | |
| Skills & passives | ❌ Not started | |
| Spear, bow, dagger, shield, grappling hook | ❌ Not started | |
| Sonny Boong W + upgrades | ❌ Not started | |
| Mike Slingshot W + upgrades | ❌ Not started | |
| Act 2 & 3 | ❌ Not started | |

---

*Version 1.5 — Implementation status updated from code review of Player.gd, main.gd, enemy.gd, projectile.gd, bounce.gd, aim_overlay.gd, sonny_charge_bar.gd, mike_timing_bar.gd, dodge_bar.gd, hextile.gd.*