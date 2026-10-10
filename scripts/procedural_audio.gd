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
		var s := _osc(wave, phase)
		var v := int(clampf(s * env * volume, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _mono_stream(data)


## Exit leak — keep this exact recipe (player preference).
static func make_leak_sfx() -> AudioStreamWAV:
	return make_tone(90.0, 0.35, 0.3, "triangle")


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
	return _mono_stream(data)


static func make_ui_blip() -> AudioStreamWAV:
	return _make_two_tone(620.0, 980.0, 0.07, 0.22, "sine")


static func make_place_thud() -> AudioStreamWAV:
	return _mix_mono([make_tone(140.0, 0.09, 0.28, "triangle"), make_tone(520.0, 0.04, 0.12, "sine")])


static func make_sell_drop() -> AudioStreamWAV:
	return _make_sweep(420.0, 160.0, 0.12, 0.2, "triangle")


static func make_wave_stinger() -> AudioStreamWAV:
	return _mix_mono([
		_make_sweep(180.0, 320.0, 0.18, 0.18, "sine"),
		make_tone(220.0, 0.22, 0.24, "square"),
	])


static func make_boss_stinger() -> AudioStreamWAV:
	return _mix_mono([
		make_tone(55.0, 0.45, 0.34, "square"),
		_make_sweep(90.0, 45.0, 0.35, 0.2, "triangle"),
		make_tone(110.0, 0.5, 0.22, "square"),
	])


static func make_kill_tick() -> AudioStreamWAV:
	return _make_two_tone(880.0, 1320.0, 0.035, 0.1, "sine")


static func make_game_over_sting() -> AudioStreamWAV:
	return _make_chord_sting([55.0, 82.5, 98.0], 0.85, 0.28)


static func make_unlock_fanfare() -> AudioStreamWAV:
	var parts: Array = []
	var freqs := [523.25, 659.25, 783.99, 1046.5]
	for i in freqs.size():
		parts.append(make_tone(freqs[i], 0.14, 0.16 - float(i) * 0.02, "sine"))
	return _mix_mono(parts, 0.06)


static func make_loop(recipe: String, duration: float = 24.0) -> AudioStreamWAV:
	var cfg := _loop_config(recipe)
	var kick_amp: float = float(cfg["kick"])
	var hat_amp: float = float(cfg["hat"])
	var bass_amp: float = float(cfg["bass"])
	var pad_amp: float = float(cfg["pad"])
	var arp_amp: float = float(cfg["arp"])
	var swish_amp: float = float(cfg["swish"])
	var master_amp: float = float(cfg["master"])
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"])
	var bpm: float = float(cfg["bpm"])
	var beat_len := 60.0 / bpm
	var bar_len := beat_len * 4.0
	var progression: PackedFloat32Array = cfg["roots"]
	var intense: bool = bool(cfg["intense"])
	var arp_rate: float = float(cfg["arp_div"])
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var bar_i := int(floor(t / bar_len)) % progression.size()
		var root: float = progression[bar_i]
		var kick := 0.0
		if fmod(t, beat_len) < 0.055:
			var kt := fmod(t, beat_len) / 0.055
			kick = (1.0 - kt) * (1.0 - kt) * kick_amp
		var hat := 0.0
		if intense or recipe == "menu":
			var eighth := beat_len * 0.5
			if fmod(t + eighth * 0.25, eighth) < 0.018:
				hat = rng.randf_range(-1.0, 1.0) * hat_amp * (0.6 + 0.4 * sin(t * 40.0))
		var bass: float = sin(t * root * 0.5 * TAU) * bass_amp
		bass += sin(t * root * 0.25 * TAU) * bass_amp * 0.35
		var pad_l := 0.0
		var pad_r := 0.0
		for det in [-0.003, 0.0, 0.003]:
			var wobble := sin(t * 0.35 + det * 20.0) * 0.015
			pad_l += sin(t * root * TAU * (1.0 + wobble + det)) * pad_amp
			pad_r += sin(t * root * 1.259 * TAU * (1.0 + wobble - det)) * pad_amp * 0.9
			pad_l += sin(t * root * 1.498 * TAU * (1.0 + wobble)) * pad_amp * 0.55
			pad_r += sin(t * root * 1.498 * TAU * (1.0 - wobble)) * pad_amp * 0.55
		var arp := 0.0
		var arp_step := int(floor(t / arp_rate)) % 8
		var arp_deg: float = [0.0, 0.25, 0.5, 0.75, 1.0, 0.75, 0.5, 0.25][arp_step]
		var arp_freq := root * pow(2.0, arp_deg + 1.0)
		var arp_env := 0.5 + 0.5 * sin(t * TAU / arp_rate * PI)
		arp = sin(t * arp_freq * TAU) * arp_amp * arp_env
		if intense:
			arp += sin(t * arp_freq * 2.0 * TAU) * arp_amp * 0.25 * arp_env
		var swish: float = sin(t * 0.08 * TAU) * swish_amp
		pad_l *= 1.0 + swish * 0.15
		pad_r *= 1.0 - swish * 0.12
		var sidechain := 1.0
		if kick > 0.01:
			sidechain = 0.72 + 0.28 * (1.0 - kick / maxf(kick_amp, 0.001))
		var l: float = (bass + (pad_l + arp) * sidechain + kick) * master_amp
		var r: float = (bass + (pad_r + arp * 0.92) * sidechain + kick) * master_amp
		l = _soft_clip(l)
		r = _soft_clip(r)
		_push_stereo(data, i, l, r)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream


static func _loop_config(recipe: String) -> Dictionary:
	match recipe:
		"menu":
			return {
				"seed": 11,
				"bpm": 108.0,
				"roots": PackedFloat32Array([146.83, 130.81, 174.61, 196.0]),
				"intense": false,
				"arp_div": 0.22,
				"kick": 0.42,
				"hat": 0.06,
				"bass": 0.14,
				"pad": 0.07,
				"arp": 0.09,
				"swish": 0.35,
				"master": 0.48,
			}
		"siege_calm":
			return {
				"seed": 23,
				"bpm": 92.0,
				"roots": PackedFloat32Array([82.41, 73.42, 87.31, 98.0]),
				"intense": false,
				"arp_div": 0.28,
				"kick": 0.38,
				"hat": 0.04,
				"bass": 0.16,
				"pad": 0.08,
				"arp": 0.06,
				"swish": 0.25,
				"master": 0.46,
			}
		"siege_intense":
			return {
				"seed": 29,
				"bpm": 98.0,
				"roots": PackedFloat32Array([82.41, 77.78, 92.5, 87.31]),
				"intense": true,
				"arp_div": 0.18,
				"kick": 0.48,
				"hat": 0.09,
				"bass": 0.17,
				"pad": 0.075,
				"arp": 0.11,
				"swish": 0.4,
				"master": 0.5,
			}
		"game_intense":
			return {
				"seed": 37,
				"bpm": 118.0,
				"roots": PackedFloat32Array([110.0, 98.0, 123.47, 130.81]),
				"intense": true,
				"arp_div": 0.16,
				"kick": 0.5,
				"hat": 0.1,
				"bass": 0.15,
				"pad": 0.065,
				"arp": 0.12,
				"swish": 0.45,
				"master": 0.5,
			}
		_:
			return {
				"seed": 17,
				"bpm": 112.0,
				"roots": PackedFloat32Array([123.47, 110.0, 146.83, 130.81]),
				"intense": false,
				"arp_div": 0.2,
				"kick": 0.4,
				"hat": 0.05,
				"bass": 0.13,
				"pad": 0.065,
				"arp": 0.085,
				"swish": 0.3,
				"master": 0.47,
			}


static func _osc(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if fmod(phase, TAU) < PI else -1.0
		"triangle":
			return asin(sin(phase)) * 1.27323954473516
		_:
			return sin(phase)


static func _soft_clip(x: float) -> float:
	return tanh(x * 1.35)


static func _mono_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


static func _push_stereo(data: PackedByteArray, frame: int, l: float, r: float) -> void:
	var il := int(clampf(l, -1.0, 1.0) * 32767.0)
	var ir := int(clampf(r, -1.0, 1.0) * 32767.0)
	var base := frame * 4
	data[base] = il & 0xFF
	data[base + 1] = (il >> 8) & 0xFF
	data[base + 2] = ir & 0xFF
	data[base + 3] = (ir >> 8) & 0xFF


static func _make_two_tone(f0: float, f1: float, duration: float, volume: float, wave: String) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var u := clampf(t / duration, 0.0, 1.0)
		var freq := lerpf(f0, f1, u * u)
		var env := 1.0 - u
		var s := _osc(wave, t * freq * TAU) * env * volume
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _mono_stream(data)


static func _make_sweep(f0: float, f1: float, duration: float, volume: float, wave: String) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var u := t / maxf(duration, 0.001)
		var freq := lerpf(f0, f1, u)
		var env := 1.0
		if u > 0.75:
			env = maxf(1.0 - (u - 0.75) / 0.25, 0.0)
		var s := _osc(wave, t * freq * TAU) * env * volume
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _mono_stream(data)


static func _make_chord_sting(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var samples := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := 1.0
		if t < 0.04:
			env = t / 0.04
		elif t > duration - 0.35:
			env = maxf((duration - t) / 0.35, 0.0)
		var s := 0.0
		for f in freqs:
			s += sin(t * float(f) * TAU) / float(freqs.size())
		s += sin(t * freqs[0] * 0.5 * TAU) * 0.35
		s *= env * volume
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _mono_stream(data)


static func _mix_mono(streams: Array, stagger: float = 0.0) -> AudioStreamWAV:
	if streams.is_empty():
		return make_tone(440.0, 0.05, 0.1)
	var stagger_samples := int(stagger * SAMPLE_RATE)
	var total := 0
	for st in streams:
		if st is AudioStreamWAV:
			total = maxi(total, int((st as AudioStreamWAV).get_length() * SAMPLE_RATE))
	if stagger_samples > 0:
		var tail := 0
		for st in streams:
			if st is AudioStreamWAV:
				tail += int((st as AudioStreamWAV).get_length() * SAMPLE_RATE)
				total = maxi(total, tail)
				tail += stagger_samples
	total = maxi(total, 1)
	var mix := PackedFloat32Array()
	mix.resize(total)
	mix.fill(0.0)
	var offset := 0
	for st in streams:
		if st is not AudioStreamWAV:
			continue
		var wav := st as AudioStreamWAV
		var raw: PackedByteArray = wav.data
		var count := raw.size() / 2
		for i in count:
			var v := raw[i * 2] | (raw[i * 2 + 1] << 8)
			if v >= 32768:
				v -= 65536
			var idx := offset + i
			if idx < mix.size():
				mix[idx] += float(v) / 32767.0
		if stagger_samples > 0:
			offset += count + stagger_samples
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i in mix.size():
		var s := _soft_clip(mix[i])
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return _mono_stream(data)
