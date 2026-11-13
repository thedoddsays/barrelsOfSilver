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
## - Engage on command: escorts ignore every other ship until the flagship engages, i.e.
##   the player opens fire or the fleet comes under fire (owner, 2026-11-13). Then they fight
##   enemies near the flagship, and the battle ends after COMBAT_TIMEOUT quiet seconds with
##   no enemy close; escorts rejoin and fleet pace comes back on.

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
var engaged := false  ## the flagship has engaged: escorts may fight
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
	s.hull_damaged.connect(_on_fleet_hit)
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


## True if any hostile ship is within `range_m` of the flagship. Battle is judged where the
## player is: sail away from a fight and fleet pace comes back on, so escorts can rejoin.
func enemies_near(range_m: float) -> bool:
	for node in get_tree().get_nodes_in_group("ships"):
		var e := node as Ship
		if e.is_sunk or not flagship.is_hostile_to(e):
			continue
		if flagship.global_position.distance_to(e.global_position) < range_m:
			return true
	return false


## Call once the flagship is set: the player firing, or the flagship being hit, engages.
func watch_flagship() -> void:
	flagship.fired.connect(_on_flagship_fired)
	flagship.hull_damaged.connect(_on_fleet_hit)


func _on_flagship_fired(_side: int) -> void:
	_engage("flagship opened fire")


func _on_fleet_fired(_side: int) -> void:
	if engaged:
		_quiet = 0.0


func _on_fleet_hit(source: String, _amount: float) -> void:
	if source == "cannon" or source == "rammed":
		_engage("fleet under fire")


func _engage(reason: String) -> void:
	_quiet = 0.0
	if not engaged:
		engaged = true
		print("[fleet] battle: %s" % reason)
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
		if _quiet > COMBAT_TIMEOUT and not enemies_near(ENGAGE_RANGE):
			engaged = false
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
	var before := escorts.size()
	escorts = escorts.filter(func(e): return is_instance_valid(e) and not e.is_sunk)
	if escorts.size() != before:
		changed.emit()


func _on_escort_sank(_s: Ship) -> void:
	_prune()
