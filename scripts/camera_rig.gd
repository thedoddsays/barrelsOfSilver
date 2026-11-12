extends Node3D
class_name CameraRig
## Two views that blend into each other:
##  - Map view: a high top-down "2.5D" camera with a narrow lens, so the world reads like a
##    map and ships like miniatures. Zooming in lowers the angle; zooming out goes nearly
##    top-down. Mouse wheel = zoom, right-drag or Q/E = rotate.
##  - Cruise view (C): the camera swings down behind the ship and follows its heading, HUD
##    hidden, for just sailing. Any map-camera input, a click, or C again returns to the map.

signal cruise_changed(on: bool)  ## hook for cruise music (crew shanties) later

@export var min_distance := 40.0
@export var max_distance := 400.0
@export var map_fov := 28.0  ## narrow lens = flatter, diorama-like perspective

@export_group("Cruise")
@export var cruise_fov := 50.0
@export var cruise_distance := 36.0
@export var cruise_pitch_deg := -9.0
@export var cruise_height := 5.0  ## aim at the rigging, so the ship sits low in frame
@export var cruise_follow := 1.2  ## how quickly the view swings round behind the ship
@export var cruise_roll := 0.35  ## share of the ship's heel the camera rolls with
@export var cruise_blend_time := 1.6

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
		if cruising and mb.pressed and (zoom or mb.button_index == MOUSE_BUTTON_RIGHT):
			set_cruise(false)  # touching the map controls brings the map view back
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = maxf(min_distance, _target_distance * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = minf(max_distance, _target_distance * 1.12)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and not cruising:
		yaw -= (event as InputEventMouseMotion).relative.x * 0.005


func _process(delta: float) -> void:
	var rotate_input := Input.get_axis("cam_right", "cam_left")
	if cruising and rotate_input != 0.0:
		set_cruise(false)

	cruise_blend = move_toward(cruise_blend, 1.0 if cruising else 0.0, delta / cruise_blend_time)
	var b := smoothstep(0.0, 1.0, cruise_blend)

	var roll := 0.0
	if target:
		var focus := _focus() + Vector3.UP * cruise_height * b
		global_position = global_position.lerp(focus, 1.0 - exp(-5.0 * delta))
		if cruising:
			var f := -target.global_basis.z
			yaw = lerp_angle(yaw, atan2(-f.x, -f.z), 1.0 - exp(-cruise_follow * delta))
		roll = asin(clampf(target.global_basis.x.y, -1.0, 1.0)) * cruise_roll * b
	if not cruising:
		yaw += rotate_input * 1.6 * delta

	distance = lerpf(distance, _target_distance, 1.0 - exp(-8.0 * delta))
	var t := inverse_lerp(min_distance, max_distance, distance)
	var map_pitch := lerpf(-32.0, -68.0, t)
	var pitch := deg_to_rad(lerpf(map_pitch, cruise_pitch_deg, b))
	var eff_distance := lerpf(distance, cruise_distance, b)
	rotation = Vector3(pitch, yaw, roll)
	camera.position = Vector3(0.0, 0.0, eff_distance)
	camera.fov = lerpf(map_fov, cruise_fov, b)

	if environment:
		environment.fog_density = lerpf(MAP_FOG, CRUISE_FOG, b)
	if sun:
		sun.directional_shadow_max_distance = eff_distance + 200.0


## Compass bearing the camera is looking toward (0 = north).
func bearing() -> float:
	return -yaw
