extends SceneTree
## P3-4: writes the two outdoor textures no CC0 library had in a usable form,
## as seamless 1024 px tiles in `art/textures/generated/`:
##
##   lawn_diff.png     a kept lawn: fine blade grain, soft clumps, faint mowing
##                     stripes (two pairs a tile). Poly Haven's grasses are all
##                     meadow, mud or leaf litter.
##   foliage_diff.png  clipped-leaf speckle for hedges and tree crowns.
##
## Our own work (no licence to record beyond ASSETS.md's "generated" row).
## Deterministic: fixed seeds, so a re-run writes the same pixels.
##   node autobuild/run_tool.mjs make_outdoor_textures
## Then let Godot import once (`--headless --import`).

const SIZE: int = 1024
const OUT_DIR: String = "res://art/textures/generated"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_lawn(), "lawn_diff.png")
	_save(_foliage(), "foliage_diff.png")
	quit(0)

func _save(image: Image, file: String) -> void:
	var path: String = "%s/%s" % [OUT_DIR, file]
	var error: Error = image.save_png(ProjectSettings.globalize_path(path))
	print("%s %s" % ["wrote" if error == OK else "FAILED", path])

## A seamless greyscale layer, values 0..1.
func _layer(kind: FastNoiseLite.NoiseType, frequency: float, noise_seed: int,
		octaves: int = 1) -> Image:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = kind
	noise.frequency = frequency
	noise.seed = noise_seed
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise.get_seamless_image(SIZE, SIZE, false, false, 0.2)

func _lawn() -> Image:
	var blade: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.32, 11)
	var tuft: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.07, 12, 2)
	var patch: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.008, 13, 3)
	var tone: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.012, 14, 2)
	var image: Image = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var deep: Color = Color(0.27, 0.43, 0.2)
	var fresh: Color = Color(0.4, 0.52, 0.24)
	for y: int in SIZE:
		for x: int in SIZE:
			var b: float = blade.get_pixel(x, y).r - 0.5
			var t: float = tuft.get_pixel(x, y).r - 0.5
			var p: float = patch.get_pixel(x, y).r - 0.5
			# Two stripe pairs a tile, with soft edges: the mower's passes.
			var stripe: float = clampf(sin(float(x) / float(SIZE) * TAU * 2.0) * 3.0, -1.0, 1.0)
			var value: float = 1.0 + 0.42 * b + 0.26 * t + 0.16 * p + 0.045 * stripe
			var colour: Color = deep.lerp(fresh, clampf(tone.get_pixel(x, y).r * 1.2 - 0.1 + 0.25 * b, 0.0, 1.0))
			image.set_pixel(x, y, Color(colour.r * value, colour.g * value, colour.b * value))
	image.generate_mipmaps()
	return image

func _foliage() -> Image:
	var cells: Image = _layer(FastNoiseLite.TYPE_CELLULAR, 0.075, 21)
	var grain: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.2, 22)
	var mass: Image = _layer(FastNoiseLite.TYPE_SIMPLEX, 0.012, 23, 3)
	var image: Image = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var shade: Color = Color(0.1, 0.2, 0.09)
	var leaf: Color = Color(0.3, 0.46, 0.2)
	for y: int in SIZE:
		for x: int in SIZE:
			var c: float = cells.get_pixel(x, y).r
			var g: float = grain.get_pixel(x, y).r - 0.5
			var m: float = mass.get_pixel(x, y).r - 0.5
			var lit: float = clampf(c * 1.5 - 0.2 + 0.5 * g + 0.5 * m, 0.0, 1.0)
			image.set_pixel(x, y, shade.lerp(leaf, lit))
	image.generate_mipmaps()
	return image
