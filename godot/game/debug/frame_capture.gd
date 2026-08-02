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

## Reads the flags after `--` on the command line:
##
##   --capture                 grab a frame, save it, and exit
##   --capture-path=<file>     where to write it
##   --capture-delay=<seconds> how long to wait first
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
	return request

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
