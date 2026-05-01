# GIVE ME BACK MY DOG — Game Design Document
> Version: 1.7
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
9. [Combat — Dodge Bar](#9-combat--dodge-bar)
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

- Trigger: **any projectile** is on a collision course with Sonny's hex border.
- Input: press **SPACE**. No separate timing bar — the reaction is tied to the real-time collision moment.
- No visual warning is shown. The player must watch the ball and react.
- Full rules, timing windows, speed interaction, and ownership changes are defined in **Section 5B — Sonny: Projectile Redirect**.

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

#### Grapple Gun — W Attack (1 uses per map)
Mike fires a hook (silver) attached to a rope (brown line) in any direction.
Hook projectile behavior:

Infinite range.
Phases through walls, columns, and Sonny's bomb.
Stops at the first character it hits, regardless of friend or enemy. That character becomes the pull target.
If no character is hit, nothing happens and the use is refunded.

On grab:

Sonny: 0 damage.
Enemy: 1 damage immediately on grab.

Pull logic:

The target is dragged along the hook's incoming angle toward Mike.
The target lands on the nearest empty, passable hex along that angle.
The drag has full collision — the target interacts with walls, columns, other characters, and bombs exactly as a pushed entity would.
If the target's path is blocked by an obstacle before reaching the destination:

Target stops at the nearest available hex next to the obstacle (best fit for the incoming angle).
Target takes 1 collision damage.
If the obstacle is Sonny's bomb: the bomb takes 1 damage and explodes normally.



Upgrades: (not yet implemented)

---

#### Reactions

##### Reaction A — Dodge Any Projectile

- Trigger: **any projectile** is on a collision course with Mike's hex border.
- Input: press **SPACE**. No separate timing bar — the reaction is tied to the real-time collision moment.
- Mike **must** attempt to dodge — there is no option to ignore it.
- No visual warning is shown.
- Full rules and timing windows are defined in **Section 5B — Mike: Projectile Dodge**.

---

### Shared Stats

| Stat | Value |
|------|-------|
| Actions per turn | 2 |
| Move range | 2 hexes (BFS, blocked by columns and enemies) |

Attacking will end the turn. Turns can only be: **move + attack** or **attack only**.

---

## 5B. PROJECTILE SYSTEM

All projectiles — player-fired and enemy-fired — use the same movement, collision, and bounce logic. The only differences between projectile types are their speed profile and their `negative_bounce` value, both set at launch time.

Projectiles move in real-time via `_process()` every frame. All logic lives in `main.gd`. `projectile.gd` is visuals only.

---

### Projectile Data

Every projectile carries these properties at spawn:

```gdscript
var speed           : float   # current speed in px/s, updated every frame
var direction       : Vector2 # normalized, updated on bounce
var damage          : float   # base damage, never changes after spawn
var negative_bounce : float   # flat px/s subtracted from speed on any collision
var owner           : Node    # the character or enemy that fired this projectile.
                              # null = god-owned (hits everyone including Sonny and Mike)
var uses_decay      : bool    # true for player-fired, false for enemy-fired
var redirect_count  : int = 0
var is_supercharged : bool = false
```

**Owner rules:**
- Projectile does **not** collide with its `owner`. It passes through them silently.
- A projectile collides with and damages every other character and enemy regardless of who fired it.
- Enemy A's projectile can hit Enemy B.
- **Exception — god ownership:** When Sonny perfectly redirects a projectile, `owner` is set to `null`. A god-owned projectile collides with and damages everyone — Sonny, Mike, and all enemies. Sonny can still redirect a god-owned projectile. God ownership is permanent for that projectile.

---

### Speed Profiles

**Player-fired projectiles** use exponential decay:

```gdscript
# Every frame, before moving:
if uses_decay:
    speed *= exp(-PROJ_DECAY_RATE * delta)
    if speed < PROJ_MIN_SPEED:
        _die()   # projectile disappears naturally, no collision
        return
```

**Enemy-fired projectiles** use fixed speed — no decay. They travel at constant speed until they collide with something, at which point `negative_bounce = 9999` kills them immediately.

**Constants (tune together — player projectiles only):**

```gdscript
const PROJ_LAUNCH_SPEED : float = ???               # px/s — tune for ≈12 hex unobstructed range
const PROJ_DECAY_RATE   : float = ???               # exponential coefficient per second
const PROJ_MIN_SPEED    : float = PROJ_LAUNCH_SPEED * 0.03  # disappear threshold (3% of launch)
```

**Design targets:**
- Unobstructed player projectile: **≈ 12 hexes** before speed drops below `PROJ_MIN_SPEED`.
- Post-collision player projectile: **≈ 3–4 hexes** remaining after one hit (varies with speed at moment of impact).

---

### Negative Bounce Values

`negative_bounce` is set at spawn and never changes. It is the flat px/s subtracted from `speed` on every collision (wall, column, or character).

| Projectile source | Default `negative_bounce` |
|-------------------|--------------------------|
| Player-fired (Mike Draw Shot, Mike counter) | `PROJ_NEGATIVE_BOUNCE` constant — tune so post-bounce range ≈ 3–4 hexes |
| Enemy-fired | `9999.0` — guarantees death on first collision with anything |

Enemy `negative_bounce` can be overridden per-attack in the enemy data dict (key: `"negative_bounce": float`) if a specific enemy attack should survive a bounce. If not specified, defaults to `9999.0`.

---

### Per-Frame Movement Loop

```gdscript
func _process(delta: float) -> void:
    # 1. Apply decay (player projectiles only)
    if uses_decay:
        speed *= exp(-PROJ_DECAY_RATE * delta)
        if speed < PROJ_MIN_SPEED:
            _die()
            return

    # 2. Move
    position += direction * speed * delta

    # 3. Check collisions (in priority order)
    _check_wall_collision()
    _check_column_collision()
    _check_character_collision()
```

---

### Collision Detection — Hex Border

All collision boundaries use the **actual hexagon border** of the occupied tile, not a circle approximation.

A hexagon in flat-top orientation has 6 sides, each with a known outward normal. Collision is detected when the projectile's position crosses the hexagon boundary of a tile.

**For walls and columns:** The tile itself is the hexagon. Use the side normal of the crossed edge as the bounce normal.

**For characters (Sonny, Mike, enemies):** The character's occupied hex is treated as a solid hexagon boundary. Crossing any side of that hexagon = collision. Use the normal of the crossed side as the bounce normal.

**Collision check order per frame:** walls → columns → characters. If multiple collisions occur in the same frame, resolve the closest one first.

---

### Collision Resolution

The same resolution logic applies to all collision types. Only the side effects differ.

```gdscript
func _resolve_collision(surface_normal: Vector2, hit_character = null) -> void:
    # 1. If character hit: deal damage first
    if hit_character != null and hit_character != owner:
        hit_character.take_damage(damage)

    # 2. Reflect direction
    direction = direction.bounce(surface_normal)

    # 3. Apply speed penalty
    speed -= negative_bounce

    # 4. Check if projectile survives
    if speed < PROJ_MIN_SPEED:
        _die()   # dies at collision point, after damage has been applied
```

**Key points:**
- Damage is applied before the bounce calculation. HP bar updates immediately.
- A projectile with `negative_bounce = 9999` will always die at step 4, after dealing damage.
- A projectile can hit the same character multiple times if its bounce trajectory re-enters their hex border. There is no immunity window.
- There is no bounce_count. The projectile lives or dies entirely by remaining speed.

---

### Collision Table

| What was hit | Owner check | Damage | Bounce |
|--------------|-------------|--------|--------|
| Wall (map edge) | N/A | None | Reflect + subtract `negative_bounce` |
| Column tile | N/A | None | Reflect + subtract `negative_bounce` |
| Character == `owner` | Skip entirely | None | No bounce, projectile continues |
| Character ≠ `owner` | Collide | `damage` to that character | Reflect + subtract `negative_bounce` |
| Any character, `owner == null` (god) | Collide with everyone | `damage` to that character | Reflect + subtract `negative_bounce` |

---

### Aim Preview (Mike Draw Shot only)

The aim preview in `aim_overlay.gd` runs a **physics simulation** using the same constants and logic as the real projectile. It does not use a separate algorithm.

```gdscript
# Simulation loop — runs ahead of time, not in real-time
var sim_speed : float   = PROJ_LAUNCH_SPEED
var sim_pos   : Vector2 = mike_position
var sim_dir   : Vector2 = shot_direction.normalized()
var sim_dt    : float   = 1.0 / 60.0

while sim_speed >= PROJ_MIN_SPEED:
    sim_speed *= exp(-PROJ_DECAY_RATE * sim_dt)
    sim_pos   += sim_dir * sim_speed * sim_dt

    var col = _sim_check_collision(sim_pos, sim_dir)
    if col.hit:
        sim_dir   = sim_dir.bounce(col.normal)
        sim_speed -= PROJ_NEGATIVE_BOUNCE
        if col.hit_character:
            record_hit(col.character)

    record_path_point(sim_pos)

# sim_pos when loop ends = where the projectile dies = endpoint shown on preview
```

**Preview shows:**
- Full path from Mike to death point, including all bounces.
- The endpoint fades/dims to indicate the projectile disappears there.
- Enemy hex borders that would be struck are highlighted.

**Characters treated as obstacles in preview:** enemies only. Sonny and Mike are not treated as obstacles in the preview.

**Critical rule:** `PROJ_LAUNCH_SPEED`, `PROJ_DECAY_RATE`, `PROJ_NEGATIVE_BOUNCE`, and `PROJ_MIN_SPEED` must be identical between the preview simulation and the real `_process()` loop. Never use different values.

---

### Reaction System — Sonny & Mike

Both characters can react to any incoming projectile that will cross their hex border. The reaction window is based on real-time arrival.

**Contact detection (per-frame):**
- Each projectile checks each frame whether its current trajectory will cross a player's hex border.
- When a crossing is imminent, `t = 0.0s` is defined as the exact moment the projectile reaches the hex border.
- Arrival time is estimated each frame from: `time_to_contact = distance_to_hex_border / current_speed`.
- The player presses SPACE at any time. The system compares the press time to `t = 0.0s`.

**No visual warning is shown.** The player must watch the ball and react.

**Reaction window (same for both characters):**
- Perfect: SPACE within ±0.2s of `t = 0.0s`.
- OK / Normal: SPACE within ±0.2s–±0.4s of `t = 0.0s`.
- Miss: SPACE not pressed within ±0.4s → collision resolves normally (damage + bounce).

**Only one reaction attempt per projectile-character crossing.** If the projectile bounces off something else and comes back, that is a new crossing and a new reaction window.

---

### Sonny — Projectile Redirect

Sonny has no projectile of his own. He can redirect **any projectile** heading toward his hex, from any source.

**On perfect redirect (SPACE within ±0.2s):**

```gdscript
# Change direction toward mouse cursor
direction = (mouse_pos - sonny_world_pos).normalized()

# Speed bonus: counteracts the negative_bounce that a collision would have cost
speed += projectile.negative_bounce * 0.5

# Ownership becomes god — hits everyone including Sonny from this point
owner = null

# Track redirects toward supercharge
redirect_count += 1
if redirect_count >= 3:
    is_supercharged = true
```

- Decay continues from the new (higher) speed — it is not reset to launch speed.
- God ownership is permanent. If Sonny redirects again, ownership stays `null`, `redirect_count` increments, and supercharge can still trigger.

**On OK redirect (SPACE within ±0.2s–±0.4s):**
- Projectile passes through Sonny's hex with no collision, no damage, no speed change, no ownership change.

**On miss:**
- Normal collision resolution: damage to Sonny, bounce, subtract `negative_bounce`.

---

### Mike — Projectile Dodge

Mike can dodge any projectile heading toward his hex. Mike cannot redirect, but he can catch the projectile.

#### On perfect dodge (SPACE within ±0.2s):
Projectile ownerResultMike himselfProjectile deleted, 0 damage.Anyone else (enemy, god, Sonny)0 damage. Projectile deleted. Mike stores a copy of that projectile.
Storing a caught projectile:

Mike stores a copy of the projectile's damage, speed, negative_bounce, and uses_decay.
Maximum 2 stored projectiles. If already at cap, the caught projectile is discarded and "Bag is full!" appears in red.
If below cap, "Caught it!" appears in green.
A counter "balls caught: N" is displayed next to Mike's name at all times (0–2).

Firing stored projectiles:

Stored projectiles only fire on a successful Draw Shot (perfect or hit result). A miss ("Oops!") does not trigger them.
After the Draw Shot fires, each stored projectile fires in the same locked direction, one every 0.3s.
All stored projectiles have owner = Mike. If any bounce back toward Mike, he must react normally.
The queue empties and the counter resets to 0 after firing, regardless of how many were stored.

#### On OK dodge (SPACE within ±0.2s–±0.4s):

0 damage. Projectile passes through Mike's hex, continues in current direction at current speed unchanged.
Applies to all projectile sources including god-owned.

#### On miss:

Normal collision resolution: damage to Mike, bounce, subtract negative_bounce.
---

### Supercharged State

**Trigger:** `redirect_count` reaches 3 on the same projectile (three perfect Sonny redirects).

Each redirect: ball radius grows by 10%, color shifts progressively more red.
At `redirect_count == 3`: ball blinks bright red — supercharged.

**Supercharged behavior:**
- Sonny can still attempt to redirect it (SPACE within ±0.2s). A perfect redirect increments `redirect_count` further, god ownership and speed bonus still apply.
- Mike can still dodge it normally.
- Speed decay still applies — the projectile can still die from speed loss before hitting anything.
- On the next collision with **anything** (wall, column, character) that is not Mike successfully dodging:
  - **Explodes** at impact point.
  - Deals `damage + 1` to the impact tile's occupants.
  - Deals `damage` to all adjacent tile occupants (AOE 2).
  - Hits everyone — Sonny, Mike, all enemies — regardless of ownership.

```gdscript
# On supercharged collision:
var affected_tiles = [impact_tile] + get_adjacent_tiles(impact_tile)
for tile in affected_tiles:
    var dmg = damage + (1 if tile == impact_tile else 0)
    for character in tile.occupants:
        character.take_damage(dmg)
_die()
```

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
attack.range  > 1  →  ranged →  spawn projectile (no dodge bar — player reacts in real-time)
```

---

### Attack Routing Rules

**Melee (range == 1):**
- Spawns a dodge bar using the attack's `perfect_window` and `ok_window`.
- If `dual_bar == true`: spawns two sequential dodge bars for that single hit, each with their own speed modifier.

**Ranged (range > 1):**
- Spawns a projectile at fixed speed with `uses_decay = false` and `negative_bounce = 9999` (dies on first collision).
- `perfect_window` and `ok_window` are **ignored** — the player reacts to the physical projectile (see Section 5B).
- The `speed` field (`slow` / `medium` / `fast`) maps to fixed px/s constants.
- `negative_bounce` can be overridden per-attack in the data dict if the attack should survive a bounce.

---

### Hits

Attack with more than 1 hit fall into 2 categories:
Range: each projectile is fired with 0.3s apart, unless specified. 
Melee: each attack spawn its own dodge bar, the later attack dodge bar is on top of the earlier one. Later dodge bar will only start running once the earlier dodge bar is finished (regardless of player's action)

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
| Hit | Damage | Speed | Delay | Perfect Window | OK Window |
|-----|--------|-------|-------|----------------|-----------|
| 1   | ...    | ...   | 0s    | ...            | ...       |
| 2   | ...    | ...   | 0.3s  | ...            | ...       |

**Special flags**: [dual_bar | immovable | none]
**Notes**: [behavior quirks]
```

**Column reference:**
- **Range**: 1 = melee (dodge bar). 2+ = ranged (projectile, dies on first hit).
- **Damage**: base damage per hit. Use `—` if hits table overrides it.
- **AOE**: 1 = target only. 2 = target + adjacent ring.
- **Hits**: how many times this attack fires per action.
- **Speed**: `—` for melee. `slow` / `medium` / `fast` for ranged (fixed speed, no decay).
- **Perfect / OK Window**: melee only. Use `—` for ranged.
- **Delay** (hits table only): seconds between projectile spawns for multi-hit ranged attacks.

---

### Grunt — G (red)

**HP**: 3
**Actions**: 2
**Move**: 2 hexes
**Behavior**: Aggressive. Moves toward the nearest player. Attacks if adjacent. If already adjacent to one player, repositions to remain adjacent while minimizing distance to the second player. Attacking ends turn.

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | 1 | — | 0.20s | 0.40s | |
| A2 | 1 | 2 | 1 | 1 | — | 0.15s | 0.35s | |

**Special flags**: none

---

### Archer — A (purple)

**HP**: 2
**Actions**: 1
**Move**: 1 hex
**Behavior**: Stays 2–5 hexes away from the nearest player. Moves away if a player is adjacent. Attacks if a player is within 4 hexes. Attacking ends turn.

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 4 | 1 | 1 | 1 | normal | — | — | Single projectile, dies on hit |
| A2 | 4 | — | 1 | 2 | — | — | — | see hits table |

**A2 — Hit Details**
| Hit | Damage | Speed | Delay | Perfect Window | OK Window |
|-----|--------|-------|-------|----------------|-----------|
| 1 | 0.5 | fast | 0s | — | — |
| 2 | 0.5 | fast | 0.3s | — | — |

**Special flags**: none

**Notes**: All Archer projectiles use `negative_bounce = 9999` (die on first collision). The second A2 projectile is fired 0.3s after the first.

---

### Assassin — S (purple) — NOT YET IMPLEMENTED

**HP**: 3
**Actions**: 2
**Move**: 2 hexes
**Behavior**: Aggressive. Moves toward the nearest player. Use range attack first, then melee attack.

A1: Poison dagger
Range: 6
hit: 1
Damage 1
Apply 1 stack of poison. (a stack of poison deal 1 damage, poison is stackable, each turn the number of poison stack decrease by 1)
Projectile speed: normal
Can only be used once a combat
A2
Range: Melee
Hit: 2
Damage: 1
Attack twice in a row, each attach deal 1 damage. There would be 2 timing bar for each attach. First attack timing bar has the ball speed slow, timing line at 0.6. 2nd timing bar has ball speed fast and timing line at 0.75

### Bulldozer — Z (gray)

**HP**: 5
**Actions**: 2
**Move**: 1 hexes
**Behavior**: Lock-and-charge. Telegraphed line attack with reaction window.

#### Lock-on

Checked **once per turn**, at the start of Bulldozer's turn, only if he has no current lock:

- Scan for the **nearest player within 4 hexes** (hex distance) **with line of sight** (columns block; same `_has_line_of_sight` rule as Mike's Draw Shot).
- If found, that player becomes the locked target. Establishing the lock costs **1 action**.
- If no eligible player is found this turn, Bulldozer does not attempt again until next turn-start.
- Bulldozer will move toward the nearest player when there is no lock on. Each move cost 1 action.

Once locked:
- The target **never changes** as long as they are alive — distance, LOS, and walls become irrelevant. The lock is permanent until the target dies.
- A persistent **red line** is drawn from Bulldozer to the locked target's current hex, redrawn each frame as the target moves. Visual telegraph only — does not block movement, projectiles, or LOS.

If the locked target dies (any cause), the lock clears. Bulldozer re-acquires on his next turn-start using the same rules above.

#### Actions per turn

Bulldozer always has **2 actions** per turn. The action a turn opens with depends on state:

| State at turn start | Action 1 | Action 2 |
|---|---|---|
| No lock | Move 1 hex toward nearest visible player (`Behavior.AGGRESSIVE`-style move) | Attempt to lock on (scan + establish if eligible). If lock succeeds, action ends; charge waits for next turn. | If lock fail, move another hex toward the nearest visible player.
| Has lock | Charge (see below) | Charge consumes the second action as well — he does nothing else that turn. |

The intent: an unlocked Bulldozer spends his turn closing distance and acquiring; a locked Bulldozer charges immediately and uses the whole turn doing it.

#### Charge

Triggered at the start of Bulldozer's turn whenever a lock is active. Consumes **both actions**.

The charge path is a straight hex line from Bulldozer's current hex to the locked target's **current hex** (re-aimed each turn — "sticky lock, fresh aim").

Bulldozer advances one hex at a time along the path. Each hex resolves as follows:

**Empty passable hex** → Bulldozer enters it. Continue.

**A non-target character on the path (player or enemy)** → Deal **1 damage** and **push 1** to that character. The push direction is **NOT** the charge direction — it is the charge direction rotated **±60°** (one hex axis offset to either side of the line):

- The first non-target character hit is pushed at **+60°** (left of the charge direction).
- The second non-target character hit is pushed at **−60°** (right).
- Subsequent hits alternate +60°, −60°, etc.
- Push collisions follow the existing `_push_enemy` chain rules — pushed-into-wall = +1 dmg to pushee; pushed-into-character = both take 1 dmg, push transfers at value−1; etc.
- After the push resolves, Bulldozer enters the now-empty hex and continues.
- If the hex cannot be emptied, charge is stop, bulldozer take 1 damage

**Wall edge / column / immovable enemy on path** → Bulldozer **stops in the previous hex** (last passable hex). He takes **1 damage**. Charge ends.

**The locked target's hex (final hex of path)** → Push the target 1 hex along the **charge direction** (straight, NOT angled — only non-target hits use ±60°). Push uses the standard `_push_enemy` chain rules. Bulldozer then occupies the target's former hex. Charge ends.

If the charge path would carry Bulldozer off the grid, he stops at the last in-bounds hex and takes 1 damage.

#### Reaction — Parry

When Bulldozer enters a player's hex during the charge, that player has a SPACE-press window to parry. Same timing logic as projectile reactions in §5B:

- **Perfect (SPACE within ±0.2s of contact)**: 0 damage. Push still applies.
- **OK (SPACE within ±0.2s–±0.4s)**: 0 damage. Push still applies.
- **Miss / no press**: full damage AND push.

Each character has only one parry attempt per charge — if a chain push pulls them back into the charge path, the second contact is not parry-able.

#### Stats table

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | charge | 1 | 1 | 1 per character on path | — | 0.20s | 0.40s | parry-able; charge consumes both actions; non-target pushes at ±60° alternating, target push along charge direction |

**Special flags**: charges, parry-able, lock-on
**Notes**: Lock established on Bulldozer's turn-start when nearest player ≤4 hexes WITH line of sight. Lock is permanent until target death. Charge re-aims each turn at locked target's current hex. See §5B for SPACE-timing implementation, `_push_enemy` for push chain rules.

### Mage — M (orange-purple)

**HP**: 2
**Actions**: 1 per turn
**Move**: 2 hexes
**Behavior**: Squishy ranged caster. All Mage attacks are **telegraphed**: aim on turn N, erupt on turn N+1. Aiming costs the action; eruption is free. Both attacks require line of sight to the target player at the moment of aiming.

#### AI

Evaluated each turn in order, first match wins:

1. If a pending eruption is queued from last turn → **erupt** (no action consumed; resolves before any other behavior this turn). After eruption resolves, continue to step 2 with whatever action is left.
2. If a player is adjacent (distance 1) → **move away** (action consumed). No attack this turn.
3. If a player is within range 6 with line of sight → **aim** (action consumed). Picks the **nearest such player** as the target. Alternates between A1 (Inferno Bloom) and A2 (Fire Lance) starting with A1 on first cast — same `attack_index` cycling as other enemies.
4. Otherwise → **move toward nearest player** (action consumed). The intent is to close into range 6 with LOS so a cast becomes possible next turn.

#### Telegraph → eruption cycle (shared rules for A1 and A2)

**Turn N (aim):**
- Costs Mage's action for the turn.
- Mage selects the target player and locks the affected hexes based on geometry **at the moment of aiming**. The hexes do NOT track the player. If the player walks out, the same hexes will erupt regardless. If the player walks back in, they will be hit.
- The affected hexes display a bright orange aura overlay until eruption or interruption.
- The aura persists through the player turn between Mage's turns.

**Interruption:**
- If the Mage **takes any damage OR is pushed** between turn N and turn N+1, the cast is interrupted.
- On interruption: the aura clears, no eruption occurs, and a floating "INTERRUPTED!" label appears over the Mage. The Mage will attempt a new cast on their next turn (i.e. the eruption is NOT rescheduled — it's cancelled, and the next aim attempt starts fresh).
- If the Mage dies before turn N+1: same as interruption (aura clears, no eruption).

**Turn N+1 (eruption):**
- At the start of Mage's turn, before any other Mage action, the aura begins a 3-2-1 countdown. Each digit appears as a large floating label over the affected area, 0.3s apart (3 → 0.3s → 2 → 0.3s → 1 → 0.3s → eruption).
- On eruption, the beam visually extends from Mage's current hex to the affected area at ultra-fast speed (one frame, or a brief tween of 0.05–0.1s — purely visual flourish, no gameplay timing tied to it).
- **Single SPACE-press resolution for all affected players:**
  - The eruption hits all caught players simultaneously. There is one shared SPACE-press window starting at the moment of contact (same timing logic as projectile reactions in §5B: perfect ±0.2s, OK ±0.2–0.4s).
  - One press resolves all caught players together. If the press is perfect or OK, **every** affected player avoids the 1 damage. If miss, **every** affected player takes the 1 damage.
  - **Burn is unavoidable:** every affected player takes 1 burn stack regardless of dodge result.
- Burn does not apply to enemies caught in the area.
- After eruption resolves, the aura clears. Mage's normal action for turn N+1 then runs (typically: aim a new attack, or move/flee per the AI rules above).

#### Burn status (new — players only)

Burn is a stacking damage-over-time effect on players, mirroring how poison works on enemies (`tick_poison`).

- **Storage**: `burn_stacks: int` on `Player.gd`, runtime state. Initial value 0.
- **Application**: every Mage eruption that catches a player adds 1 burn stack, regardless of whether the damage was dodged.
- **Stacking**: additive, no cap. Multiple Mages stacking burn on the same player adds independently.
- **Tick**: at the **start of the affected player's turn**, deal `burn_stacks` damage to that player, then decrement `burn_stacks` by 1. Implementation parallels `Enemy.tick_poison()` — add a `Player.tick_burn()` method called at the same lifecycle point that poison ticks for enemies.
- **Cannot be dodged or reduced.** No SPACE input, no minigame — it just ticks.
- **Display**: HUD should show current burn stacks next to the player's HP (small flame icon + number).

#### Line of sight (LOS)

Both attacks require LOS at the moment of aiming. LOS uses the existing `_has_line_of_sight` helper (columns block, fire pits and entities do not).

- If no player is in range AND has LOS, Mage cannot aim this turn — falls through to step 4 (move toward nearest player).
- LOS is only checked at aim time. After aiming, the eruption resolves regardless of obstacles. (You spent your one chance to interrupt by breaking LOS during the aim turn — the eruption itself is unstoppable except by killing or pushing the Mage.)

#### Attack 1 — Inferno Bloom (AOE)

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 6 | 1 | 2 | 1 | — | 0.20s | 0.40s | telegraphed; LOS required at aim; +1 burn on hit OR dodge; single shared SPACE for all caught players |

- Affected area at aim time: the target player's current hex + all 6 adjacent hexes (7 hexes total, AOE 2).
- Aura: bright orange glow on all 7 hexes during turn N.
- Beam visual on eruption: a brief flash from Mage to the AOE center (no gameplay implication).

#### Attack 2 — Fire Lance (beam)

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A2 | 6 | 1 | beam | 1 | — | 0.20s | 0.40s | telegraphed; LOS required at aim; +1 burn on hit OR dodge; single shared SPACE for all caught players |

- Affected area at aim time: every hex on the straight hex line from Mage's hex to the target player's hex (using the existing `_hex_line` helper), **excluding Mage's own hex**, **including the target player's hex**. Width = 1 hex.
- Since LOS is required at aim time, no column will be on the line at aim time. (If a column is somehow placed on the line between aiming and eruption — e.g. a future mechanic — the eruption still resolves on every hex of the line; the beam is magical fire, not a projectile.)
- Aura: bright orange glow on every hex of the line during turn N.
- Beam visual on eruption: a fast streak from Mage along the full line length.

**Special flags**: telegraphed, applies-burn, interruptible
**Notes**: Affected hexes are locked at aim time. Damage and push during turn N→N+1 interrupt the cast. See "Telegraph → eruption cycle" for shared resolution rules and §5B for SPACE-timing implementation.
---
#### Burn status (new — universal)

Burn is a stacking damage-over-time effect that applies to **any character** (players and enemies alike). It mirrors how poison currently works on enemies, but is the universal version available to both sides.

- **Storage**: `burn_stacks: int` runtime state on both `Player.gd` and `Enemy.gd`. Initial value 0.
- **Application**: every Mage eruption that catches a character adds 1 burn stack, regardless of whether the damage was dodged. Future player abilities or other enemy attacks may also apply burn.
- **Stacking**: additive, no cap. Multiple sources stack independently on the same target.
- **Tick**: at the **start of the affected character's turn**, deal `burn_stacks` damage to that character, then decrement `burn_stacks` by 1.
  - For players: implement as `Player.tick_burn()`, called at the same lifecycle point as `reset_turn()` at start of player turn.
  - For enemies: implement as `Enemy.tick_burn()`, called at the same lifecycle point as `tick_poison()` at start of enemy turn.
- **Cannot be dodged or reduced.** No SPACE input, no minigame — it just ticks.
- **Lethality**: burn damage can kill. If a character's HP drops to 0 from burn, normal death handling runs (player → death animation + game-over check; enemy → `_kill_enemy` which handles bomb explosion if applicable).
- **Display**:
  - Player HUD: small flame icon + stack number next to HP.
  - Enemy: small flame indicator on the enemy's nameplate or HP bar (mirroring however poison is shown — if poison isn't currently shown either, treat that as a follow-up task).
### Guardian Gorilla — G (silver-blue)

**HP**: 5
**Actions**: 2 per turn
**Move**: 2 hexes
**Behavior**: Aggressive melee. Always moves toward the nearest player. Maintains a shield facing that rotates to face the nearest player at key moments during the turn. Absorbs and redirects projectiles from the shielded arc.

---

#### Shield Facing

Guard always has a **facing direction** — one of the 6 cardinal hex directions. The shield covers a **180° front arc**: the 3 hexes directly in front of Guard (the faced hex and the two hexes flanking it on either side). A blue crescent glow is rendered on those 3 hex tiles to show the current shield arc.

**When facing updates** (in this order each turn):
1. At the start of Guard's turn, before any action.
2. After Guard moves (if he moves), before any attack.

At each update point: rotate facing to point toward the **nearest player character** (Sonny or Mike, by hex distance). If both players are equidistant, keep the current facing. Facing is one of the 6 discrete hex directions — pick the direction whose neighbor hex is closest to the target player's current hex.

Facing does **not** update mid-move or during attack resolution. It is a discrete snap at the two update points above.

---

#### Shield Effects

**Damage reduction:**
Any attack that originates from within the shielded 3-hex arc deals **−1 damage** to Guard (minimum 0). This applies to melee hits, projectile hits, bomb AOE, and burn/poison ticks that were applied from a shielded-direction hit (the tick reduction only applies to the initial hit reduction; DOT ticks themselves are not reduced).

**Projectile redirect:**
When a projectile enters one of the 3 shielded hexes while traveling toward Guard:
- Guard automatically redirects it toward the **nearest player character** (no player SPACE input — this is fully automatic).
- New direction = from Guard's current hex toward the nearest player's current hex, normalized.
- Ownership is set to **god-owned** (`owner_node = null`) — same as Sonny's perfect redirect. Hits everyone including Sonny and Mike.
- `negative_bounce` is set to `PROJECTILE_NEG_BOUNCE * 0.5` (half the normal penalty, so the redirected projectile travels farther than a standard bounce).
- Speed is unchanged at time of redirect.
- No SPACE window is opened for the player. The redirect is instantaneous.

**Push immunity from the front:**
Guard cannot be pushed from any direction within the shielded 180° arc. If a push source (Sonny's Boong, Bulldozer charge, etc.) originates from one of the 3 shielded hexes, the push is cancelled — Guard does not move. Push from any of the 3 rear hexes resolves normally.

---

#### AI — turn structure

**At the start of the turn:** update facing toward nearest player.

Evaluate distance `d` to nearest player:

| Condition | Action 1 | Action 2 |
|---|---|---|
| No player adjacent AND `d > 2` | Move toward nearest player (BFS, standard) | Update facing → Attack if now adjacent, else skip |
| No player adjacent AND `d ≤ 2` | Move toward nearest player | Update facing → Attack (A1 if both players adjacent after move, else alternate A1/A2) |
| Player already adjacent | Update facing → Attack (A1 if both players adjacent, else alternate A1/A2) | Move toward nearest player (reposition) OR skip if already optimal |

**Attack selection:**
- If **both** Sonny and Mike are adjacent to Guard at the moment of attacking → use **A1** (Stun Slam, hits all 3 front hexes).
- Otherwise → alternate A1 and A2, starting with A1. Track with `guard_attack_index`.

After move (if any): update facing before attack.

---

#### Attack 1 — Shield Slam (melee, priority when both players adjacent)

Guard slams the shield outward. Hits all **3 hexes in the shielded front arc** simultaneously. One shared SPACE-press window for all affected players (same model as Mage eruption and Dasher adjacency slam — one press resolves all caught players together).

| Player result | Damage | Stun |
|---|---|---|
| Perfect dodge | 0 | No |
| OK dodge | 0 | No |
| Miss | 0 | Yes — `stun_turns = 1` (skips 1 full turn) |

This attack deals **0 damage** regardless of dodge result. Its only purpose is the stun on miss. Stun applies to each missed player individually.

| # | Range | Damage | AOE | Hits | Special |
|---|-------|--------|-----|------|---------|
| A1 | front arc (3 hexes) | 0 | front arc | 1 shared | stun on miss; shared SPACE; 0 damage always |

---

#### Attack 2 — Triple Strike (melee, alternating)

3 sequential dodge bars fired one after another in a single coroutine. All 3 always fire regardless of hit or dodge on previous bars. Each bar deals 1 damage independently. Ball speed escalates across the 3 bars.

| Bar | Ball speed mult | Damage | Perfect Window | OK Window |
|-----|----------------|--------|----------------|-----------|
| 1 | 0.7× (slow) | 1 | 0.20s | 0.40s |
| 2 | 1.0× (medium) | 1 | 0.20s | 0.40s |
| 3 | 1.5× (fast) | 1 | 0.20s | 0.40s |

| # | Range | Damage | AOE | Hits | Special |
|---|-------|--------|-----|------|---------|
| A2 | 1 | 1/hit | 1 | 3 (always all fire) | slow→med→fast bars; targets nearest adjacent player only |

---

#### Preset entry

```gdscript
### Boxing Bear — R (dark orange)

**HP**: 5
**Actions**: 1
**Move**: 2 hexes
**Behavior**: Aggressive melee. Moves toward nearest player. Attacks if adjacent. One action per turn consumed by either the move or the attack chain.

#### Attack — Boxing Bear Combo

When Boxing Bear attacks, it spawns a **dodge bar** using the same timing windows as Grunt A1 (perfect_window: 0.20s, ok_window: 0.40s, 1 damage per hit), but with the ball moving at **1.5× Grunt's ball speed** (`speed_mult: 1.5`). The timing windows do not change — only the ball is faster, giving the player less time to react.

Unlike a standard melee attack that fires once and ends, the Boxing Bear Combo is a **chain**: each successful dodge by the player triggers another bar immediately, up to a maximum of 5 bars in sequence. Every bar in the chain uses the same `dodge_line` value and the same `speed_mult: 1.5`.

Resolution rules, evaluated after each bar:

| Player result | Damage taken | Chain continues? |
|---|---|---|
| Miss (hit zone) | 1 | No — chain ends, Boxing Bear turn ends |
| OK dodge | 0 | Yes — next bar spawns immediately |
| Perfect dodge | 0 | Yes — next bar spawns immediately |

The chain ends when either:
- The player is hit (any result other than perfect or OK), OR
- The player successfully dodges all 5 bars.

If the player dodges all 5 bars:
- No damage is dealt.
- **Boxing Bear is stunned for 1 full turn** (`stun_turns = 1` — see Stun below).
- Spawn a floating "STUNNED!" label over Boxing Bear in gray.

#### Implementation notes

- The 5-bar chain is a single atomic sequence from `main.gd`'s perspective — it runs inside one `await` coroutine, spawning bars back-to-back. Phase stays in `DODGE_PHASE` for the entire chain.
- Each bar in the chain uses the same `dodge_line` value (Boxing Bear does not re-roll the timing line between hits in the chain).
- The chain is not interruptible mid-sequence by other game events — the `DODGE_PHASE` lock already handles this.
- Track combo progress with a local counter inside the coroutine, not a persistent state var on the enemy — the chain is fully stateless between turns.
- This attack does NOT use `dual_bar` or `speed_mults`. It is a new action code `"boxing_bear_combo"` returned by `plan_action` and handled explicitly in `main.gd`, separate from the existing `"attack"` path.

#### Stun (new universal effect)

Stun applies to **any character** (players and enemies alike). A stunned unit skips all actions and movement until the stun expires.

**Storage**: `stun_turns: int` on both `Enemy.gd` and `Player.gd`. Initial value 0.

**Application**: set `stun_turns = N`.
- "1 full turn" means the unit skips its entire next turn. Because `stun_turns` is decremented at the **start** of the unit's turn before checking, `stun_turns = 2` achieves this: decrements to 1 on the turn it was applied (already ending anyway), decrements to 0 at the start of the next turn but skips since `stun_turns > 0` after decrement... 

Actually, to be precise: stun is applied after the chain resolves, at which point Boxing Bear's current turn is already over. So:
- Set `stun_turns = 1`.
- At the start of Boxing Bear's NEXT turn: decrement to 0, skip turn entirely since stun was > 0 before decrement.
- The turn after that: `stun_turns = 0`, acts normally.

So `stun_turns = 1` = skip 1 full turn. Use this value everywhere stun means "miss one turn."

**Tick**: at the start of the stunned unit's turn, before any action:
```gdscript
if stun_turns > 0:
    stun_turns -= 1
    # skip entire turn — no move, no attack, no special behavior
    return
```

**Integration**:
- For enemies: check `stun_turns` at the top of `_run_enemy_actions`. If `stun_turns > 0`, decrement, skip action loop, return. Still call `tick_turn()` so other per-turn state (charge flags, move flags, etc.) resets normally.
- For players: check `stun_turns` at the start of the player's turn. If `stun_turns > 0`, decrement, disable all input (movement, attacks, abilities), auto-end their turn. Display a "STUNNED" indicator on their HUD avatar panel.
- Stun the persistent state of — `pending_eruption` on a Mage, `lock_target_idx` on a Bulldozer, etc. If they are stun, they lose that state and begin their turn according to their own logic.
- Stun on a Bomb or Dummy has no effect (they already do nothing).

**Display**:
- Stunned enemy: gray pulsing overlay or floating "STUNNED" label above the unit.
- Stunned player: grayed-out action indicators in HUD, "STUNNED" label on their avatar panel.

#### Preset entry

```gdscript
"boxing_bear": {
    "enemy_type":       "boxing_bear",
    "display_label":    "R",
    "max_hp":           5,
    "actions_per_turn": 1,
    "move_range":       2,
    "body_color":       Color(0.85, 0.40, 0.10),
    "behavior":         Behavior.AGGRESSIVE,
    "immovable":        false,
    "range_min":        0,
    "range_max":        0,
    "attacks": [
        # Handled via "boxing_bear_combo" action in main.gd — values here are
        # for reference and HUD display only.
        { "range": 1, "damage": 1, "aoe": 1, "hits": 5, "speed": "",
          "perfect_window": 0.20, "ok_window": 0.40,
          "dual_bar": false, "speed_mults": [],
          "boxing_bear_combo": true, "max_chain": 5, "chain_speed_mult": 1.5 },
    ],
},
```
### Dasher — D (electric blue)

**HP**: 7
**Actions**: 2 per turn
**Move**: no standard movement — all repositioning is done via Dash
**Behavior**: Adaptive skirmisher. Behavior depends entirely on player distance at the start of the turn. Evaluated once at turn-start; does not re-evaluate mid-turn.

---

#### Dash

Dash moves Dasher in a **straight hex line** (one of the 6 cardinal hex directions). The path must be clear — columns, enemies, and players all block the dash. Dasher stops at the last unobstructed hex before any obstacle, or at the maximum dash range for this context, whichever comes first.

Dasher has **no standard BFS movement**. If all 6 directions are blocked at hex 1, the dash action is skipped.

---

#### AI — turn structure

Find the **nearest player** by hex distance. Call their distance `d`. Evaluate once at turn-start.

---

##### Case 1 — Adjacent (`d == 1`)

**Action 1: Adjacency Slam**
Hit all adjacent tiles simultaneously. One shared SPACE-press window for all affected players (same model as Mage eruption — one press resolves all caught players together).

| Player result | Damage | Stun |
|---|---|---|
| Perfect dodge | 0 | No |
| OK dodge | 1 | No |
| Miss | 1 | Yes — `stun_turns = 1` |

After the slam resolves (including stun application):

**Action 2: Dash away**
Dash up to **5 hexes** away. Evaluate all 6 directions, pick the direction and distance that maximizes hex distance to the nearest player after landing. Dasher does not need to use the full 5 hexes — stop at whatever landing hex scores best.

---

##### Case 2 — Mid-range (`2 ≤ d ≤ 3`)

**Pre-calculate before acting:** check whether any straight hex line from Dasher's current position, up to 4 hexes, would land Dasher on a hex adjacent to the nearest player.

**If yes — can reach adjacent:**

Action 1: Dash the **minimum number of hexes** along that line to become adjacent. Do not overshoot.

Action 2: Melee combo — 3 sequential dodge bars in one coroutine, always all 3 fire regardless of hit/dodge on previous bars. 1 damage per bar independently.

| Bar | Ball speed mult | Perfect Window | OK Window |
|-----|----------------|----------------|-----------|
| 1 | 0.7× (slow) | 0.20s | 0.40s |
| 2 | 1.0× (medium) | 0.20s | 0.40s |
| 3 | 1.5× (fast) | 0.20s | 0.40s |

**If no — cannot reach adjacent within 4 hexes:**

Action 1: Dash up to **4 hexes** in the direction that lands farthest from the nearest player while still making progress (i.e. prefer directions that push distance toward 5–6 range).

Action 2: Ranged attack (A1 or A2, alternating — see below).

---

##### Case 3 — Optimal range (`4 ≤ d ≤ 6`)

**Action 1: Ranged attack** (A1 or A2, alternating).

**Action 2: Repositioning dash** — dash up to **3 hexes** to maintain 5–6 hex distance from the nearest player. If already at 5–6, skip (dash 0). Pick the direction and distance that keeps distance closest to the 5–6 band.

---

##### Case 4 — Too far (`d > 6`)

**Action 1: Dash toward nearest player** — up to **4 hexes**, along the straight line that gets closest to the 5–6 range band from the player.

**Action 2: Ranged attack** (A1 or A2, alternating) — fires regardless of whether the dash fully closed the gap.

---

#### Attack 1 — Triple Shot (ranged, alternating)

3 projectiles fired in sequence at the nearest in-range player. Fixed speed: **fast**. 0.2s interval between each. Each projectile uses the standard real-time SPACE reaction (§5B), not a dodge bar. `negative_bounce = 9999`.

| # | Range | Damage | Hits | Speed | Interval |
|---|-------|--------|------|-------|----------|
| A1 | 6 | 1/hit | 3 | fast | 0.2s |

---

#### Attack 2 — Barrage (ranged, alternating)

5 projectiles fired in sequence at the nearest in-range player. Fixed speed: **slow**. 0.1s interval between each. Same real-time SPACE reaction. `negative_bounce = 9999`.

| # | Range | Damage | Hits | Speed | Interval |
|---|-------|--------|------|-------|----------|
| A2 | 6 | 1/hit | 5 | slow | 0.1s |

Ranged attacks alternate: A1 first, then A2, then A1, etc. Tracked via `dash_attack_index` on the enemy instance.

---

#### Preset entry

```gdscript
"dasher": {
    "enemy_type":       "dasher",
    "display_label":    "D",
    "max_hp":           7,
    "actions_per_turn": 2,
    "move_range":       0,
    "body_color":       Color(0.20, 0.70, 1.00),
    "behavior":         Behavior.DASHER,
    "immovable":        false,
    "range_min":        4,
    "range_max":        6,
    "attacks": [
        # A1 — Triple Shot
        { "range": 6, "damage": 1, "aoe": 1, "hits": 3, "speed": "fast",
          "perfect_window": 0.0, "ok_window": 0.0,
          "dual_bar": false, "speed_mults": [], "no_bounce": true,
          "hit_interval": 0.2 },
        # A2 — Barrage
        { "range": 6, "damage": 1, "aoe": 1, "hits": 5, "speed": "slow",
          "perfect_window": 0.0, "ok_window": 0.0,
          "dual_bar": false, "speed_mults": [], "no_bounce": true,
          "hit_interval": 0.1 },
        # A3 — Adjacency Slam (handled via "adjacency_slam" in main.gd)
        { "range": 1, "damage": 1, "aoe": 2, "hits": 1, "speed": "",
          "perfect_window": 0.20, "ok_window": 0.40,
          "dual_bar": false, "speed_mults": [0.70],
          "adjacency_slam": true, "stun_on_miss": true },
        # A4 — Dash Combo (handled via "dash_combo" in main.gd)
        { "range": 1, "damage": 1, "aoe": 1, "hits": 3, "speed": "",
          "perfect_window": 0.20, "ok_window": 0.40,
          "dual_bar": false, "speed_mults": [0.70, 1.00, 1.50] },
    ],
},
```

**New runtime state on `Enemy.gd`:**
```gdscript
var dash_attack_index : int    = 0    # alternates A1/A2 for ranged volleys
var turn_state        : String = ""   # "adjacent"|"mid"|"optimal"|"far" — set once at turn-start
```

**New behavior enum entry:**
```gdscript
enum Behavior { AGGRESSIVE, RANGER, DUMMY, BULLDOZER, MAGE, RELENTLESS, DASHER }
```

**New action codes for `main.gd`:**
- `"dash_toward"` — dash up to N hexes toward nearest player, targeting the 5–6 band or adjacency depending on context
- `"dash_away"` — dash up to 5 hexes maximizing distance from all players
- `"dash_reposition"` — dash up to 3 hexes to maintain 5–6 band
- `"adjacency_slam"` — Case 1 melee, shared SPACE, stun on miss
- `"dash_combo"` — Case 2 melee, 3 bars slow→medium→fast, all always fire
- `"ranged_volley"` — fires A1 or A2 based on `dash_attack_index`, then increments it

**Stats summary:**

| Attack | Trigger | Range | Damage | Hits | Special |
|--------|---------|-------|--------|------|---------|
| A1 Triple Shot | d ≥ 4 or fallback | 6 | 1/hit | 3 | fast, 0.2s interval |
| A2 Barrage | d ≥ 4 or fallback | 6 | 1/hit | 5 | slow, 0.1s interval |
| A3 Adjacency Slam | d == 1 | all adj | 1 | shared | OK dodge = dmg no stun; perfect = dodge both; miss = dmg + stun |
| A4 Dash Combo | 2 ≤ d ≤ 3, can reach adj | 1 | 1/hit | 3 | slow→med→fast bars, all always fire |

**Special flags**: dash-only-movement, ranged-alternating, adjacency-slam, dash-combo, stun-on-miss
**Notes**: All case evaluation happens once at turn-start using initial player positions. Dash is always straight-line, stops at first obstacle. Pre-calculation for Case 2 adjacency reachability must happen before any action is taken. See Stun section (Relentless entry) for `stun_turns` tick and integration rules. See §5B for real-time projectile reaction used by A1 and A2.
#### Stats table

| # | Range | Damage | AOE | Hits | Speed | Perfect Window | OK Window | Special |
|---|-------|--------|-----|------|-------|----------------|-----------|---------|
| A1 | 1 | 1 | 1 | up to 5 | — | 0.20s | 0.40s | ball speed ×1.5; chain stops on first hit; all-5-dodge = self-stun 1 turn |

**Special flags**: boxing_bear_combo, applies-stun-on-all-dodge
**Notes**: `plan_action` returns `"boxing_bear_combo"` when adjacent. `main.gd` runs the full chain in one coroutine, passing `speed_mult: 1.5` to each `DodgeBarScene`. Stun is universal — add `stun_turns: int` to both `Enemy.gd` and `Player.gd`. `stun_turns = 1` = skip 1 full turn. See Stun section for tick and integration rules.
### Training Dummy — D (green)

**HP**: 5 (resets to full at the start of its own turn if damaged)
**Actions**: 0
**Move**: 0 hexes
**Behavior**: Never moves. Never attacks. Spawns at col 6, row 5 after floor clear. Used for post-combat weapon testing with infinite actions.

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

# Projectile velocity system
const PROJ_LAUNCH_SPEED    := ???     # tune for ≈12 hex unobstructed range
const PROJ_DECAY_RATE      := ???     # exponential decay coefficient per second
const PROJ_MIN_SPEED       := PROJ_LAUNCH_SPEED * 0.03
const PROJ_NEGATIVE_BOUNCE := ???     # flat px/s subtracted on surface impact (player projectiles)
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
| Tab to switch character | ✅ Done | |
| Sonny charge bar (Boong Q) | ✅ Done | `sonny_charge_bar.gd` — full drift/hold/release/resolve flow |
| Mike Draw Shot (aim + timing) | ✅ Done | `mike_timing_bar.gd` — aim mode, drag-center oscillation, resolve on release |
| Projectile system — tween-based (old) | ✅ Done | `projectile.gd` (visual) + `BounceTracer` in `bounce.gd` + tracking loop in `main.gd` |
| Sonny redirect reaction | ✅ Done | SPACE reaction window, redirect toward mouse, `redirect_count` tracking |
| Mike dodge reaction + counter | ✅ Done | SPACE reaction window, counter-attack on perfect dodge of enemy projectile |
| Supercharged projectile | ✅ Done | Triggers at `redirect_count == 3`, blinking red, AoE explosion |
| Enemy data-driven attack system | ✅ Done | `enemy.gd` — all attacks as dicts with `range`, `damage`, `hits`, `dual_bar`, etc. |
| Archer enemy data | ✅ Done | Defined in `enemy.gd` |
| Assassin enemy data | ✅ Done | Defined in `enemy.gd` with `dual_bar: true`, `speed_mults: [0.80, 1.30]` |
| Sonny Bomb (W) | ✅ Done | Implemented as enemy type "bomb" with explosion on death |
| Mike Grapple Gun (W) | ✅ Done | Pull logic, immovable flag, 2 uses per map |
| World map (nodes, timer, travel) | ✅ Done | |
| **Projectile velocity decay system** | ❌ Not started | Replaces tween + BounceTracer with `_process()` physics loop. Requires rewrite of `bounce.gd` (physics sim with hex-border collision), projectile handling in `main.gd` (ownership, `negative_bounce`, `uses_decay`), and `aim_overlay.gd` (physics preview). Old tween system remains until complete. |
| Auto camera snap to targeted character | ❌ Not started | |
| Archer enemy — combat behavior | ❌ Not started | Data defined; keep-distance AI not yet in `plan_action` |
| Assassin enemy — combat behavior | ❌ Not started | Data defined; dual bar spawn not yet wired in `main.gd` |
| Skills & passives | ❌ Not started | |
| Sonny Boong W upgrades | ❌ Not started | |
| Mike Slingshot W upgrades | ❌ Not started | |
| Act 2 & 3 | ❌ Not started | |

---

*Version 1.7 — Merged new design.md (truth for all non-projectile content) with rewritten Section 5B (unified projectile system: ownership model, hex-border collision, negative_bounce, exponential decay for player projectiles, fixed-speed for enemies). Archer updated to match new projectile rules. Sonny/Mike reaction sections in Section 5 now point to 5B as the source of truth.*
