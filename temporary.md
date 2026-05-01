## 2026-05-01 — Guardian Gorilla enemy

**Changes (hextile.gd)**:
- Added `COLOR_GUARD_ARC` (silver-blue) and `"guard_arc"` tile state.

**Changes (enemy.gd)**:
- Added `GUARDIAN_GORILLA` to `Behavior` enum.
- Added `guard_facing: int = 0` and `guard_attack_index: int = 0` runtime state.
- Added `"guardian_gorilla"` preset: HP 5, 2 actions, move 2, silver-blue, `Behavior.GUARDIAN_GORILLA`. Attacks: A1 Shield Slam (front arc, 0 dmg, stun on miss, shared SPACE), A2 Triple Strike (3 bars 0.7×/1.0×/1.5×, 1 dmg each, all always fire).
- `plan_action()`: `Behavior.GUARDIAN_GORILLA` always returns `"guardian_gorilla_turn"`.

**Changes (main.gd)**:
- Added `GUARD_ARC` constant — for each of 6 facing directions, the 3 arc direction indices forming the 180° front arc.
- Added `_guard_update_facing(enemy)` — snaps guard facing to best cube direction toward nearest player.
- Added `_guard_arc_hexes(enemy)` — returns the 3 in-grid front arc hex positions.
- Added `_guard_is_shielded_from(enemy, src_col, src_row)` — direction-based front arc check (for melee/push).
- Added `_guard_proj_from_front(enemy, proj)` — checks projectile incoming direction vs front arc (using world XZ neighbor positions).
- Added `_guard_refresh_arc_hexes()` — paints front arc hexes blue; called at end of `_refresh_tile_colors()`.
- Modified `_handle_enemy_proj_hit`: front-arc projectiles are redirected toward nearest player (god-owned, neg_bounce × 0.5), no damage to guard.
- Modified `_push_enemy`: push from front arc is cancelled (push immunity).
- Modified `_player_attack_enemy`: melee from front arc deals −1 damage (min 0).
- Added `_guard_slam_async(enemy)` — A1: shared SPACE for all players in arc hexes; 0 dmg; stun on miss.
- Added `_guard_triple_strike_async(enemy, target_idx)` — A2: 3 sequential bars identical to Dasher combo.
- Added `_guard_attack_once(enemy)` — selects A1 if both players adjacent, else alternates via `guard_attack_index`.
- Added `_guardian_gorilla_turn_async(enemy)` — full turn: if adjacent: attack + reposition; else: move + update facing + attack if now adjacent or d≤2.
- Added `"guardian_gorilla_turn"` match case → `await _guardian_gorilla_turn_async(enemy); return`.

---

## 2026-05-01 — Dasher enemy

**Changes (enemy.gd)**:
- Added `DASHER` to `Behavior` enum.
- Added `"dasher"` preset: HP 7, 2 actions, no standard movement (`move_range=0`), electric blue, `Behavior.DASHER`. Attacks: A1 Triple Shot (range 6, fast, 3 hits, 0.2s interval), A2 Barrage (range 6, slow, 5 hits, 0.1s interval), A3 Adjacency Slam (range 1, stun on miss), A4 Dash Combo (range 1, 3 bars at 0.7×/1.0×/1.5×).
- Added `dash_attack_index: int = 0` runtime state (alternates A1/A2 each ranged volley).
- `plan_action()`: `Behavior.DASHER` always returns `"dasher_turn"`.

**Changes (main.gd)**:
- Added `CUBE_DIR_VECS` constant — 6 cube-coordinate unit directions for straight-line hex walks.
- Added `_is_dash_path_blocked(pos, exclude_enemy)` — impassable tile or occupied entity check.
- Added `_dasher_best_dash_dest(enemy, max_range, mode, target_col, target_row)` — scores all 6 directions (stops at first obstacle), picks best landing hex per mode: `"band"` (prefer d=5–6 from target), `"approach"` (minimize d), `"flee"` (maximize min-d from all players). Tie-break: greatest travel distance.
- Added `_dasher_do_dash(enemy, dest)` — updates grid position, smooth animation, fire-pit check.
- Added `_dasher_ranged_volley_async(enemy, target_idx)` — fires A1 or A2 projectiles sequentially with per-attack interval; toggles `dash_attack_index` after firing.
- Added `_dasher_adjacency_slam_async(enemy)` — one shared DodgeBar for all adjacent players; miss → `stun_turns=1` per affected player.
- Added `_dasher_combo_async(enemy, target_idx)` — 3 sequential DodgeBars at 0.7×/1.0×/1.5× speed; all 3 always fire regardless of result.
- Added `_dasher_find_min_adjacent_dash(enemy, target_col, target_row, max_range)` — walks all 6 directions to find the fewest-step dash that lands adjacent to target; returns `(-1,-1)` if unreachable.
- Added `_dasher_turn_async(enemy)` — full 2-action turn coroutine per new design spec: d>6: band-dash+volley; d=4–6: volley+reposition-dash(max 3); d=2–3: pre-check adjacency reachability (if reachable: min-step dash+combo; else: band-dash+volley); d=1: slam+flee-dash(max 5).
- Added `"dasher_turn"` match case → `await _dasher_turn_async(enemy); return`.

---

## 2026-04-30 — Boxing Bear (Boxing Bear) + universal Stun

**Changes (enemy.gd)**:
- Added `"boxing_bear"` preset: HP 5, 1 action, move 2, AGGRESSIVE, dark orange. Attack dict has `boxing_bear_combo: true`, `max_chain: 5`, `chain_speed_mult: 1.5`.
- Added `stun_turns: int = 0` runtime state (universal stun, 1 = skip 1 full turn).
- `plan_action()` AGGRESSIVE branch: new `elif enemy_type == "boxing_bear"` — returns `"boxing_bear_combo"` when adjacent (dist ≤ 1), else falls through to "move".

**Changes (Player.gd)**:
- Added `var stun_turns: int = 0`.

**Changes (main.gd)**:
- `_run_enemy_actions()`: after `tick_turn()`, checks `enemy.stun_turns > 0` — decrements, shows "STUNNED" popup, returns early (skips all actions).
- Added `"boxing_bear_combo"` match case → `await _boxing_bear_combo_async(enemy, target_idx)`.
- Added `_boxing_bear_combo_async(enemy, target_idx)`: spawns up to 5 sequential DodgeBars at `speed_mult 1.5` with the same `dodge_line`. Chain breaks on first hit (1 dmg). All 5 dodged → `enemy.stun_turns = 1` + "STUNNED!" popup.
- Added `_maybe_skip_stunned_current_player()`: if current player's `stun_turns > 0`, decrements, shows "STUNNED" popup, calls `_end_player_turn()`.
- Called `_maybe_skip_stunned_current_player()` at: start of player turn (after enemy turn ends) and end of `_end_player_turn()` when switching to next player.

---

## 2026-04-29 — Mage enemy wired up (aim + eruption cycle)

**Changes (enemy.gd)**:
- Added `eruption_attack_idx: int = 0` runtime state (which attack was aimed).
- `plan_action()` RANGER branch: mage special case — returns "erupt" if pending_eruption, "move_away" if adjacent (dist ≤ 1), "aim" if dist ≤ range_max (6), else falls through to "move". LOS check delegated to main.gd.
- Added `interrupt_cast()`: clears pending_eruption + locked coords, returns true if a cast was active.

**Changes (Player.gd)**:
- Added `var burn_stacks: int = 0`.

**Changes (hextile.gd)**:
- Added `COLOR_MAGE_AIM = Color(0.92, 0.50, 0.10)` and `"mage_aim"` case in `set_state`.

**Changes (main.gd)**:
- Added `var _mage_aim_hexes: Dictionary = {}` state var.
- `_refresh_tile_colors()`: calls `_mage_refresh_aim_hexes()` at the end to re-paint aura on top of normal colors.
- `_run_enemy_actions()`: before the actions loop, if mage has `pending_eruption`, calls `await _mage_erupt_async(enemy)`. Added `"aim"` match case → `_mage_set_aim(enemy, target_idx)` + ACTION_DELAY.
- `_on_charge_resolved()`: calls `_maybe_interrupt_mage_cast(target)` after damaging an enemy.
- `_handle_enemy_proj_hit()`: calls `_maybe_interrupt_mage_cast(enemy)` after damaging an enemy.
- Enemy turn end: added burn tick for players alongside existing poison tick.
- Added functions: `_mage_get_affected_hexes`, `_mage_refresh_aim_hexes`, `_mage_set_aim`, `_mage_erupt_async`, `_maybe_interrupt_mage_cast`.

---

## 2026-04-29 — Assassin fully implemented

**Changes (enemy.gd)**:
- Assassin preset rewritten: A1 = Poison Dagger (range 6, damage 1, speed medium, poison_stacks 1, single_use true); A2 = Melee Combo (range 1, hits 2, dual_bar true, timing_lines [0.60, 0.75], speed_mults [0.70, 1.40]).
- New attack dict keys documented: `poison_stacks`, `single_use`, `timing_lines`.
- Added `ranged_used: bool = false` runtime state (tracks if single-use A1 has fired).
- `plan_action()`: assassin branch prefers A1 if not `ranged_used` and player within 6 hexes; falls back to A2 if adjacent; else moves.

**Changes (main.gd)**:
- `_fire_enemy_projectile()`: passes `attack["poison_stacks"]` onto `proj.proj_poison_stacks`.
- `_handle_player_proj_contact_async()`: on "miss", increments `player.poison_stacks` and shows a POISON popup.
- `_trigger_dodge_bar()`: supports `dual_bar` — iterates `bar_count` bars, each with its own `timing_lines[i]` and `speed_mults[i]`.
- `_enemy_perform_attack()`: after a `single_use` ranged attack fires, sets `enemy.ranged_used = true`.
- `_run_enemy_turn()`: ticks player poison stacks at end of enemy turn (deal N dmg, decrement stacks, check game over).

**Changes (Player.gd)**: added `var poison_stacks: int = 0`.
**Changes (projectile.gd)**: added `var proj_poison_stacks: int = 0`.

---

## 2026-04-29 — Sonny redirect works on enemy projectiles

**Fix**: Enemy projectiles have `negative_bounce = 9999` and `uses_decay = false`. When Sonny redirected one, `redirect_to` added `9999 × 0.5 ≈ 5000` speed, making the ball teleport across the map and die on the next wall bounce.

**Change** (main.gd):
- In `_handle_player_proj_contact_async`, Sonny's "perfect" branch: before calling `proj.redirect_to(mouse_dir)`, sets `proj.negative_bounce = PROJECTILE_NEG_BOUNCE` (5.0), `proj.uses_decay = true`, and `proj.proj_speed = minf(proj.proj_speed, PROJECTILE_LAUNCH_SPEED)` (18.0). This normalizes any enemy projectile to player-like physics so redirect behaves identically to redirecting a player projectile.

---

## 2026-04-28 — Inscribed circle bounce model (columns and characters)

**Change**: Replaced hex-edge bounce (perpendicular bisector between hex centers) with inscribed-circle bounce (cylinder of radius `HEX_INRADIUS = HEX_SIZE × √3/2 ≈ 0.866` centered on each occupied hex). Both main.gd and bounce.gd now use the same model so aim preview matches real trajectory.

**Changes** (main.gd):
- Added `const HEX_INRADIUS : float = HEX_SIZE * sqrt(3.0) / 2.0`.
- Added `_circle_crossing(from_pos, to_pos, center, radius) -> Vector3`: segment–circle quadratic intersection (XZ); returns exact entry point on circle surface.
- `_check_proj_column`: iterates column_tiles, detects `dx²+dz² < HEX_INRADIUS²`, repositions to `_circle_crossing`, bounces with radial normal `(crossing − center).normalized()`.
- `_check_proj_characters`: same circle detection for enemies and players; removed hex params from signature and sub-calls.
- `_handle_enemy_proj_hit`: removed `from_hex` param; bounce normal is `(proj.position − enemy_center).normalized()`.
- `_handle_player_proj_contact_async`: removed `from_hex` param; miss branch computes radial normal from player center.
- `_on_proj_died`: removed `_proj_prev_hex.erase(pid)` (state var eliminated).
- Deleted `_hex_edge_normal` and `_hex_border_point` (no longer used).

**Changes** (bounce.gd):
- Updated doc comment.
- `trace()`: replaced `old_hex` / `world_to_hex` calls with circle-based column and entity detection using same `inradius = hex_size × √3/2`; added `_circle_crossing` helper; radial normals for all bounces.
- Removed `_hex_edge_normal` and `_hex_border` helpers.

---

## 2026-04-28 — Fix aim preview / projectile wall bounce mismatch

**Fix**: Two bugs caused the blue preview line to diverge from the actual ball trajectory.
1. Wall bounces: tracer bounced from the pre-wall position while real ball bounced from past the wall. Now both compute the exact wall-crossing point (parametric lerp along the step segment) and bounce from there.
2. `_proj_prev_pos`/`_proj_prev_hex` were saved before collision handlers ran, so after a column repositioning the next frame used the pre-reposition position for border intersection. Moved the save to after all collision handling so it reflects `proj.position` which may have been repositioned.

**Changes**:
- `main.gd`: added `_wall_crossing_point(from, to) → Vector3` (parametric boundary crossing). `_check_proj_wall` now takes `prev_pos`, repositions ball to `_wall_crossing_point(prev_pos, p)` before bouncing. `_process_projectiles` saves `_proj_prev_pos/hex` after all collision handlers, not before.
- `bounce.gd`: added `_wall_crossing(old, new) → Vector3` (same math). Wall-bounce branch in `trace()` now uses exact crossing as segment endpoint and new `pos`/`seg_start`.

---

## 2026-04-28 — Projectile bounces off hex border wall, not model center

**Fix**: Projectiles were bouncing from inside the hex (detected after crossing the border). Now the exact crossing point on the hex boundary is computed and the projectile is repositioned there before bouncing.

**Changes** (main.gd):
- Added `_proj_prev_pos : Dictionary` (instance_id → Vector3, world position previous frame). Cleaned up in `_on_proj_died`.
- `_process_projectiles`: captures `prev_pos` and `prev_hex` per projectile, stores them, passes all four (cur_pos, prev_pos, cur_hex, prev_hex) to `_check_proj_column` and `_check_proj_characters`.
- Added `_hex_border_point(prev_pos, cur_pos, obs_hex, from_hex) -> Vector3`: finds the exact point where segment `prev_pos→cur_pos` crosses the shared edge between `from_hex` and `obs_hex` using 2D segment–segment intersection (XZ plane). Edge = perpendicular bisector of the two hex centers, half-length = HEX_SIZE * 0.5.
- `_check_proj_column(proj, cur_pos, prev_pos, cur_hex, prev_hex)`: sets `proj.position = _hex_border_point(...)` before calling `bounce_off_surface`.
- `_check_proj_characters(proj, cur_pos, prev_pos, cur_hex, prev_hex)`: same — repositions to hex border before calling `_handle_enemy_proj_hit` or `_handle_player_proj_contact_async`.

---

## 2026-04-28 — Projectile bounce off hex border, not model center

**Fix**: Bounce normals were computed as `proj.position − entity_center` (model-center approximation). Now use the true hex edge normal: direction from previous hex center toward obstacle hex center.

**Changes** (main.gd):
- Added `_proj_prev_hex : Dictionary` state var (instance_id → Vector2i, previous frame's hex).
- Added `_hex_edge_normal(obstacle_hex, from_hex) -> Vector3`: returns normalized vector from obstacle hex center toward from_hex center (the outward edge normal).
- `_process_projectiles`: computes `cur_hex` + `prev_hex` once per projectile per frame; passes both to `_check_proj_column` and `_check_proj_characters`.
- `_check_proj_column(proj, cur_hex, prev_hex)`: uses `_hex_edge_normal` instead of `proj.position − col_center`. Also simplified exit logic: erase `_proj_last_col_hex[pid]` whenever cur_hex is not a column.
- `_check_proj_characters(proj, cur_hex, prev_hex)`: passes `prev_hex` to `_handle_enemy_proj_hit` and `_handle_player_proj_contact_async`.
- `_handle_enemy_proj_hit(proj, enemy, from_hex)`: bounce uses `_hex_edge_normal(enemy_hex, from_hex)`.
- `_handle_player_proj_contact_async(proj, player_idx, from_hex)`: miss bounce uses `_hex_edge_normal(player_hex, from_hex)`.
- `_on_proj_died`: now also erases `_proj_prev_hex[pid]`.

---

## 2026-04-28 — Reverted auto-end-turn on attack; turn ends only on D

**Fix**: Removed the auto-`_end_player_turn()` calls added to `_on_mike_timing_resolved` and `_on_charge_resolved`. Attacking does NOT end the turn — both characters must press D to end their turns. `mike_shot_used` and `has_attacked` still prevent re-attacking.

**Changes** (main.gd):
- `_on_mike_timing_resolved`: Removed `_end_turn_after_proj_async` / `_end_player_turn()` calls. Restored `_update_valid_moves` / `_refresh_*` / `_check_floor_clear` at the end.
- `_on_charge_resolved`: Removed `_end_player_turn()` call.
- Removed `_end_turn_after_proj_async` helper (no longer needed).

---

## 2026-04-28 — Mike Draw Shot: one shot per turn; aim phase via LMB only

**Changes** (main.gd):
- Added `mike_shot_used : bool = false` state var. Set to `true` in `_on_mike_timing_resolved` after shot fires. Reset in the player-turn-start block alongside `mike_aiming = false` + `_clear_aim_preview()`.
- `_toggle_mike_aim_mode` (Q key): replaced `can_act()` guard with `mike_shot_used` guard so Q has no effect after firing, even if `actions_left > 0`.
- `_handle_lmb_press` (Mike branch):
  - When NOT in aim phase and `not mike_shot_used`: LMB enters aim phase (`mike_aiming=true`, preview updates). Movement is blocked unconditionally for Mike — repositioning is via W (grapple).
  - When IN aim phase and `not mike_shot_used`: LMB commits direction → starts timing bar (shot preview phase). Movement still blocked.
  - When `mike_shot_used`: LMB does nothing (no aim entry, no movement).

---

## 2026-04-28 — Mike LMB: anywhere enters aim mode; movement locked while aiming

**Changes** (main.gd):
- `_handle_lmb_press` (Mike branch): LMB when not aiming + `can_act()` now sets `mike_aiming = true` and calls `_refresh_tile_colors()` / `_refresh_debug()` to activate aim preview immediately. Previously, LMB only moved Mike on valid tiles; now it always enters aim mode.
- Movement via LMB blocked unconditionally when `mike_aiming` is true (the `return` now sits outside the `can_act` guard so even a mis-click can't trigger movement).
- Fallback: if Mike has no actions left (`can_act()` false), LMB still moves on valid tiles as before.

---

## 2026-04-28 — Mike Draw Shot: aim mode fires in any direction

**Fix**: In `_handle_lmb_press`, the `valid_moves` movement check was running before the `mike_aiming` check, causing LMB on any reachable tile to move Mike instead of committing the shot.

**Changes** (main.gd):
- `_handle_lmb_press`: moved aim mode check ABOVE the `valid_moves` check. When `mike_aiming` is true, LMB always commits the shot direction (free mouse direction, any angle). Movement is blocked while aiming. Added `return` to consume LMB even when direction is invalid (too close to Mike).
- RMB handler: added aim mode cancellation on RMB press (per design §5). RMB during aim mode cancels instead of starting camera orbit.

---

## 2026-04-28 — Full projectile system rewrite (design §5B)

**New behavior**: Projectiles now move in real-time via `_process()` with per-frame collision detection in main.gd. Enemy ranged attacks (range > 1) fire real projectiles instead of a DodgeBar. Players react with SPACE in real-time (±0.2s perfect, ±0.4s ok).

**Changes**:
- `projectile.gd`: Complete rewrite. Removed pre-computed `segs`/`hit_hexes` playback. Added `proj_speed`, `proj_direction`, `proj_damage`, `negative_bounce`, `owner_node`, `uses_decay`, `redirect_count`, `is_supercharged`. Added `bounce_off_surface()`, `redirect_to()`, `die()`. Supercharged blink in `_process()`.
- `bounce.gd`: Fixed `min_speed` from 1.0 → 0.54 (= 18 × 0.03).
- `main.gd`:
  - Added constants: `PROJECTILE_MIN_SPEED = 0.54`, `PROJ_ENEMY_SPEED_SLOW/NORMAL/FAST`.
  - Added state: `active_projectiles`, `_proj_last_col_hex`, `_proj_last_char_hex`, `_proj_bounds_min/max`, `_space_pressed_at`, `_mike_caught`.
  - `_ready()`: caches `_proj_bounds_min/max` from `grid_origin`.
  - `_process()`: now calls `_process_projectiles(delta)`.
  - Added `_process_projectiles()`, `_check_proj_wall()`, `_check_proj_column()`, `_check_proj_characters()`.
  - Added `_fire_projectile()` factory; `_fire_enemy_projectile()` for ranged attacks.
  - Added `_handle_enemy_proj_hit()`: damage + bounce for enemy targets.
  - Added `_handle_player_proj_contact_async()`: ±0.4s SPACE window, Sonny redirect, Mike catch/dodge.
  - Added `_supercharged_explosion()`: AoE at impact tile + ring.
  - Added `_fire_mike_caught_projectiles_async()`: fires caught projectiles 0.3s apart.
  - `_on_mike_timing_resolved()`: removed `await _fire_bouncing_projectile`, now calls `_fire_projectile` directly.
  - `_enemy_perform_attack()`: routes range>1 attacks to `_fire_enemy_projectile` + `await proj.projectile_died`.
  - `_input()`: KEY_SPACE now records `_space_pressed_at`.
  - Removed dead `_fire_bouncing_projectile()`.

---

## 2026-04-28 — Sonny Q can now target the bomb

**Changes** (main.gd):
- `_update_valid_attack_targets`: removed `if e.enemy_type == "bomb": continue` — bomb now highlighted as a valid attack tile for Sonny when adjacent.
- `_handle_lmb_press`: removed `and target_enemy.enemy_type != "bomb"` guard — clicking the bomb tile now starts Sonny's charge bar.

The push-first mechanic already handles the rest: bomb is pushed on hit, and if it collides with a wall/column it takes damage and explodes before Sonny's damage lands.

---

## 2026-04-28 — Sonny Q attack: push 1 added

**New behavior**: Sonny's Boong (Q) now pushes the target 1 hex away before dealing damage, on both perfect and normal hits. Miss has no push.

**Changes** (main.gd):
- Added `_push_enemy(enemy, from_col, from_row, push_value)` — computes push destination via cube-coord arithmetic, handles wall/column collision (target takes push_value dmg), enemy-on-enemy collision (both take 1 dmg, chain at push_value−1), and free-tile movement.
- Modified `_on_charge_resolved`: calls `_push_enemy` before `take_damage` when dmg > 0. Guards damage with `is_instance_valid(target_enemy) and target_enemy.hp > 0` so a wall-kill during push skips the damage step.

---

## 2026-04-28 — Bomb rework: explode on death instead of fuse timer

**New behavior**: bomb explodes (AOE 2, 2 dmg) the moment its HP hits 0, from any source (Mike's projectile, etc.). No fuse countdown.

**Changes** (main.gd):
- `_place_bomb_at`: removed `fuse_turns` assignment and FuseLabel3D node.
- `_run_enemy_turn`: removed `await _tick_bombs_after_enemy_turn()` call.
- Deleted `_tick_bombs_after_enemy_turn` function entirely.
- `_kill_enemy` split into two:
  - `_kill_enemy(enemy)` — if bomb, calls `_explode_bomb` as background coroutine; otherwise calls `_do_kill_enemy`.
  - `_do_kill_enemy(enemy)` — actual removal from enemies array + death animation.
- `_explode_bomb`: replaced `_kill_enemy(bomb)` with `_do_kill_enemy(bomb)` to avoid recursion. Removed debug prints.
