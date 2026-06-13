## ArtGenerator — 9 procedural art algorithms with post-processing
##
## Generates unique NFT artwork textures for each booth using mathematical
## algorithms: gradient_noise, voronoi, geometric, plasma, mandala,
## pixel_art, fractal, nebula, and flow_field.
##
## CCGS Skills Applied: procedural-generation, gdscript-patterns
##
## Usage:
##   var generator = ArtGenerator.new()
##   var texture = generator.generate("gradient_noise", 42, colors, Vector2i(256, 320))
extends RefCounted
class_name ArtGenerator

## Generate procedural art texture for the given style.
## [br][param style] — one of 9 art style strings
## [br][param seed_val] — random seed for reproducibility
## [br][param colors] — array of Color to use
## [br][param size] — texture dimensions
## [br]Returns: ImageTexture ready for use as albedo/emission
func generate(style: String, seed_val: int, colors: Array, size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Fill with base gradient
	_fill_base_gradient(image, colors, rng)

	# Apply style-specific algorithm
	match style:
		"gradient_noise":
			_apply_gradient_noise(image, colors, rng)
		"voronoi":
			_apply_voronoi(image, colors, rng)
		"geometric":
			_apply_geometric(image, colors, rng)
		"plasma":
			_apply_plasma(image, colors, rng)
		"mandala":
			_apply_mandala(image, colors, rng)
		"pixel_art":
			_apply_pixel_art(image, colors, rng)
		"fractal":
			_apply_fractal(image, colors, rng)
		"nebula":
			_apply_nebula(image, colors, rng)
		"flow_field":
			_apply_flow_field(image, colors, rng)
		_:
			_apply_gradient_noise(image, colors, rng)

	# Post-processing pipeline
	_post_process_saturation_boost(image, 1.35)
	_post_process_vignette(image, 0.45)
	_post_process_film_grain(image, 0.04, rng)

	return ImageTexture.create_from_image(image)


# ================================================================
# Base gradient fill
# ================================================================

func _fill_base_gradient(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	for y in range(h):
		var t: float = float(y) / float(h)
		var color: Color = _sample_gradient(colors, t)
		for x in range(w):
			image.set_pixel(x, y, color)


func _sample_gradient(colors: Array, t: float) -> Color:
	if colors.is_empty():
		return Color.WHITE
	if colors.size() == 1:
		return colors[0]
	var scaled: float = t * (colors.size() - 1)
	var idx: int = int(scaled)
	var frac: float = scaled - float(idx)
	if idx >= colors.size() - 1:
		return colors[colors.size() - 1]
	return colors[idx].lerp(colors[idx + 1], frac)


# ================================================================
# Style: gradient_noise — layered simplex noise with color blending
# ================================================================

func _apply_gradient_noise(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02

	for y in range(h):
		for x in range(w):
			var n: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var base: Color = image.get_pixel(x, y)
			var noise_color: Color = _sample_gradient(colors, n)
			image.set_pixel(x, y, base.lerp(noise_color, 0.65))


# ================================================================
# Style: voronoi — cellular pattern with colored regions
# ================================================================

func _apply_voronoi(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var num_cells: int = 12 + rng.randi() % 8

	var points: Array = []
	var point_colors: Array = []
	for _i in range(num_cells):
		points.append(Vector2(rng.randf() * float(w), rng.randf() * float(h)))
		point_colors.append(colors[rng.randi() % colors.size()] if colors else Color.WHITE)

	for y in range(h):
		for x in range(w):
			var min_dist: float = 999999.0
			var second_dist: float = 999999.0
			var closest: int = 0
			for i in range(points.size()):
				var d: float = Vector2(float(x), float(y)).distance_squared_to(points[i])
				if d < min_dist:
					second_dist = min_dist
					min_dist = d
					closest = i
				elif d < second_dist:
					second_dist = d

			var edge_factor: float = sqrt(second_dist) - sqrt(min_dist)
			var base: Color = image.get_pixel(x, y)
			if edge_factor < 3.0:
				image.set_pixel(x, y, Color.WHITE)
			else:
				image.set_pixel(x, y, base.lerp(point_colors[closest], 0.7))


# ================================================================
# Style: geometric — triangles, circles, lines with sharp edges
# ================================================================

func _apply_geometric(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var bounds := Vector2i(w, h)

	# Random triangles
	for _i in range(8 + rng.randi() % 6):
		var p1 := Vector2(rng.randf() * float(w), rng.randf() * float(h))
		var p2 := Vector2(rng.randf() * float(w), rng.randf() * float(h))
		var p3 := Vector2(rng.randf() * float(w), rng.randf() * float(h))
		var col: Color = colors[rng.randi() % colors.size()] if colors else Color.WHITE
		_fill_triangle(image, p1, p2, p3, col, bounds)

	# Random circles
	for _i in range(5 + rng.randi() % 4):
		var cx: float = rng.randf() * float(w)
		var cy: float = rng.randf() * float(h)
		var radius: float = rng.randf() * 60.0 + 20.0
		var col: Color = colors[rng.randi() % colors.size()] if colors else Color.WHITE
		_fill_circle(image, Vector2(cx, cy), radius, col, bounds)

	# Random lines
	for _i in range(4 + rng.randi() % 4):
		var x0: int = rng.randi() % w
		var y0: int = rng.randi() % h
		var x1: int = rng.randi() % w
		var y1: int = rng.randi() % h
		var col: Color = colors[rng.randi() % colors.size()] if colors else Color.WHITE
		_draw_line(image, x0, y0, x1, y1, 3, col)


# ================================================================
# Style: plasma — sinusoidal color mixing
# ================================================================

func _apply_plasma(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var freq1: float = rng.randf() * 0.05 + 0.02
	var freq2: float = rng.randf() * 0.04 + 0.015
	var phase1: float = rng.randf() * TAU
	var phase2: float = rng.randf() * TAU

	for y in range(h):
		for x in range(w):
			var v1: float = sin(float(x) * freq1 + phase1) * 0.5 + 0.5
			var v2: float = sin(float(y) * freq2 + phase2) * 0.5 + 0.5
			var v3: float = sin((float(x) + float(y)) * freq1 * 0.5) * 0.5 + 0.5
			var t: float = (v1 + v2 + v3) / 3.0
			var base: Color = image.get_pixel(x, y)
			var plasma_color: Color = _sample_gradient(colors, t)
			image.set_pixel(x, y, base.lerp(plasma_color, 0.75))


# ================================================================
# Style: mandala — radial symmetry patterns
# ================================================================

func _apply_mandala(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var max_radius: float = minf(float(w), float(h)) * 0.45
	var segments: int = 8 + (rng.randi() % 8) * 2  # Must be even

	for y in range(h):
		for x in range(w):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			var angle: float = fmod(atan2(dy, dx) + PI, TAU)
			var segment_angle: float = TAU / float(segments)
			var seg_idx: int = int(floor(angle / segment_angle))
			var local_angle: float = fmod(angle, segment_angle)
			var mirrored: float = local_angle if seg_idx % 2 == 0 else segment_angle - local_angle

			var r: float = dist / max_radius
			if r > 1.0:
				continue
			var t: float = (mirrored / segment_angle + r) * 0.5
			var base: Color = image.get_pixel(x, y)
			var mandala_color: Color = _sample_gradient(colors, fmod(t, 1.0))
			image.set_pixel(x, y, base.lerp(mandala_color, 0.7))


# ================================================================
# Style: pixel_art — blocky retro pixel grid
# ================================================================

func _apply_pixel_art(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var pixel_size: int = 8 + rng.randi() % 12

	for py in range(0, h, pixel_size):
		for px in range(0, w, pixel_size):
			var col: Color = colors[rng.randi() % colors.size()] if colors else Color.WHITE
			for dy in range(mini(pixel_size, h - py)):
				for dx in range(mini(pixel_size, w - px)):
					image.set_pixel(px + dx, py + dy, col)


# ================================================================
# Style: fractal — recursive geometric patterns
# ================================================================

func _apply_fractal(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var max_iter: int = 80
	var zoom: float = rng.randf() * 0.5 + 1.0
	var offset_x: float = rng.randf() * 0.5 - 0.25
	var offset_y: float = rng.randf() * 0.5 - 0.25

	for y in range(h):
		for x in range(w):
			var zr: float = 0.0
			var zi: float = 0.0
			var cr: float = (float(x) / float(w) - 0.5 + offset_x) * zoom * 3.0
			var ci: float = (float(y) / float(h) - 0.5 + offset_y) * zoom * 3.0
			var iter: int = 0

			while zr * zr + zi * zi < 4.0 and iter < max_iter:
				var tmp: float = zr * zr - zi * zi + cr
				zi = 2.0 * zr * zi + ci
				zr = tmp
				iter += 1

			if iter == max_iter:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0))
			else:
				var t: float = float(iter) / float(max_iter)
				var col: Color = _sample_gradient(colors, t)
				image.set_pixel(x, y, col)


# ================================================================
# Style: nebula — space-like cloud formations
# ================================================================

func _apply_nebula(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()

	# Multiple noise layers for cloud effect
	var noise1 := FastNoiseLite.new()
	noise1.seed = rng.randi()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise1.frequency = 0.015

	var noise2 := FastNoiseLite.new()
	noise2.seed = rng.randi() + 1000
	noise2.noise_type = FastNoiseLite.TYPE_PERLIN
	noise2.frequency = 0.025

	for y in range(h):
		for x in range(w):
			var n1: float = noise1.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2: float = noise2.get_noise_2d(float(x) * 1.5, float(y) * 1.5) * 0.5 + 0.5
			var t: float = (n1 * 0.6 + n2 * 0.4)
			var base: Color = image.get_pixel(x, y)
			var nebula_color: Color = _sample_gradient(colors, t)
			var alpha: float = smoothstep(0.3, 0.7, t)
			image.set_pixel(x, y, base.lerp(nebula_color, alpha))


# ================================================================
# Style: flow_field — organic flowing line patterns
# ================================================================

func _apply_flow_field(image: Image, colors: Array, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.008

	var num_lines: int = 150 + rng.randi() % 100
	var line_length: int = 40 + rng.randi() % 60

	for _i in range(num_lines):
		var x: float = rng.randf() * float(w)
		var y: float = rng.randf() * float(h)
		var col: Color = colors[rng.randi() % colors.size()] if colors else Color.WHITE

		for _step in range(line_length):
			if x < 0 or x >= float(w) or y < 0 or y >= float(h):
				break
			var angle: float = noise.get_noise_2d(x, y) * TAU
			var ix: int = int(x)
			var iy: int = int(y)
			var base: Color = image.get_pixel(ix, iy)
			image.set_pixel(ix, iy, base.lerp(col, 0.3))
			x += cos(angle) * 2.0
			y += sin(angle) * 2.0


# ================================================================
# Post-processing effects
# ================================================================

## Boost color saturation for more vivid artwork
func _post_process_saturation_boost(image: Image, factor: float) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	for y in range(h):
		for x in range(w):
			var c: Color = image.get_pixel(x, y)
			var gray: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			image.set_pixel(x, y, Color(
				clampf(gray + (c.r - gray) * factor, 0.0, 1.0),
				clampf(gray + (c.g - gray) * factor, 0.0, 1.0),
				clampf(gray + (c.b - gray) * factor, 0.0, 1.0),
				c.a
			))


## Add vignette darkening at edges
func _post_process_vignette(image: Image, intensity: float) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var max_dist: float = sqrt(cx * cx + cy * cy)

	for y in range(h):
		for x in range(w):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var dist: float = sqrt(dx * dx + dy * dy) / max_dist
			var darken: float = 1.0 - dist * dist * intensity
			var c: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * darken, c.g * darken, c.b * darken, c.a))


## Add subtle film grain for texture
func _post_process_film_grain(image: Image, intensity: float, rng: RandomNumberGenerator) -> void:
	var w: int = image.get_width()
	var h: int = image.get_height()
	for y in range(h):
		for x in range(w):
			var grain: float = rng.randf() * intensity - intensity * 0.5
			var c: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(
				clampf(c.r + grain, 0.0, 1.0),
				clampf(c.g + grain, 0.0, 1.0),
				clampf(c.b + grain, 0.0, 1.0),
				c.a
			))


# ================================================================
# Drawing primitives
# ================================================================

func _fill_triangle(image: Image, p1: Vector2, p2: Vector2, p3: Vector2, col: Color, bounds: Vector2i) -> void:
	var min_y: int = maxi(int(minf(p1.y, minf(p2.y, p3.y))), 0)
	var max_y: int = mini(int(maxf(p1.y, maxf(p2.y, p3.y))), bounds.y - 1)

	for py in range(min_y, max_y + 1):
		var intersections: Array = []
		var y: float = float(py) + 0.5
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


func _fill_circle(image: Image, center: Vector2, radius: float, col: Color, bounds: Vector2i) -> void:
	var r2: float = radius * radius
	var min_y: int = maxi(int(center.y - radius), 0)
	var max_y: int = mini(int(center.y + radius), bounds.y - 1)
	for py in range(min_y, max_y + 1):
		var dy: float = float(py) - center.y
		var dx_span: float = sqrt(maxf(r2 - dy * dy, 0.0))
		var row_min_x: int = maxi(int(center.x - dx_span), 0)
		var row_max_x: int = mini(int(center.x + dx_span), bounds.x - 1)
		if row_max_x > row_min_x:
			image.fill_rect(Rect2i(row_min_x, py, row_max_x - row_min_x + 1, 1), col)


func _draw_line(image: Image, x0: int, y0: int, x1: int, y1: int, thickness: int, col: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var half_t: int = thickness / 2
	var w: int = image.get_width()
	var h: int = image.get_height()

	while true:
		for ty: int in range(-half_t, half_t + 1):
			for tx: int in range(-half_t, half_t + 1):
				var px: int = x0 + tx
				var py: int = y0 + ty
				if px >= 0 and px < w and py >= 0 and py < h:
					image.set_pixel(px, py, col)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
