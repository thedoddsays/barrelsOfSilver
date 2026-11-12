extends Node
class_name AiCaptain
## Commands an enemy Ship against a target Ship. Plays by the same wind rules as the
## player: it beats to windward on close-hauled tacks, wears ship (turns downwind)
## instead of tacking through the wind, and avoids islands.
##
## Behaviour: circle the target at a fighting distance with a loaded broadside facing
## it (steering inward when far, beam-on at the right range, outward when too close),
## fire when the target is squarely abeam, and run for it when badly holed and losing.

const THINK_INTERVAL := 0.25
const CLOSEST_TO_WIND := 1.0472  ## 60 deg: the AI won't point higher than this
const FIGHT_RANGE_FRAC := 0.6  ## preferred distance, as a fraction of the ammo's range
const TARGET_HALF_WIDTH := 5.0  ## metres either side of the aim point that still hits

var ship: Ship
var target: Ship

var _desired := 0.0  ## bearing the captain wants to sail
var _think := 0.0
var _volleys := 0
var _ammo: int = Ship.Ammo.ROUND
var _orbit_side := 0  ## which of our sides faces the target while circling (+1 stbd)


func _ready() -> void:
	if ship:
		_desired = ship.heading_bearing()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(ship):
		queue_free()
		return
	if ship.is_sunk:
		return

	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_decide()

	ship.steer_input = _steer_toward(_desired)
	if _has_target():
		_try_fire()


func _has_target() -> bool:
	return is_instance_valid(target) and not target.is_sunk


func _decide() -> void:
	if not _has_target():
		# Nothing to fight: carry on with the current heading, under easy sail.
		ship.sail_index = 1
		_desired = _avoid_islands(_sailable(_desired))
		return

	var to := _flat(target.global_position - ship.global_position)
	var dist := to.length()
	var bearing_to := _bearing(to)
	_ammo = _choose_ammo(dist)
	var gun_range := Ship.ammo_range(_ammo)

	var fleeing := ship.hull_frac() < 0.25 and target.hull_frac() > ship.hull_frac()
	if fleeing:
		_desired = bearing_to + PI
		ship.sail_index = 2
	elif dist > gun_range * 1.8:
		_desired = bearing_to  # close in
		_orbit_side = 0
		ship.sail_index = 2
	else:
		_pick_orbit_side(bearing_to)
		# Circle the target. Offset from the bearing to the target: ~20 deg when far
		# (mostly closing), 90 deg at the fighting range (beam-on), >90 when too close.
		var fight := gun_range * FIGHT_RANGE_FRAC
		var err := clampf((dist - fight) / fight, -0.5, 1.0)
		var offset := PI * 0.5 - err * 1.2
		# Starboard faces the target when heading = bearing_to - 90 deg.
		_desired = bearing_to - offset if _orbit_side == 1 else bearing_to + offset
		ship.sail_index = 2 if dist > gun_range else 1

	_desired = _avoid_islands(_sailable(_desired))


## Keep circling with the same side toward the target, unless that side is reloading
## and the other is ready. First time in, pick whichever needs the smaller turn.
func _pick_orbit_side(bearing_to: float) -> void:
	if _orbit_side == 0:
		var h := ship.heading_bearing()
		var stbd_turn := absf(wrapf(bearing_to - PI * 0.5 - h, -PI, PI))
		var port_turn := absf(wrapf(bearing_to + PI * 0.5 - h, -PI, PI))
		_orbit_side = 1 if stbd_turn <= port_turn else -1
	elif not ship.can_fire(_orbit_side) and ship.can_fire(-_orbit_side):
		_orbit_side = -_orbit_side


func _choose_ammo(dist: float) -> int:
	if dist < Ship.ammo_range(Ship.Ammo.GRAPE) * 0.85 and target.crew_frac() > 0.2:
		return Ship.Ammo.GRAPE
	if target.sails_frac() > 0.6 and dist < Ship.ammo_range(Ship.Ammo.CHAIN) and _volleys % 3 == 2:
		return Ship.Ammo.CHAIN
	return Ship.Ammo.ROUND


func _try_fire() -> void:
	var to := _flat(target.global_position - ship.global_position)
	var dist := to.length()
	var gun_range := Ship.ammo_range(_ammo)
	if dist > gun_range * 0.95:
		return
	# Lead the target: the ball carries our own velocity, so use relative motion.
	var a: Dictionary = Ship.AMMO[_ammo]
	var flight := dist / (float(a["speed"]) * 0.98)
	var lead := to + _flat(target.linear_velocity - ship.linear_velocity) * flight
	# Only fire when the target fits inside the cone, so far shots need a finer aim.
	var tolerance := clampf(atan2(TARGET_HALF_WIDTH, dist), 0.03, 0.14)
	for side: int in [-1, 1]:
		if ship.can_fire(side) and ship.side_dir(side).angle_to(lead) < tolerance:
			if ship.fire(side, _ammo):
				_volleys += 1


## Keep the desired heading outside the no-go zone around the wind, staying on the
## current tack unless the target heading is clearly on the other one.
func _sailable(desired: float) -> float:
	var upwind := Wind.angle + PI  # bearing the wind comes FROM
	var off := wrapf(desired - upwind, -PI, PI)
	if absf(off) >= CLOSEST_TO_WIND:
		return desired
	var cur := wrapf(ship.heading_bearing() - upwind, -PI, PI)
	var tack := signf(cur) if absf(off) < deg_to_rad(20.0) else signf(off)
	if tack == 0.0:
		tack = 1.0
	return upwind + tack * CLOSEST_TO_WIND


## Feel ahead with rays; if the way is blocked, pick the nearest clear heading.
func _avoid_islands(desired: float) -> float:
	var space := ship.get_world_3d().direct_space_state
	var origin := ship.global_position
	origin.y = 1.0
	var look := 60.0 + ship.linear_velocity.length() * 4.0
	for off_deg: float in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0, 160.0, -160.0]:
		var b := desired + deg_to_rad(off_deg)
		var dir := Vector3(sin(b), 0.0, -cos(b))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * look, Ship.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			return b
	return desired


## Rudder command toward a bearing. If the short way round would swing the bow
## through the wind, go the long way (wear ship) so we never stall in irons.
func _steer_toward(bearing: float) -> float:
	var h := ship.heading_bearing()
	var d := wrapf(bearing - h, -PI, PI)
	var upwind_off := wrapf(Wind.angle + PI - h, -PI, PI)
	if signf(upwind_off) == signf(d) and absf(upwind_off) < absf(d):
		d -= signf(d) * TAU
	return clampf(d * 2.0, -1.0, 1.0)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _bearing(v: Vector3) -> float:
	return atan2(v.x, -v.z)
