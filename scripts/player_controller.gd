extends Node
class_name PlayerController
## Drives the player's Ship from keyboard and mouse.
## A/D steer, W/S sail, 1/2/3 pick ammo, left click fires the broadside on whichever
## side of the ship the mouse cursor is. Draws the firing arcs for that side.

var ship: Ship
var ammo: int = Ship.Ammo.ROUND
var aim_side := 1  ## +1 starboard, -1 port: the side facing the cursor

var _arcs: ImmediateMesh
var _arc_view: MeshInstance3D


func _ready() -> void:
	_arcs = ImmediateMesh.new()
	_arc_view = MeshInstance3D.new()
	_arc_view.mesh = _arcs
	_arc_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true  # stay visible through wave crests
	_arc_view.material_override = m
	add_child(_arc_view)  # parent is a plain Node, so this sits in world space


func _unhandled_input(event: InputEvent) -> void:
	if not _alive():
		return
	if event.is_action_pressed("sails_up"):
		ship.sail_up()
	elif event.is_action_pressed("sails_down"):
		ship.sail_down()
	elif event.is_action_pressed("ammo_round"):
		ammo = Ship.Ammo.ROUND
	elif event.is_action_pressed("ammo_chain"):
		ammo = Ship.Ammo.CHAIN
	elif event.is_action_pressed("ammo_grape"):
		ammo = Ship.Ammo.GRAPE
	elif event.is_action_pressed("fire"):
		ship.fire(aim_side, ammo)


func _physics_process(_delta: float) -> void:
	if _alive():
		ship.steer_input = Input.get_axis("steer_left", "steer_right")


func _process(_delta: float) -> void:
	_arcs.clear_surfaces()
	if not _alive():
		return
	_update_aim_side()
	_draw_arcs()


func _alive() -> bool:
	return is_instance_valid(ship) and not ship.is_sunk


## Which side of the ship is the mouse on? Projects the cursor onto the sea plane.
func _update_aim_side() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if dir.y > -0.001:
		return  # cursor is on the sky
	var hit := origin + dir * (-origin.y / dir.y)
	var rel := hit - ship.global_position
	aim_side = 1 if rel.dot(ship.global_basis.x) >= 0.0 else -1


## One ballistic arc per gun out to where the ball lands, joined across the ends.
## Bright when that side is loaded, dim red while reloading.
func _draw_arcs() -> void:
	var loaded := ship.can_fire(aim_side)
	var col := Color(1.0, 0.95, 0.75, 0.55) if loaded else Color(1.0, 0.45, 0.35, 0.22)
	var step := 0.05
	var ends: Array[Vector3] = []
	_arcs.surface_begin(Mesh.PRIMITIVE_LINES)
	for g in Ship.GUN_Z.size():
		var p := ship.gun_position(aim_side, g)
		var v := ship.shot_velocity(aim_side, ammo)
		for i in 80:
			var prev := p
			v.y -= Cannonball.GRAVITY * step
			p += v * step
			_line(prev, p, col)
			if p.y < 0.0:
				break
		ends.append(p)
	for i in ends.size() - 1:
		_line(ends[i], ends[i + 1], col)
	_arcs.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_arcs.surface_set_color(col)
	_arcs.surface_add_vertex(a)
	_arcs.surface_set_color(col)
	_arcs.surface_add_vertex(b)
