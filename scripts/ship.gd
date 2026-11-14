extends RigidBody3D
class_name Ship
## A sailing ship built from a ShipSpec (data/ships/*.tres): size, mass, rig, guns and
## handling all come from the spec. Floats on buoyancy probes sampled against the Ocean,
## is driven by the wind according to its rig's point-of-sail curve, steers with a rudder
## whose bite grows with speed, and fights with broadsides.
##
## Handling was tuned on the 16 m, 20 t sloop. Every force scales from that baseline with
## the spec's mass, length and beam, so bigger ships feel heavier without hand-tuning.
##
## The ship reads no input itself. A controller (PlayerController or AiCaptain) sets
## `steer_input`, changes sail with sail_up()/sail_down(), and calls fire().
## Sides: +1 = starboard (right, local +X), -1 = port (left).

signal sank
## A collision that did damage. kind: "rammed" (we were hit), "ramming" (we hit them),
## "grounded" (an island). For sound, camera shake and HUD messages.
signal impact(kind: String, closing_speed: float, damage: float)
## Every point of hull damage, tagged: "cannon", "rammed", "ramming" or "grounded".
signal hull_damaged(source: String, amount: float)
## A broadside was ordered (the fleet uses this to mark ships in the line of fire).
signal fired(side: int, ammo: int)
## Another ship hit us with a cannonball or rammed us. `by` may be null.
signal attacked(by: Ship)
## We hit another ship with a cannonball or rammed it.
signal landed_hit(victim: Ship)

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
## Collisions. Closing speeds (m/s, along the contact normal) below BUMP_SPEED are harmless
## nudges. Above it, each m/s does this much hull damage:
## Oared craft: the crew rows when the sails can't do better, giving at least this share of
## full thrust on any heading, even dead upwind (W/S still sets how hard they pull).
const OAR_POWER := 0.65

const BUMP_SPEED := 1.5
const RAM_DAMAGE_TAKEN := 4.0  ## to the ship that gets rammed (a square hit on its side)
const RAM_DAMAGE_RAMMER := 0.8  ## to the ship doing the ramming: a stout bow takes far less
const RAM_CREW_LOSS := 0.4  ## crew thrown about / crushed on the rammed ship, per m/s
const GROUND_DAMAGE := 1.5  ## to a ship striking an island
const CONTACT_COOLDOWN := 1.0  ## one damage event per collision, not one per physics tick

const DEFAULT_SPEC := "res://data/ships/sloop.tres"
## The ship all the tuning below was done on. Other ships scale from it.
const BASE_MASS := 20000.0
const BASE_LENGTH := 16.0
const BASE_BEAM := 4.6
const BASE_HEIGHT := 2.2

## Point-of-sail curves per rig: (degrees off the wind, efficiency). Every rig keeps an
## arcade floor head to wind, so you're slow but never stopped dead (owner playtest 1).
## The second point is where "in irons" ends. MIXED is the curve the sloop was tuned on.
const RIG_CURVES := {
	ShipSpec.Rig.FORE_AND_AFT: [Vector2(0, 0.28), Vector2(25, 0.4), Vector2(60, 0.75),
		Vector2(90, 1.0), Vector2(135, 0.95), Vector2(180, 0.8)],
	ShipSpec.Rig.MIXED: [Vector2(0, 0.25), Vector2(30, 0.35), Vector2(60, 0.6),
		Vector2(90, 0.85), Vector2(135, 1.0), Vector2(180, 0.9)],
	ShipSpec.Rig.SQUARE: [Vector2(0, 0.22), Vector2(35, 0.3), Vector2(60, 0.45),
		Vector2(90, 0.8), Vector2(135, 1.0), Vector2(180, 0.95)],
	# Oared craft: small fore-and-aft sails plus the oar floor (OAR_POWER, see _efficiency).
	ShipSpec.Rig.OARED: [Vector2(0, 0.25), Vector2(30, 0.35), Vector2(60, 0.6),
		Vector2(90, 0.85), Vector2(135, 1.0), Vector2(180, 0.9)],  # sails; oars: OAR_POWER
}

var ocean: Ocean
@export var spec: ShipSpec  ## falls back to DEFAULT_SPEC (the sloop) when empty

@export_group("Baseline tuning (20 t sloop; scaled per ship)")
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
@export var reload_time := 7.0  ## seconds per broadside with a full crew
@export var free_when_sunk := true  ## false for the player, so references stay valid

@export_group("Colours")
@export var hull_color := Color(0.30, 0.18, 0.10)
@export var sail_color := Color(0.93, 0.89, 0.80)
@export var flag_color := Color(0.04, 0.04, 0.04)

var max_hull := 100.0  ## from the spec
var max_crew := 80.0  ## from the spec
## Side in a fight: 0 = the player's fleet, anything else = someone else. Ships on the same
## side can't hit each other with cannon (friendly fire is off, owner 2026-11-13).
var faction := 0
## 0..1 multiplier on sail thrust. The fleet uses it to hold the flagship to fleet pace,
## and escorts use it to keep station without visibly changing sail.
var thrust_limit := 1.0
var status_text := ""  ## what the ship's captain is doing (set by AiCaptain, shown on the HUD)

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
var _contact_cooldown := {}  ## collider instance id -> seconds until it can damage us again
## Velocity history. Contacts are reported after the physics engine has already resolved
## the crash, so impact speed is measured from where we were going a couple of ticks ago.
var _vel_hist: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _ang_hist: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

# Dimensions and forces derived from the spec in _apply_spec().
var _len := BASE_LENGTH
var _beam := BASE_BEAM
var _height := BASE_HEIGHT
var _vscale := 1.0  ## vertical scale vs. the sloop (hull height ratio)
var _mast_top := 14.1
var _buoyancy := 0.0
var _depth_cap := 2.5
var _vdamp := 0.0
var _drag_lin := 0.0
var _drag_quad := 0.0
var _drag_side := 0.0
var _thrust := 0.0
var _rudder := 0.0
var _rudder_speed := 8.0
var _heel := 0.0
var _curve: Array = []
var _irons_deg := 30.0

var _probes: Array[Vector3] = []
var _guns: Array[Vector3] = []  ## starboard-side gun positions (local); port mirrors x
var _yards: Array[Node3D] = []  ## square yards, braced round to the wind
var _booms: Array[Node3D] = []  ## gaff booms, swung out to leeward
var _jibs: Array[Dictionary] = []  ## headsails: {pivot, base}, swung round their stay
var _canvas: Array[Node3D] = []  ## sails, furled by scaling y toward their spar (origin)
var _bellied: Array[Node3D] = []  ## fore-and-aft sails, flipped to belly out to leeward
var _oars: MultiMeshInstance3D  ## oared craft: every oar in one draw call
var _oarlocks: Array[Vector3] = []  ## starboard oarlocks (port mirrors them)
var _oar_phase := 0.0
var _rowing := false  ## the crew is pulling (oars beat the sails on this heading)
var _wake: CPUParticles3D


func _ready() -> void:
	if spec == null:
		spec = load(DEFAULT_SPEC)
	_apply_spec()
	can_sleep = false
	angular_damp = 1.5
	collision_layer = LAYER_SHIPS
	collision_mask = LAYER_WORLD | LAYER_SHIPS
	contact_monitor = true  # needed for ramming / grounding damage
	max_contacts_reported = 8
	add_to_group("ships")
	hull = max_hull
	crew = max_crew
	_build_collision()
	_build_visuals()
	_build_wake()


## Derive size, physics and gun layout from the spec, scaling the sloop's tuning.
func _apply_spec() -> void:
	_len = spec.length
	_beam = spec.beam
	_height = spec.hull_height
	_vscale = _height / BASE_HEIGHT
	max_hull = spec.max_hull
	max_crew = spec.max_crew
	mass = spec.mass_t * 1000.0
	var k := mass / BASE_MASS
	var s := maxf(spec.speed_mult, 0.1)

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.9 * _vscale, 0.0)  # low ballast keeps her upright

	# Buoyancy: hold the weight at the same relative depth as the sloop.
	_buoyancy = buoyancy_per_probe * k / _vscale
	_depth_cap = 2.5 * _vscale
	_vdamp = vertical_damping * k
	# Same acceleration as the sloop; dividing drag by speed_mult (and its square) moves
	# the top speed to exactly speed_mult x the sloop's.
	_thrust = max_thrust * k
	_drag_lin = forward_drag_linear * k / s
	_drag_quad = forward_drag_quadratic * k / (s * s)
	_drag_side = lateral_drag * k
	_rudder_speed = full_rudder_speed * s
	# Turning and heeling scale with the hull's moments of inertia.
	var yaw_i := mass * (_len * _len + _beam * _beam)
	var yaw_i0 := BASE_MASS * (BASE_LENGTH * BASE_LENGTH + BASE_BEAM * BASE_BEAM)
	_rudder = rudder_torque * yaw_i / yaw_i0 * spec.turn_mult
	var roll_i := mass * (_beam * _beam + _height * _height)
	var roll_i0 := BASE_MASS * (BASE_BEAM * BASE_BEAM + BASE_HEIGHT * BASE_HEIGHT)
	_heel = heel_torque * roll_i / roll_i0

	_curve = RIG_CURVES[spec.rig]
	_irons_deg = (_curve[1] as Vector2).x
	if spec.rig == ShipSpec.Rig.OARED:
		_irons_deg = 0.0  # oars take her anywhere

	# Buoyancy probes: 2 x 4 grid under the hull, as on the sloop.
	_probes.clear()
	for x in [-0.435 * _beam, 0.435 * _beam]:
		for z in [-0.375, -0.125, 0.125, 0.375]:
			_probes.append(Vector3(x, -1.0 * _vscale, z * _len))

	# Guns: rows of ports along the side, between 25% forward and 22% aft of amidships.
	_guns.clear()
	var decks := clampi(spec.gun_decks, 1, 3)
	var rows_y: Array = [[0.11], [-0.12, 0.15], [-0.12, 0.12, 0.36]][decks - 1]
	var per_row := ceili(float(spec.guns_per_side) / decks)
	var placed := 0
	for r in decks:
		var n := mini(per_row, spec.guns_per_side - placed)
		for i in n:
			var t := 0.5 if n == 1 else float(i) / float(n - 1)
			_guns.append(Vector3(_beam * 0.5 + 0.3, float(rows_y[r]) * _height, lerpf(-0.25, 0.22, t) * _len))
		placed += n


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
	# Guns fire in a quick ripple; big broadsides ripple faster so they still land together.
	var step := minf(0.09, 1.2 / _guns.size())
	for g in _guns.size():
		_pending_shots.append({"delay": g * step + randf() * 0.05, "side": side, "gun": g, "ammo": ammo})
	var t := reload_time / crew_factor()
	_reload[side] = t
	_reload_total[side] = t
	fired.emit(side, ammo)
	return true


## Horizontal unit vector pointing out of the given side.
func side_dir(side: int) -> Vector3:
	var d := global_basis.x * float(side)
	d.y = 0.0
	return d.normalized()


func length() -> float:
	return _len


func beam() -> float:
	return _beam


## Angle off the wind (degrees) inside which this rig is "in irons".
func irons_deg() -> float:
	return _irons_deg


## Sail efficiency of this ship's rig at `off_deg` degrees off the wind.
func rig_efficiency(off_deg: float) -> float:
	return _efficiency(off_deg)


## Rough top speed (m/s) for this ship sailing at compass `bearing` in the current wind,
## full sail, undamaged. Used to work out fleet pace.
func potential_speed(bearing: float) -> float:
	var dir := Vector3(sin(bearing), 0.0, -cos(bearing))
	var off := rad_to_deg(dir.angle_to(-Wind.direction()))
	return 12.0 * spec.speed_mult * _efficiency(off)


## Like potential_speed(), but if `bearing` is closer to the wind than this rig can point
## (irons + margin), the best progress toward it by tacking ("velocity made good").
func potential_progress(bearing: float, margin_deg: float) -> float:
	var dir := Vector3(sin(bearing), 0.0, -cos(bearing))
	var off := rad_to_deg(dir.angle_to(-Wind.direction()))
	var closest := _irons_deg + margin_deg
	if off >= closest:
		return 12.0 * spec.speed_mult * _efficiency(off)
	return 12.0 * spec.speed_mult * _efficiency(closest) * cos(deg_to_rad(closest - off))


func is_hostile_to(other: Ship) -> bool:
	return other != null and other.faction != faction


## Height in ship space above which the ocean isn't drawn inside the hull outline (see
## ocean.gdshader): the deck, or an open boat's floorboards.
func water_mask_height() -> float:
	return (0.06 if not _oarlocks.is_empty() else 0.45) * _height


func gun_count() -> int:
	return _guns.size()


## Up to `max_count` guns from the lowest gun deck, evenly spread bow to stern (always
## including both ends). Used to draw readable firing arcs for big broadsides.
func aim_guns(max_count: int) -> Array[int]:
	# Lowest gun deck. Guns on a model follow the sheer, so a row isn't perfectly level.
	var low := INF
	for g in _guns:
		low = minf(low, g.y)
	var row: Array[int] = []
	for i in _guns.size():
		if _guns[i].y < low + 0.15 * _height:
			row.append(i)
	if row.size() <= max_count:
		return row
	var picked: Array[int] = []
	for j in max_count:
		picked.append(row[roundi(float(j) * (row.size() - 1) / (max_count - 1))])
	return picked


func gun_position(side: int, gun: int) -> Vector3:
	var g := _guns[gun]
	return global_transform * Vector3(g.x * side, g.y, g.z)


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
	return (absf(l.x) < _beam * 0.5 + 0.4 and l.y > -0.73 * _height and l.y < _mast_top + 0.5
		and l.z > -0.625 * _len and l.z < 0.4375 * _len)


func take_hit(ammo: int, at: Vector3, ball_velocity: Vector3, by: Ship = null, power := 1.0) -> void:
	if is_sunk:
		return
	_note_attack(by)
	var a: Dictionary = AMMO[ammo]
	var r := randf_range(0.6, 1.4) * power
	sails = maxf(sails - float(a["sails"]) * r, 0.0)
	crew = maxf(crew - float(a["crew"]) * randf_range(0.5, 1.5) * power, 0.0)
	apply_impulse(ball_velocity.normalized() * 1500.0 * power, at - global_position)
	Fx.splinters(get_parent(), at)
	_damage_hull(float(a["hull"]) * r, "cannon")


## Velocity of the hull at a world-space point (includes spin).
func point_velocity(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_position)


## Same, but from just before the latest physics steps: the velocity going into a collision.
func pre_impact_velocity(p: Vector3) -> Vector3:
	return _vel_hist[0] + _ang_hist[0].cross(p - global_position)


## Tell both sides who started it (the fleet uses this to pick its fights).
func _note_attack(by: Ship) -> void:
	attacked.emit(by)
	if is_instance_valid(by):
		by.landed_hit.emit(self)


func _damage_hull(amount: float, source: String) -> void:
	if is_sunk:
		return
	hull = maxf(hull - amount, 0.0)
	hull_damaged.emit(source, amount)
	if hull <= 0.0:
		_sink()


# ---------------------------------------------------------------------------
# Collisions: ramming and running into islands
# ---------------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_sunk:
		return
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		var id := other.get_instance_id()
		if _contact_cooldown.has(id):
			continue
		var at := state.get_contact_local_position(i)  # world space in Godot 4
		# Note: the contact normal is deliberately NOT used. On an angled box-on-box hit it
		# is often the rammer's own bow/side face, which made the rammer look rammed.
		if other is Ship:
			# One ship resolves the collision for both, so it's counted exactly once.
			if get_instance_id() < id and not (other as Ship).is_sunk:
				_resolve_ram(other as Ship, at)
		else:
			_resolve_grounding(id, at)


static func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO


func _resolve_ram(other: Ship, at: Vector3) -> void:
	var va := pre_impact_velocity(at)
	var vb := other.pre_impact_velocity(at)
	va.y = 0.0
	vb.y = 0.0
	# Who drove into whom: each ship's speed toward the point of contact. A rammer's bow
	# is at the contact and it is sailing straight at it; a ship hit amidships is moving
	# past the contact point, not into it.
	var ua := _flat_dir(at - global_position)
	var ub := _flat_dir(at - other.global_position)
	var drive_a := maxf(va.dot(ua), 0.0)
	var drive_b := maxf(vb.dot(ub), 0.0)
	if drive_a + drive_b < 0.001:
		return
	var share_a := drive_a / (drive_a + drive_b)  # 1 = we did all the ramming
	# Closing speed along the main rammer's line of approach (so an overtaking ram only
	# counts the speed difference, and a sideswipe barely counts at all).
	var line := ua if drive_a >= drive_b else -ub
	var closing := (va - vb).dot(line)
	if closing < BUMP_SPEED:
		return
	var severity := closing - BUMP_SPEED
	_take_ram(severity, 1.0 - share_a, other.mass, vb - va, closing)
	other._take_ram(severity, share_a, mass, va - vb, closing)
	if share_a >= 0.5:
		other._note_attack(self)
	else:
		_note_attack(other)
	_contact_cooldown[other.get_instance_id()] = CONTACT_COOLDOWN
	other._contact_cooldown[get_instance_id()] = CONTACT_COOLDOWN
	_impact_fx.call_deferred(at, false)


## `rammed_share`: how much of the blow the other ship delivered (1 = we were rammed,
## 0 = we did the ramming). `incoming`: the other ship's velocity relative to ours.
func _take_ram(severity: float, rammed_share: float, other_mass: float, incoming: Vector3,
		closing: float) -> void:
	# A blow square on our side hurts more than one along our length (bow or stern).
	var broadside := 0.5 + 0.5 * absf(_flat_dir(incoming).dot(side_dir(1)))
	var heft := sqrt(other_mass / mass)  # a heavier ship hits harder
	var dmg := severity * heft * (RAM_DAMAGE_TAKEN * rammed_share * broadside
		+ RAM_DAMAGE_RAMMER * (1.0 - rammed_share))
	crew = maxf(crew - severity * heft * RAM_CREW_LOSS * rammed_share * randf_range(0.6, 1.4), 0.0)
	var kind := "rammed" if rammed_share >= 0.5 else "ramming"
	_damage_hull(dmg, kind)
	impact.emit(kind, closing, dmg)


func _resolve_grounding(id: int, at: Vector3) -> void:
	# Speed toward the point of contact: driving bow-first onto rocks counts in full,
	# scraping along the shore barely counts.
	var closing := pre_impact_velocity(at).dot(_flat_dir(at - global_position))
	if closing < BUMP_SPEED:
		return
	var dmg := (closing - BUMP_SPEED) * GROUND_DAMAGE
	_damage_hull(dmg, "grounded")
	impact.emit("grounded", closing, dmg)
	_contact_cooldown[id] = CONTACT_COOLDOWN
	_impact_fx.call_deferred(at, true)


func _impact_fx(at: Vector3, grounding: bool) -> void:
	Fx.splinters(get_parent(), at)
	if grounding:
		Fx.dust(get_parent(), at)


func _tick_contacts(delta: float) -> void:
	_vel_hist.push_back(linear_velocity)
	_vel_hist.pop_front()
	_ang_hist.push_back(angular_velocity)
	_ang_hist.pop_front()
	for id in _contact_cooldown.keys():
		_contact_cooldown[id] = float(_contact_cooldown[id]) - delta
		if _contact_cooldown[id] <= 0.0:
			_contact_cooldown.erase(id)


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
	_tick_contacts(delta)

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
			var lift := _buoyancy * minf(depth, _depth_cap) * float_mult - pv.y * _vdamp
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
	var drag := -fwd * _v_fwd * (_drag_lin + _drag_quad * absf(_v_fwd))
	drag += -right * v_side * _drag_side
	apply_central_force(drag * wet_frac)

	if is_sunk:
		apply_torque(fwd * 60000.0 * mass / BASE_MASS)  # roll over as she goes down
		return

	# --- Sails ----------------------------------------------------------------
	sail_amount = move_toward(sail_amount, SAIL_STEPS[sail_index], delta * sail_handling_speed * crew_factor())
	var wind_dir: Vector3 = Wind.direction()
	var off_wind := rad_to_deg(fwd.angle_to(-wind_dir))  # 0 = bow into the wind
	sail_efficiency = _efficiency(off_wind)
	point_of_sail = _point_of_sail_name(off_wind)
	_rowing = is_rowing(off_wind) and sail_amount > 0.05
	var push := _thrust * thrust_limit * Wind.strength * sail_efficiency * sail_amount * sail_power() * wet_frac
	apply_central_force(fwd * push)

	# Crosswind on the canvas heels her over.
	var cross := wind_dir.dot(right) * Wind.strength * sail_amount
	apply_torque(fwd * cross * _heel)

	# --- Rudder ---------------------------------------------------------------
	var authority := 0.5 + 0.5 * clampf(absf(_v_fwd) / _rudder_speed, 0.0, 1.0)
	apply_torque(Vector3.UP * -steer_input * _rudder * authority * wet_frac)


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
		ball.shooter_faction = faction
		ball.ammo = ammo
		ball.power = spec.gun_power
		ball.ocean = ocean
		ball.velocity = shot_velocity(side, ammo, randf_range(-spread, spread), randf_range(-spread, spread) * 0.4)
		get_parent().add_child(ball)
		ball.global_position = muzzle
	var out := side_dir(side)
	Fx.muzzle(get_parent(), muzzle, out)
	apply_impulse(-out * 2500.0, muzzle - global_position)  # recoil rocks the hull


## Sail efficiency from this rig's point-of-sail curve (see RIG_CURVES); oared craft row
## when that beats the sails.
func _efficiency(off_deg: float) -> float:
	var e := _sail_curve(off_deg)
	if spec.rig == ShipSpec.Rig.OARED:
		return maxf(e, OAR_POWER)
	return e


## True if an oared craft is rowing at this angle off the wind (the oars beat the sails).
func is_rowing(off_deg: float) -> bool:
	return spec.rig == ShipSpec.Rig.OARED and _sail_curve(off_deg) < OAR_POWER


func _sail_curve(off_deg: float) -> float:
	for i in range(1, _curve.size()):
		var b: Vector2 = _curve[i]
		if off_deg <= b.x:
			var a: Vector2 = _curve[i - 1]
			return remap(off_deg, a.x, b.x, a.y, b.y)
	return (_curve[_curve.size() - 1] as Vector2).y


func _point_of_sail_name(off_deg: float) -> String:
	if is_rowing(off_deg):
		return "Rowing"
	if off_deg < _irons_deg:
		return "In irons"
	if off_deg < 70.0:
		return "Close-hauled"
	if off_deg < 110.0:
		return "Beam reach"
	if off_deg < 160.0:
		return "Broad reach"
	return "Running"


func _process(delta: float) -> void:
	# Furl/unfurl: square sails gather up to their yard, gaff sails drop to the boom and
	# headsails slide down their stay (each sail's origin is on the spar it furls to).
	var k := maxf(sail_amount, 0.04)
	for c in _canvas:
		c.scale.y = k
	# Trim to the wind (cosmetic). Square yards brace round; booms and jibs swing out to
	# leeward by about half the wind's angle off the bow.
	var wl := global_basis.inverse() * Wind.direction()
	var phi := atan2(wl.x, -wl.z)
	var brace := clampf(-phi * 0.5, -0.9, 0.9)
	for y in _yards:
		y.rotation.y = lerp_angle(y.rotation.y, brace, delta * 1.5)
	var off := absf(atan2(-wl.x, wl.z))  # wind's angle off the bow, 0..PI
	var boom := signf(wl.x) * minf(off * 0.5, deg_to_rad(80.0))
	for b in _booms:
		b.rotation.y = lerp_angle(b.rotation.y, boom, delta * 1.2)
	for j in _jibs:
		var a := lerp_angle(float(j["angle"]), boom * 0.6, delta * 1.2)
		j["angle"] = a
		(j["pivot"] as Node3D).basis = (j["base"] as Basis) * Basis(Vector3.UP, a)
	# Fore-and-aft canvas bellies out to leeward.
	var lee := 1.0 if wl.x >= 0.0 else -1.0
	for c in _bellied:
		c.scale.x = lee
	if _oars:
		_animate_oars(delta)
	# Forward speed only, so bobbing in a swell doesn't leave a wake.
	_wake.emitting = absf(_v_fwd) > 0.8 and not is_sunk


# ---------------------------------------------------------------------------
# Construction. Placeholder geometry built from primitives so the prototype has
# no asset dependencies; swap for a real model later.
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(_beam, _height, _len)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.0, -0.125 * _len)
	add_child(col)


func _build_visuals() -> void:
	var spar := _mat(Color(0.30, 0.21, 0.13), 0.8)
	var canvas := _mat(sail_color * 0.72, 0.95)
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	canvas.backlight_enabled = true  # sun shining through the canvas
	canvas.disable_receive_shadows = true  # thin curved canvas self-shadows in jagged streaks
	canvas.backlight = sail_color * 0.2
	var rig := _build_model() if spec.model != null else _build_placeholder()
	_build_rig(rig, spar, canvas)


## Instance the spec's model and read its marker nodes. Returns the rig layout:
## {masts: [{foot, head, top, kind}], jib: {tack, head} or {}, flag: Vector3}.
func _build_model() -> Dictionary:
	var model := spec.model.instantiate() as Node3D
	add_child(model)
	# The topsides texture is neutral; tint it with this ship's colours.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null and mat.resource_name == "Topsides":
				var tinted := mat.duplicate() as BaseMaterial3D
				tinted.albedo_color = Color(hull_color * 1.25, 1.0)
				m.set_surface_override_material(i, tinted)

	# Marker positions in ship space (the model sits at the ship's origin).
	var inv := model.global_transform.affine_inverse()
	var marker := func(name: String) -> Variant:
		var n := model.find_child(name, true, false) as Node3D
		return null if n == null else inv * n.global_position

	# Guns: starboard muzzles, bow to stern (port mirrors them)
	var guns: Array[Vector3] = []
	for i in spec.guns_per_side:
		var g: Variant = marker.call("gun_%d" % i)
		if g == null:
			break
		guns.append(g)
	if guns.size() == spec.guns_per_side:
		_guns = guns
	else:
		push_warning("%s model has %d gun markers, spec wants %d: using spec layout" % [spec.id, guns.size(), spec.guns_per_side])

	var rig := {"masts": [], "jib": {}, "flag": Vector3(0.0, _mast_top, 0.0)}
	for m in spec.masts.size():
		var foot: Variant = marker.call("mast_%d" % m)
		if foot == null:
			break
		var head: Variant = marker.call("mast_%d_head" % m)
		var top_m: Variant = marker.call("mast_%d_top" % m)
		var top: Vector3 = top_m if top_m != null else foot + Vector3.UP * spec.mast_height_frac * _len
		rig["masts"].append({"foot": foot, "head": head if head != null else top, "top": top,
			"kind": spec.masts[m], "mesh": false})
	var flag: Variant = marker.call("flag")
	if flag != null:
		rig["flag"] = flag
		_mast_top = (flag as Vector3).y
	# Oarlocks for oared craft
	for i in 64:
		var o: Variant = marker.call("oar_%d" % i)
		if o == null:
			break
		_oarlocks.append(o)
	if not _oarlocks.is_empty():
		_build_oars()
	var tack: Variant = marker.call("jib_tack")
	var jhead: Variant = marker.call("jib_head")
	if spec.jib and tack != null and jhead != null:
		rig["jib"] = {"tack": tack, "head": jhead}
	return rig


## Placeholder geometry from primitives, scaled from the original sloop layout so every
## spec without a model still gets a believable silhouette. Proportions are fractions of
## length (L), beam (B) and hull height (H).
func _build_placeholder() -> Dictionary:
	var wood := _mat(hull_color, 0.85)
	var dark := _mat(Color(0.12, 0.08, 0.05), 0.9)
	var deck := _mat(Color(0.55, 0.40, 0.25), 0.8)
	var black := _mat(Color(0.04, 0.04, 0.04), 0.9)
	var L := _len
	var B := _beam
	var H := _height

	# Hull, wale and deck
	_add_box(Vector3(B, H, 0.75 * L), Vector3.ZERO, wood)
	_add_box(Vector3(B + 0.1, 0.3 * _vscale, 0.75 * L + 0.1), Vector3(0.0, -0.25 * H, 0.0), dark)
	_add_box(Vector3(B - 0.4, 0.1, 0.725 * L), Vector3(0.0, 0.5 * H + 0.02, 0.0), deck)

	# Bow: a prism turned so its apex points forward (-Z)
	var bow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(B, 0.25 * L, H)
	bow.mesh = prism
	bow.material_override = wood
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bow.position = Vector3(0.0, 0.0, -0.5 * L)
	add_child(bow)

	var sprit_at := Vector3(0.0, 0.5 * H + 0.78 * _vscale, -0.74 * L)
	var sprit := _add_cyl(0.12 * _vscale, 0.375 * L, sprit_at, wood)
	sprit.rotation_degrees.x = -75.0
	var sprit_dir := Vector3(0.0, cos(deg_to_rad(75.0)), -sin(deg_to_rad(75.0)))

	# Sterncastle
	_add_box(Vector3(B, 0.64 * H, 0.2 * L), Vector3(0.0, 0.82 * H, 0.275 * L), wood)
	_add_box(Vector3(B - 0.3, 0.1, 0.19 * L), Vector3(0.0, 1.15 * H, 0.275 * L), deck)

	# Gun ports, one per gun
	for side in [-1.0, 1.0]:
		for g in _guns:
			_add_box(Vector3(0.1, 0.45, 0.6), Vector3((B * 0.5 + 0.02) * side, g.y, g.z), black)

	# Masts, bow to stern
	var rig := {"masts": [], "jib": {}, "flag": Vector3.ZERO}
	var n := clampi(spec.masts.size(), 1, 3)
	var mast_z: Array = [[-0.1], [-0.2, 0.12], [-0.28, -0.02, 0.22]][n - 1]
	var mast_k: Array = [[1.0], [1.0, 0.9], [0.92, 1.0, 0.75]][n - 1]
	var deck_y := 0.5 * H
	var tallest := spec.mast_height_frac * L
	_mast_top = deck_y + tallest
	for m in n:
		var h: float = tallest * float(mast_k[m])
		var foot := Vector3(0.0, deck_y, float(mast_z[m]) * L)
		_add_cyl(0.18 * _vscale, h, foot + Vector3.UP * h * 0.5, dark)
		var kind: String = spec.masts[m] if m < spec.masts.size() else "square"
		rig["masts"].append({"foot": foot, "head": foot + Vector3.UP * (1.5 * _vscale + h * 0.6),
			"top": foot + Vector3.UP * h, "kind": kind})
		if float(mast_k[m]) >= 1.0:
			rig["flag"] = foot + Vector3.UP * h
	if spec.jib:
		var fore: Dictionary = rig["masts"][0]
		rig["jib"] = {"tack": sprit_at + sprit_dir * 0.16 * L,
			"head": (fore["foot"] as Vector3).lerp(fore["top"], 0.85)}
	return rig


## Sails and running spars on the rig layout, plus the colours at the masthead.
func _build_rig(rig: Dictionary, spar: Material, canvas: Material) -> void:
	var masts: Array = rig["masts"]
	for i in masts.size():
		var m: Dictionary = masts[i]
		var foot: Vector3 = m["foot"]
		var top: Vector3 = m["top"]
		var mh := top.y - foot.y
		if m["kind"] == "lateen":
			_add_lateen_sail(foot, (m["head"] as Vector3).y - foot.y, minf(0.85 * _len, 1.7 * mh), spar, canvas)
		elif m["kind"] == "gaff" or m["kind"] == "spanker":
			# Fore-and-aft sail aft of the mast, as long as the deck allows and clear of the
			# next mast aft (schooner foresail, ketch mainsail). A "spanker" mizzen (full-rigged
			# ship) also sets a square topsail above it.
			if m["kind"] == "spanker":
				_add_square_sail(foot + Vector3.UP * 0.795 * mh, 0.29 * mh, 0.23 * mh, spar, canvas)
			var sail_len := minf(0.42 * _len, 0.4 * _len - foot.z)
			if i + 1 < masts.size():
				sail_len = minf(sail_len, (masts[i + 1]["foot"] as Vector3).z - foot.z - 0.6 * _vscale)
			var boom_h := 1.5 * _vscale
			var throat := (m["head"] as Vector3).y - foot.y
			_add_gaff_sail(foot, sail_len, throat - boom_h, boom_h, spar, canvas)
		else:
			_add_square_sail(foot + Vector3.UP * 0.555 * mh, 0.37 * mh, 0.31 * mh, spar, canvas)
			_add_square_sail(foot + Vector3.UP * 0.795 * mh, 0.29 * mh, 0.23 * mh, spar, canvas)
	var jib: Dictionary = rig["jib"]
	if not jib.is_empty() and not (rig["masts"] as Array).is_empty():
		var fore: Dictionary = rig["masts"][0]
		var foot: Vector3 = fore["foot"]
		var tack: Vector3 = jib["tack"]
		var clew := Vector3(0.0, foot.y + 1.8 * _vscale, lerpf(foot.z, tack.z, 0.3))
		_add_jib(tack, jib["head"], clew, canvas)
	# Colours at the masthead
	var flag := _mat(flag_color, 0.9)
	var fs := maxf(_vscale, 1.0)
	var flag_mi := _add_box(Vector3(1.2, 0.8, 0.03) * fs, (rig["flag"] as Vector3) + Vector3(0.65, -0.45, 0.0) * fs, flag)
	flag_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Square sail hanging from a yard that braces round to the wind; bellies forward.
func _add_square_sail(yard_pos: Vector3, w: float, h: float, spar_mat: Material, sail_mat: Material) -> void:
	var yard := Node3D.new()
	yard.position = yard_pos
	add_child(yard)
	_yards.append(yard)
	_add_spar(yard, Vector3(-w * 0.5 - 0.3, 0.0, 0.0), Vector3(w * 0.5 + 0.3, 0.0, 0.0), 0.09 * _vscale, spar_mat)
	var sail := MeshInstance3D.new()
	sail.mesh = _sail_mesh([Vector3(-w * 0.55, -h, 0.0), Vector3(w * 0.55, -h, 0.0),
		Vector3(w * 0.5, -0.05, 0.0), Vector3(-w * 0.5, -0.05, 0.0)], Vector3.FORWARD, 0.12 * h)
	sail.material_override = sail_mat
	sail.position.z = -0.08 * _vscale
	yard.add_child(sail)
	_canvas.append(sail)


## Fore-and-aft (gaff) sail: on a boom and a peaked gaff aft of the mast, swinging out to
## leeward. The gaff is part of the sail node, so furling lowers it onto the boom.
func _add_gaff_sail(mast_foot: Vector3, length: float, h: float, boom_h: float,
		spar_mat: Material, sail_mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = mast_foot
	add_child(pivot)
	_booms.append(pivot)
	var r := 0.08 * _vscale
	_add_spar(pivot, Vector3(0.0, boom_h, 0.2), Vector3(0.0, boom_h, length + 0.3), r, spar_mat)

	var sail := MeshInstance3D.new()
	sail.position.y = boom_h
	pivot.add_child(sail)
	# Gaff about two-thirds the boom's length, peaked up 30 degrees (owner: a gaff as long as
	# the boom looked wrong). The leech slants forward from the boom end up to the peak.
	var throat := Vector3(0.0, h, 0.3)
	var gaff_len := 0.65 * length
	var peak := throat + Vector3(0.0, sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))) * gaff_len
	sail.mesh = _sail_mesh([Vector3(0.0, 0.1, 0.3), Vector3(0.0, 0.1, length), peak, throat],
		Vector3.RIGHT, 0.11 * length)
	sail.material_override = sail_mat
	_add_spar(sail, throat + Vector3(0.0, 0.1, -0.15), peak + (peak - throat).normalized() * 0.4, r * 0.85, spar_mat)
	_canvas.append(sail)
	_bellied.append(sail)


## Lateen: a triangular sail under a long yard slung at the masthead, slanting up aft. It
## swings to leeward like a boom and is brailed up to the yard to furl.
func _add_lateen_sail(mast_foot: Vector3, head_h: float, yard_len: float, spar_mat: Material,
		sail_mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = mast_foot
	add_child(pivot)
	_booms.append(pivot)
	var tilt := deg_to_rad(40.0)
	var along := Vector3(0.0, sin(tilt), cos(tilt))  # up and aft
	var hang := Vector3(0.0, head_h, 0.0)
	var fore := hang - along * yard_len * 0.38
	var aft := hang + along * yard_len * 0.62
	_add_spar(pivot, fore, aft, 0.07 * _vscale, spar_mat)
	# The sail node's local z runs along the yard and -y hangs down from it, so scaling y
	# brails the canvas up to the yard.
	var frame := Node3D.new()
	frame.position = fore
	frame.basis = Basis(Vector3.RIGHT, -tilt)
	pivot.add_child(frame)
	var clew_ship := Vector3(0.0, 1.0 * _vscale, aft.z - 0.1 * yard_len)
	var clew := frame.basis.inverse() * (clew_ship - fore)
	clew.x = 0.0
	var sail := MeshInstance3D.new()
	sail.mesh = _sail_mesh([Vector3.ZERO, clew, Vector3(0.0, 0.0, yard_len * 0.98), Vector3.ZERO],
		Vector3.RIGHT, 0.08 * yard_len)
	sail.material_override = sail_mat
	frame.add_child(sail)
	_canvas.append(sail)
	_bellied.append(sail)


## Triangular headsail hoisted on a stay from `tack` up to `head`, sheeted aft to `clew`.
## It swings round the stay to leeward and is lowered down the stay to furl.
func _add_jib(tack: Vector3, head: Vector3, clew: Vector3, sail_mat: Material) -> void:
	var up := (head - tack).normalized()
	var z := Vector3.RIGHT.cross(up).normalized()
	var base := Basis(up.cross(z).normalized(), up, z)
	var pivot := Node3D.new()
	pivot.position = tack
	pivot.basis = base
	add_child(pivot)
	_jibs.append({"pivot": pivot, "base": base, "angle": 0.0})
	var inv := base.inverse()
	var lh := inv * (head - tack)
	var lc := inv * (clew - tack)
	lc.x = 0.0
	var sail := MeshInstance3D.new()
	sail.mesh = _sail_mesh([Vector3.ZERO, lc, lh, lh], Vector3.RIGHT, 0.08 * lh.length())
	sail.material_override = sail_mat
	pivot.add_child(sail)
	_canvas.append(sail)
	_bellied.append(sail)


## All the oars as one MultiMesh (one draw call). Each oar pivots at its oarlock.
func _build_oars() -> void:
	var length := maxf(3.0, 1.1 * _beam + 1.2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := BoxMesh.new()
	shaft.size = Vector3(length, 0.07, 0.07)
	st.append_from(shaft, 0, Transform3D(Basis(), Vector3(length * 0.2, 0.0, 0.0)))
	var blade := BoxMesh.new()
	blade.size = Vector3(length * 0.28, 0.03, 0.2)
	st.append_from(blade, 0, Transform3D(Basis(), Vector3(length * 0.56, 0.0, 0.0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat(Color(0.5, 0.37, 0.22), 0.8))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _oarlocks.size() * 2
	_oars = MultiMeshInstance3D.new()
	_oars.multimesh = mm
	_oars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_oars)
	_animate_oars(0.0)


## Rowing: the oars sweep fore and aft, blades dipping on the pull. Otherwise they're held
## level, blades clear of the water.
func _animate_oars(delta: float) -> void:
	var sweep := 0.0
	var dip := -0.12
	if _rowing:
		_oar_phase = fmod(_oar_phase + delta * (1.2 + 1.6 * sail_amount), TAU)
		sweep = 0.42 * sin(_oar_phase)
		dip = 0.22 + 0.12 * cos(_oar_phase)
	var mm := _oars.multimesh
	var i := 0
	for lock in _oarlocks:
		for side: float in [1.0, -1.0]:
			var yaw := (0.0 if side > 0.0 else PI) + side * sweep
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -dip)
			mm.set_instance_transform(i, Transform3D(b, Vector3(lock.x * side, lock.y, lock.z)))
			i += 1


## A sail as a curved patch between four corners (bottom-front, bottom-back, top-back,
## top-front; repeat a corner for a triangle), bellied along `belly` by up to `depth`.
static func _sail_mesh(c: Array, belly: Vector3, depth: float) -> ArrayMesh:
	const N := 8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for j in N + 1:
		var v := float(j) / N
		for i in N + 1:
			var u := float(i) / N
			var p: Vector3 = (c[0] as Vector3).lerp(c[1], u).lerp((c[3] as Vector3).lerp(c[2], u), v)
			# Deepest a third of the way back from the leading edge, flatter at the leech.
			p += belly * depth * sin(PI * pow(u, 0.7)) * sin(PI * v)
			pts.append(p)
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			var quad := [a, a + 1, a + N + 2, a, a + N + 2, a + N + 1]
			for q: int in quad:
				st.set_uv(Vector2(float(q % (N + 1)) / N, float(q / (N + 1)) / N))
				st.add_vertex(pts[q])
	st.index()  # share vertices so the normals smooth across the belly
	st.generate_normals()
	return st.commit()


## A round spar between two points, as a child of `parent`.
func _add_spar(parent: Node3D, a: Vector3, b: Vector3, radius: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = a.distance_to(b)
	c.radial_segments = 8
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	# Thin spars' shadows barely show from the map camera; skipping them saves a shadow-pass
	# draw call per spar (stress test).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


func _build_wake() -> void:
	_wake = CPUParticles3D.new()
	_wake.position = Vector3(0.0, -0.2 * _vscale, 0.41 * _len)
	_wake.amount = 120
	_wake.lifetime = 4.0
	_wake.local_coords = false
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(0.33 * _beam, 0.1, 0.5)
	_wake.direction = Vector3.UP
	_wake.spread = 30.0
	_wake.initial_velocity_min = 0.2
	_wake.initial_velocity_max = 0.8
	_wake.gravity = Vector3.ZERO
	_wake.scale_amount_min = 1.0 * _beam / BASE_BEAM
	_wake.scale_amount_max = 2.5 * _beam / BASE_BEAM
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
