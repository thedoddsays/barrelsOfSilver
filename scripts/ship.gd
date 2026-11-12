extends RigidBody3D
class_name Ship
## A small square-rigged sloop. Floats on buoyancy probes sampled against the Ocean,
## is driven by the wind according to its point of sail, steers with a rudder whose
## bite grows with speed, and fights with a broadside of four guns on each side.
##
## The ship reads no input itself. A controller (PlayerController or AiCaptain) sets
## `steer_input`, changes sail with sail_up()/sail_down(), and calls fire().
## Sides: +1 = starboard (right, local +X), -1 = port (left).

signal sank

const SAIL_STEPS := [0.0, 0.5, 1.0]
const SAIL_NAMES := ["Furled", "Battle sails", "Full sail"]

const LAYER_WORLD := 1  ## islands and other static scenery
const LAYER_SHIPS := 2

enum Ammo { ROUND, CHAIN, GRAPE }
## Ballistics and damage per ball that hits. Grape fires several small balls per gun.
## Fixed elevation (no range control, as in classic top-down sea battles): anything
## along the arc out to max range is in the line of fire.
const AMMO := [
	{"name": "Round shot", "speed": 62.0, "elevation": 10.0, "balls": 1, "spread": 1.5,
		"radius": 0.22, "hull": 5.0, "sails": 1.5, "crew": 1.2},
	{"name": "Chain shot", "speed": 54.0, "elevation": 10.0, "balls": 1, "spread": 2.5,
		"radius": 0.3, "hull": 0.8, "sails": 6.0, "crew": 0.3},
	{"name": "Grape shot", "speed": 44.0, "elevation": 8.0, "balls": 6, "spread": 7.0,
		"radius": 0.1, "hull": 0.15, "sails": 0.4, "crew": 1.0},
]
const GUN_Z := [-4.0, -1.5, 1.0, 3.5]
const GUN_X := 2.6
const GUN_Y := 0.25

var ocean: Ocean

@export_group("Hull")
@export var hull_mass := 20000.0
@export var buoyancy_per_probe := 42000.0
@export var vertical_damping := 8000.0
@export var forward_drag_linear := 1500.0
@export var forward_drag_quadratic := 800.0
@export var lateral_drag := 40000.0

@export_group("Sailing")
## Arcade "game scale": ships move much faster than real ones so crossing the
## map stays fun. Top speed is roughly 12 m/s on a broad reach in a good wind.
@export var max_thrust := 160000.0
@export var rudder_torque := 380000.0
@export var full_rudder_speed := 8.0  ## m/s at which the rudder has full bite
@export var heel_torque := 180000.0
@export var sail_handling_speed := 0.5  ## how fast the crew sets/furls sail (per second)
## Speed shown on the HUD is scaled down so the numbers read like a real ship's knots.
@export var knots_display_scale := 0.5

@export_group("Combat")
@export var max_hull := 100.0
@export var max_crew := 60.0
@export var reload_time := 7.0  ## seconds per broadside with a full crew
@export var free_when_sunk := true  ## false for the player, so references stay valid

@export_group("Colours")
@export var hull_color := Color(0.30, 0.18, 0.10)
@export var sail_color := Color(0.93, 0.89, 0.80)
@export var flag_color := Color(0.04, 0.04, 0.04)

var steer_input := 0.0  ## -1 = hard to port, +1 = hard to starboard
var sail_index := 2
var sail_amount := 0.0
var sail_efficiency := 0.0
var point_of_sail := ""
var speed_knots := 0.0

var hull := 0.0
var sails := 100.0  ## 0..100 condition of canvas and rigging
var crew := 0.0
var is_sunk := false

var _reload := {-1: 0.0, 1: 0.0}  ## seconds left, per side
var _reload_total := {-1: 1.0, 1: 1.0}
var _pending_shots: Array[Dictionary] = []  ## guns in a broadside fire in a ripple
var _sink_time := 0.0
var _v_fwd := 0.0

var _probes: Array[Vector3] = []
var _yards: Array[Node3D] = []
var _sails: Array[MeshInstance3D] = []
var _sail_heights: Array[float] = []
var _wake: CPUParticles3D


func _ready() -> void:
	mass = hull_mass
	can_sleep = false
	angular_damp = 1.5
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.9, 0.0)  # low ballast keeps her upright
	collision_layer = LAYER_SHIPS
	collision_mask = LAYER_WORLD | LAYER_SHIPS
	add_to_group("ships")
	hull = max_hull
	crew = max_crew
	for x in [-2.0, 2.0]:
		for z in [-6.0, -2.0, 2.0, 6.0]:
			_probes.append(Vector3(x, -1.0, z))
	_build_collision()
	_build_visuals()
	_build_wake()


# ---------------------------------------------------------------------------
# Controller API
# ---------------------------------------------------------------------------

func sail_up() -> void:
	sail_index = mini(sail_index + 1, SAIL_STEPS.size() - 1)


func sail_down() -> void:
	sail_index = maxi(sail_index - 1, 0)


func sail_name() -> String:
	return SAIL_NAMES[sail_index]


## Compass bearing of the bow (0 = north, PI/2 = east).
func heading_bearing() -> float:
	var f := -global_basis.z
	return atan2(f.x, -f.z)


func hull_frac() -> float:
	return hull / max_hull


func sails_frac() -> float:
	return sails / 100.0


func crew_frac() -> float:
	return crew / max_crew


## Short-handed crews reload and handle sail more slowly.
func crew_factor() -> float:
	return clampf(crew_frac() * 1.3, 0.3, 1.0)


## Torn canvas and cut rigging cost speed.
func sail_power() -> float:
	return 0.3 + 0.7 * sails_frac()


func can_fire(side: int) -> bool:
	return not is_sunk and crew >= 1.0 and _reload[side] <= 0.0


## 0 = just fired, 1 = loaded.
func reload_progress(side: int) -> float:
	return 1.0 - clampf(_reload[side] / _reload_total[side], 0.0, 1.0)


func fire(side: int, ammo: int) -> bool:
	if not can_fire(side):
		return false
	for g in GUN_Z.size():
		_pending_shots.append({"delay": g * 0.09 + randf() * 0.05, "side": side, "gun": g, "ammo": ammo})
	var t := reload_time / crew_factor()
	_reload[side] = t
	_reload_total[side] = t
	return true


## Horizontal unit vector pointing out of the given side.
func side_dir(side: int) -> Vector3:
	var d := global_basis.x * float(side)
	d.y = 0.0
	return d.normalized()


func gun_position(side: int, gun: int) -> Vector3:
	return global_transform * Vector3(GUN_X * side, GUN_Y, GUN_Z[gun])


## World velocity of a ball leaving a gun on `side`. Deliberately does NOT add the
## ship's own motion: balls fly square to the hull, so the firing arcs stay fixed
## relative to the ship and aiming is just "point the broadside at them".
func shot_velocity(side: int, ammo: int, yaw_jitter_deg := 0.0, pitch_jitter_deg := 0.0) -> Vector3:
	var a: Dictionary = AMMO[ammo]
	var speed: float = a["speed"]
	var elev := deg_to_rad(float(a["elevation"]) + pitch_jitter_deg)
	var out := side_dir(side).rotated(Vector3.UP, deg_to_rad(yaw_jitter_deg))
	return (out * cos(elev) + Vector3.UP * sin(elev)) * speed


## Approximate distance at which a ball of this type hits the water.
static func ammo_range(ammo: int) -> float:
	var a: Dictionary = AMMO[ammo]
	var speed: float = a["speed"]
	var e := deg_to_rad(float(a["elevation"]))
	var vy := speed * sin(e)
	var h := 1.3  # gun height above the water
	var t := (vy + sqrt(vy * vy + 2.0 * Cannonball.GRAVITY * h)) / Cannonball.GRAVITY
	return speed * cos(e) * t


## Rough hit volume: hull plus rigging. Cheap enough to test every ball every frame.
func contains_point(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < 2.7 and l.y > -1.6 and l.y < 14.5 and l.z > -10.0 and l.z < 7.0


func take_hit(ammo: int, at: Vector3, ball_velocity: Vector3) -> void:
	if is_sunk:
		return
	var a: Dictionary = AMMO[ammo]
	var r := randf_range(0.6, 1.4)
	hull = maxf(hull - float(a["hull"]) * r, 0.0)
	sails = maxf(sails - float(a["sails"]) * r, 0.0)
	crew = maxf(crew - float(a["crew"]) * randf_range(0.5, 1.5), 0.0)
	apply_impulse(ball_velocity.normalized() * 1500.0, at - global_position)
	Fx.splinters(get_parent(), at)
	if hull <= 0.0:
		_sink()


func _sink() -> void:
	is_sunk = true
	sail_index = 0
	steer_input = 0.0
	_pending_shots.clear()
	sank.emit()


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if ocean == null:
		return
	var t := ocean.wave_time()
	_tick_guns(delta)

	# A holed hull sits lower; a sinking one loses its buoyancy over a few seconds.
	var float_mult := 0.8 + 0.2 * hull_frac()
	if is_sunk:
		_sink_time += delta
		float_mult = clampf(0.75 - _sink_time * 0.12, 0.0, 1.0)
		if _sink_time > 25.0:
			if free_when_sunk:
				queue_free()
			else:
				freeze = true
			return

	# --- Buoyancy -------------------------------------------------------------
	var wet := 0
	for p in _probes:
		var wp: Vector3 = global_transform * p
		var depth := ocean.get_height(wp.x, wp.z, t) - wp.y
		if depth > 0.0:
			wet += 1
			var r := wp - global_position
			var pv := linear_velocity + angular_velocity.cross(r)
			var lift := buoyancy_per_probe * minf(depth, 2.5) * float_mult - pv.y * vertical_damping
			apply_force(Vector3.UP * lift, r)
	var wet_frac := float(wet) / float(_probes.size())

	# --- Hull drag: slippery fore-and-aft, the keel resists sideslip ----------
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()
	_v_fwd = linear_velocity.dot(fwd)
	var v_side := linear_velocity.dot(right)
	speed_knots = absf(_v_fwd) * 1.944 * knots_display_scale
	var drag := -fwd * _v_fwd * (forward_drag_linear + forward_drag_quadratic * absf(_v_fwd))
	drag += -right * v_side * lateral_drag
	apply_central_force(drag * wet_frac)

	if is_sunk:
		apply_torque(fwd * 60000.0)  # roll over as she goes down
		return

	# --- Sails ----------------------------------------------------------------
	sail_amount = move_toward(sail_amount, SAIL_STEPS[sail_index], delta * sail_handling_speed * crew_factor())
	var wind_dir: Vector3 = Wind.direction()
	var off_wind := rad_to_deg(fwd.angle_to(-wind_dir))  # 0 = bow into the wind
	sail_efficiency = _efficiency(off_wind)
	point_of_sail = _point_of_sail_name(off_wind)
	var push := max_thrust * Wind.strength * sail_efficiency * sail_amount * sail_power() * wet_frac
	apply_central_force(fwd * push)

	# Crosswind on the canvas heels her over.
	var cross := wind_dir.dot(right) * Wind.strength * sail_amount
	apply_torque(fwd * cross * heel_torque)

	# --- Rudder ---------------------------------------------------------------
	var authority := 0.5 + 0.5 * clampf(absf(_v_fwd) / full_rudder_speed, 0.0, 1.0)
	apply_torque(Vector3.UP * -steer_input * rudder_torque * authority * wet_frac)


func _tick_guns(delta: float) -> void:
	for side: int in [-1, 1]:
		_reload[side] = maxf(float(_reload[side]) - delta, 0.0)
	for i in range(_pending_shots.size() - 1, -1, -1):
		var s := _pending_shots[i]
		s["delay"] = float(s["delay"]) - delta
		if float(s["delay"]) <= 0.0:
			_fire_gun(s["side"], s["gun"], s["ammo"])
			_pending_shots.remove_at(i)


func _fire_gun(side: int, gun: int, ammo: int) -> void:
	var a: Dictionary = AMMO[ammo]
	var spread: float = a["spread"]
	var balls: int = a["balls"]
	var muzzle := gun_position(side, gun)
	for b in balls:
		var ball := Cannonball.new()
		ball.shooter = self
		ball.ammo = ammo
		ball.ocean = ocean
		ball.velocity = shot_velocity(side, ammo, randf_range(-spread, spread), randf_range(-spread, spread) * 0.4)
		get_parent().add_child(ball)
		ball.global_position = muzzle
	var out := side_dir(side)
	Fx.muzzle(get_parent(), muzzle, out)
	apply_impulse(-out * 2500.0, muzzle - global_position)  # recoil rocks the hull


## Arcade-forgiving point-of-sail curve: slow but never stopped dead head to wind
## (so you keep steerage and can always turn out of it), best on a broad reach,
## a touch slower dead downwind.
const IRONS_DEG := 30.0

func _efficiency(off_deg: float) -> float:
	if off_deg < IRONS_DEG:
		return remap(off_deg, 0.0, IRONS_DEG, 0.25, 0.35)
	if off_deg < 90.0:
		return remap(off_deg, IRONS_DEG, 90.0, 0.35, 0.85)
	if off_deg < 135.0:
		return remap(off_deg, 90.0, 135.0, 0.85, 1.0)
	return remap(off_deg, 135.0, 180.0, 1.0, 0.9)


func _point_of_sail_name(off_deg: float) -> String:
	if off_deg < IRONS_DEG:
		return "In irons"
	if off_deg < 70.0:
		return "Close-hauled"
	if off_deg < 110.0:
		return "Beam reach"
	if off_deg < 160.0:
		return "Broad reach"
	return "Running"


func _process(delta: float) -> void:
	# Furl/unfurl the canvas toward the yards.
	var k := maxf(sail_amount, 0.04)
	for i in _sails.size():
		_sails[i].scale.y = k
		_sails[i].position.y = -_sail_heights[i] * 0.5 * k
	# Brace the yards round to catch the wind (cosmetic).
	var wl := global_basis.inverse() * Wind.direction()
	var phi := atan2(wl.x, -wl.z)
	var brace := clampf(-phi * 0.5, -0.9, 0.9)
	for y in _yards:
		y.rotation.y = lerp_angle(y.rotation.y, brace, delta * 1.5)
	# Forward speed only, so bobbing in a swell doesn't leave a wake.
	_wake.emitting = absf(_v_fwd) > 0.8 and not is_sunk


# ---------------------------------------------------------------------------
# Construction. Placeholder geometry built from primitives so the prototype has
# no asset dependencies; swap for a real model later.
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.6, 2.2, 16.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.0, -2.0)
	add_child(col)


func _build_visuals() -> void:
	var wood := _mat(hull_color, 0.85)
	var dark := _mat(Color(0.12, 0.08, 0.05), 0.9)
	var deck := _mat(Color(0.55, 0.40, 0.25), 0.8)
	var canvas := _mat(sail_color, 0.95)
	var black := _mat(Color(0.04, 0.04, 0.04), 0.9)
	var flag := _mat(flag_color, 0.9)

	# Hull, wale and deck
	_add_box(Vector3(4.6, 2.2, 12.0), Vector3(0.0, 0.0, 0.0), wood)
	_add_box(Vector3(4.7, 0.3, 12.1), Vector3(0.0, -0.55, 0.0), dark)
	_add_box(Vector3(4.2, 0.1, 11.6), Vector3(0.0, 1.12, 0.0), deck)

	# Bow: a prism turned so its apex points forward (-Z)
	var bow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(4.6, 4.0, 2.2)
	bow.mesh = prism
	bow.material_override = wood
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bow.position = Vector3(0.0, 0.0, -8.0)
	add_child(bow)

	var sprit := _add_cyl(0.12, 6.0, Vector3(0.0, 1.88, -11.9), wood)
	sprit.rotation_degrees.x = -75.0

	# Sterncastle
	_add_box(Vector3(4.6, 1.4, 3.2), Vector3(0.0, 1.8, 4.4), wood)
	_add_box(Vector3(4.3, 0.1, 3.0), Vector3(0.0, 2.52, 4.4), deck)

	# Gun ports (positions match GUN_Z / GUN_Y)
	for side in [-1.0, 1.0]:
		for z: float in GUN_Z:
			_add_box(Vector3(0.1, 0.45, 0.6), Vector3(2.32 * side, GUN_Y, z), black)

	# Masts, yards and sails: (mast z, scale)
	for m in [[-2.6, 1.0], [2.0, 0.85]]:
		var mz: float = m[0]
		var s: float = m[1]
		var mast_h := 13.0 * s
		_add_cyl(0.18, mast_h, Vector3(0.0, 1.1 + mast_h * 0.5, mz), dark)
		var lower_y := 1.1 + 5.2 * s
		_add_sail(Vector3(0.0, lower_y, mz), 4.8 * s, 4.0 * s, dark, canvas)
		_add_sail(Vector3(0.0, lower_y + 3.6 * s, mz), 3.8 * s, 3.0 * s, dark, canvas)

	# Colours at the foremast head
	_add_box(Vector3(1.2, 0.8, 0.03), Vector3(0.65, 1.1 + 13.0 + 0.2, -2.6), flag)


func _add_sail(pos: Vector3, w: float, h: float, spar_mat: Material, sail_mat: Material) -> void:
	var yard := Node3D.new()
	yard.position = pos
	add_child(yard)
	_yards.append(yard)

	var spar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = w + 0.6
	spar.mesh = cyl
	spar.material_override = spar_mat
	spar.rotation_degrees.z = 90.0
	yard.add_child(spar)

	var sail := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, h, 0.06)
	sail.mesh = box
	sail.material_override = sail_mat
	sail.position.y = -h * 0.5
	yard.add_child(sail)
	_sails.append(sail)
	_sail_heights.append(h)


func _build_wake() -> void:
	_wake = CPUParticles3D.new()
	_wake.position = Vector3(0.0, -0.2, 6.5)
	_wake.amount = 120
	_wake.lifetime = 4.0
	_wake.local_coords = false
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(1.5, 0.1, 0.5)
	_wake.direction = Vector3.UP
	_wake.spread = 30.0
	_wake.initial_velocity_min = 0.2
	_wake.initial_velocity_max = 0.8
	_wake.gravity = Vector3.ZERO
	_wake.scale_amount_min = 1.0
	_wake.scale_amount_max = 2.5
	_wake.mesh = Fx.particle_quad()

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.45))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_wake.color_ramp = ramp
	add_child(_wake)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _add_box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _add_cyl(radius: float, height: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi
