extends SceneTree
## Writes the shipped bot profiles to content/ai/.
##
##   godot --headless --path godot --script res://tools/write_bot_profiles.gd
##
## Generated rather than hand-written so the .tres and BotProfileDef cannot
## drift apart: a field added to the resource and forgotten here shows up as a
## default, not as a silent absence. Re-run it after changing the defaults.
##
## The files are content once written. Editing them in the inspector is the
## intended way to tune a tier - this exists to create them, not to own them.

const OUT_DIR: String = "res://content/ai"

func _initialize() -> void:
	var written: int = 0
	for profile: BotProfileDef in [_standard()]:
		var path: String = "%s/bot_profile_%s.tres" % [OUT_DIR, profile.id]
		var failure: Error = ResourceSaver.save(profile, path)
		if failure != OK:
			print("FAILED %s (error %d)" % [path, failure])
			continue
		print("wrote %s" % path)
		written += 1
	print("%d profile(s)" % written)
	quit(0)

## The default opponent. Deliberately competent rather than punishing: the
## profile exists to make the slice playable alone, and a bot that wins every
## exchange teaches nothing about whether the GAME is any good.
func _standard() -> BotProfileDef:
	var profile: BotProfileDef = BotProfileDef.new()
	profile.id = &"standard"
	profile.display_name = "Standard"
	return profile
