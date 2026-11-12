extends Control
class_name Hud
## Minimal sailing HUD: compass with wind and heading, plus readouts.

var ship: Ship
var camera_rig: CameraRig

const TEXT := Color(1.0, 0.97, 0.9)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)
const WIND_COL := Color(0.55, 0.8, 1.0)
const HEADING_COL := Color(1.0, 0.75, 0.3)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ship == null or camera_rig == null:
		return
	var font := ThemeDB.fallback_font
	var cam := camera_rig.bearing()

	# Compass (rotates with the camera, so "up" on the dial is up on screen)
	var c := Vector2(size.x - 120.0, size.y - 120.0)
	var r := 85.0
	draw_circle(c, r + 8.0, Color(0.05, 0.07, 0.1, 0.55))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.9, 0.85, 0.7, 0.8), 2.0, true)
	var labels := ["N", "E", "S", "W"]
	for i in 4:
		var v := _dir(i * PI * 0.5, cam)
		_text(font, c + v * (r - 16.0) + Vector2(-6.0, 6.0), labels[i], 16)

	var wv := _dir(Wind.angle, cam)
	_arrow(c - wv * r * 0.7, c + wv * r * 0.7, WIND_COL, 3.0)
	_arrow(c, c + _dir(ship.heading_bearing(), cam) * r * 0.55, HEADING_COL, 4.0)

	# Readouts
	var lines := [
		"Speed: %.1f kn" % ship.speed_knots,
		"Heading: %03d°" % int(wrapf(rad_to_deg(ship.heading_bearing()), 0.0, 360.0)),
		"Sails: %s" % ship.sail_name(),
		"Point of sail: %s (%d%%)" % [ship.point_of_sail, int(ship.sail_efficiency * 100.0)],
		"Wind: %.0f kn" % Wind.knots(),
	]
	var y := 36.0
	for l in lines:
		_text(font, Vector2(24.0, y), l, 18)
		y += 26.0

	var help := "A/D steer    W/S sails    Q/E or right-drag rotate    wheel zoom    F11 fullscreen    Esc quit"
	_text(font, Vector2(24.0, size.y - 24.0), help, 14)


func _dir(bearing: float, cam_bearing: float) -> Vector2:
	var a := bearing - cam_bearing
	return Vector2(sin(a), -cos(a))


func _text(font: Font, pos: Vector2, s: String, font_size: int) -> void:
	draw_string(font, pos + Vector2(1.0, 1.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT)


func _arrow(from: Vector2, to: Vector2, col: Color, width: float) -> void:
	draw_line(from, to, col, width, true)
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([to + d * 8.0, to - d * 6.0 + n * 7.0, to - d * 6.0 - n * 7.0]), col)
