extends MeshInstance3D
class_name Ocean
## Gerstner-wave ocean. The mesh follows the camera (snapped to its vertex grid so the
## surface doesn't "swim"), and get_height() mirrors the shader maths for buoyancy.

const GRAVITY := 9.8
## (dir.x, dir.y, steepness, wavelength in metres). Keep total steepness well under 1.
const WAVES := [
	Vector4(1.0, 0.3, 0.14, 60.0),
	Vector4(0.6, 1.0, 0.13, 33.0),
	Vector4(-0.3, 1.0, 0.12, 21.0),
	Vector4(0.8, -0.5, 0.08, 13.0),
]
const UNIFORMS := ["wave_a", "wave_b", "wave_c", "wave_d"]

@export var size := 1200.0
@export var subdivisions := 400

var follow_target: Node3D
var _mat: ShaderMaterial
var _start_usec := 0


func _ready() -> void:
	_start_usec = Time.get_ticks_usec()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ocean.gdshader")
	for i in WAVES.size():
		_mat.set_shader_parameter(UNIFORMS[i], WAVES[i])
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16.0


const MAX_HULLS := 96  ## must match ocean.gdshader

var hull_mask_enabled := true  ## debug: false shows the raw sea (crests through decks)
var _hull_origin := PackedVector4Array()
var _hull_x := PackedVector4Array()
var _hull_z := PackedVector4Array()


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("wave_time", wave_time())
	_update_hull_mask()
	if follow_target:
		var step := size / subdivisions
		var p := follow_target.global_position
		global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))


## Tell the shader where every afloat ship is, so wave crests don't show through decks.
func _update_hull_mask() -> void:
	_hull_origin.resize(MAX_HULLS)
	_hull_x.resize(MAX_HULLS)
	_hull_z.resize(MAX_HULLS)
	var n := 0
	for node in get_tree().get_nodes_in_group("ships"):
		var s := node as Ship
		if not hull_mask_enabled:
			break
		if s == null or s.is_sunk or n >= MAX_HULLS:
			continue
		var t := s.global_transform
		var x := t.basis.x.normalized()
		var z := t.basis.z.normalized()
		_hull_origin[n] = Vector4(t.origin.x, t.origin.y, t.origin.z, s.length())
		_hull_x[n] = Vector4(x.x, x.y, x.z, s.beam())
		_hull_z[n] = Vector4(z.x, z.y, z.z, s.water_mask_height())
		n += 1
	_mat.set_shader_parameter("hull_count", n)
	_mat.set_shader_parameter("hull_origin", _hull_origin)
	_mat.set_shader_parameter("hull_x", _hull_x)
	_mat.set_shader_parameter("hull_z", _hull_z)


func wave_time() -> float:
	return float(Time.get_ticks_usec() - _start_usec) * 0.000001


func displacement(p: Vector2, t: float) -> Vector3:
	var total := Vector3.ZERO
	for w: Vector4 in WAVES:
		var k := TAU / w.w
		var c := sqrt(GRAVITY / k)
		var d := Vector2(w.x, w.y).normalized()
		var f := k * (d.dot(p) - c * t)
		var a := w.z / k
		total += Vector3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f))
	return total


## Water surface height at world (x, z). Gerstner waves move points sideways, so we
## iterate a few times to find which undisplaced point lands at (x, z).
func get_height(x: float, z: float, t: float = -1.0) -> float:
	if t < 0.0:
		t = wave_time()
	var target := Vector2(x, z)
	var p := target
	for i in 3:
		var d := displacement(p, t)
		p = target - Vector2(d.x, d.z)
	return displacement(p, t).y
