# GIVE ME BACK MY DOG — Game Design Document
> Version: 1.6
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

**Distance from current node:** 10–15 km (float, 1 decimal place).

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
- Among valid candidates, choose randomly 2 to reveal.

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

2 nodes of the same type cannot be connected, unless it is an Enemy node. Maps need to be roughly 60% enemy, 10% miniboss, 10% event, 10% healing fountain, 10% shop.

---

## 4. MAP & GRID (COMBAT)

- **Grid size**: 12 columns × 8 rows, flat-top hexagons
- **HEX_SIZE**: 38.0 pixels (radius)
- **Player spawn**: col 1, row 5 (center)
- **Ladder position**: col 12, row 5 (center, always appear, colored yellow)
- **Dummy position**: col 6, row 5 (center)
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
| Miss | Ball drifted back past all zones | do not attack - still lose action point |

All current weapon modifiers and passives apply to this attack.

---

#### Bomb — W Attack (once per map)

Sonny places a bomb on an adjacent tile (cast range 1).

**Implementation:** The bomb is coded as an **enemy** with 1 HP and a death trigger. When its HP reaches 0 for any reason, it explodes instead of dying normally. This means all existing damage, push, and projectile-collision systems interact with it automatically — no special-case code needed.

**Properties:**
- **HP**: 1. Explodes the moment it takes any damage (any hit kills it).
- **Damage on explosion**: 2, AOE 2.
- **Does not** draw enemy aggro.
- **Blocks movement** (treated as an impassable tile for pathfinding, same as an enemy occupying a tile).
- Can be hit and bounced by projectiles like any other collidable entity.

**Interaction with Sonny's attacks:**
Sonny's Q attack (Boong) always resolves in **push-first, damage-second** order (see Push & Damage Order in Section 11). The bomb gets pushed first. If the push sends it into a wall or column, it takes push collision damage and explodes before Sonny's hit damage is applied.

**Explosion logic:**
```gdscript
# Triggered by on_death() — replaces normal death behavior:
var affected_tiles = get_tiles_in_aoe(bomb_tile, 2)
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

- Trigger: **any player-fired projectile** is on a collision course with Sonny's tile.
- Input: press **SPACE**. No separate timing bar — the reaction is tied to the real-time position and moment of collision.
- No visual warning is shown. The player must watch the ball and react.

**Timing (measured from t = 0.0s — the moment of actual contact):**

| Window | Result |
|--------|--------|
| SPACE pressed within ±0.2s of contact | **Perfect redirect** → projectile redirects toward mouse cursor. Speed is set to `current_speed + NEGATIVE_BOUNCE * 0.5`. Decay restarts from this new speed as if freshly fired. Green text **"REDIRECT!"** shown. |
| SPACE pressed within ±0.2s–±0.4s of contact | **OK redirect** → projectile phases through Sonny with no damage, no speed change, no redirect. |
| SPACE not pressed within ±0.4s | **Miss** → Sonny takes full projectile damage. |

**Redirect rules:**
- Redirected projectile travels from Sonny's position toward **mouse cursor position at moment SPACE is pressed**.
- Projectile **does not gain damage** — deals original damage only.
- Decay restarts from `current_speed + NEGATIVE_BOUNCE * 0.5` — it does not reset to original launch speed.
- All other projectile properties preserved.
- If Sonny perfectly redirects the **same projectile three times in a row** (`redirect_count == 3`), the projectile becomes **Supercharged** (see Section 5B).
- Each redirect shifts the ball's color progressively more red (based on `redirect_count`).
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

Mike's Q attack uses a **3-step aim → charge → release flow**.

**Step 1 — Enter Aim Mode**
- Press Q while Mike is selected → enter **Draw Shot aim mode**.
- A wide **blue-white trajectory arrow** appears showing the full predicted path including where the projectile will die (speed → min threshold).
- Arrow direction = **same as mouse direction relative to Mike** (mouse points where the shot goes).
- Preview updates continuously with mouse movement using the same physics simulation as the real projectile.
- Right-click cancels aim mode.

**Step 2 — Left Click = Commit + Start Timing**
- Press left click while in aim mode:
  - Locks the current shot direction and path preview.
  - Starts the timing bar.
  - All input except right-click (cancel) is blocked until the timing bar resolves.
- Once left-clicked, the shot direction is **locked**.

**Step 3 — Hold and Drag = Control Timing**
- While left click is held, the player drags the mouse backward (like drawing a bow).
- This drag controls the **center point** of the timing ball on the bar.
- The timing bar is **visually rotated** to be parallel to the shot direction.
- Ball position formula:
  ```
  ball_position = drag_center + oscillation_offset
  ```
  - `drag_center` = controlled by current drag distance while holding.
  - `oscillation_offset` = automatic oscillation that **grows with hold time**: starts at ±0.02, increases at 0.08/s, caps at ±0.30.
  - Oscillation period: 1.0s per cycle.
- Timing line position: **0.7**.

**Step 4 — Release = Resolve**

| Result | Condition | Effect |
|--------|-----------|--------|
| Perfect | Ball within perfect window | Projectile fires at full launch speed |
| Hit | Ball within normal window | Projectile fires at full launch speed, normal damage |
| Miss | Ball outside window | **"Oops!"** shown; no projectile fires; action consumed |

---

#### Grapple Gun — W Attack (2 uses per map)

Mike fires a hook (silver) attached to a rope (brown line) at any target. Infinite range.

**On hit:**
- Deals **1 damage** to enemies. Does **not** damage Sonny.
- **Pull logic:**
  - If target is **movable**: pull target to the best fitting hex adjacent to Mike.
  - If target is **immovable** (walls, columns, and some enemies flagged as immovable): pull Mike to the best fitting hex adjacent to the target.

**Best fitting hex** = the empty, passable hex adjacent to the destination that minimizes remaining distance.

**Upgrades:** *(not yet implemented)*

---

#### Reactions

##### Reaction A — Dodge Any Projectile

- Trigger: **any projectile** is on a collision course with Mike's tile.
- Input: press **SPACE**. No separate timing bar — the reaction is tied to the real-time collision moment.
- Mike **must** attempt to dodge — there is no option to ignore it.
- No visual warning is shown.

**Timing (measured from t = 0.0s):**

| Window | Source: Own Projectile | Source: Other Character's Projectile |
|--------|----------------------|--------------------------------------|
| ±0.2s (Perfect) | Projectile removed, 0 damage | 0 damage + **instant counter-attack** (see below) |
| ±0.2s–±0.4s (Normal) | Projectile removed, 0 damage + projectile continues past Mike on its original trajectory | 0 damage, no counter. Projectile continues past Mike on its original trajectory. |
| Outside ±0.4s (Miss) | Take full damage | Take full damage |

**On normal dodge — projectile continues:**
- The projectile ignores collision with Mike and continues in its current direction at its current speed.
- Speed and decay are unchanged.

**Counter-attack rules (perfect dodge of non-own projectile only):**
- Counter fires **instantly** toward the attacker — no aim/timing input required.
- Counter projectile is fired at full launch speed with full exponential decay.
- Counter projectile is **still counted as Mike's** — if it comes back, Mike must dodge it.
- Counter projectile can damage Sonny or Mike if they cannot dodge it.
- All current weapon modifiers and passives apply to the counter projectile.

---

### Shared Stats

| Stat | Value |
|------|-------|
| Actions per turn | 2 |
| Move range | 2 hexes (BFS, blocked by columns and enemies) |

Attacking will end the turn. Turns can only be: **move + attack** or **attack only**.

---

## 5B. PROJECTILE SYSTEM

Projectile collision with a character deals damage immediately (HP bar is decremented on contact).

Projectiles are **independent entities** that move in real-time via `_process()`. All movement, collision, decay, and reaction logic lives in `main.gd`. `projectile.gd` handles visuals only.

---

### Velocity & Decay

Player-fired projectiles use **exponential speed decay**. Enemy projectiles use fixed speed (no decay).

**Constants (tune these together):**

```gdscript
const PROJ_LAUNCH_SPEED   : float = ???   # px/s — tune so unobstructed range ≈ 12 hexes
const PROJ_DECAY_RATE     : float = ???   # exponential decay coefficient (per second)
const PROJ_MIN_SPEED      : float = PROJ_LAUNCH_SPEED * 0.03  # disappear threshold (3% of launch)
const PROJ_NEGATIVE_BOUNCE: float = ???   # flat speed subtracted on surface impact — tune so
                                          # post-bounce range ≈ 3–4 hexes from impact point
```

**Per-frame update:**
```gdscript
func _process(delta: float) -> void:
    speed *= exp(-PROJ_DECAY_RATE * delta)   # exponential decay
    if speed < PROJ_MIN_SPEED:
        queue_free()                          # projectile dies naturally
        return
    position += direction * speed * delta    # move in world space
    _check_collisions()
```

**Design targets (tune PROJ_LAUNCH_SPEED and PROJ_DECAY_RATE to hit these):**
- Unobstructed travel: **≈ 12 hexes** before speed drops below `PROJ_MIN_SPEED`.
- Post-bounce travel: **≈ 3–4 hexes** after a single surface hit, depending on how far the projectile had already traveled before impact (the further it traveled, the slower it was at impact, the fewer hexes it has left after the speed penalty).

---

### Surface Collision & Bounce

On collision with a wall, column, or enemy (if passing through is not active):

```gdscript
# Standard vector reflection — preserves angle, no tile-snapping
direction = direction.bounce(surface_normal)

# Flat speed penalty
speed -= PROJ_NEGATIVE_BOUNCE

if speed < PROJ_MIN_SPEED:
    queue_free()   # projectile dies at the bounce point
```

**Bounceable surfaces:**

| Surface | Behavior |
|---------|----------|
| Walls (map edge) | Reflect direction, apply `PROJ_NEGATIVE_BOUNCE` |
| Columns | Reflect direction, apply `PROJ_NEGATIVE_BOUNCE` |
| Enemies | Deal damage; reflect direction, apply `PROJ_NEGATIVE_BOUNCE` (projectile continues through) |
| Sonny | Only if reaction missed or not attempted |
| Mike | Only if reaction missed or not attempted |

There is **no bounce_count**. The projectile lives or dies entirely by its remaining speed.

---

### Sonny Redirect — Speed Interaction

On **perfect redirect** (SPACE within ±0.2s):

```gdscript
# Add speed bonus
speed = speed + PROJ_NEGATIVE_BOUNCE * 0.5

# Restart decay from this new speed (same as if projectile was freshly fired at `speed`)
# Direction changes to mouse cursor direction
direction = (mouse_pos - sonny_pos).normalized()

redirect_count += 1
if redirect_count >= 3:
    is_supercharged = true
```

The decay formula is unchanged — it continues applying `exp(-PROJ_DECAY_RATE * delta)` each frame. Restarting decay simply means the speed is now higher, so the projectile travels further from this point.

---

### Aim Preview

The aim preview (aim_overlay.gd) uses the **same physics simulation** as the real projectile:

```gdscript
# BounceTracer runs a simulation loop instead of step-based raycasting:
var sim_speed     : float   = PROJ_LAUNCH_SPEED
var sim_pos       : Vector2 = start
var sim_dir       : Vector2 = direction.normalized()
var sim_dt        : float   = 1.0 / 60.0   # simulate at 60 fps

while sim_speed >= PROJ_MIN_SPEED:
    sim_speed *= exp(-PROJ_DECAY_RATE * sim_dt)
    sim_pos   += sim_dir * sim_speed * sim_dt

    var collision = _check_collision(sim_pos)
    if collision.hit_wall or collision.hit_column:
        sim_dir    = sim_dir.bounce(collision.normal)
        sim_speed -= PROJ_NEGATIVE_BOUNCE
    elif collision.hit_enemy:
        record_hit(collision.hex)
        sim_dir    = sim_dir.bounce(collision.normal)
        sim_speed -= PROJ_NEGATIVE_BOUNCE

    record_segment_point(sim_pos)

# The final sim_pos when speed drops below threshold is the endpoint shown on the preview.
```

The preview shows the **full path** including all bounces and the exact point where the projectile dies. The endpoint fades to indicate the projectile disappears there.

**Critical rule:** The same constants (`PROJ_LAUNCH_SPEED`, `PROJ_DECAY_RATE`, `PROJ_NEGATIVE_BOUNCE`, `PROJ_MIN_SPEED`) must be used by both the preview simulation and the real projectile `_process()`. Never use different values for preview vs. reality.

---

### Reaction Trigger — Sonny & Mike

**Contact detection (per-frame):**
- Every frame, each live projectile checks if its current position is within `HEX_SIZE * 0.75` of a player's world position.
- When within range, that player is marked as the **incoming target**.
- `t = 0.0s` is defined as the moment the projectile reaches the player's world position.
- Arrival time is estimated from: `time_to_contact = distance / current_speed`.
- The player presses SPACE at any time; the system measures how far that press is from `t = 0.0s`.

**No visual warning is shown.** The player must watch the ball and react.

**Reaction window:**
- Perfect: SPACE pressed within ±0.2s of contact.
- OK / Normal: SPACE pressed within ±0.2s–±0.4s of contact.
- Miss: SPACE not pressed within ±0.4s.

**On successful dodge (normal or perfect) — projectile continues:**
- The projectile ignores the dodging character's collision and continues in its current direction at its current speed.
- Speed and decay are not affected by a dodge.

**Only one reaction attempt per projectile pass.**

---

### Supercharged State

**Trigger:** Sonny perfectly redirects the **same projectile three times** (`redirect_count == 3`).

Each redirect tints the ball progressively more red and increases its radius by 10%.

**Supercharged behavior:**
- Projectile blinks bright red.
- Sonny can no longer redirect it.
- Mike can still dodge it.
- Speed decay continues normally — the projectile can still die from speed loss.
- On next collision with any surface or character (other than Mike successfully dodging):
  - **Explodes** at impact point.
  - Deals `original_damage + 1` to the impact tile.
  - Deals `original_damage` to all adjacent tiles (AOE 2).
  - Hits everything — enemies, Sonny, Mike included.

```gdscript
var affected_tiles = [impact_tile] + get_adjacent_tiles(impact_tile)
for tile in affected_tiles:
    var dmg = original_damage + (1 if tile == impact_tile else 0)
    for character in tile.occupants:
        character.take_damage(dmg)
```

---

### Enemy Projectiles

Enemy ranged attacks fire projectiles at **fixed speed** with **no decay**. They travel until they hit a surface or character. The reaction system (SPACE to dodge) applies to enemy projectiles identically to player projectiles.

Enemy projectile speed is defined per-attack as `"slow"` / `"medium"` / `"fast"` in the enemy data (see Section 13). These map to fixed `px/s` constants — they do not use `PROJ_LAUNCH_SPEED` or `PROJ_DECAY_RATE`.

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
| Left click hold + drag | While Draw Shot timing active: drag to control timing ball center. |
| Left click release | While Draw Shot timing active: resolve shot. |
| Right-click | Cancel Draw Shot aim mode or any attack mode. |
| D | End turn early. |
| SPACE | Resolve dodge bar / attempt projectile reaction. |

### Enemy Turn
- Enemies sorted by distance to player (closest first).
- Tie-break: row ASC, then col ASC.
- Each enemy gets **2 actions** per turn.
- **0.5 second delay** between each action (`ACTION_DELAY`).
- Enemies cycle through their attacks in order, 1 attack per action.

### Phase States
```
PLAYER_TURN  → actions used or D           → ENEMY_TURN
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

## 9. COMBAT — DODGE BAR

Appears above the attacking enemy when they attack. Ball moves left → right. Press **SPACE** to resolve.

**Enemy timing line position:** randomised per enemy in range **0.6–1.0**.

| Zone | Timing | Result |
|------|--------|--------|
| Perfect (green) | ≤ 0.2s from line | 0 damage + counter attack. See Section 5 for character-specific counter reactions. |
| Dodge (yellow) | 0.2–0.4s from line | 0 damage |
| Hit (outside) | Beyond yellow | Full damage |

- Swiftness bonus makes ball slower: `BALL_SPEED / (1.0 + swiftness_bonus)`

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

### Push & Damage Order

**Global rule: push always resolves before damage.**

When an attack has both a push and damage component, the sequence is always:
1. Apply push — move the target along the push vector.
2. Resolve push collisions — if the pushed target hits a wall, column, or another entity, apply collision damage.
3. Apply the attack's hit damage.

**Push collision damage:**
- Hit wall/column: pushed target takes `push_value` damage.
- Hit another enemy: both take 1 damage; push transfers to the second target at `push_value − 1`.

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

---

### Attack Routing Rules

**Melee (range == 1):**
- Spawns a dodge bar using the attack's `perfect_window` and `ok_window`.
- If `dual_bar == true`: spawns two sequential dodge bars for that single hit, each with their own speed modifier.

**Ranged (range > 1):**
- Spawns a projectile at fixed speed (`slow` / `medium` / `fast` — no decay).
- `perfect_window` and `ok_window` are **ignored** — the player reacts to the physical projectile (see Section 5B).
- Damage value on the main row (or hits table if present) is the projectile's `damage` property.

---

### Hits

An attack with `hits > 1` fires that many times **sequentially** on the same action. Each hit spawns its own dodge bar (melee) or its own projectile (ranged) independently.

If all hits are identical, the main row is sufficient (`hits: N, identical`).

If hits differ, a **hits table** is required. The main row `damage` column is left as `—`.

---

### Enemy Template

```markdown
### [Name] — [Letter] ([Color])
**HP**: [X]
**Actions**: [X]
**Move**: [X] hexes
**Behavior**: [description]

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | 1 | — | 0.20s | 0.40s | |

**[AX] — Hit Details** (only if hits > 1 AND not identical)
| Hit | Damage | Speed | Perfect Window | OK Window |
|-----|--------|-------|----------------|-----------|
| 1   | ...    | ...   | ...            | ...       |

**Special flags**: [dual_bar | immovable | none]
**Notes**: [behavior quirks]
```

**Column reference:**
- **Range**: 1 = melee. 2+ = ranged.
- **Damage**: base damage per hit. Use `—` if hits table overrides it.
- **AOE**: 1 = target only. 2 = target + adjacent ring.
- **Hits**: how many times this attack fires per action.
- **Speed**: `—` for melee. `slow` / `medium` / `fast` for ranged (fixed speed, no decay).
- **Perfect / OK Window**: melee only. Use `—` for ranged.

---

### Grunt — G (red)

**HP**: 5
**Actions**: 2
**Move**: 2 hexes
**Behavior**: Aggressive. Moves toward the nearest player. Attacks if adjacent. If already adjacent to one player, repositions to remain adjacent while minimizing distance to the second player. Attacking ends turn.

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
**Behavior**: Keeps 2–5 hexes distance from the nearest player. Moves away if a player is adjacent. Attacks if player is within range 4. Attacking ends turn.

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

**Dual bar behavior**: A1 spawns two sequential dodge bars. Bar 1 runs at 0.80× speed. Bar 2 runs at 1.30× speed. Both must be resolved. Damage applies if either bar is missed.

---

### Training Dummy — D (green)

**HP**: 5 (resets to full at the start of its own turn if damaged)
**Actions**: 0
**Move**: 0 hexes
**Behavior**: Never moves. Never attacks. Spawns at col 6, row 5 after floor clear. Used for post-combat weapon testing with infinite actions.

**Special flags**: immovable

---

### Enemy AI Priority (shared logic)

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
- REDIRECT!: green, appears on Sonny's tile on perfect redirect
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
const HEX_SIZE             := 38.0
const GRID_COLS            := 12
const GRID_ROWS            := 8
const MOVE_RANGE           := 2
const ACTION_DELAY         := 0.5
const TWEEN_SPEED          := 0.18
const BALL_SPEED           := 160.0
const ZONE_PERFECT         := 0.04
const ZONE_DODGE           := 0.08
const ACT_TIME_LIMIT       := 100
const ACT_DISTANCE         := 100

# Projectile velocity system (player-fired only)
const PROJ_LAUNCH_SPEED    := ???     # tune for ≈12 hex unobstructed range
const PROJ_DECAY_RATE      := ???     # exponential decay coefficient per second
const PROJ_MIN_SPEED       := PROJ_LAUNCH_SPEED * 0.03
const PROJ_NEGATIVE_BOUNCE := ???     # flat px/s subtracted on surface impact
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
| Floor clear → world map transition | ✅ Done | |
| Training dummy | ✅ Done | |
| Objectives (tracking + display) | ✅ Done | |
| Floor progression (10 floors) | ✅ Done | |
| Item system (prefix rolling) | ✅ Done | |
| Two-character system (Sonny + Mike) | ✅ Done | Both characters spawned and active via `PLAYER_ORDER` + `CHARACTER_PRESETS` in `Player.gd` |
| Sonny charge bar (Boong Q) | ✅ Done | `sonny_charge_bar.gd` — full drift/hold/release/resolve flow |
| Mike Draw Shot (aim + timing) | ✅ Done | `mike_timing_bar.gd` — aim mode, drag-center oscillation, resolve on release |
| Projectile system — tween-based (old) | ✅ Done | `projectile.gd` (visual) + `BounceTracer` in `bounce.gd` + tracking loop in `main.gd` |
| Sonny redirect reaction | ✅ Done | SPACE reaction window, redirect toward mouse, `redirect_count` tracking |
| Mike dodge reaction + counter | ✅ Done | SPACE reaction window, counter-attack on perfect dodge of enemy projectile |
| Supercharged projectile | ✅ Done | Triggers at `redirect_count == 3`, blinking red, AoE explosion |
| Enemy data-driven attack system | ✅ Done | `enemy.gd` — all attacks as dicts with `range`, `damage`, `hits`, `dual_bar`, etc. |
| Archer enemy data | ✅ Done | Defined in `enemy.gd` with correct A1/A2 hit table |
| Assassin enemy data | ✅ Done | Defined in `enemy.gd` with `dual_bar: true`, `speed_mults: [0.80, 1.30]` |
| Sonny Bomb (W) | ✅ Done | Implemented as enemy type "bomb" with explosion on death |
| Mike Grapple Gun (W) | ✅ Done | Pull logic, immovable flag, 2 uses per map |
| **Projectile velocity decay system** | ❌ Not started | Replaces tween + BounceTracer with `_process()` physics loop. Requires rewrite of `bounce.gd` (physics sim), `projectile.gd` (visual only, no logic change), and projectile handling in `main.gd`. Old system remains until new one is complete. |
Already have it
| Auto camera snap to targeted character | ❌ Not started | |
| Archer enemy — combat behavior | ❌ Not started | Data defined; keep-distance AI not yet in `plan_action` |
| Assassin enemy — combat behavior | ❌ Not started | Data defined; dual bar spawn not yet wired in `main.gd` |
Already have it
| Skills & passives | ❌ Not started | |
| Sonny Boong W upgrades | ❌ Not started | |
| Mike Slingshot W upgrades | ❌ Not started | |
| Act 2 & 3 | ❌ Not started | |

---

*Version 1.6 — Projectile system reworked: exponential velocity decay, physics-loop movement via `_process()`, `PROJ_NEGATIVE_BOUNCE` flat speed penalty on surface impact, Sonny redirect grants `NEGATIVE_BOUNCE * 0.5` speed with decay restart. `bounce_count` concept removed. BounceTracer rewritten as physics simulation for accurate aim preview. Enemy projectiles retain fixed speed. Old tween-based system remains in code until new system is implemented.*