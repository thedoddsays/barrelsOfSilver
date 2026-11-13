extends Node
class_name Fleet
## The player's fleet: the flagship (sailed by the player) plus up to MAX_SHIPS - 1 escorts,
## each commanded by an AiCaptain in follow mode. See docs/gdd.md section 6.1.
##
## - Loose formation: escorts hold stations around and behind the flagship, spaced by ship
##   size, each drifting slowly so the fleet never looks rigid.
## - Fleet pace (soft cap): while the fleet sails together, the flagship is held to what the
##   slowest escort can make on the current heading, with a 20% margin so stragglers can
##   close up. "Break away" lifts the cap; escorts follow as best they can.
## - Fight aggressors only (owner, 2026-11-13): escorts ignore every other ship. An
##   aggressor is a ship that hit or rammed any ship of the fleet, or one the PLAYER hit,
##   rammed or fired a broadside at (it was in the line of fire). Escorts' own stray shots
##   don't make aggressors, so passing or fleeing ships are left alone. The battle ends when
##   no aggressor is left afloat, or after COMBAT_TIMEOUT quiet seconds with none near the
##   flagship; then the list clears, escorts rejoin and fleet pace comes back on.

signal changed

const MAX_SHIPS := 4  ## including the flagship (owner, 2026-11-13; may be revisited)
## Once engaged, escorts fight enemies this close to the FLAGSHIP (not to themselves), so they
## stay with the player instead of wandering off after distant ships (owner playtest).
const ENGAGE_RANGE := 250.0
## Battle ends after this many seconds with no shots fired or taken by the fleet, once no
## enemy is within ENGAGE_RANGE of the flagship.
const COMBAT_TIMEOUT := 20.0
const PACE_IGNORE_RANGE := 500.0  ## escorts further away than this don't slow the flagship
const PACE_MARGIN := 0.8  ## flagship sails at 80% of the slowest escort, so stragglers can catch up
## Waiting for stragglers: once an escort is more than WAIT_START metres behind her station,
## fleet pace drops further, down to WAIT_MIN when she's WAIT_START + WAIT_SPAN behind.
const WAIT_START := 20.0
const WAIT_SPAN := 100.0
const WAIT_MIN := 0.35
## Formation stations: (side, rank). Side -1 = port, +1 = starboard, 0 = astern.
## Kept fairly tight (owner playtest: escorts were dropping out of the camera view).
const STATIONS := [Vector2(-1, 1), Vector2(1, 1), Vector2(0, 1.7)]
## How fast the formation swings round after the flagship turns (per second). Stations
## follow this smoothed heading, so a turn doesn't whip the outer ships around.
const FORMATION_TURN_RATE := 0.35

var flagship: Ship
var escorts: Array[Ship] = []
var keep_together := true  ## false = "break away": the flagship ignores fleet pace
var engaged := false  ## in battle: there are aggressors, and escorts may fight them
var aggressors: Array[Ship] = []
var _quiet := 0.0  ## seconds since the fleet last fired or was hit
var pace := 1.0  ## current fleet-pace speed fraction on the flagship (1 = not limited)

var _time := 0.0
var _heading := NAN  ## smoothed flagship heading the formation is laid out on


func size() -> int:
	return 1 + escorts.size()


func is_full() -> bool:
	return size() >= MAX_SHIPS


func is_member(s: Ship) -> bool:
	return s == flagship or escorts.has(s)


## Add an escort under AI command. Returns false if the fleet is full.
func add_escort(s: Ship) -> bool:
	if is_full() or s == null:
		return false
	s.faction = flagship.faction
	escorts.append(s)
	var captain := AiCaptain.new()
	captain.ship = s
	captain.fleet = self
	captain.auto_target = true
	captain.engage_range = ENGAGE_RANGE
	s.get_parent().add_child(captain)
	s.sank.connect(_on_escort_sank.bind(s))
	s.fired.connect(_on_fleet_fired)  # escorts firing keeps a battle going
	s.attacked.connect(_on_fleet_attacked)
	changed.emit()
	return true


## Compass bearing the formation is currently laid out along (lags the flagship's turns).
func formation_heading() -> float:
	return _heading if not is_nan(_heading) else flagship.heading_bearing()


## World position (y = 0) of an escort's formation station right now.
func station_position(s: Ship) -> Vector3:
	var i := escorts.find(s)
	if i < 0 or not is_instance_valid(flagship):
		return s.global_position
	var st: Vector2 = STATIONS[i % STATIONS.size()]
	var rank := st.y + floorf(i / STATIONS.size()) * 2.0
	var gap_back := flagship.length() * 0.5 + s.length() * 0.5 + 14.0
	var gap_side := flagship.beam() * 0.5 + s.beam() * 0.5 + 18.0
	var h := formation_heading()
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	# Loose: each station wanders a few metres on its own slow cycle.
	var drift := Vector3(sin(_time * 0.05 + i * 1.7), 0.0, cos(_time * 0.043 + i * 2.3)) * 6.0
	var p := flagship.global_position - fwd * gap_back * rank + right * gap_side * st.x * (1.0 if rank <= 1.0 else 0.4)
	p += drift
	p.y = 0.0
	return p


func is_aggressor(s: Ship) -> bool:
	return aggressors.has(s)


## True if any aggressor is within `range_m` of the flagship. Battle is judged where the
## player is: sail away from a fight and fleet pace comes back on, so escorts can rejoin.
func aggressors_near(range_m: float) -> bool:
	for e in aggressors:
		if flagship.global_position.distance_to(e.global_position) < range_m:
			return true
	return false


## Call once the flagship is set.
func watch_flagship() -> void:
	flagship.fired.connect(_on_flagship_fired)
	flagship.attacked.connect(_on_fleet_attacked)
	flagship.landed_hit.connect(_on_flagship_hit_ship)


## A broadside marks every outside ship in its line of fire (roughly abeam on that side and
## within range), so firing at a ship and missing still counts as attacking it.
func _on_flagship_fired(side: int, ammo: int) -> void:
	var out := flagship.side_dir(side)
	var reach := Ship.ammo_range(ammo) * 1.15
	for node in get_tree().get_nodes_in_group("ships"):
		var s := node as Ship
		if s.is_sunk or is_member(s):
			continue
		var off := s.global_position - flagship.global_position
		off.y = 0.0
		var d := off.length()
		if d < 0.01 or d > reach + s.length() * 0.5:
			continue
		# Allow for the target's length: a long ship near the edge of the arc still counts.
		var half_arc := deg_to_rad(28.0) + atan2(s.length() * 0.5, d)
		if out.angle_to(off) < half_arc:
			_add_aggressor(s, "flagship fired on %s" % s.spec.display_name)
	if engaged:
		_quiet = 0.0


func _on_flagship_hit_ship(victim: Ship) -> void:
	if not is_member(victim):
		_add_aggressor(victim, "flagship hit %s" % victim.spec.display_name)


func _on_fleet_attacked(by: Ship) -> void:
	if is_instance_valid(by) and not is_member(by):
		_add_aggressor(by, "fleet attacked by %s" % by.spec.display_name)


func _on_fleet_fired(_side: int, _ammo: int) -> void:
	if engaged:
		_quiet = 0.0


func _add_aggressor(s: Ship, reason: String) -> void:
	_quiet = 0.0
	if aggressors.has(s):
		return
	aggressors.append(s)
	print("[fleet] aggressor: %s" % reason)
	if not engaged:
		engaged = true
		print("[fleet] battle")
	changed.emit()


func _physics_process(delta: float) -> void:
	_time += delta
	if not is_instance_valid(flagship):
		return
	var fh := flagship.heading_bearing()
	_heading = fh if is_nan(_heading) else lerp_angle(_heading, fh, 1.0 - exp(-FORMATION_TURN_RATE * delta))
	_prune()
	pace = 1.0
	if engaged:
		_quiet += delta
		if aggressors.is_empty() or (_quiet > COMBAT_TIMEOUT and not aggressors_near(ENGAGE_RANGE)):
			engaged = false
			aggressors.clear()
			print("[fleet] battle over: rejoining formation")
			changed.emit()
	if keep_together and not escorts.is_empty() and not engaged:
		var h := flagship.heading_bearing()
		var mine := maxf(flagship.potential_speed(h), 0.1)
		for e in escorts:
			if e.global_position.distance_to(flagship.global_position) > PACE_IGNORE_RANGE:
				continue  # left far behind: don't crawl waiting for her
			# Progress the escort can make along our heading, tacking if she can't point
			# as high as we can (a square-rigger upwind sets a slow pace).
			var hers := e.potential_progress(h, AiCaptain.FOLLOW_POINTING_MARGIN) * e.sail_power()
			pace = minf(pace, hers / mine * PACE_MARGIN)
			# And wait for anyone who has dropped behind her station.
			var behind := (station_position(e) - e.global_position).dot(Vector3(sin(h), 0.0, -cos(h)))
			if behind > WAIT_START:
				pace = minf(pace, lerpf(1.0, WAIT_MIN, clampf((behind - WAIT_START) / WAIT_SPAN, 0.0, 1.0)))
		pace = clampf(pace, WAIT_MIN, 1.0)
	# Top speed goes roughly with the square root of thrust (drag is mostly quadratic).
	flagship.thrust_limit = pace * pace


func _prune() -> void:
	aggressors = aggressors.filter(func(e): return is_instance_valid(e) and not e.is_sunk)
	var before := escorts.size()
	escorts = escorts.filter(func(e): return is_instance_valid(e) and not e.is_sunk)
	if escorts.size() != before:
		changed.emit()


func _on_escort_sank(_s: Ship) -> void:
	_prune()
