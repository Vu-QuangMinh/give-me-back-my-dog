# Maps
Have something to let people know that it is getting late.
Get to the end of the combat map without killing all enemies will allow you to move out of that node but you only get reward if all enemies are killed.
Maybe have the characters comment about it. Calculate the percentage of passing, assume random choices. IF it is less than 70%, says we need to hurry up. If it is less than 50%, says that we are going to be late. If it is less than 30% says that we are doomed unless something great happen.
SHow this percentage out.



uhm xong r có boss kiểu immune damage của mình
nhưng trong phòng có trap
mình phải redirect mấy cái đó
đánh mới có dam

# Problem: if there are attacks that affect both players, how do we even time the dodge?

## Enemies:
1) Grunt (already have) = Skull crab
2) Archer (already have, nerf it down a bit) = Bat (sonic wave attac).
3) Assassin - Attack twice, move faster. Also 3HP = Squirrel
4) Bulldozer (tanky, charge attack, push even if blocked) (5HP)
5) Mage - Squishy, attacks are forecasted. 1 with AOE 2 aimin on the closest player. The other damage everything in a line also aim at a player
6) Guard: hold a shield, always try to FACE the closest character, get -1 damage if attacked from the direction it is facing +45 degree angle both side (total of 120* degree, will have a visual crescent to show it)
7) Spider: Move 3, 1HP, explode when in melee range, 2 actions.
8) Feral beast: if you counter attack, he will attack you again. This keep on going until you miss a parry or if he dies. 5HP
## Miniboss
1) Dasher (7HP): Dash in and out. If there is no player within 6 hexes: Dash up to 4 tiles toward the closest player, prefer to stay 5-6 range from them if there were no player within 6 hexes at the start of the turn. IF there is a player within 5-6 range, will attack range mode : A1: 3 shots at very fast speed (0.2 interval between each). A2: 5 shots at slow speed (0.1 interval between each). If there is an adjacent player: Attack all adjacent tile and apply stun then dash up to 6 hexes away (prefer to stay as far from player as possible) dodge ball is slow, a perfect dodge will dodge both the damage and the stun, a normal dodge only dodge the damage but still get stunned. If there is a player within 2-3-4 hexes but not adjacent: Dash to the closes player and attack melee 3 times (3 separate timing bar, 1 with slow ball, 1 with medium speed bar and 1 with fast speed bar). Dash need to be on a straight line, need to calculate which dash direction and what distance to optimize the range from player to be 5 or 6.
2) Summoner (7HP): Keep summoning random enemies.
3) High guard (10HP): Grunt + bulldozer + Assassin + Guard
4) Brood mother: Shoot out spider within 4 range of the characters. 2 a turn as a free action. Attack: spit web: Aim at the closest player, deal no damage but apply 1 slow (move 1 less). Effect: in AOE 2, apply the web effect (visual effect: has white webline lay on top of it). Spider movement on the webbed area does not cost movement point. The Brood mother try to move run away from players. Movement =1. If it has a player adjacent to it,  no longer spawn spiderling, no longer run away, no longer spit web. Attack: 1 damage + 1 poison (poison stack)
5) Arch mage: Squishy, attacks are forecasted. 1 with AOE 3 aimin on the closest player. The other damage everything in a line at 3 hex width. Teleport to the other side of the map if there is a player within 2 hexes.

# Terrains
## Types of overall terrains: 
Each arc will have 3 types of terrains with different composition, relating to the actual lore/ position of that place
For example: Arc 1 would be from the house to the mountain so any nodes within the first 33 km would be suburban or abandonned type. from 33.1 to 66.0km would be Forest / meadow type and from 66.1 to end would be mountain type. Would this be too many assets?

Type tiles need for Arc 1-1 (surburban)
- Road
- Tree
- House
- Traffic light, stop signs
- Trash can
- Bigger house with glass windows.

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