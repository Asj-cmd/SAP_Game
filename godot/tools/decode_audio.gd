extends SceneTree
## Debug tool (PT2-4): decodes an .mp3 / .ogg / .wav to raw 32-bit float stereo PCM at
## 44.1 kHz (interleaved, little-endian), trimming near-silence at both ends, so
## `autobuild/encode_ogg.mjs` can turn it into Ogg Vorbis (there is no ffmpeg here).
##   node autobuild/run_tool.mjs decode_audio <abs in> <abs out.f32> [gain]

const RATE: float = 44100.0
const SILENCE: float = 0.003

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: decode_audio <in> <out.f32> [gain]")
		quit(2)
		return
	var gain: float = float(args[2]) if args.size() > 2 else 1.0
	var stream: AudioStream = null
	match args[0].get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(args[0])
		"ogg": stream = AudioStreamOggVorbis.load_from_file(args[0])
		"wav": stream = AudioStreamWAV.load_from_file(args[0])
	if stream == null:
		print("cannot load %s" % args[0])
		quit(1)
		return
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(0.0)
	var frames: PackedVector2Array = PackedVector2Array()
	var total: int = int(stream.get_length() * RATE)
	while frames.size() < total:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, 4096)
		if chunk.is_empty():
			break
		frames.append_array(chunk)
	frames.resize(mini(frames.size(), total))
	var first: int = 0
	while first < frames.size() and maxf(absf(frames[first].x), absf(frames[first].y)) < SILENCE:
		first += 1
	var last: int = frames.size() - 1
	while last > first and maxf(absf(frames[last].x), absf(frames[last].y)) < SILENCE:
		last -= 1
	var peak: float = 0.0
	var out: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(first, last + 1):
		var f: Vector2 = frames[i] * gain
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		out.append(clampf(f.x, -1.0, 1.0))
		out.append(clampf(f.y, -1.0, 1.0))
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_buffer(out.to_byte_array())
	file.close()
	print("decoded %s: %.3f s kept of %.3f s (from %.3f), peak %.2f -> %s" % [args[0].get_file(),
			(last - first + 1) / RATE, stream.get_length(), first / RATE, peak, args[1]])
	quit(0)
