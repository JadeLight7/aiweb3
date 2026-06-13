"""
NFT Art Generator — 为每个展位生成独特的程序化 NFT 艺术图片

Uses Python + PIL to create visually rich procedural artwork for each booth,
then saves them as PNG files that Godot's SceneBuilder can load as textures.

Usage:
    python generate_nft_art.py
"""
import json
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DEMOS_DIR = Path(__file__).parent.parent
SHARED_DIR = DEMOS_DIR / "godot" / "shared"
SCENE_SPEC = SHARED_DIR / "scene_spec.json"
ART_DIR = SHARED_DIR / "art"
ART_SIZE = (512, 640)  # Higher res than Godot's 256x320


def load_scene_spec() -> dict:
    with open(SCENE_SPEC) as f:
        return json.load(f)


def hex_to_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def sample_gradient(colors: list, t: float) -> tuple:
    if not colors:
        return (128, 128, 128)
    if len(colors) == 1:
        return colors[0]
    t = max(0.0, min(1.0, t))
    idx = t * (len(colors) - 1)
    lo = int(idx)
    hi = min(lo + 1, len(colors) - 1)
    frac = idx - lo
    return tuple(
        int(colors[lo][c] + (colors[hi][c] - colors[lo][c]) * frac)
        for c in range(3)
    )


def lerp_color(c1: tuple, c2: tuple, t: float) -> tuple:
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


# ================================================================
# 9 Art Styles
# ================================================================

def generate_fractal(seed: int, colors: list, size: tuple) -> Image:
    """Mandelbrot/Julia set fractal with color mapping"""
    rng = random.Random(seed)
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()

    # Julia set parameters
    zoom = rng.uniform(0.8, 2.0)
    cx = rng.uniform(-0.8, 0.3)
    cy = rng.uniform(-0.5, 0.5)
    ox = rng.uniform(-0.3, 0.3)
    oy = rng.uniform(-0.3, 0.3)
    max_iter = 120

    for y in range(h):
        for x in range(w):
            zr = (x / w - 0.5 + ox) * zoom * 3
            zi = (y / h - 0.5 + oy) * zoom * 3
            it = 0
            while zr * zr + zi * zi < 4 and it < max_iter:
                zr, zi = zr * zr - zi * zi + cx, 2 * zr * zi + cy
                it += 1
            if it == max_iter:
                pixels[x, y] = colors[0] if colors else (0, 0, 0)
            else:
                t = (it / max_iter) ** 0.6
                pixels[x, y] = sample_gradient(colors, t)

    return img


def generate_nebula(seed: int, colors: list, size: tuple) -> Image:
    """Space nebula effect with multiple noise layers and stars"""
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    rng = random.Random(seed)

    # Multi-octave noise via sin-based pseudo-noise
    def noise2d(x, y, freq, phase):
        return (math.sin(x * freq + phase) * math.cos(y * freq * 0.7 + phase * 1.3) + 1) * 0.5

    phases = [rng.uniform(0, 100) for _ in range(6)]
    freqs = [0.01, 0.02, 0.04, 0.008, 0.03, 0.015]

    for y in range(h):
        for x in range(w):
            val = 0
            for i in range(6):
                val += noise2d(x, y, freqs[i], phases[i]) * (0.5 ** (i // 2))
            val = val / 3.0

            # Map to colors with smooth transition
            t = max(0, min(1, val))
            c = sample_gradient(colors, t)

            # Add depth variation
            dx = (x / w - 0.5) * 2
            dy = (y / h - 0.5) * 2
            edge = 1.0 - (dx*dx + dy*dy) * 0.3
            c = tuple(max(0, min(255, int(v * edge))) for v in c)
            pixels[x, y] = c

    # Add stars
    for _ in range(200):
        sx, sy = rng.randint(0, w-1), rng.randint(0, h-1)
        brightness = rng.randint(180, 255)
        size_s = rng.choice([1, 1, 1, 2])
        for dx in range(size_s):
            for dy in range(size_s):
                px, py = sx+dx, sy+dy
                if 0 <= px < w and 0 <= py < h:
                    base = pixels[px, py]
                    pixels[px, py] = tuple(min(255, b + brightness//2) for b in base)

    return img


def generate_flow_field(seed: int, colors: list, size: tuple) -> Image:
    """Organic flowing line patterns"""
    w, h = size
    img = Image.new("RGB", size, colors[0] if colors else (10, 10, 30))
    draw = ImageDraw.Draw(img)
    rng = random.Random(seed)

    def angle_at(x, y):
        return (math.sin(x * 0.008 + seed * 0.1) * math.cos(y * 0.006) +
                math.sin((x + y) * 0.005) * 0.5) * math.pi * 2

    for _ in range(300):
        x = rng.uniform(0, w)
        y = rng.uniform(0, h)
        color = colors[rng.randint(0, len(colors)-1)] if colors else (100, 100, 255)
        alpha_color = tuple(min(255, c + 30) for c in color)
        points = []

        for step in range(80):
            a = angle_at(x, y)
            x += math.cos(a) * 2.5
            y += math.sin(a) * 2.5
            if x < 0 or x >= w or y < 0 or y >= h:
                break
            points.append((x, y))

        if len(points) > 2:
            draw.line(points, fill=alpha_color, width=2)

    return img


def generate_voronoi(seed: int, colors: list, size: tuple) -> Image:
    """Voronoi cell diagram with glowing edges"""
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    rng = random.Random(seed)

    num_cells = 15 + seed % 10
    points = [(rng.randint(0, w), rng.randint(0, h)) for _ in range(num_cells)]
    point_colors = [colors[i % len(colors)] if colors else (128,128,128) for i in range(num_cells)]

    for y in range(h):
        for x in range(w):
            dists = sorted([(abs(x-px)**2 + abs(y-py)**2, i) for i, (px, py) in enumerate(points)])
            d1, i1 = dists[0]
            d2, _ = dists[1]
            edge = math.sqrt(d2) - math.sqrt(d1)

            if edge < 2.5:
                pixels[x, y] = (255, 255, 255)
            else:
                t = math.sqrt(d1) / 200
                base = point_colors[i1]
                pixels[x, y] = tuple(max(0, min(255, int(c * (0.4 + 0.6 * (1-t))))) for c in base)

    return img


def generate_mandala(seed: int, colors: list, size: tuple) -> Image:
    """Radial symmetry mandala pattern"""
    w, h = size
    img = Image.new("RGB", size, (5, 5, 15))
    draw = ImageDraw.Draw(img)
    rng = random.Random(seed)
    cx, cy = w // 2, h // 2
    segments = rng.choice([6, 8, 10, 12, 16])

    for layer in range(8):
        radius = (layer + 1) * min(w, h) // 18
        color = colors[layer % len(colors)] if colors else (128, 128, 200)
        line_w = max(1, 4 - layer // 2)

        for seg in range(segments):
            angle = 2 * math.pi * seg / segments
            # Draw arcs and radial lines
            x1 = cx + int(radius * math.cos(angle))
            y1 = cy + int(radius * math.sin(angle))
            x2 = cx + int(radius * math.cos(angle + 2 * math.pi / segments))
            y2 = cy + int(radius * math.sin(angle + 2 * math.pi / segments))

            draw.line([(cx, cy), (x1, y1)], fill=color, width=line_w)
            draw.line([(x1, y1), (x2, y2)], fill=color, width=line_w)

            # Decorative dots at intersections
            dot_r = max(2, 6 - layer)
            draw.ellipse([x1-dot_r, y1-dot_r, x1+dot_r, y1+dot_r], fill=color)

    # Central ornament
    for r in range(20, 5, -3):
        c = sample_gradient(colors, r / 20) if colors else (200, 200, 255)
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=c, width=2)

    return img


def generate_geometric(seed: int, colors: list, size: tuple) -> Image:
    """Abstract geometric composition"""
    w, h = size
    img = Image.new("RGB", size, colors[0] if colors else (20, 20, 40))
    draw = ImageDraw.Draw(img)
    rng = random.Random(seed)

    # Large background triangles
    for _ in range(6):
        pts = [(rng.randint(0, w), rng.randint(0, h)) for _ in range(3)]
        c = colors[rng.randint(0, len(colors)-1)] if colors else (100, 100, 200)
        alpha = rng.randint(80, 200)
        overlay = Image.new("RGB", size, c)
        mask = Image.new("L", size, alpha)
        draw_temp = ImageDraw.Draw(mask)
        draw_temp.polygon(pts, fill=alpha)
        img = Image.composite(overlay, img, mask)

    draw = ImageDraw.Draw(img)

    # Circles
    for _ in range(8):
        cx, cy = rng.randint(0, w), rng.randint(0, h)
        r = rng.randint(20, 120)
        c = colors[rng.randint(0, len(colors)-1)] if colors else (200, 200, 100)
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=c, width=3)

    # Lines
    for _ in range(12):
        x1, y1 = rng.randint(0, w), rng.randint(0, h)
        x2, y2 = rng.randint(0, w), rng.randint(0, h)
        c = colors[rng.randint(0, len(colors)-1)] if colors else (255, 200, 100)
        draw.line([(x1, y1), (x2, y2)], fill=c, width=2)

    # Small rectangles
    for _ in range(10):
        x, y = rng.randint(0, w), rng.randint(0, h)
        bw, bh = rng.randint(10, 60), rng.randint(10, 60)
        c = colors[rng.randint(0, len(colors)-1)] if colors else (100, 255, 200)
        draw.rectangle([x, y, x+bw, y+bh], fill=c)

    return img


def generate_plasma(seed: int, colors: list, size: tuple) -> Image:
    """Sinusoidal plasma color mixing"""
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    rng = random.Random(seed)
    f1, f2, f3 = rng.uniform(0.01, 0.05), rng.uniform(0.01, 0.04), rng.uniform(0.005, 0.03)
    p1, p2, p3 = rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28)

    for y in range(h):
        for x in range(w):
            v1 = math.sin(x * f1 + p1) * 0.5 + 0.5
            v2 = math.sin(y * f2 + p2) * 0.5 + 0.5
            v3 = math.sin((x + y) * f3 + p3) * 0.5 + 0.5
            t = (v1 + v2 + v3) / 3.0
            pixels[x, y] = sample_gradient(colors, t)

    return img


def generate_pixel_art(seed: int, colors: list, size: tuple) -> Image:
    """Retro pixel art grid"""
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    rng = random.Random(seed)
    pixel_size = 16
    cols = w // pixel_size
    rows = h // pixel_size

    # Generate a small grid and scale up
    for gy in range(rows):
        for gx in range(cols):
            # Symmetric pattern
            mirror_gx = cols - 1 - gx if gx > cols // 2 else gx
            rng_state = hash((mirror_gx, gy, seed))
            rng2 = random.Random(rng_state)
            c = colors[rng2.randint(0, len(colors)-1)] if colors else (128, 128, 128)

            # Add some pattern constraints
            dist_from_center = math.sqrt((gx - cols/2)**2 + (gy - rows/2)**2)
            if dist_from_center > rows * 0.45:
                c = colors[0] if colors else (10, 10, 20)

            for dy in range(pixel_size):
                for dx in range(pixel_size):
                    px, py = gx * pixel_size + dx, gy * pixel_size + dy
                    if 0 <= px < w and 0 <= py < h:
                        pixels[px, py] = c

    return img


def generate_gradient_noise(seed: int, colors: list, size: tuple) -> Image:
    """Layered noise with smooth color transitions"""
    w, h = size
    img = Image.new("RGB", size)
    pixels = img.load()
    rng = random.Random(seed)

    # Base gradient
    angle = rng.uniform(0, math.pi)
    for y in range(h):
        for x in range(w):
            t = (x * math.cos(angle) / w + y * math.sin(angle) / h)
            t = max(0, min(1, t))
            pixels[x, y] = sample_gradient(colors, t)

    # Noise overlay using sin-based pseudo-random
    freq = rng.uniform(0.01, 0.03)
    phase = rng.uniform(0, 100)
    for y in range(h):
        for x in range(w):
            n = (math.sin(x * freq + phase + y * 0.01) +
                 math.sin(y * freq * 1.3 + phase * 0.7) +
                 math.sin((x + y) * freq * 0.5)) / 3.0
            n = n * 0.5 + 0.5
            base = pixels[x, y]
            tint = colors[int(n * (len(colors) - 1))] if colors else (128, 128, 128)
            pixels[x, y] = lerp_color(base, tint, 0.4)

    return img


# ================================================================
# Style dispatcher
# ================================================================

STYLE_MAP = {
    "gradient_noise": generate_gradient_noise,
    "voronoi": generate_voronoi,
    "geometric": generate_geometric,
    "plasma": generate_plasma,
    "mandala": generate_mandala,
    "pixel_art": generate_pixel_art,
    "fractal": generate_fractal,
    "nebula": generate_nebula,
    "flow_field": generate_flow_field,
}


def post_process(img: Image, seed: int) -> Image:
    """Apply post-processing: vignette + bloom + grain"""
    w, h = img.size
    rng = random.Random(seed * 997)

    # Vignette
    from PIL import ImageFilter
    for y in range(h):
        for x in range(w):
            dx = (x / w - 0.5) * 2
            dy = (y / h - 0.5) * 2
            d = math.sqrt(dx*dx + dy*dy)
            factor = max(0.35, 1.0 - d * d * 0.65)
            r, g, b = img.getpixel((x, y))
            img.putpixel((x, y), (int(r*factor), int(g*factor), int(b*factor)))

    # Bloom (cheap: blur bright areas and screen-blend)
    bright = img.point(lambda p: min(255, max(0, (p - 128) * 2)))
    bloom = bright.filter(ImageFilter.GaussianBlur(radius=8))
    img = Image.blend(img, Image.frombytes("RGB", (w,h),
        bytes(min(255, a+b) for a, b in zip(img.tobytes(), bloom.tobytes()))), 0.3)

    return img


def generate_all_art():
    """Generate NFT art for all booths in scene_spec.json"""
    ART_DIR.mkdir(parents=True, exist_ok=True)
    spec = load_scene_spec()

    for booth in spec.get("booths", []):
        nft = booth.get("nft", {})
        art_style = nft.get("art_style", "gradient_noise")
        art_seed = int(nft.get("art_seed", 42))
        art_colors_hex = nft.get("art_colors", ["#C5A04E", "#2E4A2E", "#1A0F0A"])
        art_colors = [hex_to_rgb(c) for c in art_colors_hex]
        booth_id = booth.get("id", "unknown")
        nft_name = nft.get("name", "Untitled")

        print(f"Generating: {booth_id} — '{nft_name}' ({art_style}, seed={art_seed})")

        generator = STYLE_MAP.get(art_style, generate_gradient_noise)
        img = generator(art_seed, art_colors, ART_SIZE)
        img = post_process(img, art_seed)

        out_path = ART_DIR / f"{booth_id}.png"
        img.save(out_path, "PNG")
        print(f"  → Saved: {out_path} ({img.size[0]}x{img.size[1]})")

    print(f"\n✅ Generated {len(spec.get('booths', []))} NFT artworks in {ART_DIR}/")


if __name__ == "__main__":
    generate_all_art()
