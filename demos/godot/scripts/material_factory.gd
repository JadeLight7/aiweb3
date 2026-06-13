## MaterialFactory — Cached material creation for 3D scene building
##
## Provides material creation with automatic caching to avoid duplicate
## materials across the scene. Supports standard, emission, floor,
## glass, and metallic material types.
##
## CCGS Skills Applied: godot-optimization (material caching),
## gdscript-patterns (factory pattern)
extends RefCounted
class_name MaterialFactory

var _material_cache: Dictionary = {}
var _floor_material_cache: Dictionary = {}
var _emission_material_cache: Dictionary = {}


## Create a standard wall material with subtle noise roughness. Cached by color.
func make_material(color: Color) -> StandardMaterial3D:
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


## Create a reflective floor material with procedural grid texture.
func make_floor_material(color: Color) -> StandardMaterial3D:
	var cache_key: String = "#" + color.to_html(false)
	if _floor_material_cache.has(cache_key):
		return _floor_material_cache[cache_key]

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

	# Noise roughness map
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

	# Normal map for surface detail
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

	_floor_material_cache[cache_key] = material
	return material


## Create an emissive material for glow effects. Cached by color + energy.
func make_emission_material(color: Color, energy_multiplier: float = 1.8) -> StandardMaterial3D:
	var cache_key: String = "#" + color.to_html(false) + ":e%.1f" % energy_multiplier
	if _emission_material_cache.has(cache_key):
		return _emission_material_cache[cache_key]

	var material: StandardMaterial3D = make_material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy_multiplier
	material.roughness_texture = null
	material.roughness = 0.3
	material.metallic = 0.1
	material.emission_operator = BaseMaterial3D.EMISSION_OP_ADD

	_emission_material_cache[cache_key] = material
	return material


## Create a transparent glass material.
func make_glass_material(tint: Color = Color(0.6, 0.8, 0.9)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.8
	material.roughness = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Create a dark metallic material for fixtures and frames.
func make_metallic_material(color: Color = Color(0.5, 0.5, 0.55)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.85
	material.roughness = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Create a glow gradient texture for environment effects.
func make_glow_gradient(base_color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color.BLACK,
		base_color.lerp(Color.WHITE, 0.5),
		Color.WHITE,
		base_color.lerp(Color.WHITE, 0.8),
		Color.WHITE,
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.4, 0.7, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


## Clear all material caches (call when rebuilding scene).
func clear_caches() -> void:
	_material_cache.clear()
	_floor_material_cache.clear()
	_emission_material_cache.clear()
