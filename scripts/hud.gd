extends Control
class_name Hud
## Sailing and combat HUD: compass (wind, heading, enemies), sailing readouts, ship
## condition, broadside reload bars, ammo, floating bars over enemy ships, game over.

var ship: Ship
var controller: PlayerController
var camera_rig: CameraRig
var main: Node  ## main.gd, for the score

const TEXT := Color(1.0, 0.97, 0.9)
const DIM := Color(1.0, 0.97, 0.9, 0.45)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)
const PANEL := Color(0.05, 0.07, 0.1, 0.55)
const WIND_COL := Color(0.55, 0.8, 1.0)
const HEADING_COL := Color(1.0, 0.75, 0.3)
const ENEMY_COL := Color(1.0, 0.35, 0.3)
const HULL_COL := Color(0.85, 0.55, 0.3)
const SAIL_COL := Color(0.92, 0.9, 0.82)
const CREW_COL := Color(0.5, 0.85, 0.55)
const READY_COL := Color(1.0, 0.85, 0.4)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ship == null or camera_rig == null:
		return
	var font := ThemeDB.fallback_font
	_draw_enemy_labels(font)
	_draw_compass(font)
	_draw_readouts(font)
	_draw_status(font)
	if ship.is_sunk:
		_draw_game_over(font)


func _enemies() -> Array[Ship]:
	var out: Array[Ship] = []
	for n in get_tree().get_nodes_in_group("ships"):
		var s := n as Ship
		if s != ship and not s.is_sunk:
			out.append(s)
	return out


func _draw_compass(font: Font) -> void:
	# Rotates with the camera, so "up" on the dial is up on screen.
	var cam := camera_rig.bearing()
	var c := Vector2(size.x - 120.0, size.y - 120.0)
	var r := 85.0
	draw_circle(c, r + 8.0, PANEL)
	draw_arc(c, r, 0.0, TAU, 64, Color(0.9, 0.85, 0.7, 0.8), 2.0, true)
	var labels := ["N", "E", "S", "W"]
	for i in 4:
		var v := _dir(i * PI * 0.5, cam)
		_text(font, c + v * (r - 16.0) + Vector2(-6.0, 6.0), labels[i], 16)

	var wv := _dir(Wind.angle, cam)
	_arrow(c - wv * r * 0.7, c + wv * r * 0.7, WIND_COL, 3.0)
	_arrow(c, c + _dir(ship.heading_bearing(), cam) * r * 0.55, HEADING_COL, 4.0)

	# Enemy pips on the rim
	for e in _enemies():
		var rel := e.global_position - ship.global_position
		var pip := c + _dir(atan2(rel.x, -rel.z), cam) * (r + 1.0)
		draw_circle(pip, 6.0, ENEMY_COL)


func _draw_readouts(font: Font) -> void:
	var lines := [
		"Speed: %.1f kn" % ship.speed_knots,
		"Heading: %03d°" % int(wrapf(rad_to_deg(ship.heading_bearing()), 0.0, 360.0)),
		"Sails: %s" % ship.sail_name(),
		"Point of sail: %s (%d%%)" % [ship.point_of_sail, int(ship.sail_efficiency * 100.0)],
		"Wind: %.0f kn" % Wind.knots(),
	]
	if main:
		lines.append("Ships sunk: %d" % main.get("ships_sunk"))
	var y := 36.0
	for l in lines:
		_text(font, Vector2(24.0, y), l, 18)
		y += 26.0


## Bottom-left: hull/sails/crew, port and starboard reload, ammo choice.
func _draw_status(font: Font) -> void:
	var x := 24.0
	var y := size.y - 196.0
	draw_rect(Rect2(x - 12.0, y - 24.0, 380.0, 180.0), PANEL)

	_labeled_bar(font, Vector2(x, y), "Hull", ship.hull_frac(), HULL_COL, "%d%%" % roundi(ship.hull_frac() * 100.0))
	_labeled_bar(font, Vector2(x, y + 24.0), "Sails", ship.sails_frac(), SAIL_COL, "%d%%" % roundi(ship.sails))
	_labeled_bar(font, Vector2(x, y + 48.0), "Crew", ship.crew_frac(), CREW_COL, "%d / %d" % [int(ship.crew), int(ship.max_crew)])

	# Reload: the side under the cursor is highlighted.
	var aim := controller.aim_side if is_instance_valid(controller) else 0
	for side: int in [-1, 1]:
		var bx := x + (0.0 if side == -1 else 180.0)
		var p := ship.reload_progress(side)
		var loaded := ship.can_fire(side)
		var side_name := "Port" if side == -1 else "Starboard"
		var label := "%s  %s" % [side_name, "READY" if loaded else ""]
		_text(font, Vector2(bx, y + 86.0), label, 15, TEXT if side == aim else DIM)
		_bar(Rect2(bx, y + 93.0, 160.0, 8.0), p, READY_COL if loaded else Color(0.75, 0.4, 0.3))

	# Ammo
	var ammo := controller.ammo if is_instance_valid(controller) else 0
	var ax := x
	for i in Ship.AMMO.size():
		var s := "[%d] %s" % [i + 1, Ship.AMMO[i]["name"]]
		_text(font, Vector2(ax, y + 132.0), s, 15, READY_COL if i == ammo else DIM)
		ax += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18.0

	var help := "A/D steer   W/S sails   Left click fire broadside (side facing cursor)   1/2/3 ammo   Q/E or right-drag rotate   wheel zoom   F11   Esc quit"
	_text(font, Vector2(24.0, size.y - 18.0), help, 13, DIM)


## Small bars floating above each enemy ship.
func _draw_enemy_labels(font: Font) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for e in _enemies():
		var top := e.global_position + Vector3.UP * 17.0
		if cam.is_position_behind(top):
			continue
		var p := cam.unproject_position(top)
		var dist := (e.global_position - ship.global_position).length()
		var w := 70.0
		var x := p.x - w * 0.5
		_text(font, Vector2(x, p.y - 8.0), "Enemy  %d m" % roundi(dist), 13, ENEMY_COL)
		_bar(Rect2(x, p.y, w, 5.0), e.hull_frac(), HULL_COL)
		_bar(Rect2(x, p.y + 7.0, w, 5.0), e.sails_frac(), SAIL_COL)
		_bar(Rect2(x, p.y + 14.0, w, 5.0), e.crew_frac(), CREW_COL)


func _draw_game_over(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.35))
	var msg := "Your ship has gone down"
	var sub := "Press R to sail again"
	var big := 42
	var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(font, Vector2((size.x - w) * 0.5, size.y * 0.45), msg, big)
	var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(font, Vector2((size.x - w2) * 0.5, size.y * 0.45 + 44.0), sub, 20)


func _labeled_bar(font: Font, pos: Vector2, label: String, frac: float, col: Color, value: String) -> void:
	_text(font, pos + Vector2(0.0, 6.0), label, 15)
	_bar(Rect2(pos.x + 56.0, pos.y - 6.0, 220.0, 12.0), frac, col)
	_text(font, pos + Vector2(286.0, 6.0), value, 15)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.5))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)


func _dir(bearing: float, cam_bearing: float) -> Vector2:
	var a := bearing - cam_bearing
	return Vector2(sin(a), -cos(a))


func _text(font: Font, pos: Vector2, s: String, font_size: int, col := TEXT) -> void:
	draw_string(font, pos + Vector2(1.0, 1.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _arrow(from: Vector2, to: Vector2, col: Color, width: float) -> void:
	draw_line(from, to, col, width, true)
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to + d * 8.0, to - d * 6.0 + n * 7.0, to - d * 6.0 - n * 7.0]), col)
