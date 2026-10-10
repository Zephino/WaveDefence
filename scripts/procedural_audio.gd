class_name ProceduralAudio
extends RefCounted

const SAMPLE_RATE := 22050


static func make_tone(
	freq: float,
	duration: float,
	volume: float = 0.3,
	wave: String = "sine"
) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	samples = maxi(samples, 1)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := 1.0
		var attack := 0.01
		var release := 0.08
		if t < attack:
			env = t / attack
		elif t > duration - release:
			env = maxf((duration - t) / release, 0.0)
		var phase := t * freq * TAU
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if fmod(phase, TAU) < PI else -1.0
			"triangle":
				s = asin(sin(phase)) * 1.27323954473516
			_:
				s = sin(phase)
		var v := int(clampf(s * env * volume, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


static func make_noise_burst(duration: float, volume: float = 0.15) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := 1.0 - t / maxf(duration, 0.001)
		var s := rng.randf_range(-1.0, 1.0) * env * volume
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


static func make_loop(recipe: String, duration: float = 24.0) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var bass_freq := 55.0
	var pad_freq := 110.0
	match recipe:
		"menu":
			bass_freq = 65.0
			pad_freq = 130.0
		"siege_calm":
			bass_freq = 45.0
			pad_freq = 90.0
		"siege_intense":
			bass_freq = 50.0
			pad_freq = 100.0
		"game_intense":
			bass_freq = 60.0
			pad_freq = 120.0
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var beat := fmod(t, 1.2)
		var kick := 0.0
		if recipe.contains("intense") and beat < 0.08:
			kick = 0.35 * (1.0 - beat / 0.08)
		var bass := sin(t * bass_freq * TAU) * 0.12
		var pad := sin(t * pad_freq * TAU) * 0.06 + sin(t * pad_freq * 1.5 * TAU) * 0.04
		if recipe == "menu":
			pad *= 1.2
		var s := bass + pad + kick
		s = clampf(s, -1.0, 1.0) * 0.45
		var v := int(s * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream
