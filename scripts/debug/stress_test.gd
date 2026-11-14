extends "res://scripts/main.gd"
## Performance stress test. Open scenes/debug/stress_test.tscn and press F6 (Run Current Scene).
##
## The normal game world, plus pairs of AI ships fighting each other near the player with
## full broadsides: the heaviest realistic load (physics, AI, cannonballs, smoke trails,
## wakes). Stress ships can't sink, so the load stays constant. The map gets extra islands.
##
## Keys:  ]  add 5 pairs     [  remove 5 pairs     B  run the automatic benchmark
##        V  toggle vsync (off = true frame rate; on = capped at the monitor's refresh)
##
## The benchmark steps through BENCH_SHIPS, settles, measures, prints a table to the Output
## panel and saves it to user://stress_results.txt. Launch with `-- --bench` to start it
## automatically, or `-- --bench --quit` to also exit when done.
## Not shipped: scenes/debug and scripts/debug are excluded in export_presets.cfg.

const STRESS_ISLANDS := 40
const PAIR_STEP := 5
const BENCH_SHIPS := [0, 10, 20, 30, 40, 60]  ## AI ships per step (always even)
const BENCH_SETTLE := 4.0
const BENCH_MEASURE := 10.0
const BENCH_ZOOM := 300.0  ## camera distance during the benchmark, so the fight is on screen
## Stress ships are a random mix of every modelled ship type, weighted roughly like a real
## sea (lots of small ships, a few big ones). Launch with `-- --sloops` for sloops only.
const STRESS_MIX := {"sloop": 4, "ketch": 2, "schooner": 1, "brigantine": 3, "brig": 2, "snow": 1,
	"barque": 1, "merchantman": 2, "pirate_frigate": 1, "east_indiaman": 1,
	"periagua": 1, "barco_luengo": 2, "navy_sloop": 2, "fluyt": 2, "galleon": 1, "fourth_rate": 1,
	"third_rate": 1, "second_rate": 1, "first_rate": 1}

var _pairs: Array = []  ## [ship_a, ship_b] per pair
var _rig: CameraRig
var _label: Label
var _ui_timer := 0.0
var _balls := 0

var _bench_step := -1  ## -1 = not benchmarking
var _bench_timer := 0.0
var _bench_frames := PackedFloat32Array()
var _bench_process := 0.0
var _bench_physics := 0.0
var _bench_draws := 0.0
var _bench_samples := 0
var _bench_max_balls := 0
var _bench_rows: Array[String] = []
var _quit_after_bench := false
var _sloops_only := false
var _specs := {}  ## id -> ShipSpec


func _ready() -> void:
	island_count = STRESS_ISLANDS
	super._ready()
	for c in get_children():
		if c is CameraRig:
			_rig = c
	# The player is just a camera anchor here: keep it in place and out of trouble.
	player.max_hull = 1.0e6
	player.hull = 1.0e6
	player.sail_index = 0
	_build_overlay()
	var args := OS.get_cmdline_user_args()
	_quit_after_bench = "--quit" in args
	_sloops_only = "--sloops" in args
	if "--bench" in args:
		_start_bench.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_BRACKETRIGHT:
			_set_ship_count(_pairs.size() * 2 + PAIR_STEP * 2)
		KEY_BRACKETLEFT:
			_set_ship_count(_pairs.size() * 2 - PAIR_STEP * 2)
		KEY_B:
			if _bench_step < 0:
				_start_bench()
		KEY_V:
			var on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if on else DisplayServer.VSYNC_ENABLED)


func _process(delta: float) -> void:
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.25
		_balls = _count_balls()
		_update_overlay()
	if _bench_step >= 0:
		_tick_bench(delta)


# ---------------------------------------------------------------------------
# Stress ships
# ---------------------------------------------------------------------------

func _set_ship_count(n: int) -> void:
	var pairs := clampi(n / 2, 0, 100)
	while _pairs.size() < pairs:
		_add_pair()
	while _pairs.size() > pairs:
		var pair: Array = _pairs.pop_back()
		for s in pair:
			if is_instance_valid(s):
				s.queue_free()  # their AiCaptains free themselves


func _add_pair() -> void:
	var centre := player.global_position
	var pos := centre
	for attempt in 40:
		var ang := randf() * TAU
		pos = centre + Vector3(sin(ang), 0.0, -cos(ang)) * randf_range(60.0, 260.0)
		if _clear_of_islands(pos, 45.0):
			break
	var b_angle := randf() * TAU
	var offset := Vector3(sin(b_angle), 0.0, -cos(b_angle)) * 120.0
	var a := _spawn_stress_ship(pos - offset * 0.5, offset)
	var b := _spawn_stress_ship(pos + offset * 0.5, -offset)
	a.faction = 1  # opposing sides, so their shots hit each other (no friendly fire)
	b.faction = 2
	_add_captain(a, b)
	_add_captain(b, a)
	_pairs.append([a, b])


func _spawn_stress_ship(pos: Vector3, facing: Vector3) -> Ship:
	var s := Ship.new()
	s.ocean = ocean
	s.spec = _random_spec()
	s.hull_color = Color.from_hsv(randf(), 0.4, 0.35)
	s.sail_color = Color(0.85, 0.82, 0.74)
	s.flag_color = Color.from_hsv(randf(), 0.8, 0.7)
	s.position = Vector3(pos.x, 0.5, pos.z)
	s.rotation.y = atan2(-facing.x, -facing.z)
	add_child(s)
	# After add_child, because the ship's spec sets its hull and crew in _ready().
	s.max_hull = 1.0e6  # unsinkable, so the load stays constant
	s.hull = s.max_hull
	s.max_crew = 5000.0  # crew losses never slow the guns
	s.crew = s.max_crew
	return s


func _random_spec() -> ShipSpec:
	var id := "sloop"
	if not _sloops_only:
		var total := 0
		for k in STRESS_MIX:
			total += int(STRESS_MIX[k])
		var r := randi() % total
		for k in STRESS_MIX:
			r -= int(STRESS_MIX[k])
			if r < 0:
				id = k
				break
	if not _specs.has(id):
		_specs[id] = load("res://data/ships/%s.tres" % id)
	return _specs[id]


func _add_captain(ship: Ship, target: Ship) -> void:
	var c := AiCaptain.new()
	c.ship = ship
	c.target = target
	add_child(c)


func _count_balls() -> int:
	var n := 0
	for c in get_children():
		if c is Cannonball:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Benchmark
# ---------------------------------------------------------------------------

func _start_bench() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _rig:
		_rig.set_cruise(false)
		_rig.set("_target_distance", BENCH_ZOOM)
	_bench_rows.clear()
	_bench_step = 0
	_begin_step()


func _begin_step() -> void:
	_set_ship_count(BENCH_SHIPS[_bench_step])
	_bench_timer = -BENCH_SETTLE  # negative = settling, not measured yet
	_bench_frames.clear()
	_bench_process = 0.0
	_bench_physics = 0.0
	_bench_draws = 0.0
	_bench_samples = 0
	_bench_max_balls = 0


func _tick_bench(delta: float) -> void:
	_bench_timer += delta
	if _bench_timer < 0.0:
		return
	_bench_frames.append(delta)
	_bench_process += Performance.get_monitor(Performance.TIME_PROCESS)
	_bench_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_bench_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_samples += 1
	_bench_max_balls = maxi(_bench_max_balls, _balls)
	if _bench_timer < BENCH_MEASURE:
		return

	var sorted := _bench_frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in sorted:
		total += f
	var avg_fps := sorted.size() / total
	var worst := sorted[int((sorted.size() - 1) * 0.99)]  # 99th-percentile frame time
	var k := float(_bench_samples)
	_bench_rows.append("| %3d | %6.0f | %6.0f | %8.1f | %8.1f | %6.0f | %5d |" % [
		BENCH_SHIPS[_bench_step], avg_fps, 1.0 / worst,
		_bench_process / k * 1000.0, _bench_physics / k * 1000.0,
		_bench_draws / k, _bench_max_balls])

	_bench_step += 1
	if _bench_step < BENCH_SHIPS.size():
		_begin_step()
	else:
		_finish_bench()


func _finish_bench() -> void:
	_bench_step = -1
	var lines: Array[String] = [
		"Barrels of Silver stress test, %s" % Time.get_datetime_string_from_system(false, true),
		"GPU: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"CPU: %s, %d threads | OS: %s | renderer: %s" % [OS.get_processor_name(), OS.get_processor_count(),
			OS.get_name(), RenderingServer.get_current_rendering_driver_name()],
		"Window: %s, %d islands, vsync off, camera at %d m" % [str(get_viewport().get_visible_rect().size),
			STRESS_ISLANDS, int(BENCH_ZOOM)],
		"Ships: %s" % ("sloops only" if _sloops_only else "random mix of all modelled types (STRESS_MIX)"),
		"",
		"| AI ships | avg FPS | 1% low FPS | process ms | physics ms | draw calls | max balls |",
		"|---|---|---|---|---|---|---|",
	]
	lines.append_array(_bench_rows)
	var text := "\n".join(PackedStringArray(lines))
	print("\n" + text + "\n")
	var f := FileAccess.open("user://stress_results.txt", FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		f.close()
		print("Saved to %s" % ProjectSettings.globalize_path("user://stress_results.txt"))
	if _quit_after_bench:
		get_tree().quit()


# ---------------------------------------------------------------------------
# Overlay
# ---------------------------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20.0, 200.0)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _update_overlay() -> void:
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	var lines := [
		"STRESS TEST   ] add 5 pairs   [ remove   B benchmark   V vsync (%s)" % ("on" if vsync else "off"),
		"FPS %d   process %.1f ms   physics %.1f ms" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"AI ships %d   cannonballs %d   islands %d   draw calls %d   nodes %d" % [_pairs.size() * 2,
			_balls, _islands.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
	]
	if _bench_step >= 0:
		lines.append("BENCHMARK step %d/%d: %d ships, %s" % [_bench_step + 1, BENCH_SHIPS.size(),
			BENCH_SHIPS[_bench_step], "settling" if _bench_timer < 0.0 else "measuring"])
	elif not _bench_rows.is_empty():
		lines.append("Benchmark done: results in the Output panel and user://stress_results.txt")
	_label.text = "\n".join(PackedStringArray(lines))
