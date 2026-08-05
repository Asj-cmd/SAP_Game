class_name FrameCapture
extends RefCounted
## Saves what is actually on the screen to a PNG.
##
## Exists because a green test suite says nothing about whether anything was
## drawn. Two renderer regressions have now shipped past one, because nothing
## in the loop ever looked at the screen - the rules were right, the tests were
## right, and the window was blank. So "I have viewed a frame" is part of
## finishing visual work now, not a courtesy.
##
## Deliberately captures the ROOT viewport rather than a camera or a subview:
## the question being answered is "what would a player see", and the failures
## worth catching are exactly the ones that live between a correct 3D scene and
## the window - a viewport with no camera, a near plane that eats the world, an
## opaque layer covering it all.
##
## Debug presentation. It reads a viewport and writes a file; nothing it does
## can change what the rules decide.

const DEFAULT_PATH: String = "user://capture.png"
## Long enough for the level to build, the roster to spawn and the camera to
## settle onto a body. A frame captured at t=0 shows a loading screen and
## proves nothing.
const DEFAULT_DELAY: float = 2.0

var requested: bool = false
var path: String = DEFAULT_PATH
var delay: float = DEFAULT_DELAY
var quit_after: bool = false
## Hold the grab key just before capturing.
##
## A screenshot cannot press a button, and the state worth photographing here -
## an action asked for and not yet answered - only exists while one is held. The
## key is injected through the ordinary input path rather than by reaching past
## it, so what the frame shows is what a player would see.
var grab: bool = false
## Turn the bot path overlay on before capturing. Same reason as `grab`: the
## state worth photographing is behind a key nobody can press unattended.
var paths: bool = false

## Places to stand the camera, and what to point it at.
##
## Without these the only view available is the one behind whoever spawned,
## which makes every defect away from the spawn point something you inspect by
## proxy - walking a bot past it and hoping. That pattern has cost this project
## three wrong turns, and the art phase will want a hundred views a day.
##
## A LIST rather than one, because the questions worth asking visually are
## nearly always plural: eighteen rooms of wall joins is eighteen shots, and
## taking them one command at a time is how people stop taking them.
var eyes: PackedVector3Array = PackedVector3Array()
var looks: PackedVector3Array = PackedVector3Array()

## Where shot `index` should be written when several were asked for.
func path_for(index: int) -> String:
	if eyes.size() <= 1:
		return path
	var extension: String = path.get_extension()
	var stem: String = path.get_basename()
	return "%s_%d.%s" % [stem, index + 1, extension if extension != "" else "png"]

## Reads the flags after `--` on the command line:
##
##   --capture                 grab a frame, save it, and exit
##   --capture-path=<file>     where to write it
##   --capture-delay=<seconds> how long to wait first
##   --capture-at=x,y,z        stand the camera here instead of behind a body
##   --capture-look=x,y,z      point the preceding --capture-at at this
##
## `--capture-at` may be repeated; each one is a separate shot, numbered
## `<name>_1.png`, `<name>_2.png`. A `--capture-look` applies to the
## `--capture-at` before it, so the pairs read in order on the command line.
static func from_command_line(args: PackedStringArray) -> FrameCapture:
	var request: FrameCapture = FrameCapture.new()
	for arg: String in args:
		if arg == "--capture":
			request.requested = true
			# An autorun capture is for an unattended run, so it has to end by
			# itself. A window left open blocks whatever asked for the shot.
			request.quit_after = true
		elif arg.begins_with("--capture-path="):
			request.requested = true
			request.path = arg.trim_prefix("--capture-path=")
		elif arg.begins_with("--capture-delay="):
			request.delay = maxf(0.0, float(arg.trim_prefix("--capture-delay=")))
		elif arg == "--capture-paths":
			request.requested = true
			request.quit_after = true
			request.paths = true
		elif arg == "--capture-grab":
			request.requested = true
			request.quit_after = true
			request.grab = true
		elif arg.begins_with("--capture-at="):
			var eye: Vector3 = _point(arg.trim_prefix("--capture-at="))
			request.requested = true
			request.quit_after = true
			request.eyes.append(eye)
			# Straight ahead until told otherwise, so --capture-at alone works.
			request.looks.append(eye + Vector3(0.0, 0.0, -1000.0))
		elif arg.begins_with("--capture-look="):
			if request.eyes.is_empty():
				push_error("frame capture: --capture-look with no --capture-at before it")
				continue
			request.looks[request.looks.size() - 1] = _point(
				arg.trim_prefix("--capture-look="))
	return request

static func _point(text: String) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		push_error("frame capture: expected x,y,z but got '%s'" % text)
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

## Writes the viewport's current contents, and returns the absolute path it
## landed at so a caller can print somewhere findable. Empty on failure.
##
## Must be called after a draw has completed - see await_frame().
static func save(viewport: Viewport, to_path: String) -> String:
	if viewport == null:
		push_error("frame capture: no viewport")
		return ""
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		push_error("frame capture: viewport has no texture yet")
		return ""
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		push_error("frame capture: viewport produced no image")
		return ""
	var failure: Error = image.save_png(to_path)
	if failure != OK:
		push_error("frame capture: could not write %s (error %d)" % [to_path, failure])
		return ""
	return ProjectSettings.globalize_path(to_path)

## One line describing what the shot contains, printed alongside it.
##
## A PNG on its own cannot say whether the frame was blank because the camera
## was wrong or because the level never loaded, and those want opposite fixes.
static func describe(camera: Camera3D, actors: int) -> String:
	if camera == null:
		return "no camera - nothing was rendering"
	return "camera at %s looking %s, %d bodies" % [
		camera.global_position.round(),
		(-camera.global_transform.basis.z).round(),
		actors,
	]
