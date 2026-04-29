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
