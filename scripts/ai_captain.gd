extends Node
class_name AiCaptain
## Commands a Ship: an enemy, or an escort in the player's fleet. Plays by the same wind
## rules as the player: it beats to windward on close-hauled tacks, wears ship (turns
## downwind) instead of tacking through the wind, and avoids islands and friendly ships.
##
## Combat: circle the target at a fighting distance with a loaded broadside facing it
## (steering inward when far, beam-on at the right range, outward when too close), fire
## when the target is squarely abeam, and run for it when badly holed and losing.
## With `auto_target`, the captain picks the nearest hostile ship itself.
## Escorts (`fleet` set): with no enemy in range, keep station in the fleet's formation.

const THINK_INTERVAL := 0.25
const POINTING_MARGIN := 20.0  ## deg: the AI sails no closer to the wind than irons + this
const FOLLOW_POINTING_MARGIN := 8.0  ## escorts keeping station may pinch closer to the wind
const RETARGET_RATIO := 0.7  ## switch targets only for one this much closer than the current
const DISENGAGE_RANGE := 450.0  ## escorts give up a chase this far from the flagship
## An escort further than this from the flagship drops any fight and comes back. Escorts stay
## with the flagship, not with the battle (owner playtest: they were left fighting alone).
const ESCORT_LEASH := 300.0
const FIGHT_RANGE_FRAC := 0.6  ## preferred distance, as a fraction of the ammo's range
## Escorts circle a shared target in separate lanes (offsets to FIGHT_RANGE_FRAC by fleet
## position), so they aren't all on the same circle getting in each other's way.
const ESCORT_LANES := [0.0, 0.14, -0.12]
const TARGET_HALF_WIDTH := 5.0  ## metres either side of the aim point that still hits

var ship: Ship
var target: Ship
var fleet: Fleet  ## set for escorts in the player's fleet
var auto_target := false  ## pick the nearest hostile ship instead of a fixed target
var engage_range := INF  ## auto_target only considers hostiles this close

var _desired := 0.0  ## bearing the captain wants to sail
var _think := 0.0
var _volleys := 0
var _ammo: int = Ship.Ammo.ROUND
var _orbit_side := 0  ## which of our sides faces the target while circling (+1 stbd)
var _friend_brake := 1.0  ## < 1 when a friendly ship is close ahead (set by _avoid_friends)
var _last_status := ""
var _recalled := false  ## escort strayed past the leash and is heading back to the flagship


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
	if _friend_brake < 1.0:
		ship.thrust_limit = minf(ship.thrust_limit, _friend_brake)
	if _has_target():
		_try_fire()


func _has_target() -> bool:
	return is_instance_valid(target) and not target.is_sunk


func _decide() -> void:
	if auto_target:
		_pick_target()
	_update_status()
	if not _has_target():
		if fleet != null and is_instance_valid(fleet.flagship):
			_decide_follow()
		else:
			# Nothing to fight: carry on with the current heading, under easy sail.
			ship.sail_index = 1
			ship.thrust_limit = 1.0
			_desired = _avoid_islands(_avoid_friends(_sailable(_desired)))
		return
	ship.thrust_limit = 1.0

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
		var fight := gun_range * (FIGHT_RANGE_FRAC + _lane())
		var err := clampf((dist - fight) / fight, -0.5, 1.0)
		var offset := PI * 0.5 - err * 1.2
		# Starboard faces the target when heading = bearing_to - 90 deg.
		_desired = bearing_to - offset if _orbit_side == 1 else bearing_to + offset
		ship.sail_index = 2 if dist > gun_range else 1

	_desired = _avoid_islands(_avoid_friends(_sailable(_desired)))


## What this captain is doing, shown on the HUD for escorts and printed to the Output panel
## when it changes (owner playtest: escorts leaving formation needed explaining).
func _update_status() -> void:
	var status := ""
	if _has_target():
		var d := target.global_position.distance_to(ship.global_position)
		status = "engaging %s (%d m)" % [target.spec.display_name, roundi(d)]
	elif fleet != null:
		var off := ship.global_position.distance_to(fleet.station_position(ship))
		status = "rejoining" if off > 60.0 else "in formation"
	ship.status_text = status
	var kind := status.split(" (")[0]
	if fleet != null and kind != _last_status:
		print("[fleet] %s: %s" % [ship.spec.display_name, status])
	_last_status = kind


func _lane() -> float:
	if fleet == null:
		return 0.0
	var i := fleet.escorts.find(ship)
	return ESCORT_LANES[i % ESCORT_LANES.size()] if i >= 0 else 0.0


## Nearest hostile within engage range. Sticks with the current target unless another is
## clearly closer, so captains don't flip-flop between two ships. Escorts also drop a
## target that has drawn them too far from the flagship.
func _pick_target() -> void:
	var anchor := ship
	if fleet != null and is_instance_valid(fleet.flagship):
		anchor = fleet.flagship
	if fleet != null:
		# Past the leash: drop the fight and come back. Don't pick a new one until we're well
		# inside it again (70%), so escorts don't flip-flop at the boundary.
		var from_flag := ship.global_position.distance_to(anchor.global_position)
		if from_flag > ESCORT_LEASH:
			_recalled = true
		elif from_flag < ESCORT_LEASH * 0.7:
			_recalled = false
		if _recalled or (_has_target() and
				target.global_position.distance_to(anchor.global_position) > DISENGAGE_RANGE):
			target = null
		if _recalled:
			return
		if not fleet.engaged:
			target = null  # engage on command: ignore everyone until the flagship engages
			return
	var best: Ship = null
	var best_d := INF
	for node in ship.get_tree().get_nodes_in_group("ships"):
		var e := node as Ship
		if e.is_sunk or not ship.is_hostile_to(e):
			continue
		var d := e.global_position.distance_to(ship.global_position)
		if fleet != null:
			# Escorts fight what's near the flagship.
			if e.global_position.distance_to(anchor.global_position) > engage_range:
				continue
		elif d > engage_range:
			continue
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		if fleet != null:
			target = null  # nothing in range: escorts return to formation
		return
	if not _has_target():
		target = best
	elif best != target:
		var cur_d := target.global_position.distance_to(ship.global_position)
		if best_d < cur_d * RETARGET_RATIO:
			target = best


## Escort with nothing to fight: sail to our formation station and match the flagship.
func _decide_follow() -> void:
	var flag := fleet.flagship
	var station := fleet.station_position(ship)
	var flag_v := _flat(flag.linear_velocity)
	var to := _flat(station + flag_v * 3.0 - ship.global_position)  # aim a little ahead
	var dist := to.length()
	var flag_h := fleet.formation_heading()
	var fwd := Vector3(sin(flag_h), 0.0, -cos(flag_h))
	var right := Vector3(cos(flag_h), 0.0, sin(flag_h))
	var rel := station - _flat(ship.global_position)
	var along := rel.dot(fwd)  # + = station is ahead of us
	if along < -12.0:
		# We've overshot: never turn back for the station. Hold the fleet's heading,
		# ease off and drift across, and let the station come to us.
		_desired = flag_h + clampf(rel.dot(right) * 0.015, -0.6, 0.6)
	else:
		# Far off: head for the station. Close in: blend toward the fleet's heading.
		var blend := clampf((dist - 8.0) / 30.0, 0.0, 1.0)
		_desired = lerp_angle(flag_h, _bearing(to), blend)
	_desired = _avoid_islands(_avoid_friends(_sailable(_desired, FOLLOW_POINTING_MARGIN), true))

	# Speed: full sail set, trimmed with thrust so we close the along-track gap and
	# match the flagship's speed. Furl only when the flagship has stopped and we're home.
	var speed_err := flag_v.dot(fwd) - _flat(ship.linear_velocity).dot(fwd)
	if flag_v.length() < 0.6 and dist < 30.0:
		ship.sail_index = 0
		ship.thrust_limit = 1.0
		return
	ship.sail_index = 2
	if dist > 60.0:
		ship.thrust_limit = 1.0
	else:
		ship.thrust_limit = clampf(0.6 + along * 0.04 + speed_err * 0.15, 0.0, 1.0)


## Steer clear of friendly ships. Keeps escorts from ramming each other or the player.
## Two layers:
## - Look-ahead: predict the closest approach to each friend over the next few seconds from
##   both ships' velocities; if we'll pass too close, turn away from where they'll be and
##   ease off, early enough that a heavy, slow-turning ship still makes it (owner playtest:
##   the frigate kept ramming its own fleet mid-battle).
## - Close range: push away from any friend already near our path.
## In formation everyone sails the same way at the same speed, so the close-range layer
## needs less room (formation stations must sit outside it, or ships fight their stations).
const LOOKAHEAD := 6.0  ## seconds

func _avoid_friends(desired: float, in_formation := false) -> float:
	var dir := Vector3(sin(desired), 0.0, -cos(desired))
	var my_v := _flat(ship.linear_velocity)
	var push := Vector3.ZERO
	_friend_brake = 1.0
	for node in ship.get_tree().get_nodes_in_group("ships"):
		var f := node as Ship
		if f == ship or f.is_sunk or ship.is_hostile_to(f):
			continue
		var off := _flat(f.global_position - ship.global_position)
		var d := off.length()
		if d < 0.01 or d > 250.0:
			continue

		# Look-ahead: closest point of approach within LOOKAHEAD seconds.
		var rel_v := _flat(f.linear_velocity) - my_v
		var t_cpa := 0.0
		if rel_v.length_squared() > 0.01:
			t_cpa = clampf(-off.dot(rel_v) / rel_v.length_squared(), 0.0, LOOKAHEAD)
		var miss := off + rel_v * t_cpa  # where they'll be relative to us, at closest approach
		var clearance := (ship.length() + f.length()) * 0.35 + 8.0
		if miss.length() < clearance:
			var urgency := (1.0 - t_cpa / LOOKAHEAD) * (1.0 - miss.length() / clearance)
			var away := -miss.normalized() if miss.length() > 0.5 else -off / d
			push += away * urgency * 3.0
			if dir.dot(off / d) > 0.2:  # they're ahead of us: ease off too
				_friend_brake = minf(_friend_brake, clampf(1.0 - urgency * 1.5, 0.0, 1.0))

		# Close range: push away from friends already near our path.
		var safe := (ship.length() + f.length()) * (0.35 if in_formation else 0.6) + (10.0 if in_formation else 16.0)
		if d >= safe:
			continue
		var ahead := dir.dot(off / d)
		if ahead < -0.3:
			continue  # well behind us: their problem
		var closeness := (safe - d) / safe
		push -= off / d * closeness * (1.0 + ahead) * 2.5
		# Close and dead ahead: ease off as well as turn, so we never rear-end a friend.
		if ahead > 0.5:
			_friend_brake = minf(_friend_brake, clampf(1.0 - closeness * 1.6, 0.0, 1.0))
	if push == Vector3.ZERO:
		return desired
	return _bearing(dir + push)


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
	# Lead the target. Balls leave square to the hull and don't carry our own
	# velocity, so only the target's motion matters.
	var a: Dictionary = Ship.AMMO[_ammo]
	var flight := dist / (float(a["speed"]) * 0.98)
	var lead := to + _flat(target.linear_velocity) * flight
	# Only fire when the target fits inside the cone, so far shots need a finer aim.
	var tolerance := clampf(atan2(TARGET_HALF_WIDTH, dist), 0.03, 0.14)
	for side: int in [-1, 1]:
		if ship.can_fire(side) and ship.side_dir(side).angle_to(lead) < tolerance:
			if ship.fire(side, _ammo):
				_volleys += 1


## Keep the desired heading outside the no-go zone around the wind, staying on the
## current tack unless the target heading is clearly on the other one.
func _sailable(desired: float, margin_deg := POINTING_MARGIN) -> float:
	var upwind := Wind.angle + PI  # bearing the wind comes FROM
	var closest := deg_to_rad(ship.irons_deg() + margin_deg)  # per rig
	var off := wrapf(desired - upwind, -PI, PI)
	if absf(off) >= closest:
		return desired
	var cur := wrapf(ship.heading_bearing() - upwind, -PI, PI)
	var tack := signf(cur) if absf(off) < deg_to_rad(20.0) else signf(off)
	if tack == 0.0:
		tack = 1.0
	return upwind + tack * closest


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
