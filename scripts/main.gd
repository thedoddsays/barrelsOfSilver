extends Node3D
## Builds the prototype world in code: sky, sun, ocean, islands, ship, camera, HUD.

const ISLAND_SEED := 1715


func _ready() -> void:
	_setup_input()
	_setup_environment()

	var ocean := Ocean.new()
	add_child(ocean)

	var ship := Ship.new()
	ship.ocean = ocean
	ship.position = Vector3(0.0, 0.5, 0.0)
	# Start on a broad reach (wind over the port quarter), the fastest point of sail.
	var start_heading := wrapf(Wind.angle - deg_to_rad(40.0), 0.0, TAU)
	ship.rotation.y = -start_heading
	add_child(ship)

	var rig := CameraRig.new()
	rig.target = ship
	rig.yaw = -start_heading  # look the way the ship is sailing
	add_child(rig)
	ocean.follow_target = rig

	_spawn_islands()

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Hud.new()
	hud.ship = ship
	hud.camera_rig = rig
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("quit"):
		get_tree().quit()


func _setup_input() -> void:
	_bind("steer_left", [KEY_A, KEY_LEFT])
	_bind("steer_right", [KEY_D, KEY_RIGHT])
	_bind("sails_up", [KEY_W, KEY_UP])
	_bind("sails_down", [KEY_S, KEY_DOWN])
	_bind("cam_left", [KEY_Q])
	_bind("cam_right", [KEY_E])
	_bind("toggle_fullscreen", [KEY_F11])
	_bind("quit", [KEY_ESCAPE])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.66, 0.79, 0.9)
	sky_mat.ground_horizon_color = Color(0.66, 0.79, 0.9)
	sky_mat.ground_bottom_color = Color(0.05, 0.15, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.8, 0.9)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.3

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


func _spawn_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ISLAND_SEED
	var sand := _mat(Color(0.86, 0.78, 0.56))
	var grass := _mat(Color(0.22, 0.45, 0.18))
	var trunk := _mat(Color(0.4, 0.3, 0.2))
	var leaves := _mat(Color(0.18, 0.4, 0.12))

	for i in 14:
		var pos := Vector2.ZERO
		while pos.length() < 150.0:
			pos = Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
		var r := rng.randf_range(25.0, 80.0)

		var body := StaticBody3D.new()
		body.position = Vector3(pos.x, 0.0, pos.y)
		add_child(body)

		_add_blob(body, r, r * 0.12, -r * 0.03, sand)
		_add_blob(body, r * 0.75, r * 0.25, -r * 0.05, grass)

		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 0.85
		cyl.height = 20.0
		col.shape = cyl
		body.add_child(col)

		for p in rng.randi_range(3, 7):
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.1, 0.55) * r
			var h := rng.randf_range(6.0, 10.0)
			var base := Vector3(cos(a) * d, r * 0.15, sin(a) * d)
			var t := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.25
			tm.bottom_radius = 0.4
			tm.height = h
			t.mesh = tm
			t.material_override = trunk
			t.position = base + Vector3(0.0, h * 0.5, 0.0)
			t.rotation.z = rng.randf_range(-0.2, 0.2)
			body.add_child(t)
			var crown := MeshInstance3D.new()
			var cm := SphereMesh.new()
			cm.radius = 2.6
			cm.height = 1.4
			crown.mesh = cm
			crown.material_override = leaves
			crown.position = base + Vector3(0.0, h, 0.0)
			body.add_child(crown)


func _add_blob(parent: Node3D, radius: float, height: float, y: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	mi.mesh = s
	mi.material_override = m
	mi.scale = Vector3(radius, height, radius)
	mi.position.y = y
	parent.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
