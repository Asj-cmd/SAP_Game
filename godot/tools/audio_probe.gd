extends SceneTree
## Debug tool (PT2-4): a rough pitch contour of Ogg Vorbis files, so a jingle that ends
## going up or down can be told apart without listening. Decodes through
## AudioStreamPlayback.mix_audio (no audio driver needed), then per 40 ms window prints
## the loudness and an autocorrelation pitch estimate (80-1200 Hz).
##   node autobuild/run_tool.mjs audio_probe -- <abs path.ogg> [...]

const WINDOW: int = 1764 # 40 ms at 44.1 kHz
const MIN_HZ: float = 80.0
const MAX_HZ: float = 1200.0

## `--ends` prints only the loudness of the first and last 2 s in 0.25 s steps (a loop check).
var _ends_only: bool = false

func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--ends":
			_ends_only = true
		else:
			_probe(arg)
	quit(0)

func _probe(path: String) -> void:
	var stream: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		print("%s: cannot load" % path)
		return
	var rate: float = 44100.0
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(0.0)
	var mono: PackedFloat32Array = PackedFloat32Array()
	var total: int = int(stream.get_length() * rate)
	while mono.size() < total:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, 4096)
		if chunk.is_empty():
			break
		for f: Vector2 in chunk:
			mono.append((f.x + f.y) * 0.5)
	var line: PackedStringArray = PackedStringArray()
	if _ends_only:
		var step: int = int(rate * 0.25)
		for start: int in [0, maxi(mono.size() - step * 8, 0)]:
			for k: int in 8:
				var sum: float = 0.0
				for i: int in step:
					var j: int = start + k * step + i
					if j < mono.size():
						sum += mono[j] * mono[j]
				line.append("%.2f:%d" % [(start + k * step) / rate, int(sqrt(sum / step) * 1000.0)])
		var last_loud: int = mono.size() - 1
		while last_loud > 0 and absf(mono[last_loud]) < 0.01:
			last_loud -= 1
		var first_loud: int = 0
		while first_loud < mono.size() - 1 and absf(mono[first_loud]) < 0.01:
			first_loud += 1
		print("%s (%.2f s, %d frames) sound %.2f..%.2f s  t:rms  %s" % [path.get_file(), stream.get_length(), mono.size(),
				first_loud / rate, last_loud / rate, " ".join(line)])
		return
	var at: int = 0
	while at + WINDOW * 2 <= mono.size():
		var rms: float = 0.0
		for i: int in WINDOW:
			rms += mono[at + i] * mono[at + i]
		rms = sqrt(rms / WINDOW)
		var hz: float = _pitch(mono, at, rate) if rms > 0.01 else 0.0
		line.append("%.2f:%d/%d" % [at / rate, int(hz), int(rms * 1000.0)])
		at += WINDOW
	print("%s (%.2f s)  t:hz/rms  %s" % [path.get_file(), stream.get_length(), " ".join(line)])

func _pitch(mono: PackedFloat32Array, at: int, rate: float) -> float:
	var best_lag: int = 0
	var best: float = 0.0
	var min_lag: int = int(rate / MAX_HZ)
	var max_lag: int = int(rate / MIN_HZ)
	var energy: float = 0.0
	for i: int in WINDOW:
		energy += mono[at + i] * mono[at + i]
	if energy <= 0.0:
		return 0.0
	for lag: int in range(min_lag, max_lag):
		var sum: float = 0.0
		for i: int in WINDOW:
			sum += mono[at + i] * mono[at + i + lag]
		if sum > best:
			best = sum
			best_lag = lag
	# A weak peak is noise or a chord, not a note.
	if best_lag == 0 or best / energy < 0.3:
		return 0.0
	return rate / best_lag
