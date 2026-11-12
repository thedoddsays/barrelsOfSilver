class_name Fx
## One-shot particle effects: muzzle flash and smoke, splashes, splinters, dust.
## Each effect is a CPUParticles3D that frees itself when it finishes.

static var _quad: QuadMesh


## Shared billboard quad that takes its colour from the particle colour ramp.
## A soft radial-falloff texture makes each particle a round puff instead of a square.
static func particle_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		_quad.material = m
	return _quad


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Continuous smoke trail behind a cannonball so its flight is easy to follow.
static func ball_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.7
	p.local_coords = false
	p.mesh = particle_quad()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.95, 0.93, 0.88, 0.75))
	ramp.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	p.color_ramp = ramp
	return p


static func muzzle(parent: Node, pos: Vector3, out: Vector3) -> void:
	# Flash
	_burst(parent, pos, Color(1.0, 0.78, 0.4, 1.0), 8, out, 15.0, 6.0, 14.0,
		0.6, 1.3, 0.25, Vector3.ZERO, 4.0)
	# Smoke: drifts out of the port, slows, rises a little and hangs around
	_burst(parent, pos, Color(0.88, 0.88, 0.85, 0.7), 14, (out + Vector3.UP * 0.2).normalized(), 18.0,
		3.0, 9.0, 2.0, 4.5, 3.5, Vector3(0.0, 0.4, 0.0), 2.5)


static func splash(parent: Node, pos: Vector3, small := false) -> void:
	var n := 6 if small else 18
	var size := 0.5 if small else 1.0
	_burst(parent, pos, Color(0.95, 0.97, 1.0, 0.9), n, Vector3.UP, 16.0, 5.0, 11.0,
		0.4 * size, 1.0 * size, 1.3, Vector3(0.0, -12.0, 0.0), 0.0)


static func splinters(parent: Node, pos: Vector3) -> void:
	_burst(parent, pos, Color(0.45, 0.3, 0.17, 1.0), 14, Vector3.UP, 70.0, 3.0, 9.0,
		0.15, 0.4, 1.2, Vector3(0.0, -9.8, 0.0), 0.0)
	_burst(parent, pos, Color(0.5, 0.48, 0.45, 0.6), 5, Vector3.UP, 40.0, 1.0, 3.0,
		1.0, 2.0, 1.5, Vector3(0.0, 0.5, 0.0), 1.0)


static func dust(parent: Node, pos: Vector3) -> void:
	_burst(parent, pos, Color(0.8, 0.7, 0.5, 0.8), 12, Vector3.UP, 60.0, 2.0, 6.0,
		0.6, 1.4, 1.4, Vector3(0.0, -4.0, 0.0), 1.0)


static func _burst(parent: Node, pos: Vector3, color: Color, amount: int, dir: Vector3,
		spread_deg: float, speed_min: float, speed_max: float, size_min: float,
		size_max: float, lifetime: float, gravity: Vector3, damping: float) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = particle_quad()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = gravity
	p.damping_min = damping
	p.damping_max = damping
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.emitting = true
