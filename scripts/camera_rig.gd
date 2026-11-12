extends Node3D
class_name CameraRig
## Pirates!-style high camera that follows the ship. Zooming in lowers the angle for a
## more cinematic view; zooming out goes nearly top-down for navigation.
## Mouse wheel = zoom, right-drag or Q/E = rotate.

@export var min_distance := 22.0
@export var max_distance := 220.0

var target: Node3D
var yaw := 0.0
var distance := 75.0
var camera: Camera3D

var _target_distance := 75.0
var _dragging := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 4000.0
	add_child(camera)
	camera.current = true
	if target:
		global_position = _focus()


func _focus() -> Vector3:
	var p := target.global_position
	return Vector3(p.x, 0.0, p.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = maxf(min_distance, _target_distance * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = minf(max_distance, _target_distance * 1.12)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		yaw -= (event as InputEventMouseMotion).relative.x * 0.005


func _process(delta: float) -> void:
	if target:
		global_position = global_position.lerp(_focus(), 1.0 - exp(-5.0 * delta))
	yaw += Input.get_axis("cam_right", "cam_left") * 1.6 * delta
	distance = lerpf(distance, _target_distance, 1.0 - exp(-8.0 * delta))
	var t := inverse_lerp(min_distance, max_distance, distance)
	var pitch := deg_to_rad(lerpf(-32.0, -68.0, t))
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)


## Compass bearing the camera is looking toward (0 = north).
func bearing() -> float:
	return -yaw
