## SceneBuilder — GLM-5.1 驱动的 3D 展厅构建引擎
##
## 从 scene_spec.json 自动构建完整的 3D 虚拟展厅：
## 房间几何体、NFT 展位、9 种程序化艺术风格、灯光系统、
## 装饰元素、第一人称相机。
##
## CCGS Skills Applied:
##   - scene-organization: 模块化组件拆分 (scripts/)
##   - procedural-generation: 9 种程序化艺术算法 + 后处理
##   - godot-optimization: Material 缓存、PackedByteArray 快速像素处理
##   - gdscript-patterns: 类型安全常量、材质工厂模式
##
## Architecture: agent/orchestrator.py → scene_spec.json → SceneBuilder → render.png
##
## @experimental: Modular components available in scripts/ directory
extends Node3D

# --- CCGS Modular Components (preload for future refactoring) ---
const ArtGeneratorScript := preload("res://scripts/art_generator.gd")
const MaterialFactoryScript := preload("res://scripts/material_factory.gd")

const SCENE_SPEC_PATH := "res://shared/scene_spec.json"
const RENDER_PATH := "res://shared/render.png"
const WALL_THICKNESS := 0.2
const ROOM_SPACING := 4.0
const BOOTH_SIZE := Vector3(1.5, 1.5, 1.5)
const CAMERA_SPEED := 7.0
const MOUSE_SENSITIVITY := 0.002
const WATCH_INTERVAL_SECONDS := 1.0
const CAMERA_EYE_HEIGHT := 1.6
const CAMERA_BACK_OFFSET_RATIO := 0.42
const OMNI_RANGE_PADDING := 1.5
const OMNI_ENERGY_MULTIPLIER := 0.01
const ENV_AMBIENT_ENERGY := 0.45
const ENV_FOG_DENSITY := 0.018
const ENV_FOG_LIGHT_ENERGY := 0.35
const ENV_GLOW_INTENSITY := 0.38
const ENV_GLOW_STRENGTH := 0.55
const VOLUMETRIC_FOG_DENSITY := 0.04
const VOLUMETRIC_FOG_LENGTH := 48.0
const DUST_PARTICLE_COUNT := 50
const FLOATING_ORB_COUNT := 20
const BOOTH_BASE_SIZE := Vector3(1.4, 0.35, 1.0)
const ART_FRAME_SIZE := Vector3(1.25, 1.55, 0.08)
const ART_FRAME_LIFT := 0.12
const FLOOR_METALLIC := 0.30
const FLOOR_ROUGHNESS := 0.35
const WALL_STRIP_THICKNESS := 0.04
const WALL_STRIP_HEIGHT := 0.06
const WALL_STRIP_Y_RATIO := 0.78
const WALL_STRIP_EMISSION_MULTIPLIER := 2.2
const SCREENSHOT_SCRIPT := preload("res://screenshot.gd")
const FRAME_BORDER := 0.06
const FRAME_DEPTH := 0.12
const ART_TEXTURE_SIZE := Vector2i(256, 320)

var generation_root: Node3D
var screenshotter: Node
var loading_label: Label3D
var watch_timer: Timer
var camera: Camera3D
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var last_scene_spec_mtime: int = 0
var primary_room_center: Vector3 = Vector3.ZERO
var primary_room_dimensions: Vector3 = Vector3(8.0, 4.0, 10.0)

# Material caches — avoid creating duplicate NoiseTexture2D per rebuild
var _material_cache: Dictionary = {}
var _floor_material_cache: Dictionary = {}
var _emission_material_cache: Dictionary = {}

## CCGS modular component instances
var _art_generator: RefCounted  ## ArtGenerator from scripts/art_generator.gd
var _mat_factory: RefCounted    ## MaterialFactory from scripts/material_factory.gd


func _ready() -> void:
	# Initialize CCGS modular components
	_art_generator = ArtGeneratorScript.new()
	_mat_factory = MaterialFactoryScript.new()

	_setup_screenshotter()
	_setup_watch_timer()
	last_scene_spec_mtime = _get_scene_spec_mtime()
	_rebuild_from_scene_spec()


## Handle WASD camera movement each frame.
func _process(delta: float) -> void:
	if camera == null:
		return

	var direction: Vector3 = Vector3.ZERO
	var basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x

	if Input.is_key_pressed(KEY_W):
		direction += forward
	if Input.is_key_pressed(KEY_S):
		direction -= forward
	if Input.is_key_pressed(KEY_A):
		direction -= right
	if Input.is_key_pressed(KEY_D):
		direction += right

	direction.y = 0.0
	if direction.length() > 0.0:
		camera.global_position += direction.normalized() * CAMERA_SPEED * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.4)
		if camera != null:
			camera.rotation = Vector3(camera_pitch, camera_yaw, 0.0)


func _setup_screenshotter() -> void:
	screenshotter = SCREENSHOT_SCRIPT.new()
	screenshotter.name = "Screenshotter"
	screenshotter.set("capture_on_ready", false)
	add_child(screenshotter)


func _setup_watch_timer() -> void:
	watch_timer = Timer.new()
	watch_timer.name = "SceneSpecWatchTimer"
	watch_timer.wait_time = WATCH_INTERVAL_SECONDS
	watch_timer.one_shot = false
	watch_timer.autostart = true
	watch_timer.timeout.connect(_on_watch_timer_timeout)
	add_child(watch_timer)


func _on_watch_timer_timeout() -> void:
	var current_mtime: int = _get_scene_spec_mtime()
	if current_mtime == 0 or current_mtime == last_scene_spec_mtime:
		return

	last_scene_spec_mtime = current_mtime
	_rebuild_from_scene_spec()


## Rebuild the entire 3D scene from the current scene_spec.json.
## Clears previous scene, builds environment, rooms, booths, lights,
## then takes a screenshot for the agent's vision evaluation.
func _rebuild_from_scene_spec() -> void:
	var scene_spec: Dictionary = _load_scene_spec()
	if scene_spec.is_empty():
		push_error("Scene specification is empty or could not be loaded: %s" % SCENE_SPEC_PATH)
		return

	_clear_generated_scene()
	_show_loading_label()
	_build_environment(scene_spec)
	var palette: Array = scene_spec.get("global_color_palette", []) as Array
	_build_rooms(scene_spec.get("rooms", []) as Array, palette)
	_build_booths(scene_spec.get("booths", []) as Array, palette)
	_build_lights(scene_spec.get("lights", []) as Array)
	_finalize_scene()
	_add_first_person_camera()
	_hide_loading_label()
	_take_screenshot()


func _clear_generated_scene() -> void:
	if generation_root == null:
		generation_root = Node3D.new()
		generation_root.name = "GeneratedScene"
		add_child(generation_root)
	else:
		for child in generation_root.get_children():
			child.queue_free()

	camera = null
	camera_yaw = 0.0
	camera_pitch = 0.0
	primary_room_center = Vector3.ZERO
	primary_room_dimensions = Vector3(8.0, 4.0, 10.0)
	_material_cache.clear()
	_floor_material_cache.clear()
	_emission_material_cache.clear()


func _show_loading_label() -> void:
	if loading_label == null:
		loading_label = Label3D.new()
		loading_label.name = "LoadingLabel"
		loading_label.text = "🤖 GLM-5.1 Agent 正在构建世界..."
		loading_label.font_size = 28
		loading_label.modulate = Color(0.0, 0.83, 0.67)
		loading_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		loading_label.outline_modulate = Color(0.0, 0.0, 0.0)
		loading_label.outline_size = 8
		add_child(loading_label)
	loading_label.position = primary_room_center + Vector3(0.0, CAMERA_EYE_HEIGHT + 0.5, -primary_room_dimensions.z * CAMERA_BACK_OFFSET_RATIO + 2.0)
	loading_label.visible = true


func _hide_loading_label() -> void:
	if loading_label != null:
		loading_label.visible = false


func _take_screenshot() -> void:
	if screenshotter != null and screenshotter.has_method("capture_after_frame"):
		screenshotter.call("capture_after_frame", RENDER_PATH)


func _get_scene_spec_mtime() -> int:
	if not FileAccess.file_exists(SCENE_SPEC_PATH):
		return 0

	return FileAccess.get_modified_time(SCENE_SPEC_PATH)


func _load_scene_spec() -> Dictionary:
	if not FileAccess.file_exists(SCENE_SPEC_PATH):
		push_error("Missing scene specification: %s" % SCENE_SPEC_PATH)
		return {}

	var file: FileAccess = FileAccess.open(SCENE_SPEC_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open scene specification: %s" % SCENE_SPEC_PATH)
		return {}

	var json_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Scene specification must be a JSON object.")
		return {}

	return parsed as Dictionary


# ================================================================
# Environment + Rendering
# ================================================================

## Build the world environment: sky, fog, glow, SSR, SSAO, SSIL, SDFGI, volumetric fog.
## Uses the global_color_palette to theme the atmosphere.
func _build_environment(scene_spec: Dictionary) -> void:
	var palette: Array = scene_spec.get("global_color_palette", []) as Array
	var sky_color: Color = _palette_color(palette, 0, Color(0.02, 0.03, 0.06))

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_color.lerp(Color.BLACK, 0.35)
	sky_material.sky_horizon_color = sky_color.lerp(Color.WHITE, 0.10)
	sky_material.ground_bottom_color = sky_color.lerp(Color.BLACK, 0.55)
	sky_material.ground_horizon_color = sky_color.lerp(Color.BLACK, 0.25)
	sky_material.sky_energy_multiplier = 0.55
	sky_material.ground_energy_multiplier = 0.25

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.6
	environment.ambient_light_color = sky_color.lerp(Color.WHITE, 0.35)
	environment.ambient_light_energy = ENV_AMBIENT_ENERGY
	environment.fog_enabled = true
	environment.fog_light_color = sky_color.lerp(Color.WHITE, 0.25)
	environment.fog_light_energy = ENV_FOG_LIGHT_ENERGY
	environment.fog_density = ENV_FOG_DENSITY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.2

	# Glow — boosted for cyberpunk sci-fi bloom
	environment.glow_enabled = true
	environment.glow_intensity = ENV_GLOW_INTENSITY
	environment.glow_strength = ENV_GLOW_STRENGTH
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 0.8
	environment.glow_hdr_scale = 1.5
	environment.glow_map = _make_glow_gradient(sky_color)

	# Screen-space reflections (4.6 quality upgrade applies automatically)
	environment.ssr_enabled = true
	environment.ssr_max_steps = 64
	environment.ssr_fade_in = 0.5
	environment.ssr_fade_out = 4.0

	# Screen-space ambient occlusion
	environment.ssao_enabled = true
	environment.ssao_radius = 2.0
	environment.ssao_intensity = 1.5
	environment.ssao_power = 1.5
	environment.ssao_detail = 0.5
	environment.ssao_horizon = 0.4
	environment.ssao_sharpness = 0.98

	# Screen-space indirect lighting for realistic light bounce
	environment.ssil_enabled = true
	environment.ssil_radius = 3.0
	environment.ssil_intensity = 1.2
	environment.ssil_sharpness = 0.8
	environment.ssil_normal_rejection = 0.3

	# Volumetric fog for atmospheric depth
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = VOLUMETRIC_FOG_DENSITY
	environment.volumetric_fog_albedo = sky_color.lerp(Color.WHITE, 0.15)
	environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	environment.volumetric_fog_length = VOLUMETRIC_FOG_LENGTH
	environment.volumetric_fog_temporal_reprojection_enabled = true

	# SDFGI for global illumination
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_bounce_feedback = 0.5
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_probe_bias = 1.5

	# Adjustments for auto-exposure
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.05
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 1.05

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "GeneratedWorldEnvironment"
	world_environment.environment = environment
	generation_root.add_child(world_environment)


func _finalize_scene() -> void:
	# Reflection probe centered in the room
	var reflection_probe := ReflectionProbe.new()
	reflection_probe.name = "RoomReflectionProbe"
	reflection_probe.position = primary_room_center + Vector3(0.0, primary_room_dimensions.y * 0.5, 0.0)
	reflection_probe.size = primary_room_dimensions
	reflection_probe.intensity = 0.8
	reflection_probe.max_distance = max(primary_room_dimensions.x, primary_room_dimensions.z)
	reflection_probe.mesh_lod_threshold = 4.0
	reflection_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	generation_root.add_child(reflection_probe)

	# Second reflection probe near the entrance
	var entrance_probe := ReflectionProbe.new()
	entrance_probe.name = "EntranceReflectionProbe"
	entrance_probe.position = primary_room_center + Vector3(0.0, primary_room_dimensions.y * 0.5, primary_room_dimensions.z * 0.35)
	entrance_probe.size = Vector3(primary_room_dimensions.x * 0.5, primary_room_dimensions.y, primary_room_dimensions.z * 0.4)
	entrance_probe.intensity = 0.7
	entrance_probe.max_distance = max(primary_room_dimensions.x, primary_room_dimensions.z) * 0.5
	entrance_probe.mesh_lod_threshold = 4.0
	entrance_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	generation_root.add_child(entrance_probe)

	# Ambient floating dust particles
	_add_dust_particles()

	# Floating decorative orbs
	_add_floating_orbs()

	# Floor reflection planes in front of each booth
	_add_floor_reflection_planes()


# ================================================================
# Rooms
# ================================================================

## Build room geometry from spec: floor, ceiling, 4 walls, plus decorative elements
## (columns, baseboards, entrance frame, crown molding, chair rail, accent panels, niches).
func _build_rooms(rooms: Array, palette: Array) -> void:
	var next_room_x: float = 0.0

	for room in rooms:
		if typeof(room) != TYPE_DICTIONARY:
			continue

		var dimensions: Vector3 = _vector3_from_array(room.get("dimensions", [12.0, 5.0, 12.0]))
		var wall_color: Color = _color_from_hex(room.get("wall_color", "#FFFFFF"))
		var wall_material: StandardMaterial3D = _make_material(wall_color)
		var floor_color: Color = _palette_color(palette, 3, Color(0.12, 0.13, 0.15)).lerp(Color.BLACK, 0.25)
		var floor_material: StandardMaterial3D = _make_floor_material(floor_color)
		var room_origin: Vector3 = Vector3(next_room_x, 0.0, 0.0)
		var room_id: String = str(room.get("id", "room"))

		if next_room_x == 0.0:
			primary_room_center = room_origin
			primary_room_dimensions = dimensions

		var floor_position: Vector3 = room_origin + Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0)
		_add_box("floor_%s" % room_id, floor_position, Vector3(dimensions.x, WALL_THICKNESS, dimensions.z), floor_material)

		var ceiling_position: Vector3 = room_origin + Vector3(0.0, dimensions.y + WALL_THICKNESS * 0.5, 0.0)
		_add_box("ceiling_%s" % room_id, ceiling_position, Vector3(dimensions.x, WALL_THICKNESS, dimensions.z), wall_material)

		var back_wall_position: Vector3 = room_origin + Vector3(0.0, dimensions.y * 0.5, -dimensions.z * 0.5 - WALL_THICKNESS * 0.5)
		_add_box("back_wall_%s" % room_id, back_wall_position, Vector3(dimensions.x + WALL_THICKNESS * 2.0, dimensions.y, WALL_THICKNESS), wall_material)

		var front_wall_position: Vector3 = room_origin + Vector3(0.0, dimensions.y * 0.5, dimensions.z * 0.5 + WALL_THICKNESS * 0.5)
		_add_box("front_wall_%s" % room_id, front_wall_position, Vector3(dimensions.x + WALL_THICKNESS * 2.0, dimensions.y, WALL_THICKNESS), wall_material)

		var left_wall_position: Vector3 = room_origin + Vector3(-dimensions.x * 0.5 - WALL_THICKNESS * 0.5, dimensions.y * 0.5, 0.0)
		_add_box("left_wall_%s" % room_id, left_wall_position, Vector3(dimensions.z, dimensions.y, WALL_THICKNESS), wall_material, Vector3(0.0, PI * 0.5, 0.0))

		var right_wall_position: Vector3 = room_origin + Vector3(dimensions.x * 0.5 + WALL_THICKNESS * 0.5, dimensions.y * 0.5, 0.0)
		_add_box("right_wall_%s" % room_id, right_wall_position, Vector3(dimensions.z, dimensions.y, WALL_THICKNESS), wall_material, Vector3(0.0, PI * 0.5, 0.0))

		_add_wall_light_strips(room_origin, dimensions, palette, room_id)
		_add_room_columns(room_origin, dimensions, palette, room_id)
		_add_baseboard_trim(room_origin, dimensions, palette, room_id)
		_add_entrance_frame(room_origin, dimensions, palette, room_id)
		_add_crown_molding(room_origin, dimensions, palette, room_id)
		_add_chair_rail(room_origin, dimensions, palette, room_id)
		_add_wall_accent_panels(room_origin, dimensions, palette, room_id)
		_add_back_wall_niches(room_origin, dimensions, palette, room_id)
		_add_ceiling_details(room_origin, dimensions, palette, room_id)

		next_room_x += dimensions.x + ROOM_SPACING


func _add_wall_light_strips(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var strip_color: Color = _palette_color(palette, 2, Color(0.95, 0.72, 0.38))
	var strip_material: StandardMaterial3D = _make_emission_material(strip_color, WALL_STRIP_EMISSION_MULTIPLIER)
	var strip_y: float = dimensions.y * WALL_STRIP_Y_RATIO
	var inset: float = 0.012

	var back_position: Vector3 = room_origin + Vector3(0.0, strip_y, -dimensions.z * 0.5 + inset)
	_add_box("wall_strip_back_%s" % room_id, back_position, Vector3(dimensions.x * 0.86, WALL_STRIP_HEIGHT, WALL_STRIP_THICKNESS), strip_material)

	var front_position: Vector3 = room_origin + Vector3(0.0, strip_y, dimensions.z * 0.5 - inset)
	_add_box("wall_strip_front_%s" % room_id, front_position, Vector3(dimensions.x * 0.86, WALL_STRIP_HEIGHT, WALL_STRIP_THICKNESS), strip_material)

	var left_position: Vector3 = room_origin + Vector3(-dimensions.x * 0.5 + inset, strip_y, 0.0)
	_add_box("wall_strip_left_%s" % room_id, left_position, Vector3(dimensions.z * 0.86, WALL_STRIP_HEIGHT, WALL_STRIP_THICKNESS), strip_material, Vector3(0.0, PI * 0.5, 0.0))

	var right_position: Vector3 = room_origin + Vector3(dimensions.x * 0.5 - inset, strip_y, 0.0)
	_add_box("wall_strip_right_%s" % room_id, right_position, Vector3(dimensions.z * 0.86, WALL_STRIP_HEIGHT, WALL_STRIP_THICKNESS), strip_material, Vector3(0.0, PI * 0.5, 0.0))


func _add_room_columns(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var column_material := StandardMaterial3D.new()
	column_material.albedo_color = Color(0.12, 0.12, 0.14)
	column_material.metallic = 0.5
	column_material.roughness = 0.35
	column_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = _palette_color(palette, 2, Color(0.7, 0.7, 0.7))
	cap_material.metallic = 0.7
	cap_material.roughness = 0.25
	cap_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var column_radius: float = 0.15
	var column_height: float = dimensions.y
	var col_offset: float = 0.5  # inset from corner

	var positions: Array[Vector3] = [
		room_origin + Vector3(-dimensions.x * 0.5 + col_offset, 0.0, -dimensions.z * 0.5 + col_offset),
		room_origin + Vector3(dimensions.x * 0.5 - col_offset, 0.0, -dimensions.z * 0.5 + col_offset),
		room_origin + Vector3(-dimensions.x * 0.5 + col_offset, 0.0, dimensions.z * 0.5 - col_offset),
		room_origin + Vector3(dimensions.x * 0.5 - col_offset, 0.0, dimensions.z * 0.5 - col_offset),
	]

	# Add mid-wall columns on long walls
	if dimensions.x > 12.0:
		positions.append(room_origin + Vector3(0.0, 0.0, -dimensions.z * 0.5 + col_offset))
		positions.append(room_origin + Vector3(0.0, 0.0, dimensions.z * 0.5 - col_offset))

	for i in range(positions.size()):
		var pos: Vector3 = positions[i]
		# Column shaft
		_add_cylinder("column_%s_%d" % [room_id, i],
			pos + Vector3(0.0, column_height * 0.5, 0.0),
			column_radius, column_height, column_material)
		# Base cap
		_add_cylinder("column_base_%s_%d" % [room_id, i],
			pos + Vector3(0.0, 0.06, 0.0),
			column_radius + 0.06, 0.12, cap_material)
		# Top cap
		_add_cylinder("column_cap_%s_%d" % [room_id, i],
			pos + Vector3(0.0, column_height - 0.06, 0.0),
			column_radius + 0.06, 0.12, cap_material)


func _add_baseboard_trim(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var trim_material := StandardMaterial3D.new()
	trim_material.albedo_color = Color(0.08, 0.08, 0.10)
	trim_material.metallic = 0.3
	trim_material.roughness = 0.5
	trim_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var trim_height: float = 0.15
	var trim_depth: float = 0.05
	var trim_y: float = trim_height * 0.5
	var inset: float = 0.012

	# Back wall
	_add_box("baseboard_back_%s" % room_id,
		room_origin + Vector3(0.0, trim_y, -dimensions.z * 0.5 + inset),
		Vector3(dimensions.x, trim_height, trim_depth), trim_material)
	# Front wall
	_add_box("baseboard_front_%s" % room_id,
		room_origin + Vector3(0.0, trim_y, dimensions.z * 0.5 - inset),
		Vector3(dimensions.x, trim_height, trim_depth), trim_material)
	# Left wall
	_add_box("baseboard_left_%s" % room_id,
		room_origin + Vector3(-dimensions.x * 0.5 + inset, trim_y, 0.0),
		Vector3(dimensions.z, trim_height, trim_depth), trim_material, Vector3(0.0, PI * 0.5, 0.0))
	# Right wall
	_add_box("baseboard_right_%s" % room_id,
		room_origin + Vector3(dimensions.x * 0.5 - inset, trim_y, 0.0),
		Vector3(dimensions.z, trim_height, trim_depth), trim_material, Vector3(0.0, PI * 0.5, 0.0))


func _add_entrance_frame(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var accent_color: Color = _palette_color(palette, 1, Color(1.0, 0.85, 0.3))
	var frame_mat := _make_emission_material(accent_color, 2.0)

	var front_z: float = dimensions.z * 0.5 - 0.02
	var arch_w: float = 3.2
	var arch_h: float = dimensions.y * 0.78
	var bar_thickness: float = 0.14

	# Top bar (thicker)
	_add_box("entrance_top_%s" % room_id,
		room_origin + Vector3(0.0, arch_h, front_z),
		Vector3(arch_w, bar_thickness, bar_thickness * 1.2), frame_mat)
	# Left pillar (thicker)
	_add_box("entrance_left_%s" % room_id,
		room_origin + Vector3(-arch_w * 0.5, arch_h * 0.5, front_z),
		Vector3(bar_thickness, arch_h, bar_thickness * 1.2), frame_mat)
	# Right pillar (thicker)
	_add_box("entrance_right_%s" % room_id,
		room_origin + Vector3(arch_w * 0.5, arch_h * 0.5, front_z),
		Vector3(bar_thickness, arch_h, bar_thickness * 1.2), frame_mat)

	# Archway decorative trim — horizontal accent band at spring line
	var trim_mat := _make_emission_material(accent_color.lerp(Color.WHITE, 0.3), 1.0)
	_add_box("entrance_trim_%s" % room_id,
		room_origin + Vector3(0.0, arch_h - bar_thickness, front_z),
		Vector3(arch_w + 0.2, 0.04, 0.18), trim_mat)


# ================================================================
# Booths — premium holographic gallery with procedural NFT art
# ================================================================

## Build NFT exhibition booths with pedestal, holographic art display, frame,
## glow strips, spot lighting, labels, and floor glow decorations.
func _build_booths(booths: Array, palette: Array) -> void:
	var base_material: StandardMaterial3D = _make_material(Color(0.08, 0.09, 0.11))

	# Pedestal top material — darker, more metallic beveled cap
	var pedestal_top_material := StandardMaterial3D.new()
	pedestal_top_material.albedo_color = Color(0.05, 0.06, 0.08)
	pedestal_top_material.metallic = 0.75
	pedestal_top_material.roughness = 0.2
	pedestal_top_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Frame material — dark chrome with slight blue tint
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.08, 0.09, 0.14)
	frame_material.metallic = 0.85
	frame_material.roughness = 0.15
	frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Pedestal skirt material
	var skirt_material := StandardMaterial3D.new()
	skirt_material.albedo_color = Color(0.04, 0.04, 0.06)
	skirt_material.metallic = 0.4
	skirt_material.roughness = 0.6
	skirt_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	for booth_index in range(booths.size()):
		var booth: Variant = booths[booth_index]
		if typeof(booth) != TYPE_DICTIONARY:
			continue

		var booth_dict: Dictionary = booth as Dictionary
		var position: Vector3 = _vector3_from_array(booth_dict.get("position", [0.0, 0.0, 0.0]))
		var half_booth: Vector3 = BOOTH_SIZE * 0.5
		position.x = clamp(position.x, primary_room_center.x - primary_room_dimensions.x * 0.5 + half_booth.x, primary_room_center.x + primary_room_dimensions.x * 0.5 - half_booth.x)
		position.z = clamp(position.z, primary_room_center.z - primary_room_dimensions.z * 0.5 + half_booth.z, primary_room_center.z + primary_room_dimensions.z * 0.5 - half_booth.z)
		position.y = 0.0

		var booth_root: Node3D = Node3D.new()
		booth_root.name = "booth_%s" % booth_dict.get("id", "unnamed")
		booth_root.position = position
		booth_root.rotation.y = deg_to_rad(float(booth_dict.get("orientation", 0.0)))
		generation_root.add_child(booth_root)

		# --- NFT art parameters ---
		var nft_data: Dictionary = booth_dict.get("nft", {})
		var art_style: String = nft_data.get("art_style", "gradient_noise")
		var art_seed: int = int(nft_data.get("art_seed", booth_index * 137 + 42))
		var art_colors_raw: Array = nft_data.get("art_colors", [])
		var art_colors: Array = []
		if art_colors_raw.is_empty():
			for ci in range(3):
				art_colors.append(_palette_color(palette, booth_index + ci + 1, Color(0.8, 0.55, 0.25)))
		else:
			for raw_color in art_colors_raw:
				if typeof(raw_color) == TYPE_STRING:
					art_colors.append(_color_from_hex(raw_color))
				else:
					art_colors.append(Color.WHITE)

		# Accent color derived from first art color
		var accent_color: Color = art_colors[0] if not art_colors.is_empty() else Color(0.3, 0.6, 1.0)
		var glow_ring_material: StandardMaterial3D = _make_emission_material(accent_color, 3.0)

		# === PEDESTAL ===
		_add_booth_pedestal(booth_root, base_material, pedestal_top_material, skirt_material, glow_ring_material, accent_color)

		# === ART DISPLAY ===
		# Priority 1: Load pre-generated PNG from shared/art/ (by booth_id)
		# Priority 2: Fallback to procedural generation
		var booth_id_for_art: String = booth_dict.get("id", "")
		var art_texture: ImageTexture = _load_art_image(booth_id_for_art)
		if art_texture == null:
			push_warning("[ArtLoader] File not found for booth '%s', trying procedural..." % booth_id_for_art)
			art_texture = _generate_art_texture(art_style, art_seed, art_colors, ART_TEXTURE_SIZE)
		if art_texture != null:
			push_warning("[ArtLoader] SUCCESS: texture loaded for booth '%s' (%dx%d)" % [booth_id_for_art, art_texture.get_width(), art_texture.get_height()])
		else:
			push_error("[ArtLoader] FAILED: no texture for booth '%s'" % booth_id_for_art)

		# Art material with increased emission for vivid holographic display
		var art_material := StandardMaterial3D.new()
		art_material.albedo_texture = art_texture
		art_material.emission_enabled = true
		art_material.emission = Color.WHITE
		art_material.emission_energy_multiplier = 0.8
		art_material.emission_texture = art_texture
		art_material.roughness = 0.4
		art_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		var art_z: float = -BOOTH_BASE_SIZE.z * 0.35
		var frame_z: float = art_z + 0.02
		var art_y_center: float = BOOTH_BASE_SIZE.y + ART_FRAME_LIFT + ART_FRAME_SIZE.y * 0.5
		var frame_w: float = ART_FRAME_SIZE.x + FRAME_BORDER * 2.0
		var frame_h: float = ART_FRAME_SIZE.y + FRAME_BORDER * 2.0

		# Art panel (recessed)
		_add_box_to_parent(booth_root, "art_panel",
			Vector3(0.0, art_y_center, art_z),
			ART_FRAME_SIZE, art_material)

		# === HOLOGRAPHIC SHIMMER PLANE ===
		_add_holographic_shimmer(booth_root, art_y_center, art_z, accent_color)

		# === FRAME ===
		_add_booth_frame(booth_root, art_y_center, frame_z, frame_w, frame_h, frame_material, accent_color)

		# === LIGHTING ===
		_add_booth_lighting(booth_root, art_y_center, art_z, accent_color)

		# === LABELS & INFO ===
		_add_booth_labels(booth_root, nft_data, art_z)

		# === DECORATIVE ELEMENTS ===
		_add_booth_decorations(booth_root, accent_color)


# ------------------------------------------------------------------
# Booth helper: pedestal with glow ring, beveled top, inner glow, skirt
# ------------------------------------------------------------------

func _add_booth_pedestal(
	booth_root: Node3D,
	base_material: StandardMaterial3D,
	top_material: StandardMaterial3D,
	skirt_material: StandardMaterial3D,
	glow_ring_material: StandardMaterial3D,
	accent_color: Color
) -> void:
	# Pedestal skirt — slightly larger, very thin dark box under the pedestal
	var skirt_size := Vector3(BOOTH_BASE_SIZE.x + 0.12, 0.02, BOOTH_BASE_SIZE.z + 0.12)
	_add_box_to_parent(booth_root, "pedestal_skirt",
		Vector3(0.0, skirt_size.y * 0.5, 0.0),
		skirt_size, skirt_material)

	# Pedestal main body
	var base_position: Vector3 = Vector3(0.0, BOOTH_BASE_SIZE.y * 0.5, 0.0)
	_add_box_to_parent(booth_root, "base", base_position, BOOTH_BASE_SIZE, base_material)

	# Beveled top — slightly wider, thinner metallic cap
	var top_size := Vector3(BOOTH_BASE_SIZE.x + 0.06, 0.025, BOOTH_BASE_SIZE.z + 0.06)
	_add_box_to_parent(booth_root, "pedestal_top",
		Vector3(0.0, BOOTH_BASE_SIZE.y + top_size.y * 0.5, 0.0),
		top_size, top_material)

	# Glow ring around pedestal base — torus with emissive accent color
	var glow_torus_mesh := TorusMesh.new()
	glow_torus_mesh.inner_radius = BOOTH_BASE_SIZE.x * 0.55 - 0.015
	glow_torus_mesh.outer_radius = BOOTH_BASE_SIZE.x * 0.55 + 0.015

	var glow_ring := MeshInstance3D.new()
	glow_ring.name = "pedestal_glow_ring"
	glow_ring.mesh = glow_torus_mesh
	glow_ring.position = Vector3(0.0, 0.025, 0.0)
	glow_ring.set_surface_override_material(0, glow_ring_material)
	booth_root.add_child(glow_ring)

	# Pedestal inner glow — small OmniLight3D inside, pointing up
	var inner_glow := OmniLight3D.new()
	inner_glow.name = "PedestalInnerGlow"
	inner_glow.position = Vector3(0.0, BOOTH_BASE_SIZE.y * 0.6, 0.0)
	inner_glow.light_color = accent_color
	inner_glow.light_energy = 0.5
	inner_glow.omni_range = 1.0
	booth_root.add_child(inner_glow)


# ------------------------------------------------------------------
# Booth helper: beveled frame with glow strip (holographic display)
# ------------------------------------------------------------------

func _add_booth_frame(
	booth_root: Node3D,
	art_y_center: float,
	frame_z: float,
	frame_w: float,
	frame_h: float,
	frame_material: StandardMaterial3D,
	accent_color: Color
) -> void:
	# Frame — top bar
	_add_box_to_parent(booth_root, "frame_top",
		Vector3(0.0, art_y_center + ART_FRAME_SIZE.y * 0.5 + FRAME_BORDER * 0.5, frame_z),
		Vector3(frame_w, FRAME_BORDER, FRAME_DEPTH), frame_material)

	# Frame — bottom bar
	_add_box_to_parent(booth_root, "frame_bottom",
		Vector3(0.0, art_y_center - ART_FRAME_SIZE.y * 0.5 - FRAME_BORDER * 0.5, frame_z),
		Vector3(frame_w, FRAME_BORDER, FRAME_DEPTH), frame_material)

	# Frame — left bar
	_add_box_to_parent(booth_root, "frame_left",
		Vector3(-ART_FRAME_SIZE.x * 0.5 - FRAME_BORDER * 0.5, art_y_center, frame_z),
		Vector3(FRAME_BORDER, ART_FRAME_SIZE.y, FRAME_DEPTH), frame_material)

	# Frame — right bar
	_add_box_to_parent(booth_root, "frame_right",
		Vector3(ART_FRAME_SIZE.x * 0.5 + FRAME_BORDER * 0.5, art_y_center, frame_z),
		Vector3(FRAME_BORDER, ART_FRAME_SIZE.y, FRAME_DEPTH), frame_material)

	# Frame glow strip — thin emissive line along inside edge of frame (holographic look)
	var glow_strip_material: StandardMaterial3D = _make_emission_material(accent_color.lerp(Color.WHITE, 0.3), 2.5)
	var glow_strip_thickness: float = 0.008
	var glow_strip_z: float = frame_z - FRAME_DEPTH * 0.5 - glow_strip_thickness * 0.5

	# Top inner glow strip
	_add_box_to_parent(booth_root, "frame_glow_top",
		Vector3(0.0, art_y_center + ART_FRAME_SIZE.y * 0.5 + glow_strip_thickness * 0.5, glow_strip_z),
		Vector3(ART_FRAME_SIZE.x, glow_strip_thickness, glow_strip_thickness), glow_strip_material)
	# Bottom inner glow strip
	_add_box_to_parent(booth_root, "frame_glow_bottom",
		Vector3(0.0, art_y_center - ART_FRAME_SIZE.y * 0.5 - glow_strip_thickness * 0.5, glow_strip_z),
		Vector3(ART_FRAME_SIZE.x, glow_strip_thickness, glow_strip_thickness), glow_strip_material)
	# Left inner glow strip
	_add_box_to_parent(booth_root, "frame_glow_left",
		Vector3(-ART_FRAME_SIZE.x * 0.5 - glow_strip_thickness * 0.5, art_y_center, glow_strip_z),
		Vector3(glow_strip_thickness, ART_FRAME_SIZE.y, glow_strip_thickness), glow_strip_material)
	# Right inner glow strip
	_add_box_to_parent(booth_root, "frame_glow_right",
		Vector3(ART_FRAME_SIZE.x * 0.5 + glow_strip_thickness * 0.5, art_y_center, glow_strip_z),
		Vector3(glow_strip_thickness, ART_FRAME_SIZE.y, glow_strip_thickness), glow_strip_material)


# ------------------------------------------------------------------
# Booth helper: holographic shimmer plane with scan line effect
# ------------------------------------------------------------------

func _add_holographic_shimmer(
	booth_root: Node3D,
	art_y_center: float,
	art_z: float,
	accent_color: Color
) -> void:
	# Holographic glass plane — semi-transparent, slightly emissive
	var holo_material := StandardMaterial3D.new()
	holo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo_material.albedo_color = Color(accent_color.r * 0.3 + 0.1, accent_color.g * 0.3 + 0.1, accent_color.b * 0.3 + 0.2, 0.12)
	holo_material.metallic = 0.5
	holo_material.roughness = 0.1
	holo_material.emission_enabled = true
	holo_material.emission = accent_color.lerp(Color.WHITE, 0.5)
	holo_material.emission_energy_multiplier = 0.3
	holo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Scan line procedural texture
	var scan_line_image := Image.create(ART_TEXTURE_SIZE.x, ART_TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	scan_line_image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var scan_spacing: int = 4
	var scan_alpha: float = 0.06
	for y in range(0, ART_TEXTURE_SIZE.y, scan_spacing):
		for x in range(ART_TEXTURE_SIZE.x):
			scan_line_image.set_pixel(x, y, Color(1.0, 1.0, 1.0, scan_alpha))
	var scan_texture := ImageTexture.create_from_image(scan_line_image)
	holo_material.albedo_texture = scan_texture

	var holo_z: float = art_z + 0.04  # Slightly in front of the art
	_add_box_to_parent(booth_root, "holographic_shimmer",
		Vector3(0.0, art_y_center, holo_z),
		Vector3(ART_FRAME_SIZE.x, ART_FRAME_SIZE.y, 0.003), holo_material)


# ------------------------------------------------------------------
# Booth helper: improved lighting (warmer spot, back light, side accents)
# ------------------------------------------------------------------

func _add_booth_lighting(
	booth_root: Node3D,
	art_y_center: float,
	art_z: float,
	accent_color: Color
) -> void:
	# Primary spot light — warmer color for gallery feel, better angle attenuation
	var spot_light := SpotLight3D.new()
	spot_light.name = "ArtSpotLight"
	spot_light.position = Vector3(0.0, art_y_center + ART_FRAME_SIZE.y * 0.5 + 0.6, 0.5)
	spot_light.rotation = Vector3(deg_to_rad(-55.0), 0.0, 0.0)
	# Warmer gallery light color
	var spot_color := Color(1.0, 0.95, 0.88)
	if accent_color != Color.BLACK:
		spot_color = accent_color.lerp(Color(1.0, 0.95, 0.88), 0.7)
	spot_light.light_color = spot_color
	spot_light.light_energy = 4.5
	spot_light.spot_range = 3.5
	spot_light.spot_angle = 40.0
	spot_light.spot_angle_attenuation = 2.0  # Sharper falloff at edge
	spot_light.shadow_enabled = true
	booth_root.add_child(spot_light)

	# Back light — dimmer, behind the art for depth
	var back_light := SpotLight3D.new()
	back_light.name = "ArtBackLight"
	back_light.position = Vector3(0.0, art_y_center, art_z - 0.4)
	back_light.rotation = Vector3(deg_to_rad(10.0), 0.0, 0.0)
	back_light.light_color = accent_color.lerp(Color.WHITE, 0.5)
	back_light.light_energy = 1.2
	back_light.spot_range = 2.0
	back_light.spot_angle = 60.0
	back_light.spot_angle_attenuation = 1.8
	booth_root.add_child(back_light)

	# Side accent lights — two small PointLight3D nodes for edge lighting
	var side_y: float = art_y_center
	var side_x: float = ART_FRAME_SIZE.x * 0.5 + FRAME_BORDER + 0.15
	var side_z: float = art_z + 0.1
	var side_color: Color = accent_color.lerp(Color.WHITE, 0.35)

	var left_side := OmniLight3D.new()
	left_side.name = "SideLightLeft"
	left_side.position = Vector3(-side_x, side_y, side_z)
	left_side.light_color = side_color
	left_side.light_energy = 0.6
	left_side.omni_range = 1.2
	booth_root.add_child(left_side)

	var right_side := OmniLight3D.new()
	right_side.name = "SideLightRight"
	right_side.position = Vector3(side_x, side_y, side_z)
	right_side.light_color = side_color
	right_side.light_energy = 0.6
	right_side.omni_range = 1.2
	booth_root.add_child(right_side)


# ------------------------------------------------------------------
# Booth helper: enhanced NFT labels (name, collection, token ID badge)
# ------------------------------------------------------------------

func _add_booth_labels(
	booth_root: Node3D,
	nft_data: Dictionary,
	art_z: float
) -> void:
	var nft_name: String = nft_data.get("name", "")
	if nft_name.is_empty():
		return

	# NFT name label — larger and brighter
	var label := Label3D.new()
	label.name = "NFTLabel"
	label.text = nft_name
	label.position = Vector3(0.0, BOOTH_BASE_SIZE.y + ART_FRAME_LIFT - 0.2, art_z + 0.05)
	label.font_size = 18
	label.modulate = Color(0.95, 0.95, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	booth_root.add_child(label)

	# Collection label — smaller, dimmer, below the NFT name
	var collection_name: String = nft_data.get("collection", "")
	if not collection_name.is_empty():
		var collection_label := Label3D.new()
		collection_label.name = "CollectionLabel"
		collection_label.text = collection_name
		collection_label.position = Vector3(0.0, BOOTH_BASE_SIZE.y + ART_FRAME_LIFT - 0.38, art_z + 0.05)
		collection_label.font_size = 11
		collection_label.modulate = Color(0.55, 0.55, 0.65)
		collection_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		booth_root.add_child(collection_label)

	# Token ID badge — small emissive rectangle below the collection label
	var token_id: String = nft_data.get("token_id", "")
	if token_id.is_empty():
		token_id = "#%04d" % (int(nft_data.get("art_seed", 42)) % 10000)
	else:
		token_id = "#" + token_id
	var badge_y: float = BOOTH_BASE_SIZE.y + ART_FRAME_LIFT - 0.55
	var badge_size := Vector3(0.28, 0.065, 0.008)

	var badge_material := StandardMaterial3D.new()
	badge_material.albedo_color = Color(0.04, 0.06, 0.10)
	badge_material.emission_enabled = true
	badge_material.emission = Color(0.15, 0.25, 0.5)
	badge_material.emission_energy_multiplier = 0.6
	badge_material.metallic = 0.7
	badge_material.roughness = 0.3
	badge_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_add_box_to_parent(booth_root, "token_id_badge",
		Vector3(0.0, badge_y, art_z + 0.04),
		badge_size, badge_material)

	var token_label := Label3D.new()
	token_label.name = "TokenIDLabel"
	token_label.text = token_id
	token_label.position = Vector3(0.0, badge_y, art_z + 0.05)
	token_label.font_size = 9
	token_label.modulate = Color(0.5, 0.7, 1.0)
	token_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	booth_root.add_child(token_label)


# ------------------------------------------------------------------
# Booth helper: decorative elements (base platform glow line)
# ------------------------------------------------------------------

func _add_booth_decorations(
	booth_root: Node3D,
	accent_color: Color
) -> void:
	# Base platform glow line — emissive rectangle on the floor in front of booth
	var glow_line_material: StandardMaterial3D = _make_emission_material(accent_color.lerp(Color.WHITE, 0.2), 1.8)
	var glow_line_thickness: float = 0.02
	var half_w: float = BOOTH_BASE_SIZE.x * 0.5 + 0.08
	var half_d: float = BOOTH_BASE_SIZE.z * 0.5 + 0.08

	# Front glow line (most visible from viewer approach)
	_add_box_to_parent(booth_root, "floor_glow_front",
		Vector3(0.0, 0.005, half_d),
		Vector3(half_w * 2.0, glow_line_thickness, glow_line_thickness), glow_line_material)


# ================================================================
# Lights — with fixture geometry
# ================================================================

func _build_lights(lights: Array) -> void:
	var light_count: int = max(lights.size(), 1)

	for light_index in range(lights.size()):
		var light_data: Variant = lights[light_index]
		if typeof(light_data) != TYPE_DICTIONARY:
			continue

		var light_dict: Dictionary = light_data as Dictionary
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "OmniLight3D"
		var source_position: Vector3 = _vector3_from_array(light_dict.get("position", [0.0, primary_room_dimensions.y - 0.5, 0.0]))
		var distribution_ratio: float = (float(light_index) + 1.0) / (float(light_count) + 1.0)
		var distributed_x: float = primary_room_center.x - primary_room_dimensions.x * 0.35 + primary_room_dimensions.x * 0.7 * distribution_ratio
		var light_y: float = clamp(source_position.y, 2.2, max(2.2, primary_room_dimensions.y - 0.35))
		light.position = Vector3(distributed_x, light_y, primary_room_center.z)
		light.light_color = _color_from_hex(light_dict.get("color", "#FFFFFF"))
		light.light_energy = clamp(float(light_dict.get("intensity", 1.0)) * OMNI_ENERGY_MULTIPLIER, 1.5, 8.0)
		light.omni_range = max(primary_room_dimensions.x, primary_room_dimensions.z) + OMNI_RANGE_PADDING
		generation_root.add_child(light)

		# Light fixture — larger emissive sphere
		var fixture_material := _make_emission_material(light.light_color, 3.5)
		_add_sphere("light_fixture_%d" % light_index, light.position, 0.22, fixture_material)

		# Fixture collar ring
		var collar_material := _make_metallic_material(Color(0.4, 0.4, 0.45))
		_add_torus("fixture_collar_%d" % light_index,
			light.position + Vector3(0.0, 0.12, 0.0),
			0.28, 0.03, collar_material)

		# Pendant rod connecting fixture to ceiling
		var pendant_material := _make_metallic_material(Color(0.3, 0.3, 0.35))
		var pendant_top: float = primary_room_dimensions.y
		var pendant_height: float = pendant_top - light_y
		if pendant_height > 0.1:
			_add_cylinder("light_pendant_%d" % light_index,
				Vector3(light.position.x, light_y + pendant_height * 0.5, light.position.z),
				0.025, pendant_height, pendant_material)

		# Recessed ceiling light panel above each fixture
		var panel_material := _make_emission_material(light.light_color.lerp(Color.WHITE, 0.3), 1.0)
		var panel_size := Vector3(1.2, 0.02, 1.2)
		_add_box("ceiling_panel_%d" % light_index,
			Vector3(light.position.x, primary_room_dimensions.y - 0.05, primary_room_center.z),
			panel_size, panel_material)

	# Central chandelier ring at ceiling height
	_add_chandelier_ring(lights)

	# Colored rim lights at wall bases
	_add_rim_lights(lights)

	# Corner fill lights to eliminate dark spots
	_add_corner_fill_lights()


# ================================================================
# Scene decoration helpers
# ================================================================

func _add_crown_molding(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var molding_material := _make_metallic_material(Color(0.15, 0.15, 0.18))
	var molding_height: float = 0.10
	var molding_depth: float = 0.08
	var molding_y: float = dimensions.y - molding_height * 0.5
	var inset: float = WALL_THICKNESS * 0.5 + molding_depth * 0.5

	# Back wall
	_add_box("crown_back_%s" % room_id,
		room_origin + Vector3(0.0, molding_y, -dimensions.z * 0.5 + inset),
		Vector3(dimensions.x, molding_height, molding_depth), molding_material)
	# Front wall
	_add_box("crown_front_%s" % room_id,
		room_origin + Vector3(0.0, molding_y, dimensions.z * 0.5 - inset),
		Vector3(dimensions.x, molding_height, molding_depth), molding_material)
	# Left wall
	_add_box("crown_left_%s" % room_id,
		room_origin + Vector3(-dimensions.x * 0.5 + inset, molding_y, 0.0),
		Vector3(molding_depth, molding_height, dimensions.z), molding_material)
	# Right wall
	_add_box("crown_right_%s" % room_id,
		room_origin + Vector3(dimensions.x * 0.5 - inset, molding_y, 0.0),
		Vector3(molding_depth, molding_height, dimensions.z), molding_material)


func _add_chair_rail(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var rail_material := _make_metallic_material(Color(0.18, 0.18, 0.22))
	var rail_height: float = 0.06
	var rail_depth: float = 0.04
	var rail_y: float = 1.0  # waist height
	var inset: float = WALL_THICKNESS * 0.5 + rail_depth * 0.5

	# Back wall
	_add_box("chair_rail_back_%s" % room_id,
		room_origin + Vector3(0.0, rail_y, -dimensions.z * 0.5 + inset),
		Vector3(dimensions.x, rail_height, rail_depth), rail_material)
	# Front wall
	_add_box("chair_rail_front_%s" % room_id,
		room_origin + Vector3(0.0, rail_y, dimensions.z * 0.5 - inset),
		Vector3(dimensions.x, rail_height, rail_depth), rail_material)
	# Left wall
	_add_box("chair_rail_left_%s" % room_id,
		room_origin + Vector3(-dimensions.x * 0.5 + inset, rail_y, 0.0),
		Vector3(rail_depth, rail_height, dimensions.z), rail_material)
	# Right wall
	_add_box("chair_rail_right_%s" % room_id,
		room_origin + Vector3(dimensions.x * 0.5 - inset, rail_y, 0.0),
		Vector3(rail_depth, rail_height, dimensions.z), rail_material)


func _add_wall_accent_panels(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var accent_color: Color = _palette_color(palette, 4, Color(0.15, 0.16, 0.20))
	var accent_material := _make_material(accent_color)

	var panel_height: float = dimensions.y * 0.35
	var panel_width: float = dimensions.x * 0.22
	var panel_thickness: float = 0.025
	var panel_y: float = dimensions.y * 0.45
	var wall_inset: float = WALL_THICKNESS + panel_thickness * 0.5

	# Two accent panels on back wall, symmetric
	for sign_x: float in [-0.3, 0.3]:
		_add_box("accent_panel_back_%s_%s" % [room_id, "l" if sign_x < 0 else "r"],
			room_origin + Vector3(dimensions.x * sign_x, panel_y, -dimensions.z * 0.5 + wall_inset),
			Vector3(panel_width, panel_height, panel_thickness), accent_material)

	# One accent panel on each side wall
	_add_box("accent_panel_left_%s" % room_id,
		room_origin + Vector3(-dimensions.x * 0.5 + wall_inset, panel_y, 0.0),
		Vector3(panel_thickness, panel_height, dimensions.z * 0.3), accent_material)
	_add_box("accent_panel_right_%s" % room_id,
		room_origin + Vector3(dimensions.x * 0.5 - wall_inset, panel_y, 0.0),
		Vector3(panel_thickness, panel_height, dimensions.z * 0.3), accent_material)


func _add_back_wall_niches(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var niche_material := _make_material(Color(0.06, 0.06, 0.08))
	var niche_width: float = 0.6
	var niche_height: float = 0.8
	var niche_depth: float = 0.15
	var niche_y: float = dimensions.y * 0.55

	# Three niches evenly spaced on back wall
	var niche_count: int = 3
	var spacing: float = dimensions.x * 0.7 / float(niche_count + 1)
	var wall_surface_z: float = -dimensions.z * 0.5 + WALL_THICKNESS * 0.5 - niche_depth * 0.5

	for i in range(niche_count):
		var niche_x: float = -dimensions.x * 0.35 + spacing * float(i + 1)
		_add_box("niche_back_%s_%d" % [room_id, i],
			room_origin + Vector3(niche_x, niche_y, wall_surface_z),
			Vector3(niche_width, niche_height, niche_depth), niche_material)

		# Small emissive accent light above each niche
		var accent_light_color: Color = _palette_color(palette, 2, Color(0.95, 0.72, 0.38))
		var niche_spot := SpotLight3D.new()
		niche_spot.name = "NicheLight_%s_%d" % [room_id, i]
		niche_spot.position = room_origin + Vector3(niche_x, niche_y + niche_height * 0.5 + 0.1, wall_surface_z + 0.5)
		niche_spot.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
		niche_spot.light_color = accent_light_color
		niche_spot.light_energy = 2.0
		niche_spot.spot_range = 2.0
		niche_spot.spot_angle = 35.0
		generation_root.add_child(niche_spot)


func _add_ceiling_details(room_origin: Vector3, dimensions: Vector3, palette: Array, room_id: String) -> void:
	var accent_color: Color = _palette_color(palette, 2, Color(0.95, 0.72, 0.38))
	var ceiling_y: float = dimensions.y

	# Ceiling medallion — torus ring centered in room
	var medallion_material := _make_metallic_material(Color(0.2, 0.2, 0.24))
	_add_torus("ceiling_medallion_%s" % room_id,
		room_origin + Vector3(0.0, ceiling_y - 0.05, 0.0),
		1.5, 0.08, medallion_material)

	# Inner ring of medallion with subtle emissive
	var medallion_emission := _make_emission_material(accent_color.lerp(Color.WHITE, 0.6), 0.5)
	_add_torus("ceiling_medallion_inner_%s" % room_id,
		room_origin + Vector3(0.0, ceiling_y - 0.04, 0.0),
		0.8, 0.04, medallion_emission)

	# Coffered ceiling grid lines — thin strips forming a pattern
	var grid_material := _make_metallic_material(Color(0.12, 0.12, 0.15))
	var strip_width: float = 0.06
	var strip_depth: float = 0.04
	var grid_divisions: int = 3
	var x_step: float = dimensions.x / float(grid_divisions + 1)
	var z_step: float = dimensions.z / float(grid_divisions + 1)

	# X-parallel strips
	for i in range(1, grid_divisions + 1):
		var strip_z: float = -dimensions.z * 0.5 + z_step * float(i)
		_add_box("ceiling_grid_x_%s_%d" % [room_id, i],
			room_origin + Vector3(0.0, ceiling_y - strip_depth * 0.5, strip_z),
			Vector3(dimensions.x, strip_depth, strip_width), grid_material)

	# Z-parallel strips
	for i in range(1, grid_divisions + 1):
		var strip_x: float = -dimensions.x * 0.5 + x_step * float(i)
		_add_box("ceiling_grid_z_%s_%d" % [room_id, i],
			room_origin + Vector3(strip_x, ceiling_y - strip_depth * 0.5, 0.0),
			Vector3(strip_width, strip_depth, dimensions.z), grid_material)


func _add_chandelier_ring(lights: Array) -> void:
	var chandelier_material := _make_emission_material(
		_palette_color([], 0, Color(1.0, 0.92, 0.8)),
		2.0
	)
	var chandelier_y: float = primary_room_dimensions.y - 0.3
	var chandelier_radius: float = min(primary_room_dimensions.x, primary_room_dimensions.z) * 0.18

	_add_torus("chandelier_ring",
		primary_room_center + Vector3(0.0, chandelier_y, 0.0),
		chandelier_radius, 0.04, chandelier_material)

	# Decorative hanging points on the ring — small emissive spheres
	var point_count: int = 8
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		var px: float = primary_room_center.x + cos(angle) * chandelier_radius
		var pz: float = primary_room_center.z + sin(angle) * chandelier_radius
		_add_sphere("chandelier_point_%d" % i,
			Vector3(px, chandelier_y - 0.12, pz),
			0.05, chandelier_material)


func _add_rim_lights(lights: Array) -> void:
	if lights.is_empty():
		return

	var rim_color: Color
	var first_light: Dictionary = lights[0] as Dictionary if typeof(lights[0]) == TYPE_DICTIONARY else {}
	if first_light.has("color"):
		rim_color = _color_from_hex(first_light.get("color", "#4488FF")).lerp(Color(0.2, 0.4, 1.0), 0.5)
	else:
		rim_color = Color(0.2, 0.4, 1.0)

	var rim_material := _make_emission_material(rim_color, 1.5)
	var rim_height: float = 0.04
	var rim_depth: float = 0.03
	var rim_y: float = 0.08
	var inset: float = WALL_THICKNESS * 0.5 + rim_depth * 0.5

	# Back wall base
	_add_box("rim_light_back",
		primary_room_center + Vector3(0.0, rim_y, -primary_room_dimensions.z * 0.5 + inset),
		Vector3(primary_room_dimensions.x * 0.95, rim_height, rim_depth), rim_material)
	# Front wall base
	_add_box("rim_light_front",
		primary_room_center + Vector3(0.0, rim_y, primary_room_dimensions.z * 0.5 - inset),
		Vector3(primary_room_dimensions.x * 0.95, rim_height, rim_depth), rim_material)
	# Left wall base
	_add_box("rim_light_left",
		primary_room_center + Vector3(-primary_room_dimensions.x * 0.5 + inset, rim_y, 0.0),
		Vector3(rim_depth, rim_height, primary_room_dimensions.z * 0.95), rim_material)
	# Right wall base
	_add_box("rim_light_right",
		primary_room_center + Vector3(primary_room_dimensions.x * 0.5 - inset, rim_y, 0.0),
		Vector3(rim_depth, rim_height, primary_room_dimensions.z * 0.95), rim_material)


func _add_corner_fill_lights() -> void:
	var fill_energy: float = 1.0
	var fill_range: float = max(primary_room_dimensions.x, primary_room_dimensions.z) * 0.5
	var fill_y: float = primary_room_dimensions.y * 0.7
	var half_x: float = primary_room_dimensions.x * 0.5 - 0.5
	var half_z: float = primary_room_dimensions.z * 0.5 - 0.5

	var corner_positions: Array[Vector3] = [
		primary_room_center + Vector3(-half_x, fill_y, -half_z),
		primary_room_center + Vector3(half_x, fill_y, -half_z),
		primary_room_center + Vector3(-half_x, fill_y, half_z),
		primary_room_center + Vector3(half_x, fill_y, half_z),
	]

	for i in range(corner_positions.size()):
		var fill_light := OmniLight3D.new()
		fill_light.name = "CornerFill_%d" % i
		fill_light.position = corner_positions[i]
		fill_light.light_color = Color(1.0, 0.97, 0.94)
		fill_light.light_energy = fill_energy
		fill_light.omni_range = fill_range
		generation_root.add_child(fill_light)


func _add_dust_particles() -> void:
	# Subtle ambient floating dust via GPUParticles3D
	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(
		primary_room_dimensions.x * 0.45,
		primary_room_dimensions.y * 0.45,
		primary_room_dimensions.z * 0.45
	)
	particle_material.direction = Vector3(0.0, 1.0, 0.0)
	particle_material.spread = 20.0
	particle_material.gravity = Vector3.ZERO
	particle_material.initial_velocity_min = 0.01
	particle_material.initial_velocity_max = 0.03
	particle_material.damping_min = 0.5
	particle_material.damping_max = 1.0
	particle_material.scale_min = 0.01
	particle_material.scale_max = 0.03

	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.02, 0.02)

	var particles := GPUParticles3D.new()
	particles.name = "DustParticles"
	particles.position = primary_room_center + Vector3(0.0, primary_room_dimensions.y * 0.5, 0.0)
	particles.amount = DUST_PARTICLE_COUNT
	particles.lifetime = 12.0
	particles.explosiveness = 0.0
	particles.randomness = 0.8
	particles.process_material = particle_material
	particles.draw_pass_1 = particle_mesh
	generation_root.add_child(particles)


func _add_floating_orbs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var orb_root := Node3D.new()
	orb_root.name = "FloatingOrbs"
	orb_root.position = primary_room_center
	generation_root.add_child(orb_root)

	var palette_colors: Array = [
		_palette_color([], 0, Color(0.3, 0.5, 1.0)),
		_palette_color([], 1, Color(1.0, 0.85, 0.3)),
		_palette_color([], 2, Color(0.95, 0.72, 0.38)),
		_palette_color([], 3, Color(0.1, 0.8, 0.6)),
	]

	for i in range(FLOATING_ORB_COUNT):
		var orb_color: Color = palette_colors[i % palette_colors.size()].lerp(Color.WHITE, 0.3)
		var orb_material := _make_emission_material(orb_color, 1.2)
		orb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		orb_material.albedo_color.a = 0.7

		var orb_x: float = rng.randf_range(-primary_room_dimensions.x * 0.4, primary_room_dimensions.x * 0.4)
		var orb_y: float = rng.randf_range(0.8, primary_room_dimensions.y * 0.85)
		var orb_z: float = rng.randf_range(-primary_room_dimensions.z * 0.4, primary_room_dimensions.z * 0.4)
		var orb_radius: float = rng.randf_range(0.03, 0.08)

		_add_sphere_to_parent(orb_root, "orb_%d" % i,
			Vector3(orb_x, orb_y, orb_z), orb_radius, orb_material)


func _add_floor_reflection_planes() -> void:
	# Find all booth nodes and place reflective quads in front of each
	var reflection_material := StandardMaterial3D.new()
	reflection_material.albedo_color = Color(0.05, 0.05, 0.06)
	reflection_material.metallic = 0.95
	reflection_material.roughness = 0.05
	reflection_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var booth_index: int = 0
	for child in generation_root.get_children():
		if child.name.begins_with("booth_") and child is Node3D:
			var booth_node: Node3D = child as Node3D
			var reflect_plane := MeshInstance3D.new()
			reflect_plane.name = "reflection_plane_%d" % booth_index
			var plane_mesh := QuadMesh.new()
			plane_mesh.size = Vector2(1.8, 1.2)
			reflect_plane.mesh = plane_mesh
			reflect_plane.position = booth_node.position + Vector3(0.0, 0.005, 0.8)
			reflect_plane.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			reflect_plane.set_surface_override_material(0, reflection_material)
			generation_root.add_child(reflect_plane)
			booth_index += 1


func _add_torus(node_name: String, position: Vector3, ring_radius: float, tube_radius: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ring_radius - tube_radius
	mesh.outer_radius = ring_radius + tube_radius

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	generation_root.add_child(instance)
	return instance


func _make_glow_gradient(base_color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(base_color.r, base_color.g, base_color.b, 0.0),
		Color(base_color.r * 1.5, base_color.g * 1.5, base_color.b * 1.5, 0.4),
		Color(base_color.r * 2.0, base_color.g * 2.0, base_color.b * 2.0, 1.0),
		Color.WHITE,
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])

	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	tex.width = 64
	return tex


func _add_quad_to_parent(parent: Node3D, node_name: String, position: Vector3, size: Vector2, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	parent.add_child(instance)
	return instance

## Load pre-generated NFT art image from shared/art/{booth_id}.png
## Returns null if file not found (fallback to procedural generation).
func _load_art_image(booth_id: String) -> ImageTexture:
	if booth_id.is_empty():
		push_warning("[ArtLoader] booth_id is empty")
		return null
	var art_path: String = "res://shared/art/" + booth_id + ".png"
	push_warning("[ArtLoader] Trying to load: " + art_path)
	if not FileAccess.file_exists(art_path):
		push_warning("[ArtLoader] File does not exist: " + art_path)
		return null
	var image := Image.load_from_file(art_path)
	if image == null:
		push_error("[ArtLoader] Image.load_from_file returned null for: " + art_path)
		return null
	push_warning("[ArtLoader] Loaded image: %dx%d" % [image.get_width(), image.get_height()])
	return ImageTexture.create_from_image(image)

func _generate_art_texture(art_style: String, seed_value: int, colors: Array, size: Vector2i) -> ImageTexture:
	var image: Image
	match art_style:
		"gradient_noise":
			image = _generate_gradient_noise_art(seed_value, colors, size)
		"voronoi":
			image = _generate_voronoi_art(seed_value, colors, size)
		"geometric":
			image = _generate_geometric_art(seed_value, colors, size)
		"plasma":
			image = _generate_plasma_art(seed_value, colors, size)
		"mandala":
			image = _generate_mandala_art(seed_value, colors, size)
		"pixel_art":
			image = _generate_pixel_art(seed_value, colors, size)
		"fractal":
			image = _generate_fractal_art(seed_value, colors, size)
		"nebula":
			image = _generate_nebula_art(seed_value, colors, size)
		"flow_field":
			image = _generate_flow_field_art(seed_value, colors, size)
		_:
			image = _generate_gradient_noise_art(seed_value, colors, size)
	_apply_art_post_processing(image, colors, seed_value)
	return ImageTexture.create_from_image(image)



	# ---------------------------------------------------------------
# Post-processing applied to ALL styles
# Uses PackedByteArray for ~10x faster pixel access vs set_pixel
# ---------------------------------------------------------------

func _apply_art_post_processing(image: Image, colors: Array, seed_val: int) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 997 + 31

	var center_x: float = w * 0.5
	var center_y: float = h * 0.5
	var max_dist: float = sqrt(center_x * center_x + center_y * center_y)
	var grain_seed_1: float = rng.randf() * 100.0
	var grain_seed_2: float = rng.randf() * 100.0

	# Convert to PackedByteArray for fast pixel access
	var data: PackedByteArray = image.get_data()
	var pixel_count: int = w * h

	for i in range(pixel_count):
		var byte_offset: int = i * 4
		var r: float = float(data[byte_offset]) / 255.0
		var g: float = float(data[byte_offset + 1]) / 255.0
		var b: float = float(data[byte_offset + 2]) / 255.0

		# Saturation boost via rough approximation (avoid Color.from_hsv overhead)
		var max_c: float = maxf(maxf(r, g), b)
		var min_c: float = minf(minf(r, g), b)
		var delta: float = max_c - min_c
		if max_c > 0.001 and delta > 0.001:
			var sat: float = clampf(delta / max_c * 1.3, 0.0, 1.0)
			var chroma_boost: float = sat * max_c / delta
			r = clampf(min_c + (r - min_c) * chroma_boost, 0.0, 1.0)
			g = clampf(min_c + (g - min_c) * chroma_boost, 0.0, 1.0)
			b = clampf(min_c + (b - min_c) * chroma_boost, 0.0, 1.0)

		# Vignette
		var ix: int = i % w
		var iy: int = i / w
		var dx: float = float(ix) - center_x
		var dy: float = float(iy) - center_y
		var dist_ratio: float = sqrt(dx * dx + dy * dy) / max_dist
		var vignette: float = 1.0 - clampf(dist_ratio * dist_ratio * 0.8, 0.0, 0.65)
		r *= vignette
		g *= vignette
		b *= vignette

		# Subtle bloom
		var luminance: float = r * 0.2126 + g * 0.7152 + b * 0.0722
		if luminance > 0.7:
			var bloom_strength: float = (luminance - 0.7) * 0.6
			r = r + (1.0 - r) * bloom_strength
			g = g + (1.0 - g) * bloom_strength
			b = b + (1.0 - b) * bloom_strength

		# Subtle film grain
		var grain_noise: float = sin(float(ix) * 12.9898 + float(iy) * 78.233 + grain_seed_1) * 43758.5453
		grain_noise = grain_noise - floorf(grain_noise)
		var grain2_noise: float = sin(float(ix) * 7.4531 + float(iy) * 93.1291 + grain_seed_2) * 27463.7291
		grain2_noise = grain2_noise - floorf(grain2_noise)
		var grain_amount: float = ((grain_noise + grain2_noise) * 0.5 - 0.5) * 0.04

		data[byte_offset] = clampi(int((r + grain_amount) * 255.0), 0, 255)
		data[byte_offset + 1] = clampi(int((g + grain_amount) * 255.0), 0, 255)
		data[byte_offset + 2] = clampi(int((b + grain_amount) * 255.0), 0, 255)
		data[byte_offset + 3] = 255

	image.set_data(w, h, false, Image.FORMAT_RGBA8, data)

# Shared color blend helpers
# ---------------------------------------------------------------

func _hsv_interpolate(c1: Color, c2: Color, t: float) -> Color:
	var h1: Color = Color.from_hsv(c1.h, c1.s, c1.v)
	var h2: Color = Color.from_hsv(c2.h, c2.s, c2.v)
	var hue: float = fposmod(h1.h + _short_angle_dist(h1.h, h2.h) * t, 1.0)
	var sat: float = lerpf(h1.s, h2.s, t)
	var val: float = lerpf(h1.v, h2.v, t)
	return Color.from_hsv(hue, sat, val)


func _short_angle_dist(from: float, to: float) -> float:
	var diff: float = fposmod(to - from, 1.0)
	if diff > 0.5:
		diff -= 1.0
	return diff


func _get_pixel_or_black(image: Image, x: int, y: int) -> Color:
	if x < 0 or x >= image.get_width() or y < 0 or y >= image.get_height():
		return Color.BLACK
	return image.get_pixel(x, y)


func _blend_add(base: Color, layer: Color, strength: float = 1.0) -> Color:
	return Color(
		clampf(base.r + layer.r * strength, 0.0, 1.0),
		clampf(base.g + layer.g * strength, 0.0, 1.0),
		clampf(base.b + layer.b * strength, 0.0, 1.0),
		1.0
	)


func _blend_screen(base: Color, layer: Color) -> Color:
	return Color(
		1.0 - (1.0 - base.r) * (1.0 - layer.r),
		1.0 - (1.0 - base.g) * (1.0 - layer.g),
		1.0 - (1.0 - base.b) * (1.0 - layer.b),
		1.0
	)


func _blend_overlay(base: Color, layer: Color) -> Color:
	var r: float = (base.r * base.r * 2.0 * layer.r + (1.0 - layer.r) * base.r) if base.r < 0.5 else (1.0 - (1.0 - base.r) * 2.0 * (1.0 - layer.r))
	var g: float = (base.g * base.g * 2.0 * layer.g + (1.0 - layer.g) * base.g) if base.g < 0.5 else (1.0 - (1.0 - base.g) * 2.0 * (1.0 - layer.g))
	var b: float = (base.b * base.b * 2.0 * layer.b + (1.0 - layer.b) * base.b) if base.b < 0.5 else (1.0 - (1.0 - base.b) * 2.0 * (1.0 - layer.b))
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0)


func _blend_multiply(base: Color, layer: Color) -> Color:
	return Color(base.r * layer.r, base.g * layer.g, base.b * layer.b, 1.0)


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------
# Style: gradient_noise (multi-layer, HSV interp, bloom glow)
# ---------------------------------------------------------------

func _generate_gradient_noise_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.2, 0.1, 0.4), Color(0.9, 0.3, 0.6), Color(0.1, 0.7, 0.9)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# --- Layer 1: Primary gradient (HSV-interpolated) ---
	var fill_radial: bool = seed_val % 3 == 0
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var max_dist: float = center.length()
	var grad_angle: float = deg_to_rad(float((seed_val % 8) * 45))

	for y in range(size.y):
		for x in range(size.x):
			var t: float
			if fill_radial:
				t = clamp(Vector2(float(x), float(y)).distance_to(center) / max_dist, 0.0, 1.0)
			else:
				var ndx: float = float(x) / float(size.x)
				var ndy: float = float(y) / float(size.y)
				t = clamp(ndx * cos(grad_angle) + ndy * sin(grad_angle), 0.0, 1.0)

			var idx_f: float = t * float(colors.size() - 1)
			var lo: int = int(idx_f)
			var hi: int = mini(lo + 1, colors.size() - 1)
			var frac: float = idx_f - float(lo)
			var col: Color = _hsv_interpolate(colors[lo], colors[hi], frac)
			image.set_pixel(x, y, col)

	# --- Layer 2: Low-frequency noise (additive tinted overlay) ---
	var noise_lo := FastNoiseLite.new()
	noise_lo.seed = seed_val * 7 + 13
	noise_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_lo.frequency = 0.008 + (seed_val % 6) * 0.002
	noise_lo.fractal_octaves = 4
	var noise_lo_img := noise_lo.get_image(size.x, size.y)

	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var n: float = noise_lo_img.get_pixel(x, y).r * 0.35
			var tint: Color = colors[(x + y) % colors.size()]
			var layer_col: Color = Color(tint.r * n, tint.g * n, tint.b * n)
			image.set_pixel(x, y, _blend_add(base, layer_col))

	# --- Layer 3: High-frequency noise (overlay blend for texture) ---
	var noise_hi := FastNoiseLite.new()
	noise_hi.seed = seed_val * 31 + 7
	noise_hi.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_hi.frequency = 0.04 + (seed_val % 8) * 0.008
	noise_hi.fractal_octaves = 3
	var noise_hi_img := noise_hi.get_image(size.x, size.y)

	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var n: float = noise_hi_img.get_pixel(x, y).r
			var layer_col := Color(n, n, n)
			image.set_pixel(x, y, _blend_overlay(base, layer_col))

	# --- Edge glow / bloom effect (extract bright areas, blur, screen blend) ---
	var glow_image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var lum: float = base.r * 0.2126 + base.g * 0.7152 + base.b * 0.0722
			var glow: float = clampf((lum - 0.55) * 2.5, 0.0, 1.0)
			glow_image.set_pixel(x, y, Color(base.r * glow, base.g * glow, base.b * glow, 1.0))

	# Simple box blur for glow spread
	var blurred := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var blur_radius: int = 3
	for y in range(size.y):
		for x in range(size.x):
			var accum := Color(0.0, 0.0, 0.0, 0.0)
			var count: int = 0
			for by in range(-blur_radius, blur_radius + 1):
				for bx in range(-blur_radius, blur_radius + 1):
					accum += _get_pixel_or_black(glow_image, x + bx, y + by)
					count += 1
			accum /= float(count)
			blurred.set_pixel(x, y, accum)

	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var glow: Color = blurred.get_pixel(x, y)
			image.set_pixel(x, y, _blend_screen(base, glow))

	return image


# ---------------------------------------------------------------
# Style: voronoi (neon edge glow, inner cell gradients)
# ---------------------------------------------------------------

func _generate_voronoi_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.1, 0.0, 0.3), Color(0.0, 0.8, 0.6), Color(1.0, 0.5, 0.2), Color(0.3, 0.1, 0.8)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Cell value noise
	var noise_cell := FastNoiseLite.new()
	noise_cell.seed = seed_val
	noise_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_cell.frequency = 0.025 + (seed_val % 5) * 0.004
	noise_cell.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise_cell.cellular_jitter = 1.5
	noise_cell.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var cell_img := noise_cell.get_image(size.x, size.y)

	# Distance noise for edges
	var noise_dist := FastNoiseLite.new()
	noise_dist.seed = seed_val
	noise_dist.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_dist.frequency = noise_cell.frequency
	noise_dist.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise_dist.cellular_jitter = 1.5
	noise_dist.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var dist_img := noise_dist.get_image(size.x, size.y)

	# Second noise layer for inner cell color variation
	var noise_inner := FastNoiseLite.new()
	noise_inner.seed = seed_val * 17 + 5
	noise_inner.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_inner.frequency = 0.015
	noise_inner.fractal_octaves = 3
	var inner_img := noise_inner.get_image(size.x, size.y)

	# Pick neon edge color from palette
	var neon_color: Color = colors[1 % colors.size()].lerp(Color.WHITE, 0.3)

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	for y in range(size.y):
		for x in range(size.x):
			var cell_val: float = cell_img.get_pixel(x, y).r
			var dist_val: float = dist_img.get_pixel(x, y).r
			var inner_val: float = inner_img.get_pixel(x, y).r

			# Cell color with inner gradient variation
			var color_idx: int = int(absf(cell_val) * 100.0) % colors.size()
			var cell_base: Color = colors[color_idx]
			var cell_bright: Color = colors[(color_idx + 1) % colors.size()]
			var inner_t: float = clampf(inner_val * 0.5 + 0.5, 0.0, 1.0)
			var col: Color = _hsv_interpolate(cell_base, cell_bright, inner_t)

			# Darken cell interiors slightly for depth
			col = col * 0.75

			# Neon edge glow: bright at edges, fading outward
			var edge_intensity: float = 1.0 - clampf(dist_val * 4.0, 0.0, 1.0)
			edge_intensity = pow(edge_intensity, 1.5)
			col = col.lerp(neon_color, edge_intensity * 0.9)

			# Extra bloom on edges
			if edge_intensity > 0.6:
				col = col.lerp(Color.WHITE, (edge_intensity - 0.6) * 0.5)

			image.set_pixel(x, y, col)

	return image


# ---------------------------------------------------------------
# Style: geometric (alpha-blended shapes, shadows, overlapping)
# ---------------------------------------------------------------

func _generate_geometric_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.05, 0.05, 0.1), Color(0.9, 0.4, 0.1), Color(0.2, 0.6, 0.9), Color(0.8, 0.2, 0.5)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# Background: gradient with subtle noise
	var bg_color1: Color = colors[0]
	var bg_color2: Color = colors[0].lerp(Color.BLACK, 0.3)
	for y in range(size.y):
		var t: float = float(y) / float(size.y)
		var row_col: Color = bg_color1.lerp(bg_color2, t)
		image.fill_rect(Rect2i(0, y, size.x, 1), row_col)

	# Noise texture for background grain
	var bg_noise := FastNoiseLite.new()
	bg_noise.seed = seed_val * 3 + 1
	bg_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bg_noise.frequency = 0.01
	bg_noise.fractal_octaves = 2
	var bg_noise_img := bg_noise.get_image(size.x, size.y)
	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var n: float = bg_noise_img.get_pixel(x, y).r * 0.15
			image.set_pixel(x, y, _blend_overlay(base, Color(n + 0.5, n + 0.5, n + 0.5)))

	var shape_count: int = 12 + rng.randi() % 16

	for _i in range(shape_count):
		var shape_type: int = rng.randi() % 5
		var col: Color = colors[(rng.randi() % (colors.size() - 1)) + 1]
		var alpha: float = rng.randf_range(0.25, 0.7)
		var cx: int = rng.randi() % size.x
		var cy: int = rng.randi() % size.y

		# Shadow behind shape
		var shadow_offset: int = 4 + rng.randi() % 6
		var shadow_col: Color = Color(0.0, 0.0, 0.0, alpha * 0.5)

		match shape_type:
			0:  # Circle
				var radius: float = float(20 + rng.randi() % 80)
				_fill_alpha_circle_on_image(image, Vector2(float(cx + shadow_offset), float(cy + shadow_offset)), radius, shadow_col, size)
				_fill_alpha_circle_on_image(image, Vector2(float(cx), float(cy)), radius, Color(col.r, col.g, col.b, alpha), size)
			1:  # Rectangle
				var rw: int = 30 + rng.randi() % 120
				var rh: int = 30 + rng.randi() % 120
				var rx: int = clampi(cx - rw / 2, 0, size.x - 1)
				var ry: int = clampi(cy - rh / 2, 0, size.y - 1)
				var sx: int = clampi(rx + shadow_offset, 0, size.x - 1)
				var sy: int = clampi(ry + shadow_offset, 0, size.y - 1)
				_alpha_fill_rect(image, Rect2i(sx, sy, mini(rw, size.x - sx), mini(rh, size.y - sy)), shadow_col)
				_alpha_fill_rect(image, Rect2i(rx, ry, mini(rw, size.x - rx), mini(rh, size.y - ry)), Color(col.r, col.g, col.b, alpha))
			2:  # Rotated grid of small squares
				var grid_size: int = 3 + rng.randi() % 4
				var cell_size: int = 12 + rng.randi() % 20
				var spacing: int = cell_size + 6
				for gy in range(grid_size):
					for gx in range(grid_size):
						var px: int = cx - (grid_size * spacing) / 2 + gx * spacing
						var py: int = cy - (grid_size * spacing) / 2 + gy * spacing
						var small_col: Color = Color(col.r, col.g, col.b, alpha * rng.randf_range(0.5, 1.0))
						if px >= 0 and py >= 0 and px + cell_size < size.x and py + cell_size < size.y:
							_alpha_fill_rect(image, Rect2i(px, py, cell_size, cell_size), small_col)
			3:  # Line
				var x2: int = rng.randi() % size.x
				var y2: int = rng.randi() % size.y
				var thickness: int = 2 + rng.randi() % 6
				_draw_line_on_image(image, cx + shadow_offset, cy + shadow_offset, x2 + shadow_offset, y2 + shadow_offset, thickness + 2, Color(0.0, 0.0, 0.0))
				_draw_line_on_image(image, cx, cy, x2, y2, thickness, col)
			4:  # Triangle (rotated)
				var s: float = float(30 + rng.randi() % 80)
				var angle_off: float = rng.randf() * TAU
				var p1 := Vector2(float(cx) + cos(angle_off) * s, float(cy) + sin(angle_off) * s)
				var p2 := Vector2(float(cx) + cos(angle_off + TAU / 3.0) * s, float(cy) + sin(angle_off + TAU / 3.0) * s)
				var p3 := Vector2(float(cx) + cos(angle_off + TAU * 2.0 / 3.0) * s, float(cy) + sin(angle_off + TAU * 2.0 / 3.0) * s)
				var sh_off := Vector2(float(shadow_offset), float(shadow_offset))
				_fill_triangle_on_image(image, p1 + sh_off, p2 + sh_off, p3 + sh_off, Color(0.0, 0.0, 0.0), size)
				_fill_triangle_on_image(image, p1, p2, p3, col, size)

	return image


func _fill_alpha_circle_on_image(image: Image, center: Vector2, radius: float, col: Color, bounds: Vector2i) -> void:
	var r2: float = radius * radius
	var min_y: int = maxi(int(center.y - radius), 0)
	var max_y: int = mini(int(center.y + radius), bounds.y - 1)
	for py in range(min_y, max_y + 1):
		var dy: float = float(py) - center.y
		var dx_span: float = sqrt(maxf(r2 - dy * dy, 0.0))
		var row_min_x: int = maxi(int(center.x - dx_span), 0)
		var row_max_x: int = mini(int(center.x + dx_span), bounds.x - 1)
		for px in range(row_min_x, row_max_x + 1):
			var base: Color = image.get_pixel(px, py)
			var blended: Color = base.lerp(Color(col.r, col.g, col.b), col.a)
			image.set_pixel(px, py, blended)


func _alpha_fill_rect(image: Image, rect: Rect2i, col: Color) -> void:
	for y in range(rect.position.y, mini(rect.end.y, image.get_height())):
		for x in range(rect.position.x, mini(rect.end.x, image.get_width())):
			var base: Color = image.get_pixel(x, y)
			var blended: Color = base.lerp(Color(col.r, col.g, col.b), col.a)
			image.set_pixel(x, y, blended)


# ---------------------------------------------------------------
# Style: plasma (5 sine layers, HSV interpolation, sparkle)
# ---------------------------------------------------------------

func _generate_plasma_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 3:
		colors = [Color(0.0, 0.1, 0.3), Color(1.0, 0.0, 0.5), Color(0.0, 0.9, 0.9), Color(1.0, 0.9, 0.2)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Pre-compute random parameters for 5 sine layers
	var freqs: Array = []
	var phases: Array = []
	var axis_types: Array = []  # 0=x, 1=y, 2=xy, 3=radial, 4=swirl
	for i in range(5):
		freqs.append(0.005 + rng.randf() * 0.03)
		phases.append(rng.randf() * TAU)
		axis_types.append(rng.randi() % 5)

	var center := Vector2(size.x * 0.5, size.y * 0.5)

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	for y in range(size.y):
		for x in range(size.x):
			var fx: float = float(x)
			var fy: float = float(y)
			var total: float = 0.0

			for i in range(5):
				var v: float
				match axis_types[i]:
					0:
						v = sin(fx * freqs[i] + phases[i])
					1:
						v = sin(fy * freqs[i] + phases[i])
					2:
						v = sin((fx + fy) * freqs[i] + phases[i])
					3:
						var dist: float = Vector2(fx, fy).distance_to(center)
						v = sin(dist * freqs[i] * 2.0 + phases[i])
					4:
						var angle: float = atan2(fy - center.y, fx - center.x)
						var dist: float = Vector2(fx, fy).distance_to(center)
						v = sin(angle * 3.0 + dist * freqs[i] + phases[i])
				total += v

			# Normalize from [-5, 5] to [0, 1]
			var t: float = clampf((total + 5.0) / 10.0, 0.0, 1.0)

			# Map through color palette using HSV interpolation
			var idx_f: float = t * float(colors.size() - 1)
			var lo: int = int(idx_f)
			var hi: int = mini(lo + 1, colors.size() - 1)
			var frac: float = idx_f - float(lo)
			var col: Color = _hsv_interpolate(colors[lo], colors[hi], frac)

			image.set_pixel(x, y, col)

	# Sparkle overlay layer
	var sparkle_noise := FastNoiseLite.new()
	sparkle_noise.seed = seed_val * 41 + 3
	sparkle_noise.noise_type = FastNoiseLite.TYPE_VALUE
	sparkle_noise.frequency = 0.08
	sparkle_noise.fractal_octaves = 1
	var sparkle_img := sparkle_noise.get_image(size.x, size.y)

	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var s: float = sparkle_img.get_pixel(x, y).r
			if s > 0.85:
				var sparkle_strength: float = (s - 0.85) * 6.67
				base = base.lerp(Color.WHITE, sparkle_strength * 0.3)
			image.set_pixel(x, y, base)

	return image


# ---------------------------------------------------------------
# Style: mandala (rotation symmetry, petal curves, glow)
# ---------------------------------------------------------------

func _generate_mandala_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 3:
		colors = [Color(0.03, 0.01, 0.08), Color(0.95, 0.75, 0.2), Color(0.4, 0.1, 0.85), Color(0.1, 0.8, 0.6)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	# Dark background with subtle radial gradient
	for y in range(size.y):
		for x in range(size.x):
			var ddx: float = float(x) - size.x * 0.5
			var ddy: float = float(y) - size.y * 0.5
			var dist: float = sqrt(ddx * ddx + ddy * ddy) / (size.x * 0.5)
			var bg: Color = colors[0].lerp(Color.BLACK, clampf(dist * 0.5, 0.0, 0.5))
			image.set_pixel(x, y, bg)

	var center := Vector2(float(size.x) * 0.5, float(size.y) * 0.5)
	var max_radius: float = min(float(size.x), float(size.y)) * 0.44

	var symmetry: int = [6, 8, 12][seed_val % 3]

	# Concentric ring bands
	var ring_count: int = 5 + rng.randi() % 4
	for r in range(ring_count):
		var outer_r: float = max_radius * (float(r + 1) / float(ring_count))
		var inner_r: float = max_radius * (float(r) / float(ring_count))
		var ring_col: Color = colors[(r + 1) % colors.size()]
		var ring_col_inner: Color = colors[r % colors.size()]

		# Draw filled ring band
		_fill_circle_on_image(image, center, outer_r, ring_col, size)
		# Glow ring at the boundary
		_draw_glow_ring(image, center, outer_r, ring_col.lerp(Color.WHITE, 0.4), 4.0, size)
		_fill_circle_on_image(image, center, inner_r + 2.0, ring_col_inner, size)

	# Petal curves at each symmetry arm
	for s in range(symmetry):
		var base_angle: float = TAU * float(s) / float(symmetry)
		for r in range(1, ring_count + 1):
			var petal_r: float = max_radius * float(r) / float(ring_count)
			var petal_length: float = max_radius / float(ring_count) * 0.7
			var petal_width: float = 8.0 + rng.randf() * 6.0
			var petal_col: Color = colors[(r + s) % colors.size()]

			# Draw petal as series of overlapping circles along the arm
			var steps: int = 8
			for step_i in range(steps):
				var t: float = float(step_i) / float(steps - 1)
				var petal_center := Vector2(
					center.x + cos(base_angle) * (petal_r - petal_length * 0.5 + petal_length * t),
					center.y + sin(base_angle) * (petal_r - petal_length * 0.5 + petal_length * t)
				)
				# Width tapers at ends, widest in middle
				var taper: float = sin(t * PI)
				var pr: float = petal_width * taper
				if pr > 1.0:
					_fill_circle_on_image(image, petal_center, pr, petal_col.lerp(Color.WHITE, 0.15 * taper), size)

			# Glow at petal tip
			var tip_pos := Vector2(
				center.x + cos(base_angle) * petal_r,
				center.y + sin(base_angle) * petal_r
			)
			_fill_circle_on_image(image, tip_pos, 5.0, petal_col.lerp(Color.WHITE, 0.5), size)

	# Radial spokes
	var line_col: Color = colors[1 % colors.size()].lerp(Color.WHITE, 0.2)
	for s in range(symmetry):
		var angle: float = TAU * float(s) / float(symmetry)
		var end_x: float = center.x + cos(angle) * max_radius
		var end_y: float = center.y + sin(angle) * max_radius
		_draw_line_on_image(image, int(center.x), int(center.y), int(end_x), int(end_y), 2, line_col)

	# Central rosette
	var central_r: float = max_radius * 0.1
	_fill_circle_on_image(image, center, central_r, colors[1 % colors.size()], size)
	_draw_glow_ring(image, center, central_r, colors[2 % colors.size()].lerp(Color.WHITE, 0.6), 3.0, size)
	_fill_circle_on_image(image, center, central_r * 0.5, colors[2 % colors.size()].lerp(Color.WHITE, 0.3), size)

	# Dots at ring/spoke intersections
	for r in range(1, ring_count + 1):
		var dot_radius: float = max_radius * float(r) / float(ring_count)
		for s in range(symmetry):
			var angle: float = TAU * float(s) / float(symmetry) + TAU * float(r) * 0.03
			var dot_pos := Vector2(
				center.x + cos(angle) * dot_radius,
				center.y + sin(angle) * dot_radius
			)
			var dot_r: float = 3.0 + rng.randf() * 3.0
			var dot_col: Color = colors[(r + s) % colors.size()].lerp(Color.WHITE, 0.35)
			_fill_circle_on_image(image, dot_pos, dot_r + 2.0, dot_col.lerp(Color.WHITE, 0.2), size)
			_fill_circle_on_image(image, dot_pos, dot_r, dot_col, size)

	return image


func _draw_glow_ring(image: Image, center: Vector2, radius: float, col: Color, width: float, bounds: Vector2i) -> void:
	for offset in range(int(width)):
		var alpha: float = 1.0 - float(offset) / width
		var r: float = radius + float(offset)
		if r > 0.0:
			_draw_circle_outline(image, center, r, col.lerp(Color(col.r, col.g, col.b), 1.0 - alpha * 0.7), bounds)


func _draw_circle_outline(image: Image, center: Vector2, radius: float, col: Color, bounds: Vector2i) -> void:
	var steps: int = maxi(int(TAU * radius * 0.5), 36)
	for i in range(steps):
		var angle: float = TAU * float(i) / float(steps)
		var px: int = int(center.x + cos(angle) * radius)
		var py: int = int(center.y + sin(angle) * radius)
		if px >= 0 and px < bounds.x and py >= 0 and py < bounds.y:
			image.set_pixel(px, py, col)


# ---------------------------------------------------------------
# Style: pixel_art (constrained palette, outlines, grid overlay)
# ---------------------------------------------------------------

func _generate_pixel_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.1, 0.1, 0.15), Color(1.0, 0.3, 0.3), Color(0.3, 1.0, 0.3), Color(0.3, 0.3, 1.0)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Constrain to 4-5 color palette
	var palette: Array = []
	palette.append(colors[0])  # Background
	var palette_size: int = mini(colors.size(), 5)
	for i in range(1, palette_size):
		palette.append(colors[i % colors.size()])
	# Outline color (dark version of background)
	var outline_col: Color = palette[0].lerp(Color.BLACK, 0.7)

	var pixel_size: int = 16 + rng.randi() % 24
	var grid_w: int = size.x / pixel_size
	var grid_h: int = size.y / pixel_size

	# Grid: -1 = empty, 0+ = palette index
	var grid: Array = []
	for gy in range(grid_h):
		var row: Array = []
		for gx in range(grid_w):
			row.append(-1)
		grid.append(row)

	# Generate symmetric pixel pattern
	var half_w: int = (grid_w + 1) / 2
	for gy in range(grid_h):
		for gx in range(half_w):
			if rng.randf() < 0.5:
				var pal_idx: int = 1 + rng.randi() % (palette_size - 1)
				grid[gy][gx] = pal_idx
				var mirror_gx: int = grid_w - 1 - gx
				if mirror_gx != gx:
					grid[gy][mirror_gx] = pal_idx

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(palette[0])

	# Render pixels with outlines
	for gy in range(grid_h):
		for gx in range(grid_w):
			if grid[gy][gx] < 0:
				continue
			var pal_idx: int = grid[gy][gx]
			var col: Color = palette[pal_idx]
			var rx: int = gx * pixel_size
			var ry: int = gy * pixel_size

			if rx + pixel_size > size.x or ry + pixel_size > size.y:
				continue

			# Check neighbors - draw outline edge where adjacent to empty
			var has_empty_neighbor: bool = false
			if gx == 0 or grid[gy][gx - 1] < 0:
				has_empty_neighbor = true
			if gx == grid_w - 1 or grid[gy][gx + 1] < 0:
				has_empty_neighbor = true
			if gy == 0 or grid[gy - 1][gx] < 0:
				has_empty_neighbor = true
			if gy == grid_h - 1 or grid[gy + 1][gx] < 0:
				has_empty_neighbor = true

			# Fill pixel block
			image.fill_rect(Rect2i(rx, ry, pixel_size, pixel_size), col)

			# Outline border on edges adjacent to background
			if has_empty_neighbor:
				# Top edge
				if gy == 0 or grid[gy - 1][gx] < 0:
					image.fill_rect(Rect2i(rx, ry, pixel_size, 2), outline_col)
				# Bottom edge
				if gy == grid_h - 1 or grid[gy + 1][gx] < 0:
					image.fill_rect(Rect2i(rx, ry + pixel_size - 2, pixel_size, 2), outline_col)
				# Left edge
				if gx == 0 or grid[gy][gx - 1] < 0:
					image.fill_rect(Rect2i(rx, ry, 2, pixel_size), outline_col)
				# Right edge
				if gx == grid_w - 1 or grid[gy][gx + 1] < 0:
					image.fill_rect(Rect2i(rx + pixel_size - 2, ry, 2, pixel_size), outline_col)

	# Subtle grid overlay
	for gx in range(grid_w + 1):
		var lx: int = gx * pixel_size
		if lx < size.x:
			for y in range(size.y):
				var base: Color = image.get_pixel(lx, y)
				image.set_pixel(lx, y, base.lerp(Color.BLACK, 0.08))
	for gy in range(grid_h + 1):
		var ly: int = gy * pixel_size
		if ly < size.y:
			for x in range(size.x):
				var base: Color = image.get_pixel(x, ly)
				image.set_pixel(x, ly, base.lerp(Color.BLACK, 0.08))

	return image


# ---------------------------------------------------------------
# Style: fractal (recursive spiral tree, glowing branches)
# ---------------------------------------------------------------

func _generate_fractal_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.02, 0.02, 0.06), Color(0.3, 0.8, 1.0), Color(0.8, 0.3, 1.0), Color(0.1, 1.0, 0.6)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# Dark background with subtle radial glow
	var bg_col: Color = colors[0]
	var glow_col: Color = colors[1 % colors.size()].lerp(bg_col, 0.85)
	for y in range(size.y):
		for x in range(size.x):
			var ddx: float = float(x) - size.x * 0.5
			var ddy: float = float(y) - size.y * 0.5
			var dist: float = sqrt(ddx * ddx + ddy * ddy) / (size.x * 0.5)
			image.set_pixel(x, y, bg_col.lerp(glow_col, clampf(1.0 - dist, 0.0, 0.3)))

	# Fractal tree parameters
	var start_pos := Vector2(float(size.x) * 0.5, float(size.y) * 0.85)
	var start_angle: float = -PI / 2.0  # Straight up
	var start_length: float = float(size.y) * 0.22
	var branch_angle_spread: float = rng.randf_range(0.35, 0.55)
	var length_decay: float = rng.randf_range(0.65, 0.78)
	var max_depth: int = 8 + rng.randi() % 3

	_draw_fractal_branch(image, start_pos, start_angle, start_length, max_depth, branch_angle_spread, length_decay, colors, rng, size)

	# Scattered particle glow points
	var particle_count: int = 40 + rng.randi() % 30
	for _p in range(particle_count):
		var px: float = rng.randf() * float(size.x)
		var py: float = rng.randf() * float(size.y)
		var p_col: Color = colors[rng.randi() % colors.size()].lerp(Color.WHITE, 0.4)
		var p_size: float = rng.randf_range(1.0, 3.0)
		_fill_circle_on_image(image, Vector2(px, py), p_size, p_col, size)

	return image


func _draw_fractal_branch(image: Image, pos: Vector2, angle: float, length: float, depth: int, spread: float, decay: float, colors: Array, rng: RandomNumberGenerator, size: Vector2i) -> void:
	if depth <= 0 or length < 2.0:
		# Draw a glowing leaf dot at the tip
		var leaf_col: Color = colors[(depth + 2) % colors.size()].lerp(Color.WHITE, 0.3)
		_fill_circle_on_image(image, pos, 3.0, leaf_col, size)
		_fill_circle_on_image(image, pos, 5.0, leaf_col.lerp(colors[0], 0.6), size)
		return

	var end_pos := Vector2(
		pos.x + cos(angle) * length,
		pos.y + sin(angle) * length
	)

	# Branch color: base color at trunk, brighter toward tips
	var t: float = 1.0 - float(depth) / 10.0
	var branch_col: Color = colors[1 % colors.size()].lerp(colors[2 % colors.size()], t)
	# Glow: thicker and more luminous at trunk
	var thickness: int = maxi(int(float(depth) * 1.2), 1)
	var glow_thickness: int = thickness + 3

	# Draw glow layer first (wider, dimmer)
	var glow_col: Color = branch_col.lerp(colors[0], 0.5)
	_draw_line_on_image(image, int(pos.x), int(pos.y), int(end_pos.x), int(end_pos.y), glow_thickness, glow_col)

	# Draw main branch on top
	_draw_line_on_image(image, int(pos.x), int(pos.y), int(end_pos.x), int(end_pos.y), thickness, branch_col)

	# Recurse with slight random variation
	var angle_jitter: float = rng.randf_range(-0.1, 0.1)
	_draw_fractal_branch(image, end_pos, angle - spread + angle_jitter, length * decay, depth - 1, spread, decay, colors, rng, size)
	_draw_fractal_branch(image, end_pos, angle + spread + angle_jitter, length * decay, depth - 1, spread, decay, colors, rng, size)

	# Occasional third branch for spiral feel
	if rng.randf() < 0.3 and depth > 3:
		var third_angle: float = angle + rng.randf_range(-0.3, 0.3)
		_draw_fractal_branch(image, end_pos, third_angle, length * decay * 0.7, depth - 2, spread, decay, colors, rng, size)


# ---------------------------------------------------------------
# Style: nebula (multi-noise space nebula, stars, gas clouds)
# ---------------------------------------------------------------

func _generate_nebula_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.02, 0.0, 0.05), Color(0.4, 0.0, 0.8), Color(0.0, 0.5, 1.0), Color(1.0, 0.2, 0.4), Color(0.0, 0.9, 0.6)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# Deep space background
	image.fill(colors[0])

	# Layer 1: Large-scale gas cloud structure
	var noise_gas := FastNoiseLite.new()
	noise_gas.seed = seed_val
	noise_gas.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_gas.frequency = 0.004
	noise_gas.fractal_octaves = 5
	noise_gas.fractal_lacunarity = 2.2
	noise_gas.fractal_gain = 0.5
	var gas_img := noise_gas.get_image(size.x, size.y)

	# Layer 2: Medium turbulence
	var noise_turb := FastNoiseLite.new()
	noise_turb.seed = seed_val * 13 + 7
	noise_turb.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_turb.frequency = 0.012
	noise_turb.fractal_octaves = 4
	var turb_img := noise_turb.get_image(size.x, size.y)

	# Layer 3: Fine detail noise
	var noise_detail := FastNoiseLite.new()
	noise_detail.seed = seed_val * 29 + 3
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_detail.frequency = 0.035
	noise_detail.fractal_octaves = 3
	var detail_img := noise_detail.get_image(size.x, size.y)

	# Color selection for nebula palette
	var nebula_color_a: Color = colors[1 % colors.size()]
	var nebula_color_b: Color = colors[2 % colors.size()]
	var nebula_color_c: Color = colors[3 % colors.size()] if colors.size() > 3 else nebula_color_a.lerp(Color.WHITE, 0.3)

	for y in range(size.y):
		for x in range(size.x):
			var gas: float = gas_img.get_pixel(x, y).r * 0.5 + 0.5
			var turb: float = turb_img.get_pixel(x, y).r * 0.5 + 0.5
			var detail: float = detail_img.get_pixel(x, y).r * 0.5 + 0.5

			# Combine noise layers
			var combined: float = gas * 0.6 + turb * 0.25 + detail * 0.15
			combined = clampf(combined, 0.0, 1.0)

			# Threshold to create cloud-like shapes
			combined = _smoothstep(0.3, 0.7, combined)

			# Three-way color blend based on noise
			var col: Color
			if combined < 0.5:
				col = _hsv_interpolate(nebula_color_a, nebula_color_b, combined * 2.0)
			else:
				col = _hsv_interpolate(nebula_color_b, nebula_color_c, (combined - 0.5) * 2.0)

			# Modulate brightness
			col = col * combined * 1.4
			col.a = 1.0

			image.set_pixel(x, y, col)

	# Layer 4: Secondary gas cloud with additive blend
	var noise_gas2 := FastNoiseLite.new()
	noise_gas2.seed = seed_val * 47 + 11
	noise_gas2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_gas2.frequency = 0.006
	noise_gas2.fractal_octaves = 4
	var gas2_img := noise_gas2.get_image(size.x, size.y)

	var secondary_col: Color = colors[4 % colors.size()] if colors.size() > 4 else nebula_color_c
	for y in range(size.y):
		for x in range(size.x):
			var g2: float = gas2_img.get_pixel(x, y).r * 0.5 + 0.5
			g2 = _smoothstep(0.35, 0.75, g2) * 0.5
			var base: Color = image.get_pixel(x, y)
			var add_col: Color = Color(secondary_col.r * g2, secondary_col.g * g2, secondary_col.b * g2)
			image.set_pixel(x, y, _blend_add(base, add_col))

	# Stars: bright points scattered across the image
	var star_count: int = 80 + rng.randi() % 60
	for _s in range(star_count):
		var sx: int = rng.randi() % size.x
		var sy: int = rng.randi() % size.y
		var star_brightness: float = rng.randf_range(0.5, 1.0)
		var star_size: float = rng.randf_range(0.5, 2.5)
		var star_col: Color = Color(star_brightness, star_brightness, star_brightness * rng.randf_range(0.9, 1.0))

		if star_size < 1.0:
			if sx >= 0 and sx < size.x and sy >= 0 and sy < size.y:
				var base: Color = image.get_pixel(sx, sy)
				image.set_pixel(sx, sy, _blend_add(base, star_col))
		else:
			_fill_circle_on_image(image, Vector2(float(sx), float(sy)), star_size, star_col, size)
			# Star glow halo
			_fill_circle_on_image(image, Vector2(float(sx), float(sy)), star_size * 3.0, star_col.lerp(colors[0], 0.7), size)

	# Bright stars with diffraction spikes
	var bright_star_count: int = 3 + rng.randi() % 4
	for _bs in range(bright_star_count):
		var bsx: float = rng.randf_range(float(size.x) * 0.1, float(size.x) * 0.9)
		var bsy: float = rng.randf_range(float(size.y) * 0.1, float(size.y) * 0.9)
		var bs_col: Color = Color(1.0, 0.98, 0.95)
		_fill_circle_on_image(image, Vector2(bsx, bsy), 3.0, bs_col, size)
		# Cross spikes
		var spike_len: float = rng.randf_range(12.0, 25.0)
		_draw_line_on_image(image, int(bsx - spike_len), int(bsy), int(bsx + spike_len), int(bsy), 1, bs_col.lerp(colors[0], 0.3))
		_draw_line_on_image(image, int(bsx), int(bsy - spike_len), int(bsx), int(bsy + spike_len), 1, bs_col.lerp(colors[0], 0.3))

	return image


# ---------------------------------------------------------------
# Style: flow_field (Perlin noise flow field with particle traces)
# ---------------------------------------------------------------

func _generate_flow_field_art(seed_val: int, colors: Array, size: Vector2i) -> Image:
	if colors.size() < 2:
		colors = [Color(0.02, 0.03, 0.06), Color(0.2, 0.6, 1.0), Color(1.0, 0.4, 0.3), Color(0.3, 1.0, 0.5), Color(0.9, 0.8, 0.2)]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(colors[0])

	# Generate flow field from noise
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.004 + rng.randf() * 0.004
	noise.fractal_octaves = 3
	var field_img := noise.get_image(size.x, size.y)

	# Second noise layer for more complex flows
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed_val * 23 + 9
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.003 + rng.randf() * 0.003
	noise2.fractal_octaves = 2
	var field2_img := noise2.get_image(size.x, size.y)

	# Trace particles through the field
	var particle_count: int = 300 + rng.randi() % 200
	var steps_per_particle: int = 60 + rng.randi() % 40

	for _p in range(particle_count):
		# Random starting position
		var px: float = rng.randf() * float(size.x)
		var py: float = rng.randf() * float(size.y)

		# Color for this particle trace
		var particle_col: Color = colors[1 + rng.randi() % (colors.size() - 1)]
		var alpha: float = rng.randf_range(0.15, 0.5)

		for step in range(steps_per_particle):
			var ix: int = clampi(int(px), 0, size.x - 1)
			var iy: int = clampi(int(py), 0, size.y - 1)

			# Sample flow angle from combined noise
			var n1: float = field_img.get_pixel(ix, iy).r
			var n2: float = field2_img.get_pixel(ix, iy).r
			var angle: float = (n1 + n2) * TAU * 2.0

			# Move along flow direction
			var speed: float = 1.5 + absf(n1) * 1.0
			var new_px: float = px + cos(angle) * speed
			var new_py: float = py + sin(angle) * speed

			# Check bounds
			if new_px < 0.0 or new_px >= float(size.x) or new_py < 0.0 or new_py >= float(size.y):
				break

			# Draw trace segment with alpha blend
			var base: Color = image.get_pixel(ix, iy)
			var traced: Color = base.lerp(particle_col, alpha)
			image.set_pixel(ix, iy, traced)

			# Thicker traces for some particles (every 3rd step, draw neighbor pixels)
			if step % 3 == 0:
				var nix: int = clampi(ix + 1, 0, size.x - 1)
				var niy: int = clampi(iy + 1, 0, size.y - 1)
				var b1: Color = image.get_pixel(nix, iy)
				image.set_pixel(nix, iy, b1.lerp(particle_col, alpha * 0.5))
				var b2: Color = image.get_pixel(ix, niy)
				image.set_pixel(ix, niy, b2.lerp(particle_col, alpha * 0.5))

			px = new_px
			py = new_py

	# Overlay subtle noise texture for richness
	var overlay_noise := FastNoiseLite.new()
	overlay_noise.seed = seed_val * 11 + 2
	overlay_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	overlay_noise.frequency = 0.02
	overlay_noise.fractal_octaves = 2
	var overlay_img := overlay_noise.get_image(size.x, size.y)

	for y in range(size.y):
		for x in range(size.x):
			var base: Color = image.get_pixel(x, y)
			var n: float = overlay_img.get_pixel(x, y).r
			var layer: Color = Color(n, n, n)
			image.set_pixel(x, y, _blend_overlay(base, layer))

	return image


# ================================================================
# Pixel-level drawing helpers (Image has no draw_* methods in Godot 4)
# ================================================================

func _fill_circle_on_image(image: Image, center: Vector2, radius: float, col: Color, bounds: Vector2i) -> void:
	var r2: float = radius * radius
	var min_y: int = maxi(int(center.y - radius), 0)
	var max_y: int = mini(int(center.y + radius), bounds.y - 1)
	var min_x: int = maxi(int(center.x - radius), 0)
	var max_x: int = mini(int(center.x + radius), bounds.x - 1)
	for py in range(min_y, max_y + 1):
		var dy: float = float(py) - center.y
		var dx_span: float = sqrt(maxf(r2 - dy * dy, 0.0))
		var row_min_x: int = maxi(int(center.x - dx_span), 0)
		var row_max_x: int = mini(int(center.x + dx_span), bounds.x - 1)
		if row_max_x > row_min_x:
			image.fill_rect(Rect2i(row_min_x, py, row_max_x - row_min_x + 1, 1), col)


func _draw_line_on_image(image: Image, x0: int, y0: int, x1: int, y1: int, thickness: int, col: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var half_t: int = thickness / 2
	var img: Image = image
	var w: int = image.get_width()
	var h: int = image.get_height()

	while true:
		# Fill a small square around each point for thickness
		for ty: int in range(-half_t, half_t + 1):
			for tx: int in range(-half_t, half_t + 1):
				var px: int = x0 + tx
				var py: int = y0 + ty
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, col)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


func _fill_triangle_on_image(image: Image, p1: Vector2, p2: Vector2, p3: Vector2, col: Color, bounds: Vector2i) -> void:
	# Scanline triangle fill using barycentric coordinates
	var min_y: int = maxi(int(minf(p1.y, minf(p2.y, p3.y))), 0)
	var max_y: int = mini(int(maxf(p1.y, maxf(p2.y, p3.y))), bounds.y - 1)

	for py in range(min_y, max_y + 1):
		var intersections: Array = []
		var y: float = float(py) + 0.5
		# Find edge intersections with this scanline
		var edges: Array = [[p1, p2], [p2, p3], [p3, p1]]
		for edge in edges:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				var t: float = (y - a.y) / (b.y - a.y)
				intersections.append(a.x + t * (b.x - a.x))
		intersections.sort()
		if intersections.size() >= 2:
			var x_start: int = maxi(int(intersections[0]), 0)
			var x_end: int = mini(int(intersections[intersections.size() - 1]), bounds.x - 1)
			if x_end > x_start:
				image.fill_rect(Rect2i(x_start, py, x_end - x_start + 1, 1), col)


# ================================================================
# Camera
# ================================================================

func _add_first_person_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.current = true
	camera.position = primary_room_center + Vector3(0.0, CAMERA_EYE_HEIGHT, -primary_room_dimensions.z * CAMERA_BACK_OFFSET_RATIO)
	generation_root.add_child(camera)
	camera.look_at(primary_room_center + Vector3(0.0, CAMERA_EYE_HEIGHT, 0.0), Vector3.UP)
	camera_pitch = camera.rotation.x
	camera_yaw = camera.rotation.y


# ================================================================
# Mesh helpers
# ================================================================

func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.set_surface_override_material(0, material)
	generation_root.add_child(mesh_instance)

	return mesh_instance


func _add_box_to_parent(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation = rotation
	mesh_instance.set_surface_override_material(0, material)
	parent.add_child(mesh_instance)

	return mesh_instance


func _add_cylinder(
	node_name: String,
	position: Vector3,
	radius: float,
	height: float,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	generation_root.add_child(instance)
	return instance


func _add_cylinder_to_parent(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	radius: float,
	height: float,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	parent.add_child(instance)
	return instance


func _add_sphere(
	node_name: String,
	position: Vector3,
	radius: float,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	generation_root.add_child(instance)
	return instance


func _add_sphere_to_parent(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	radius: float,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.set_surface_override_material(0, material)
	parent.add_child(instance)
	return instance


# ================================================================
# Material factories
# ================================================================

func _make_material(color: Color) -> StandardMaterial3D:
	var cache_key: String = "#" + color.to_html(false)
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Subtle noise texture for wall surface variation
	var wall_noise := FastNoiseLite.new()
	wall_noise.seed = 7777
	wall_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wall_noise.frequency = 0.03
	var wall_noise_tex := NoiseTexture2D.new()
	wall_noise_tex.noise = wall_noise
	wall_noise_tex.seamless = true
	wall_noise_tex.width = 256
	wall_noise_tex.height = 256
	material.roughness_texture = wall_noise_tex

	_material_cache[cache_key] = material
	return material


func _make_floor_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.30
	material.roughness = 0.35

	# Procedural grid texture — subtle sci-fi gallery floor
	var grid_size := 512
	var grid_image := Image.create(grid_size, grid_size, false, Image.FORMAT_RGBA8)
	grid_image.fill(Color.WHITE)
	var grid_spacing := 64
	var grid_line_color := Color(0.65, 0.65, 0.68, 1.0)
	var grid_line_width := 1
	for gx in range(0, grid_size, grid_spacing):
		for y in range(grid_size):
			for lw in range(grid_line_width):
				if gx + lw < grid_size:
					grid_image.set_pixel(gx + lw, y, grid_line_color)
	for gy in range(0, grid_size, grid_spacing):
		for x in range(grid_size):
			for lw in range(grid_line_width):
				if gy + lw < grid_size:
					grid_image.set_pixel(x, gy + lw, grid_line_color)
	var grid_texture := ImageTexture.create_from_image(grid_image)
	material.albedo_texture = grid_texture

	# Noise roughness map for subtle surface variation
	var noise := FastNoiseLite.new()
	noise.seed = 12345
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	noise_tex.width = 512
	noise_tex.height = 512
	material.roughness_texture = noise_tex

	# Normal map from noise for surface detail
	var normal_noise := FastNoiseLite.new()
	normal_noise.seed = 54321
	normal_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	normal_noise.frequency = 0.08
	var normal_noise_tex := NoiseTexture2D.new()
	normal_noise_tex.noise = normal_noise
	normal_noise_tex.seamless = true
	normal_noise_tex.as_normal_map = true
	normal_noise_tex.width = 512
	normal_noise_tex.height = 512
	material.normal_map = normal_noise_tex
	material.normal_map_scale = 0.15

	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.uv1_scale = Vector3(4.0, 4.0, 4.0)

	return material


func _make_emission_material(color: Color, energy_multiplier: float = 1.8) -> StandardMaterial3D:
	var cache_key: String = "#" + color.to_html(false) + ":e%.1f" % energy_multiplier
	if _emission_material_cache.has(cache_key):
		return _emission_material_cache[cache_key]

	var material: StandardMaterial3D = _make_material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy_multiplier
	# Bloom-friendly: disable roughness texture noise on emissive surfaces
	material.roughness_texture = null
	material.roughness = 0.3
	material.metallic = 0.1
	# Boost HDR contribution for glow pipeline (4.6+ pre-tonemap bloom)
	material.emission_operator = BaseMaterial3D.EMISSION_OP_ADD

	_emission_material_cache[cache_key] = material
	return material


func _make_glass_material(tint: Color = Color(0.6, 0.8, 0.9)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.8
	material.roughness = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_metallic_material(color: Color = Color(0.5, 0.5, 0.55)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.85
	material.roughness = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# ================================================================
# Utility helpers
# ================================================================

func _vector3_from_array(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return Vector3.ZERO

	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _color_from_hex(value: Variant) -> Color:
	if typeof(value) != TYPE_STRING:
		return Color.WHITE

	return Color.html(value)


func _palette_color(palette: Array, index: int, fallback: Color) -> Color:
	if palette.is_empty():
		return fallback

	var raw_color: Variant = palette[index % palette.size()]
	if typeof(raw_color) != TYPE_STRING:
		return fallback

	return Color.html(raw_color)
