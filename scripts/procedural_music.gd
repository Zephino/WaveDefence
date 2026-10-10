class_name ProceduralMusic
extends RefCounted

## Low gothic beds: held lines, chord crossfades, one tempo per mode so layers lock.

const SAMPLE_RATE := 16000
const STEPS_PER_BAR := 16
const BARS := 8


static func make_track(recipe: String) -> AudioStreamWAV:
	return _render(_song_def(recipe))


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func _degree_to_midi(root_midi: int, scale: PackedInt32Array, degree: int) -> float:
	if degree < 0:
		return -1.0
	var oct := degree / scale.size()
	var idx := degree % scale.size()
	if idx < 0:
		idx += scale.size()
		oct -= 1
	return float(root_midi + scale[idx] + oct * 12)


static func _gothic_prog() -> PackedInt32Array:
	# i → VI → III → VII → i → iv → v → i. Ends where it starts.
	return PackedInt32Array([0, -3, -7, -2, 0, -5, -2, 0])


static func _quarters(notes: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in notes:
		for _s in 4:
			out.append(int(n))
	return out


static func _song_def(recipe: String) -> Dictionary:
	var harmonic_minor := PackedInt32Array([0, 2, 3, 5, 7, 8, 10])
	var phrygian := PackedInt32Array([0, 1, 3, 5, 7, 8, 10])
	var menu_line := _quarters([
		0, 2, 3, 5,
		3, 2, 0, 2,
		3, 5, 3, 2,
		0, 2, 3, 2,
		5, 3, 2, 0,
		2, 3, 2, 0,
		0, 2, 0, -1,
		0, 0, 0, 0,
	])
	var game_line := _quarters([
		0, 3, 2, 0,
		5, 3, 2, 0,
		2, 3, 5, 3,
		2, 0, 2, 3,
		0, 2, 3, 5,
		3, 2, 0, -1,
		2, 0, 0, -1,
		0, 0, 0, 0,
	])
	var siege_line := _quarters([
		0, 1, 3, 1,
		0, 3, 1, 0,
		5, 3, 1, 0,
		3, 1, 0, -1,
		0, 1, 0, 3,
		1, 0, -1, 0,
		0, 1, 0, -1,
		0, 0, 0, 0,
	])
	match recipe:
		"menu":
			return _bed(66.0, 38, harmonic_minor, menu_line, false)
		"siege_intense":
			var siege: Dictionary = _bed(64.0, 36, phrygian, siege_line, true)
			return siege
		"siege_calm":
			return _bed(64.0, 36, phrygian, siege_line, false)
		"game_intense":
			return _bed(70.0, 36, harmonic_minor, game_line, true)
		_:
			return _bed(70.0, 36, harmonic_minor, game_line, false)


static func _bed(bpm: float, root: int, scale: PackedInt32Array, melody: PackedInt32Array, intense: bool) -> Dictionary:
	return {
		"bpm": bpm,
		"root_midi": root,
		"scale": scale,
		"prog": _gothic_prog(),
		"melody": melody,
		"lead_mix": 0.16 if intense else 0.13,
		"pad_mix": 0.24,
		"drum_mix": 0.34 if intense else 0.2,
		"intense": intense,
	}


static func _render(song: Dictionary) -> AudioStreamWAV:
	var bpm: float = float(song["bpm"])
	var beat_len := 60.0 / bpm
	var step_len := beat_len / 4.0
	var bar_len := beat_len * 4.0
	var duration := bar_len * float(BARS)
	var samples := int(round(duration * float(SAMPLE_RATE)))
	duration = float(samples) / float(SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(samples * 4)
	var lead_mix: float = float(song["lead_mix"])
	var pad_mix: float = float(song["pad_mix"])
	var drum_mix: float = float(song["drum_mix"])
	var intense: bool = bool(song["intense"])
	var root_midi: int = int(song["root_midi"])
	var scale: PackedInt32Array = song["scale"]
	var prog: PackedInt32Array = song["prog"]
	var melody: PackedInt32Array = song["melody"]
	var mel_len := melody.size()
	var starts := PackedInt32Array()
	var ends := PackedInt32Array()
	var prev_hz := PackedFloat32Array()
	starts.resize(mel_len)
	ends.resize(mel_len)
	prev_hz.resize(mel_len)
	for step in mel_len:
		var bounds := _run_bounds(melody, step)
		starts[step] = int(bounds.x)
		ends[step] = int(bounds.y)
		var prev_deg := int(melody[posmod(int(bounds.x) - 1, mel_len)])
		prev_hz[step] = _degree_to_midi(root_midi, scale, prev_deg) if prev_deg >= 0 else -1.0
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var t_loop := fmod(t, duration)
		var bar_f := t_loop / bar_len
		var bar_i := int(floor(bar_f)) % BARS
		var bar_phase: float = bar_f - float(floor(bar_f))
		var next_bar := (bar_i + 1) % BARS
		var blend := 0.0
		if bar_phase > 0.72:
			blend = smoothstep(0.72, 1.0, bar_phase)
		var step_f := t_loop / step_len
		var step_i := int(floor(step_f)) % mel_len
		var step_in_bar := step_i % STEPS_PER_BAR
		var kick := _hit_body(t_loop, step_f, step_len, step_in_bar, 0, 0.22, 70.0, 38.0)
		var timp_steps: Array = [8, 4, 12] if intense else [8]
		var timp := 0.0
		for ts in timp_steps:
			timp += _hit_body(t_loop, step_f, step_len, step_in_bar, int(ts), 0.45, 110.0, 55.0) * 0.55
		var drums := (kick * 0.7 + timp) * drum_mix
		var mel_deg := int(melody[step_i])
		var lead := 0.0
		if mel_deg >= 0:
			var run_start := float(starts[step_i])
			var run_end := float(ends[step_i])
			var span := maxf(run_end - run_start, 0.001)
			var along := (step_f - run_start) / span
			var env := 1.0 if span >= float(mel_len) - 0.5 else _phrase_env(along)
			var target := _hz(_degree_to_midi(root_midi, scale, mel_deg))
			var from_hz := target
			if prev_hz[step_i] > 0.0:
				from_hz = _hz(prev_hz[step_i])
			var age := (step_f - run_start) * step_len
			var glide := smoothstep(0.0, 0.12, age)
			var mel_hz := minf(lerpf(from_hz, target, glide), 311.0)
			lead = _cello_tone(t_loop, mel_hz) * env * lead_mix
		var pad := _pad_crossfade(t_loop, root_midi, scale, prog[bar_i], prog[next_bar], blend) * pad_mix
		var l: float = (drums + pad + lead) * 0.92
		var r: float = (drums * 0.96 + pad * 1.05 + lead * 0.9) * 0.92
		_push_stereo(data, i, _soft_clip(l), _soft_clip(r))
	return _stereo_stream(data, samples)


static func _run_bounds(seq: PackedInt32Array, step: int) -> Vector2:
	var n := seq.size()
	var deg := int(seq[step % n])
	if deg < 0:
		return Vector2(-1, -1)
	var s := step
	var walked := 0
	while walked < n and int(seq[posmod(s - 1, n)]) == deg:
		s -= 1
		walked += 1
	var e := step + 1
	walked = 0
	while walked < n and int(seq[posmod(e, n)]) == deg:
		e += 1
		walked += 1
	return Vector2(s, e)


static func _phrase_env(along: float) -> float:
	var u := clampf(along, 0.0, 1.0)
	var env := 1.0
	if u < 0.08:
		env = smoothstep(0.0, 0.08, u)
	elif u > 0.78:
		env = 1.0 - smoothstep(0.78, 1.0, u)
	return env


static func _pad_crossfade(t: float, root_midi: int, scale: PackedInt32Array, shift_a: int, shift_b: int, blend: float) -> float:
	var a := _organ_chord(t, float(root_midi + shift_a), scale)
	if blend <= 0.001:
		return a
	var b := _organ_chord(t, float(root_midi + shift_b), scale)
	return lerpf(a, b, blend)


static func _organ_chord(t: float, root_midi: float, scale: PackedInt32Array) -> float:
	var root := _hz(root_midi)
	var third := _hz(root_midi + float(scale[2]))
	var fifth := _hz(root_midi + float(scale[4]))
	var s := _organ_voice(t, root * 0.5) * 0.55
	s += _organ_voice(t, root) * 0.4
	s += _organ_voice(t, third) * 0.22
	s += _organ_voice(t, fifth) * 0.2
	return s


static func _organ_voice(t: float, hz: float) -> float:
	var fund := minf(hz, 220.0)
	var s := sin(TAU * fund * t)
	s += sin(TAU * fund * 2.0 * t) * 0.08
	s += sin(TAU * fund * 1.003 * t) * 0.35
	return s * 0.42


static func _cello_tone(t: float, hz: float) -> float:
	var fund := minf(hz, 311.0)
	var s := sin(TAU * fund * t) * 0.75
	s += sin(TAU * fund * 2.0 * t) * 0.08
	return s


static func _hit_body(t: float, step_f: float, step_len: float, step_in_bar: int, hit_step: int, decay: float, hz0: float, hz1: float) -> float:
	var back := (step_in_bar - hit_step + STEPS_PER_BAR) % STEPS_PER_BAR
	var age: float = (float(back) + (step_f - float(floor(step_f)))) * step_len
	if age > decay or age < 0.0:
		return 0.0
	var u: float = age / decay
	var hz := lerpf(hz0, hz1, clampf(u * 3.0, 0.0, 1.0))
	return sin(TAU * hz * t) * (1.0 - u) * (1.0 - u)


static func _soft_clip(x: float) -> float:
	return tanh(x * 1.15)


static func _stereo_stream(data: PackedByteArray, frames: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = maxi(frames - 1, 1)
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
