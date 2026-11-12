extends RigidBody3D
class_name Ship
## A small square-rigged sloop. Floats on buoyancy probes sampled against the Ocean,
## is driven by the wind according to its point of sail, and steers with a rudder
## whose bite grows with speed.

const SAIL_STEPS := [0.0, 0.5, 1.0]
const SAIL_NAMES := ["Furled", "Battle sails", "Full sail"]

var ocean: Ocean

@export_group("Hull")
@export var hull_mass := 20000.0
@export var buoyancy_per_probe := 42000.0
@export var vertical_damping := 8000.0
@export var forward_drag_linear := 1500.0
@export var forward_drag_quadratic := 800.0
@export var lateral_drag := 40000.0

@export_group("Sailing")
## Pirates!-style "game scale": ships move much faster than real ones so crossing the
## map stays fun. Top speed is roughly 12 m/s on a broad reach in a good wind.
@export var max_thrust := 160000.0
@export var rudder_torque := 380000.0
@export var full_rudder_speed := 8.0  ## m/s at which the rudder has full bite
@export var heel_torque := 180000.0
@export var sail_handling_speed := 0.5  ## how fast the crew sets/furls sail (per second)
## Speed shown on the HUD is scaled down so the numbers read like a real ship's knots.
@export var knots_display_scale := 0.5

var sail_index := 2
var sail_amount := 0.0
var sail_efficiency := 0.0
var point_of_sail := ""
var speed_knots := 0.0

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
	for x in [-2.0, 2.0]:
		for z in [-6.0, -2.0, 2.0, 6.0]:
			_probes.append(Vector3(x, -1.0, z))
	_build_collision()
	_build_visuals()
	_build_wake()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sails_up"):
		sail_index = mini(sail_index + 1, SAIL_STEPS.size() - 1)
	elif event.is_action_pressed("sails_down"):
		sail_index = maxi(sail_index - 1, 0)


func sail_name() -> String:
	return SAIL_NAMES[sail_index]


func heading_bearing() -> float:
	var f := -global_basis.z
	return atan2(f.x, -f.z)


func _physics_process(delta: float) -> void:
	if ocean == null:
		return
	var t := ocean.wave_time()

	# --- Buoyancy -------------------------------------------------------------
	var wet := 0
	for p in _probes:
		var wp: Vector3 = global_transform * p
		var depth := ocean.get_height(wp.x, wp.z, t) - wp.y
		if depth > 0.0:
			wet += 1
			var r := wp - global_position
			var pv := linear_velocity + angular_velocity.cross(r)
			var lift := buoyancy_per_probe * minf(depth, 2.5) - pv.y * vertical_damping
			apply_force(Vector3.UP * lift, r)
	var wet_frac := float(wet) / float(_probes.size())

	# --- Hull drag: slippery fore-and-aft, the keel resists sideslip ----------
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()
	var v_fwd := linear_velocity.dot(fwd)
	var v_side := linear_velocity.dot(right)
	speed_knots = absf(v_fwd) * 1.944 * knots_display_scale
	var drag := -fwd * v_fwd * (forward_drag_linear + forward_drag_quadratic * absf(v_fwd))
	drag += -right * v_side * lateral_drag
	apply_central_force(drag * wet_frac)

	# --- Sails ----------------------------------------------------------------
	sail_amount = move_toward(sail_amount, SAIL_STEPS[sail_index], delta * sail_handling_speed)
	var wind_dir: Vector3 = Wind.direction()
	var off_wind := rad_to_deg(fwd.angle_to(-wind_dir))  # 0 = bow into the wind
	sail_efficiency = _efficiency(off_wind)
	point_of_sail = _point_of_sail_name(off_wind)
	var push := max_thrust * Wind.strength * sail_efficiency * sail_amount * wet_frac
	apply_central_force(fwd * push)

	# Crosswind on the canvas heels her over.
	var cross := wind_dir.dot(right) * Wind.strength * sail_amount
	apply_torque(fwd * cross * heel_torque)

	# --- Rudder ---------------------------------------------------------------
	var steer := Input.get_axis("steer_left", "steer_right")
	var authority := 0.25 + 0.75 * clampf(absf(v_fwd) / full_rudder_speed, 0.0, 1.0)
	apply_torque(Vector3.UP * -steer * rudder_torque * authority * wet_frac)


## Square-riggers can't point high: dead in irons inside ~40 degrees of the wind,
## happiest on a broad reach, a touch slower dead downwind.
func _efficiency(off_deg: float) -> float:
	if off_deg < 40.0:
		return 0.0
	if off_deg < 90.0:
		return remap(off_deg, 40.0, 90.0, 0.0, 0.8)
	if off_deg < 135.0:
		return remap(off_deg, 90.0, 135.0, 0.8, 1.0)
	return remap(off_deg, 135.0, 180.0, 1.0, 0.85)


func _point_of_sail_name(off_deg: float) -> String:
	if off_deg < 40.0:
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
	_wake.emitting = linear_velocity.length() > 0.8


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
	var wood := _mat(Color(0.30, 0.18, 0.10), 0.85)
	var dark := _mat(Color(0.12, 0.08, 0.05), 0.9)
	var deck := _mat(Color(0.55, 0.40, 0.25), 0.8)
	var canvas := _mat(Color(0.93, 0.89, 0.80), 0.95)
	var black := _mat(Color(0.04, 0.04, 0.04), 0.9)

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

	# Gun ports
	for side in [-1.0, 1.0]:
		for z in [-4.0, -1.5, 1.0, 3.5]:
			_add_box(Vector3(0.1, 0.45, 0.6), Vector3(2.32 * side, 0.25, z), black)

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
	_add_box(Vector3(1.2, 0.8, 0.03), Vector3(0.65, 1.1 + 13.0 + 0.2, -2.6), black)


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

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	quad.material = pm
	_wake.mesh = quad

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
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
