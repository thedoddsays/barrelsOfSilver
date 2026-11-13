extends Node3D
## Builds the prototype world in code: sky, sun, ocean, islands, ships, camera, HUD.
## Runs an endless skirmish: one enemy at a time, a new one arrives after each sinking.

const ISLAND_SEED := 1715
const ENEMY_RESPAWN_DELAY := 10.0
const ENEMY_FACTION := 1
## Debug: N adds an escort to the fleet, cycling through these (until capture exists).
const DEBUG_ESCORTS := ["sloop", "brigantine", "pirate_frigate"]

var ocean: Ocean
var environment: Environment
var sun: DirectionalLight3D
var player: Ship
var fleet: Fleet
var hud: Hud
var ships_sunk := 0
var island_count := 14  ## raised by the stress test

var _islands: Array[Vector3] = []  ## (x, z, radius) of each island
var _debug_escort_index := 0


func _ready() -> void:
	_setup_input()
	_setup_environment()

	ocean = Ocean.new()
	add_child(ocean)

	player = Ship.new()
	player.ocean = ocean
	player.free_when_sunk = false
	player.position = Vector3(0.0, 0.5, 0.0)
	# Start on a broad reach (wind over the port quarter), the fastest point of sail.
	var start_heading := wrapf(Wind.angle - deg_to_rad(40.0), 0.0, TAU)
	player.rotation.y = -start_heading
	add_child(player)

	fleet = Fleet.new()
	fleet.flagship = player
	add_child(fleet)
	fleet.watch_flagship()

	var controller := PlayerController.new()
	controller.ship = player
	add_child(controller)

	var rig := CameraRig.new()
	rig.target = player
	rig.yaw = -start_heading  # look the way the ship is sailing
	rig.environment = environment
	rig.sun = sun
	add_child(rig)
	ocean.follow_target = rig
	controller.camera_rig = rig

	_spawn_islands()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.ship = player
	hud.controller = controller
	hud.camera_rig = rig
	hud.main = self
	hud.fleet = fleet
	layer.add_child(hud)

	_spawn_enemy()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("restart") and player.is_sunk:
		get_tree().reload_current_scene()
	elif event.is_action_pressed("fleet_together"):
		fleet.keep_together = not fleet.keep_together
	elif event.is_action_pressed("debug_add_escort"):
		_debug_add_escort()


## Debug stand-in for capturing: spawn an escort astern of the flagship and add it to
## the fleet. Cycles sloop -> brigantine -> frigate.
func _debug_add_escort() -> void:
	if fleet.is_full() or player.is_sunk:
		return
	var id: String = DEBUG_ESCORTS[_debug_escort_index % DEBUG_ESCORTS.size()]
	_debug_escort_index += 1
	var h := player.heading_bearing()
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	var pos := player.global_position - fwd * 70.0 + right * randf_range(-40.0, 40.0)
	for attempt in 20:
		if _clear_of_islands(pos, 30.0):
			break
		pos = player.global_position - fwd * randf_range(60.0, 140.0) + right * randf_range(-80.0, 80.0)
	var s := Ship.new()
	s.ocean = ocean
	s.spec = load("res://data/ships/%s.tres" % id)
	s.hull_color = player.hull_color.lerp(Color(0.4, 0.3, 0.2), 0.3)
	s.flag_color = player.flag_color
	s.position = Vector3(pos.x, 0.5, pos.z)
	s.rotation.y = player.rotation.y
	add_child(s)
	s.linear_velocity = player.linear_velocity
	fleet.add_escort(s)
	# Start her on her formation station if that's open water, so escorts never spawn
	# on top of each other.
	var station := fleet.station_position(s)
	if _clear_of_islands(station, 30.0):
		s.global_position = Vector3(station.x, 0.5, station.z)


## Place an enemy 260-360 m away in clear water, pointed roughly at the player.
func _spawn_enemy() -> void:
	if player.is_sunk:
		return
	var pos := Vector3.ZERO
	for attempt in 40:
		var a := randf() * TAU
		pos = player.global_position + Vector3(sin(a), 0.0, -cos(a)) * randf_range(260.0, 360.0)
		if _clear_of_islands(pos, 40.0):
			break
	pos.y = 0.5

	var enemy := Ship.new()
	enemy.ocean = ocean
	enemy.spec = _random_enemy_spec()
	enemy.hull_color = Color(0.17, 0.13, 0.11)
	enemy.sail_color = Color(0.78, 0.74, 0.66)
	enemy.flag_color = Color(0.7, 0.1, 0.08)
	enemy.position = pos
	enemy.faction = ENEMY_FACTION
	var to_player := player.global_position - pos
	enemy.rotation.y = -atan2(to_player.x, -to_player.z)
	add_child(enemy)
	enemy.sank.connect(_on_enemy_sank)

	# Hunts the nearest ship of the player's fleet, starting with the player.
	var captain := AiCaptain.new()
	captain.ship = enemy
	captain.target = player
	captain.auto_target = true
	add_child(captain)


func _on_enemy_sank() -> void:
	ships_sunk += 1
	get_tree().create_timer(ENEMY_RESPAWN_DELAY).timeout.connect(_spawn_enemy)


## Prototype stand-in for the roster's rarity system: mostly sloops, some brigantines,
## the occasional frigate.
func _random_enemy_spec() -> ShipSpec:
	var r := randf()
	if r < 0.5:
		return load("res://data/ships/sloop.tres")
	if r < 0.85:
		return load("res://data/ships/brigantine.tres")
	return load("res://data/ships/pirate_frigate.tres")


func _clear_of_islands(p: Vector3, margin: float) -> bool:
	for isl in _islands:
		if Vector2(p.x - isl.x, p.z - isl.y).length() < isl.z + margin:
			return false
	return true


func _setup_input() -> void:
	_bind("steer_left", [KEY_A, KEY_LEFT])
	_bind("steer_right", [KEY_D, KEY_RIGHT])
	_bind("sails_up", [KEY_W, KEY_UP])
	_bind("sails_down", [KEY_S, KEY_DOWN])
	_bind("cam_left", [KEY_Q])
	_bind("cam_right", [KEY_E])
	_bind("toggle_fullscreen", [KEY_F11])
	_bind("quit", [KEY_ESCAPE])
	_bind("fleet_together", [KEY_F])
	_bind("debug_add_escort", [KEY_N])
	_bind("ammo_round", [KEY_1])
	_bind("ammo_chain", [KEY_2])
	_bind("ammo_grape", [KEY_3])
	_bind("restart", [KEY_R])
	_bind("cruise", [KEY_C])
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)


## Adds key bindings, once. (Guarded so a scene reload doesn't stack duplicates.)
func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
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
	environment = env
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
	env.fog_density = 0.00065  # CameraRig drives this per view
	env.fog_sky_affect = 0.3

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
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

	for i in island_count:
		var pos := Vector2.ZERO
		while pos.length() < 150.0:
			pos = Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
		var r := rng.randf_range(25.0, 80.0)
		_islands.append(Vector3(pos.x, pos.y, r))

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
