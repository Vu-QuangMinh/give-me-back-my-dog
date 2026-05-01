class_name TimeOfDay
extends Node

# ═══════════════════════════════════════════════════════════
#  Quản lý ánh sáng theo giờ (slider 0-12) + toggle Day/Night.
#  ► Mặt trời/trăng arc từ đông (slider=0) → đỉnh (slider=6) → tây (slider=12).
#  ► Day mode: ánh sáng vàng-cam ở chân trời, vàng-trắng ở đỉnh.
#  ► Night mode: ánh sáng trắng lạnh (moonlight), năng lượng thấp hơn.
# ═══════════════════════════════════════════════════════════

const SUN_DIST : float = 100.0

# Ánh nắng — ấm ở chân trời (sunset/sunrise), gần trắng ở đỉnh.
const SUN_COLOR_HORIZON  : Color = Color(1.00, 0.55, 0.30)   # cam-đỏ
const SUN_COLOR_ZENITH   : Color = Color(1.00, 0.96, 0.88)   # trắng-vàng
const SUN_ENERGY_HORIZON : float = 0.35
const SUN_ENERGY_ZENITH  : float = 1.50

# Ánh trăng — trắng lạnh, năng lượng thấp.
const MOON_COLOR_HORIZON : Color = Color(0.78, 0.72, 0.95)   # tím-lavender ở chân trời
const MOON_COLOR_ZENITH  : Color = Color(0.78, 0.85, 1.00)   # trắng-xanh
const MOON_ENERGY_HORIZON : float = 0.15
const MOON_ENERGY_ZENITH  : float = 0.55

var sun_light : DirectionalLight3D = null
var environment : Environment = null
var is_night : bool = false
var slider_value : float = 6.0   # 0..12, mặc định 6 (đỉnh)

func setup(light: DirectionalLight3D, env: Environment = null) -> void:
	sun_light = light
	environment = env

func set_value(v: float) -> void:
	slider_value = clampf(v, 0.0, 12.0)
	apply()

func set_night(b: bool) -> void:
	is_night = b
	apply()

# Cửa sổ chạng vạng (dusk): trong phase đêm, từ slider 0 (18:00) đến slider
# DUSK_END (21:00) sẽ blend ánh nắng hoàng hôn → ánh trăng. Sau 21:00 chỉ
# còn moon thuần.
const DUSK_END : float = 3.0   # 21:00 = 18:00 + 3h

# Tính góc + position của thiên thể theo slider, set color/energy theo elevation.
func apply() -> void:
	if sun_light == null: return
	var t : float = slider_value / 12.0
	var angle : float = PI * t                  # 0 → π
	var elevation : float = sin(angle)          # 0 ở chân trời, 1 ở đỉnh
	# Sun position trên arc (XY plane, slight Z tilt cho cảm giác nghiêng).
	var sun_pos : Vector3 = Vector3(cos(angle), sin(angle), 0.3) * SUN_DIST
	sun_light.global_position = sun_pos
	if sun_pos.length() > 0.01:
		sun_light.look_at(Vector3.ZERO, Vector3.UP)
	# Pre-compute moon params (dùng cho cả pure-moon + dusk blend).
	var moon_color  : Color = MOON_COLOR_HORIZON.lerp(MOON_COLOR_ZENITH, elevation)
	var moon_energy : float = lerpf(MOON_ENERGY_HORIZON, MOON_ENERGY_ZENITH, elevation)
	if not is_night:
		# Day mode: ánh nắng theo elevation (warm chân trời → trắng đỉnh).
		sun_light.light_color  = SUN_COLOR_HORIZON.lerp(SUN_COLOR_ZENITH, elevation)
		sun_light.light_energy = lerpf(SUN_ENERGY_HORIZON, SUN_ENERGY_ZENITH, elevation)
	else:
		# Night mode: dusk blend trong [0, DUSK_END] giờ.
		# Tại slider=0 (18:00): sun-at-horizon (nối tiếp 18:00 day).
		# Tại slider≥DUSK_END (21:00+): pure moon.
		if slider_value < DUSK_END:
			var dusk_t : float = slider_value / DUSK_END   # 0 → 1
			# Anchor: ánh nắng hoàng hôn (slider=12 day = chân trời tây).
			var sun_sunset_color  : Color = SUN_COLOR_HORIZON
			var sun_sunset_energy : float = SUN_ENERGY_HORIZON
			sun_light.light_color  = sun_sunset_color.lerp(moon_color, dusk_t)
			sun_light.light_energy = lerpf(sun_sunset_energy, moon_energy, dusk_t)
		else:
			sun_light.light_color  = moon_color
			sun_light.light_energy = moon_energy
	# Environment: ambient blend khớp với light.
	if environment:
		var ambient_day  : Color = Color(0.55, 0.60, 0.70)
		var ambient_night : Color = Color(0.10, 0.12, 0.20)
		if not is_night:
			environment.ambient_light_color  = ambient_day
			environment.ambient_light_energy = lerpf(0.6, 1.0, elevation)
		elif slider_value < DUSK_END:
			var dusk_t : float = slider_value / DUSK_END
			environment.ambient_light_color  = ambient_day.lerp(ambient_night, dusk_t)
			environment.ambient_light_energy = lerpf(0.7, 0.6, dusk_t)
		else:
			environment.ambient_light_color  = ambient_night
			environment.ambient_light_energy = 0.6
