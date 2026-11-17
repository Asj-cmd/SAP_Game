extends SceneTree
## Loads the given scripts and reports whether each one parses: a cheap check
## before a capture run, which would otherwise spend its frames on a script error.
##   node autobuild/run_tool.mjs parse_check -- res://game/art/a.gd res://game/art/b.gd

func _initialize() -> void:
	var bad: int = 0
	for path: String in OS.get_cmdline_user_args():
		if not path.begins_with("res://"):
			continue
		var script: Script = load(path) as Script
		var ok: bool = script != null and script.can_instantiate()
		print("%s %s" % ["ok  " if ok else "FAIL", path])
		if not ok:
			bad += 1
	quit(1 if bad > 0 else 0)
