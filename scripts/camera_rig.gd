extends Node3D
class_name CameraRig
## Two views that blend into each other:
##  - Map view: a high top-down "2.5D" camera with a narrow lens, so the world reads like a
##    map and ships like miniatures. Zooming in lowers the angle; zooming out goes nearly
##    top-down. Mouse wheel = zoom, right-drag or Q/E = rotate.
##  - Chase view (C, "cruise" in code): the camera swings down behind the ship and follows
##    its heading. Fully playable (owner, 2026-11-14): wheel zooms, right-drag or Q/E orbits
##    round the ship (easing back astern when let go), clicks fire. Only C returns to the map.

signal cruise_changed(on: bool)  ## hook for cruise music (crew shanties) later

@export var min_distance := 40.0
@export var max_distance := 650.0  ## far enough to see a whole fleet (owner playtest)
## Map tilt: one steady arc (owner, 2026-11-14). Near overhead when zoomed in; zooming out
## swings the camera back toward the bottom of the screen so you see further ahead. Even
## steps per wheel notch (interpolated on log distance, as zoom is multiplicative).
@export var map_pitch_near := -65.0
@export var map_pitch_far := -45.0
## Beyond this the haze is thinned as the camera pulls back (keeps far zoom from washing out).
@export var steepest_at := 400.0
@export var map_fov := 28.0  ## narrow lens = flatter, diorama-like perspective

@export_group("Cruise")
@export var cruise_fov := 50.0
@export var cruise_distance := 36.0
@export var cruise_pitch_deg := -9.0
@export var cruise_height := 5.0  ## aim at the rigging, so the ship sits low in frame
@export var cruise_follow := 1.2  ## how quickly the view swings round behind the ship
@export var cruise_roll := 0.35  ## share of the ship's heel the camera rolls with
@export var cruise_blend_time := 1.6
@export var chase_zoom_min := 0.6
@export var chase_zoom_max := 1.5  ## further out and the ocean mesh edge shows on the horizon
@export var chase_orbit_return_delay := 2.5  ## seconds after the last orbit input
@export var chase_orbit_return := 0.8  ## how quickly the view eases back astern after that

## Fog is heavier in cruise so the edge of the ocean mesh melts into the horizon.
const MAP_FOG := 0.00065
const CRUISE_FOG := 0.0045

var target: Node3D
var environment: Environment  ## set by main; fog follows the view
var sun: DirectionalLight3D  ## set by main; shadow range follows the view
var yaw := 0.0
var distance := 140.0
var camera: Camera3D
var cruising := false
var cruise_blend := 0.0  ## 0 = map view, 1 = fully behind the ship

var _target_distance := 140.0
var _dragging := false
var chase_orbit := 0.0  ## radians the chase view is swung round from dead astern
var _chase_zoom := 1.0
var _chase_target_zoom := 1.0
var _orbit_idle := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = map_fov
	camera.near = 0.3
	camera.far = 4000.0
	add_child(camera)
	camera.current = true
	if target:
		global_position = _focus()


func set_cruise(on: bool) -> void:
	if on == cruising:
		return
	cruising = on
	_dragging = false
	cruise_changed.emit(on)


## Cruise distance and height scale with the ship (the defaults are for the 16 m sloop):
## x = distance factor, y = height factor. Sub-linear, so a first rate isn't a speck.
var _cruise_scale: Vector2:
	get:
		if target == null or not target.has_method("length"):
			return Vector2.ONE
		return Vector2(pow(maxf(target.length() / 16.0, 1.0), 0.65),
				pow(maxf(target.hull_height() / 2.2, 1.0), 0.65))


func _focus() -> Vector3:
	var p := target.global_position
	return Vector3(p.x, 0.0, p.z)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cruise"):
		set_cruise(not cruising)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var zoom := mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		if cruising and zoom and mb.pressed:
			var k := 0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9
			_chase_target_zoom = clampf(_chase_target_zoom * k, chase_zoom_min, chase_zoom_max)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = maxf(min_distance, _target_distance * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = minf(max_distance, _target_distance * 1.12)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var dx := (event as InputEventMouseMotion).relative.x * 0.005
		if cruising:
			chase_orbit = wrapf(chase_orbit - dx, -PI, PI)
			_orbit_idle = 0.0
		else:
			yaw -= dx


func _process(delta: float) -> void:
	var rotate_input := Input.get_axis("cam_right", "cam_left")
	if cruising:
		if rotate_input != 0.0 or _dragging:
			chase_orbit = wrapf(chase_orbit + rotate_input * 1.6 * delta, -PI, PI)
			_orbit_idle = 0.0
		else:
			_orbit_idle += delta
			if _orbit_idle > chase_orbit_return_delay:
				chase_orbit = lerpf(chase_orbit, 0.0, 1.0 - exp(-chase_orbit_return * delta))
	_chase_zoom = lerpf(_chase_zoom, _chase_target_zoom, 1.0 - exp(-8.0 * delta))

	cruise_blend = move_toward(cruise_blend, 1.0 if cruising else 0.0, delta / cruise_blend_time)
	var b := smoothstep(0.0, 1.0, cruise_blend)

	var roll := 0.0
	if target:
		var focus := _focus() + Vector3.UP * cruise_height * _cruise_scale.y * _chase_zoom * b
		global_position = global_position.lerp(focus, 1.0 - exp(-5.0 * delta))
		if cruising:
			var f := -target.global_basis.z
			# Lazy swing behind the ship, but snappy while the player is orbiting by hand.
			var follow := cruise_follow if _orbit_idle > 0.4 else 10.0
			yaw = lerp_angle(yaw, atan2(-f.x, -f.z) + chase_orbit, 1.0 - exp(-follow * delta))
		roll = asin(clampf(target.global_basis.x.y, -1.0, 1.0)) * cruise_roll * b
	if not cruising:
		yaw += rotate_input * 1.6 * delta

	distance = lerpf(distance, _target_distance, 1.0 - exp(-8.0 * delta))
	var zt := clampf(log(distance / min_distance) / log(max_distance / min_distance), 0.0, 1.0)
	var map_pitch := lerpf(map_pitch_near, map_pitch_far, zt)
	var pitch := deg_to_rad(lerpf(map_pitch, cruise_pitch_deg, b))
	var eff_distance := lerpf(distance, cruise_distance * _cruise_scale.x * _chase_zoom, b)
	rotation = Vector3(pitch, yaw, roll)
	camera.position = Vector3(0.0, 0.0, eff_distance)
	camera.fov = lerpf(map_fov, cruise_fov, b)

	if environment:
		# Beyond the steepest-tilt distance, thin the haze as we pull back so the amount of
		# fog between camera and sea stays the same (otherwise far zoom looks washed out).
		var map_fog := MAP_FOG * minf(1.0, steepest_at / maxf(distance, 1.0))
		# Pulled back behind a big ship, thin the cruise fog a little so she isn't hazed out.
		environment.fog_density = lerpf(map_fog, CRUISE_FOG / sqrt(_cruise_scale.x), b)
	if sun:
		sun.directional_shadow_max_distance = eff_distance + 200.0


## Compass bearing the camera is looking toward (0 = north).
func bearing() -> float:
	return -yaw
