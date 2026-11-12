extends Node3D
class_name Cannonball
## A ball in flight. Simple ballistics; each physics step it checks the islands (ray),
## enemy ships (Ship.contains_point) and the water surface, then frees itself on impact.

const GRAVITY := 9.8
const MAX_LIFETIME := 8.0

var velocity := Vector3.ZERO
var shooter: Ship
var ammo := 0
var ocean: Ocean

var _life := 0.0

static var _mesh_cache := {}  # radius -> SphereMesh
static var _material: StandardMaterial3D


func _ready() -> void:
	var a: Dictionary = Ship.AMMO[ammo]
	var mi := MeshInstance3D.new()
	mi.mesh = _ball_mesh(a["radius"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME:
		queue_free()
		return

	var from := global_position
	velocity.y -= GRAVITY * delta
	var to := from + velocity * delta

	# Islands and other scenery
	var q := PhysicsRayQueryParameters3D.create(from, to, Ship.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		Fx.dust(get_parent(), hit["position"])
		queue_free()
		return

	# Ships. Test the midpoint too so fast balls can't skip through a thin hull.
	var mid := (from + to) * 0.5
	for node in get_tree().get_nodes_in_group("ships"):
		var s := node as Ship
		if s == shooter or s.is_sunk:
			continue
		if s.contains_point(mid) or s.contains_point(to):
			s.take_hit(ammo, to, velocity)
			queue_free()
			return

	global_position = to

	if ocean and to.y < ocean.get_height(to.x, to.z):
		Fx.splash(get_parent(), to, Ship.AMMO[ammo]["balls"] > 1)
		queue_free()


static func _ball_mesh(radius: float) -> SphereMesh:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.08, 0.08, 0.08)
		_material.roughness = 0.6
		_material.metallic = 0.6
	if not _mesh_cache.has(radius):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 10
		m.rings = 6
		m.material = _material
		_mesh_cache[radius] = m
	return _mesh_cache[radius]
