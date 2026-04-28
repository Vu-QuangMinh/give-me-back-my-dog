# Changelog — Give Me Back My Dog

Lịch sử thay đổi của project, sắp xếp theo thứ tự ngược (mới nhất trên cùng).
Định dạng theo phong cách [Keep a Changelog](https://keepachangelog.com/),
nhóm theo mốc (Mốc N) và loại thay đổi.

Liên kết commit: thay `<HASH>` trong URL `https://github.com/Vu-QuangMinh/give-me-back-my-dog/commit/<HASH>`.

---

## Branch `port-3d` — 2D → 3D rewrite (2026-04-27 → 2026-04-28)

Toàn bộ branch chuyển game từ 2D Node2D sang 3D Node3D, giữ 100% gameplay
mechanics, swap visual sang model `.glb` thật cho 2 nhân vật.

### `fad0cea` — Prune unused assets (2026-04-28)

**chore:** giảm dung lượng project và file `.exe` xuất ra.

- Xoá 5 file `.glb` không được tham chiếu trong `Player.gd MODEL_PATHS_BY_CHAR`:
  Sonny `Run 2 / Walking / Attack`, Mike `output / Walk` (mỗi file kèm
  `.glb.import` + `_texture_0.png` + `.import` = 4 file/asset, tổng 20 file).
- Xoá 2D leftovers tự re-create: `player.tscn`, `CharacterAsset/Sonny/Sonny.png`,
  `SonnyAvatar.png`, `MikeAvatar.png`, `Map/Arc1/LV1.png` + thư mục `Map/`.
- Giữ `world_map.gd / .tscn` (chuẩn bị Mốc 9 polish), HUD `pan_lv2-5` +
  `hype_25/50/75/100` (chuẩn bị item upgrade system).
- **Tiết kiệm**: ~50 MB (Sonny 50→31 MB, Mike 103→69 MB). Export `.exe`
  ước tính giảm từ 194 MB xuống ~140 MB.

### `ab62a86` — Gitignore exported binaries (2026-04-28)

**chore:** thêm `*.exe`, `*.pck`, `*.dll`, `dist/` vào `.gitignore`. Untrack
file 194 MB `Give me back my dog.exe` đã commit nhầm. Giữ source + `.import`
file để bất kỳ ai cũng rebuild lại được.

### `b6e2baf` — Remove 2D leftover files (2026-04-28)

**chore:** xoá các file 2D không dùng làm export báo lỗi
`script 'res://archer.gd' / 'res://grunt.gd' not found`:
- `Archer.tscn`, `Grunt.tscn` (per-enemy 2D scenes; port-3d dùng unified
  `enemy.tscn` với presets trong `enemy.gd`).
- `player.tscn`, `spritesheet.png(.import)` (2D player sprite atlas).
- `main_test.tscn`, `main_test.gd` (2D test harness, broken sau khi main
  thành Node3D).
- `bomb.gd` (2D bomb visual; port-3d dùng Enemy preset `type="bomb"`).

### `9e8c84b` — Mốc 9: Floor scenarios + transition modals (2026-04-28)

**Floor scenarios data-driven (5 floors)** trong `FLOOR_SCENARIOS`:
- Floor 1: 2 grunts (intro, no columns)
- Floor 2: + archer + 1 column
- Floor 3: 2 archers + 2 columns
- Floor 4: assassin + archer + grunt + 3 columns
- Floor 5 (BOSS, `is_boss=true`): 2 grunts + 1 archer + 2 assassins + 2 columns

`_setup_demo_columns` / `_spawn_enemies` đọc từ `_current_scenario()` thay
hardcoded demo. Phase enum thêm `FLOOR_CLEAR`, `VICTORY`.

**Modal screens** (CanvasLayer layer=20 trên HUD layer=5):
- `_show_modal(title, hint, color, callback)` helper — dim BG + Label
  styled (96 pt title / 36 pt hint). Click hoặc ENTER kích hoạt callback.
- Floor clear non-boss → "Floor X CLEARED" xanh → `_next_floor()`.
- Boss clear → "VICTORY!" xanh → `_restart_from_floor_zero()`.
- All players dead → "GAME OVER" đỏ → `_restart_from_floor_zero()`. Trễ
  0.6 s trước modal để xem death animation.

**State persistence**: `Engine.has_meta("current_floor")` đọc trong `_ready`,
set khi advance/restart. Survives scene reload.

**Skipped (defer)**: world_map random graph, reward cards/chests/forging,
3D model cho enemy/bomb (vẫn capsule placeholder).

### `a2202eb` — Mốc 8.3: Bouncing projectile + grapple + aim mode + polish (2026-04-28)

**8.3.1 BounceTracer3D** ([bounce.gd](bounce.gd)) — `RefCounted` class, port
từ 2D `bounce.gd`. Pre-compute path projectile trên XZ plane với
exponential decay + reflection off walls/columns/entities. `stop_on_hit=false`
để projectile bounce off enemy (multiple enemies trên path đều ăn damage).

**8.3.2 Projectile3D** ([projectile.gd](projectile.gd)) — Node3D với sphere
mesh + emission, animate dọc segs. CPUParticles3D trail (24 particles,
lifetime 0.4s, scale_amount_curve fade). Emit
`projectile_finished(hit_hexes)` khi xong.

**8.3.3 Wire Mike timing bar resolve** — `_compute_projectile_trace` build
tracer với grid bounds + columns + enemy positions, dùng cho cả fire AND
aim preview (path khớp 100%).

**8.3.4 Grapple gun** (Mike W key, 2 uses/floor) — Hex-line phase qua
walls/columns; first character (enemy hoặc other player) bị kéo 1 ô về
phía Mike. Pull dest phải passable + empty, else `BLOCKED`. Tile colors
trong grapple mode tô đỏ tất cả enemies. `_spawn_grapple_line` animate
BoxMesh (hold 0.20s + fade 0.30s).

**Polish**:
- **AimOverlay3D** ([aim_overlay.gd](aim_overlay.gd)) vẽ projectile path bằng
  BoxMesh segments stretched (atan2(-z, x) quanh Y axis). Seg đầu xanh đậm,
  bounces sau xanh nhạt + lower alpha.
- **Free direction**: `mike_timing_target Node` → `mike_timing_target_pos
  Vector3`. `_compute_projectile_trace / _fire_bouncing_projectile /
  _start_mike_timing / _on_mike_timing_resolved` tất cả nhận `Vector3`.
  Aim preview dùng `hover_world_pos` (free pixel direction, không lock hex
  center).
- **Q aim mode** chống mis-fire: `mike_aiming` toggle (Q key, chỉ Mike +
  còn action + ngoài timing bar). Preview chỉ hiện khi `mike_aiming=true`.
  LMB outside `valid_moves` chỉ fire nếu aim mode on. Auto-cancel khi click
  fire / switch player / enemy turn.

**`_clear_action_modes()`** helper reset `placing_bomb / grappling /
mike_aiming` + clear preview, gọi tại switch player + start enemy turn.

### `91d7637` — Mốc 7 + 8 partial: Sonny charge bar + bomb, Mike timing bar, .glb models (2026-04-28)

**Mốc 7 — Sonny:**
- **SonnyChargeBar 3D** ([sonny_charge_bar.gd](sonny_charge_bar.gd)) port từ
  2D. Hold LMB → ball push toward 1.0, release → resolve. Zones thu hẹp
  còn 30% (`THRESH_NORMAL=0.895 / THRESH_PERFECT=0.955`). Ball đỏ matching
  Sonny color theme.
- **Bomb** (W key, 1 use/floor) — toggle placement mode, click ô kề bên
  passable → spawn Enemy `type=bomb` với `fuse_turns=2`. Tile preview
  highlight xanh/đỏ. Sau enemy turn, FUSE Label3D giảm dần; tới 0 → AOE
  explosion (target + 6 ô kề, 2 dmg) với `BOOM` popup.

**Mốc 8.1/8.2 — Mike (placeholder, chưa có bouncing):**
- **MikeTimingBar 3D** ([mike_timing_bar.gd](mike_timing_bar.gd)) port từ 2D.
  Click LMB enemy có LOS → spawn bar. Ball oscillate sin quanh `drag_center`
  (biên độ tăng dần). Drag chuột X-axis → dịch `drag_center`. Release →
  resolve theo `|ball_pos - TIMING_LINE 0.7|`. Ball xanh dương + ghost
  sphere indicator.

**.glb model integration:**
- Sonny: scale 0.99, model `Sonny Idle.glb` / `Sonny Run.glb` /
  `Sonny Combo Attack.glb`.
- Mike: scale 0.81, model `Mike idle.glb` / `Mike Run.glb` / `Mike Skill.glb`.
- **Multi-model swap visibility** (KHÔNG inject animation — Godot 4 .glb
  importer phân library theo file). Pre-instantiate 3 model làm con của
  player, swap `visible` trên `play_idle/run/attack`. `play_attack`
  auto-revert idle qua `animation_finished` signal.
- `_try_play_default_animation()` MUST gọi từ `setup_from_preset()` (sau
  `character_name` set), KHÔNG `_ready()` — main.gd `add_child` (fires
  `_ready`) TRƯỚC `setup_from_preset` nên character_name rỗng trong `_ready`.
- Models Mixamo/Blender face +Z; `_face_player_to_nearest_enemy` dùng
  `look_at` rồi `rotate_object_local(Y, PI)` bù.

**Click-to-switch character:**
- Map: LMB on other player capsule (smart pick) → switch active.
- HUD avatar: hover → tween scale 1.15 (12% bigger, pivot center), click →
  emit `player_avatar_clicked` signal.

**Bug fixes:**
- Archer (range>1) bypass DodgeBar với direct damage. Fix: tất cả enemy
  attack đều trigger DodgeBar (Mốc 9+ sẽ thay ranged bằng projectile bounce).
- `enemy.tscn` shared `SubResource("Mat_enemy")` giữa instances; death anim
  alpha tween làm tất cả enemies disappear cùng lúc. Fix:
  `material_override.duplicate()` mỗi instance trong `enemy.gd._ready`.
- Click capsule body (above ground) ray-miss to ground hex sau capsule.
  Fix: smart-pick check XZ projection to capsule axis + 3D Y verify
  (`PICK_Y_MIN/MAX`).
- Hover highlight rule rewrite: chỉ valid_moves tiles light-up trên hover,
  chỉ attackable enemies (Sonny adjacent / Mike LOS-clear) light-up.
- LMB attack: check adjacency tại click time, không qua stale
  `valid_attack_targets` array.

**Polish khác:**
- Name labels font_size 64 → 96 trên Sonny/Mike/enemy scenes.
- Hex line-of-sight algo (cube interpolation + cube_round, ε-nudge).
- HUD END TURN button: end turn cho cả 2 player (D key giữ rotate).
- Camera default `yaw=180°` (camera west of grid, players col=0, enemies
  col=8-10 east → "behind heroes looking forward"). Pitch 41°, distance 37.

### `22a503e` — Mốc 6 polish: damage popups, death animations, attack telegraph (2026-04-28)

- **Damage popup**: 3D `Label3D` billboard float lên + fade trong 0.95 s
  khi entity ăn damage. Màu khác theo result: `-N` (cam) cho enemy hit by
  player, `-N HP` (đỏ) cho player hit, `PERFECT!` (xanh lá) / `DODGE!`
  (vàng) cho successful reactions.
- **Death animation**: scale → 0.15 + sink 0.6m + fade alpha → 0 trong
  0.45 s. Enemies `queue_free` sau, players `visible=false` (giữ node trong
  array cho HUD). Cần `StandardMaterial3D.transparency = ALPHA` trên
  `material_override`.
- **Attack telegraph**: ô của target player flash `attack/selected` 3 lần
  (~0.5 s) trước khi DodgeBar xuất hiện cho player có thời gian phản xạ.
  Apply cho cả melee và ranged stub.

### `29b6b3c` — Mốc 6: Combat melee + DodgeBar 3D (2026-04-28)

**Player melee attack:**
- LMB on adjacent enemy = melee (Sonny dist=1, Mike LOS-clear at any range
  as Mốc 8 placeholder).
- Click-time adjacency check (defensive against stale
  `valid_attack_targets`).
- Capsule-aware mouse picking: ray-vs-capsule với XZ projection + 3D Y
  verify để empty hexes không false-pick nearby entities.
- Hover highlight rules: chỉ `valid_moves` tiles light-up, chỉ attackable
  enemies light-up.

**Hex line-of-sight**: cube-coord interpolation + cube_round. Columns
chặn, fire pits + entities không. Mike attack range = LOS clear.

**Enemy turn execution**: coroutine queue, `ACTION_DELAY=0.5s` giữa
actions. AI per enemy: `tick_turn` → `plan_action × actions_per_turn`.
Move (`best_move_toward / best_move_away` cho RANGER), Attack (`range=1`
spawns DodgeBar, `range>1` damage stub), DUMMY idle.

**DodgeBar 3D**: Node3D với mesh-based tray, 2 rails, 2 caps, yellow/green
zone overlays, white dodge line, sphere ball. BarRoot sub-node scaled
0.20 + tilted +25° quanh X (top hướng camera); labels ở root level giữ
readable size. Attached vào `Camera3D` tại local `(0, -0.18, -1.2)` →
luôn trong view, không bị scene che. Logic không đổi từ 2D: `ball_t /
SPACE freeze / perfect ±4% / dodged ±8% / hit`, signal `bar_finished(result)`.

**Damage flow + death:**
- `_apply_damage_to_player` xử lý perfect/dodged → +1 perfection, hit →
  `take_damage` + reset perfection. Dead player capsule hidden.
- HUD `set_hp` + `set_hype_from_perfection` mỗi đòn damage.
- `_all_players_dead()` → `DEAD` phase, ENTER restart scene.
- Floor clear log khi enemies empty (Mốc 9 sẽ wire world_map).

**Camera default**: yaw 180° (camera west of grid, looking east).

**HUD END TURN button**: end turn cho cả 2 player bất kể remaining
actions. D key giữ per-player rotate.

### `8671855` — Ignore .claude session artifacts (2026-04-28)

**chore:** thêm `.claude/` vào `.gitignore`. `.godot/` và `/android/` đã có sẵn.

### `bbb336e` — Mốc 1-5: 3D port + complete HUD (2026-04-27)

**3D scene rewrite (Mốc 1-4):** Node3D tree với hex grid trong XZ plane
(flat-top brown tiles + white outline), orbital camera (RMB rotate / wheel
zoom / [/] pitch slider), fullscreen 1920x1080 với canvas_items +
camera_distance scaling. Camera default `pitch=41° yaw=-90° dist=37`
(behind Sonny+Mike at row=1 looking north toward enemies). Capsule
placeholders cho player/enemy models, ESC quit.

**HUD (Mốc 5):** [hud.tscn](hud.tscn) CanvasLayer + [hud.gd](hud.gd) với
player panel (avatar + single outer slot column × 2 + HP head/mid/end
với uniform gems + status emoji), HYPE smooth-fill bar giữa Sonny/Mike,
enemy panel (3 dynamic blocks với type-letter avatar placeholder + HP bar),
4 buttons (BACKPACK/UNDO/RESET/END_TURN), dialogue scroll. Wired vào
main.gd qua `_init_hud()` / `_refresh_hud()`; button signals connected.

HUD assets trong `CharacterAsset/HUD/` (panel/avatar/items/font). Item lv1
icons preloaded (pan, bomb cho Sonny; slingshot, hook cho Mike).

---

## Branch `main` — 2D version (origin)

| Commit  | Tác giả | Note |
|---------|---------|------|
| `8c905db` | original | `04/26/2026` |
| `50efdf1` | original | `26/04/2026 play tested` |
| `8e7e856` | original | `Initial commit` |

Branch `main` giữ version 2D gốc làm reference. Branch `port-3d` là version
3D hoàn chỉnh (mục tiêu chính).

---

## Trạng thái hiện tại (2026-04-28)

- **Branch `port-3d`**: 9 mốc xong (Mốc 1-9), đã build `.exe` ~194 MB
  (chưa apply `.glb` exclude filters → có thể giảm xuống ~140 MB sau
  re-export với prune assets).
- **Branch `main`**: 2D gốc, không thay đổi.
- **Push lên GitHub**: Tất cả commit `port-3d` đang **local only**, chưa
  push. Để upload: `git push -u origin port-3d`.

## Mốc reserved (chưa làm, ý tưởng cho future)

- **Mốc 9 polish**: random world_map graph navigation (port `world_map.gd`
  2D đầy đủ), reward cards / chests / forging system, branching paths.
- **3D model thật cho enemy + bomb** (hiện vẫn capsule placeholder).
- **HUD upgrade system**: `pan_lv2-5`, `bomb_lv2-5`, `slingshot_lv2-5`,
  `hook_lv2-5` (assets đã có sẵn, cần wire logic).
- **Save/load**: Engine.meta hiện chỉ persist trong session — thêm save
  file để giữ tiến độ qua khi tắt game.
- **Audio**: SFX cho attack/dodge/move/death, BGM combat + world map.
- **Status effects**: Bleed (stacks), Disarm (turns) đã define trong
  `enemy.gd` attack dicts nhưng chưa wire visual.
