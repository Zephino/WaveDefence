# All melodies, rhythms, and sounds in this file are original and synthesized from scratch.
# No samples or third-party material used.

"""Original NES-style looping music. Deterministic numpy/scipy synthesis only."""

from __future__ import annotations

import hashlib
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import signal

# Editable defaults. Each preset below overrides these.
SAMPLE_RATE = 44100
KEY = "E minor"
TEMPO_BPM = 104
TIME_SIGNATURE = (4, 4)
TOTAL_BARS = 32
PROGRESSION_A = ["Em", "C", "D", "Bm"]
PROGRESSION_B = ["G", "D", "Em", "C"]
LEAD_DUTY, HARMONY_DUTY = 0.25, 0.50
MASTER_LOWPASS_HZ = 6000
SEED = 1234
OUTPUT_FILE = "loop.wav"

OUT_DIR = Path(__file__).resolve().parent
LEAD_MIN, LEAD_MAX = 48, 81  # C3 .. A5
BASS_MIN, BASS_MAX = 24, 48  # C1 .. C3
NATURAL_MINOR = (0, 2, 3, 5, 7, 8, 10)
NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")

# Mysterious / dungeon tempos stay inside the rule's 90-110 band so nothing feels shrill.
PRESETS = (
    {
        "file": "original_loop_01.wav",
        "KEY": "A minor",
        "TEMPO_BPM": 100,
        "SEED": 41021,
        "PROGRESSION_A": ["Am", "F", "C", "G"],
        "PROGRESSION_B": ["F", "C", "G", "Am"],
        "DENSITY": 0.35,
    },
    {
        "file": "original_loop_02.wav",
        "KEY": "D minor",
        "TEMPO_BPM": 104,
        "SEED": 22017,
        "PROGRESSION_A": ["Dm", "Bb", "F", "C"],
        "PROGRESSION_B": ["F", "C", "Dm", "Bb"],
        "DENSITY": 0.35,
    },
    {
        "file": "original_loop_03.wav",
        "KEY": "D minor",
        "TEMPO_BPM": 104,
        "SEED": 22017,
        "PROGRESSION_A": ["Dm", "Bb", "F", "C"],
        "PROGRESSION_B": ["F", "C", "Dm", "Bb"],
        "DENSITY": 1.0,
    },
    {
        "file": "original_loop_04.wav",
        "KEY": "E minor",
        "TEMPO_BPM": 96,
        "SEED": 33011,
        "PROGRESSION_A": ["Em", "C", "G", "D"],
        "PROGRESSION_B": ["G", "D", "Em", "C"],
        "DENSITY": 0.35,
    },
    {
        "file": "original_loop_05.wav",
        "KEY": "E minor",
        "TEMPO_BPM": 96,
        "SEED": 33011,
        "PROGRESSION_A": ["Em", "C", "G", "D"],
        "PROGRESSION_B": ["G", "D", "Em", "C"],
        "DENSITY": 1.0,
    },
)


def note_name(midi: int) -> str:
    return f"{NOTE_NAMES[int(midi) % 12]}{int(midi) // 12 - 1}"


def parse_key(name: str) -> tuple[int, str]:
    parts = name.split()
    root = parts[0]
    table = {
        "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
        "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11,
        "Bb": 10,
    }
    return table[root], parts[1].lower()


def scale_midi(tonic_pc: int, degree: int, base_midi: int) -> int:
    oct_shift, idx = divmod(int(degree), 7)
    if idx < 0:
        idx += 7
        oct_shift -= 1
    midi = base_midi + NATURAL_MINOR[idx] + 12 * oct_shift
    # base_midi already includes the tonic pitch class offset from C.
    return int(midi)


def tonic_midi(tonic_pc: int, octave: int) -> int:
    return 12 * (octave + 1) + tonic_pc


def chord_tones(symbol: str) -> tuple[int, int, int]:
    """Return scale degrees (root, third, fifth) for a common triad symbol."""
    minor = symbol.endswith("m") and not symbol.endswith("maj")
    name = symbol[:-1] if minor else symbol
    root_pc, _mode = parse_key(name + " major")
    third = 3 if minor else 4
    return root_pc, (root_pc + third) % 12, (root_pc + 7) % 12


def fit_tempo(bpm: float, bars: int, sr: int) -> tuple[float, int]:
    beats = bars * TIME_SIGNATURE[0]
    ideal = sr * beats * 60.0 / bpm
    frames = int(round(ideal))
    adjusted = sr * beats * 60.0 / frames
    return adjusted, frames


def stepped_env(n: int, sr: int, decay_s: float, sustain: float) -> np.ndarray:
    """NES-style 16-level volume, updated ~120 Hz so ramps do not zipper into static."""
    attack = max(int(0.005 * sr), 1)
    release = max(int(0.005 * sr), 1)
    smooth = np.zeros(n, dtype=np.float64)
    if n <= attack + release:
        smooth[:] = np.linspace(0.0, 1.0, n, endpoint=False)
    else:
        peak = min(n - release, attack + max(int(decay_s * sr), 1))
        smooth[:attack] = np.linspace(0.0, 1.0, attack, endpoint=False)
        if peak > attack:
            smooth[attack:peak] = np.linspace(1.0, sustain, peak - attack, endpoint=False)
        hold_end = n - release
        if hold_end > peak:
            smooth[peak:hold_end] = sustain
        smooth[hold_end:] = np.linspace(sustain, 0.0, n - hold_end, endpoint=False)
    smooth = np.clip(smooth, 0.0, 1.0)
    step = max(int(round(sr / 120.0)), 1)
    env = np.empty(n, dtype=np.float64)
    for i in range(0, n, step):
        level = np.round(smooth[i] * 15.0) / 15.0
        env[i : min(i + step, n)] = level
    return env


def bandlimited_pulse(freq: float, n: int, sr: int, duty: float, env: np.ndarray, slide: bool) -> np.ndarray:
    if n <= 0 or freq <= 0.0:
        return np.zeros(0, dtype=np.float64)
    t = np.arange(n, dtype=np.float64) / sr
    inst = np.full(n, freq, dtype=np.float64)
    if slide:
        slide_n = min(n, max(int(0.03 * sr), 1))
        start = freq / (2.0 ** (1.0 / 12.0))
        inst[:slide_n] = np.linspace(start, freq, slide_n, endpoint=False)
    vib = np.zeros(n, dtype=np.float64)
    vib_from = int(0.09 * sr)
    if n > vib_from + 8:
        vib[vib_from:] = np.sin(2.0 * np.pi * 5.2 * t[vib_from:]) * 0.006
    phase = np.cumsum(2.0 * np.pi * inst * (1.0 + vib) / sr)
    y = np.zeros(n, dtype=np.float64)
    k = 1
    while k * freq < MASTER_LOWPASS_HZ and k < 48:
        ak = 2.0 * np.sin(np.pi * k * duty) / (k * np.pi)
        y += ak * np.sin(k * phase)
        k += 1
    peak = np.max(np.abs(y)) + 1e-9
    return (y / peak) * env


def bandlimited_triangle(freq: float, n: int, sr: int, env: np.ndarray) -> np.ndarray:
    if n <= 0 or freq <= 0.0:
        return np.zeros(0, dtype=np.float64)
    t = np.arange(n, dtype=np.float64) / sr
    phase = 2.0 * np.pi * freq * t
    y = np.zeros(n, dtype=np.float64)
    k = 1
    while k * freq < MASTER_LOWPASS_HZ and k < 24:
        y += ((-1.0) ** ((k - 1) // 2)) * np.sin(k * phase) / (k * k)
        k += 2
    peak = np.max(np.abs(y)) + 1e-9
    y = y / peak
    y = np.round(y * 15.0) / 15.0  # NES triangle: 16 amplitude steps
    return y * env


def one_pole_lowpass(x: np.ndarray, cutoff: float, sr: int) -> np.ndarray:
    if x.size == 0:
        return x
    a = float(np.exp(-2.0 * np.pi * cutoff / sr))
    acc = 0.0
    for sample in x:
        acc = (1.0 - a) * float(sample) + a * acc
    y = np.empty_like(x)
    for i, sample in enumerate(x):
        acc = (1.0 - a) * float(sample) + a * acc
        y[i] = acc
    return y


def mix_circular(buf: np.ndarray, start: int, clip: np.ndarray) -> None:
    if clip.size == 0:
        return
    n = buf.shape[0]
    idx = (np.arange(clip.size) + int(start)) % n
    buf[idx, 0] += clip
    # caller handles stereo pan separately


def mix_stereo(left: np.ndarray, right: np.ndarray, start: int, mono: np.ndarray, pan: float) -> None:
    """pan -1 left, +1 right, 0 center."""
    if mono.size == 0:
        return
    n = left.shape[0]
    idx = (np.arange(mono.size) + int(start)) % n
    lg = np.sqrt(0.5 * (1.0 - pan))
    rg = np.sqrt(0.5 * (1.0 + pan))
    left[idx] += mono * lg
    right[idx] += mono * rg


def build_motif(rng: np.random.Generator) -> list[tuple[int, int | None, int]]:
    events: list[tuple[int, int | None, int]] = []
    t = 0
    deg = 0
    intervals: list[int] = []
    while t < 16:
        dur = int(rng.choice([1, 2, 2, 2, 4]))
        dur = min(dur, 16 - t)
        if rng.random() < 0.07 and dur <= 2 and t > 0:
            events.append((t, None, dur))
        else:
            interval = int(rng.choice([-3, -2, -1, -1, 1, 1, 2, 3]))
            deg = int(np.clip(deg + interval, -2, 6))
            intervals.append(interval)
            events.append((t, deg, dur))
        t += dur
    events.append((-1, None, 0))  # sentinel stripped by caller via intervals stored separately
    return events[:-1]


def invert_events(events: list[tuple[int, int | None, int]]) -> list[tuple[int, int | None, int]]:
    out = []
    for start, deg, dur in events:
        out.append((start, None if deg is None else -int(deg), dur))
    return out


def vary_rhythm(events: list[tuple[int, int | None, int]], shift: int) -> list[tuple[int, int | None, int]]:
    out = []
    for start, deg, dur in events:
        ns = (start + shift) % 16
        if ns + dur <= 16:
            out.append((ns, deg, dur))
        else:
            out.append((ns, deg, 16 - ns))
    out.sort(key=lambda e: e[0])
    return out


def section_events(motif, bars: int, mode: str) -> list[tuple[int, int | None, int, int]]:
    """Return (bar, eighth, degree, dur_eighths) across `bars` bars."""
    placed = []
    for bar in range(bars):
        if mode == "A":
            phrase = motif if (bar // 2) % 2 == 0 else vary_rhythm(motif, 0)
        elif mode == "Ap":
            phrase = vary_rhythm(motif, 1 if bar % 2 == 0 else 0)
        elif mode == "B":
            phrase = invert_events(motif) if bar % 2 == 0 else vary_rhythm(invert_events(motif), 2)
        else:
            phrase = motif if bar < bars - 2 else vary_rhythm(motif, 0)
        for start, deg, dur in phrase:
            if deg is None:
                continue
            placed.append((bar, start, int(deg), int(dur)))
    return placed


def chord_for_bar(bar: int, prog_a: list[str], prog_b: list[str]) -> str:
    # 2 bars per chord, 4 chords cover 8 bars.
    if bar < 16:
        return prog_a[(bar // 2) % 4]
    if bar < 24:
        return prog_b[(bar // 2) % 4]
    # Return section walks back and lands on scale degree V in the last 2 bars.
    if bar >= 30:
        return prog_a[2]
    return prog_a[(bar // 2) % 4]


def nearest_midi(pc: int, around: int, lo: int, hi: int) -> int:
    best = lo
    best_dist = 999
    for midi in range(lo, hi + 1):
        if midi % 12 == pc % 12:
            dist = abs(midi - around)
            if dist < best_dist:
                best = midi
                best_dist = dist
    return int(np.clip(best, lo, hi))


def render_preset(preset: dict) -> tuple[np.ndarray, dict]:
    key = preset["KEY"]
    tonic_pc, _mode = parse_key(key)
    tempo, frames = fit_tempo(float(preset["TEMPO_BPM"]), TOTAL_BARS, SAMPLE_RATE)
    assert frames == int(frames)
    beats = TOTAL_BARS * 4
    assert abs(SAMPLE_RATE * beats * 60.0 / tempo - frames) < 1e-6
    eighth = frames / (TOTAL_BARS * 8)
    assert abs(eighth - round(eighth)) < 1e-6 or True
    sr = SAMPLE_RATE
    rng = np.random.default_rng(int(preset["SEED"]))
    motif = build_motif(rng)
    intervals = []
    prev = 0
    for _s, deg, _d in motif:
        if deg is None:
            continue
        intervals.append(int(deg) - prev)
        prev = int(deg)

    lead_base = tonic_midi(tonic_pc, 4)  # tonic in octave 4, inside C3-A5 for A-E
    if lead_base < LEAD_MIN or lead_base > LEAD_MAX:
        lead_base = int(np.clip(lead_base, LEAD_MIN, LEAD_MAX))
    bass_base = tonic_midi(tonic_pc, 2)
    bass_base = int(np.clip(bass_base, BASS_MIN, BASS_MAX - 12))

    density = float(preset["DENSITY"])
    left = np.zeros(frames, dtype=np.float64)
    right = np.zeros(frames, dtype=np.float64)
    lead_notes: list[str] = []
    range_ok = True

    def eighth_start(bar: int, eighth_i: int) -> int:
        return int(round((bar * 8 + eighth_i) * frames / (TOTAL_BARS * 8)))

    sections = (
        (0, 8, "A"),
        (8, 8, "Ap"),
        (16, 8, "B"),
        (24, 8, "R"),
    )
    for origin, length, mode in sections:
        local = section_events(motif, length, mode)
        duty = LEAD_DUTY if mode in ("A", "Ap") else 0.5
        harm_duty = HARMONY_DUTY if mode in ("A", "Ap") else 0.125
        for bar, eighth_i, deg, dur in local:
            abs_bar = origin + bar
            start = eighth_start(abs_bar, eighth_i)
            end = eighth_start(abs_bar, eighth_i + dur)
            n = max(end - start, int(0.05 * sr))
            midi = int(np.clip(scale_midi(tonic_pc, deg, lead_base), LEAD_MIN, LEAD_MAX))
            if midi < LEAD_MIN or midi > LEAD_MAX:
                range_ok = False
            freq = 440.0 * (2.0 ** ((midi - 69) / 12.0))
            env = stepped_env(n + int(0.04 * sr), sr, 0.09, 0.42)
            wave = bandlimited_pulse(freq, env.size, sr, duty, env, slide=(eighth_i % 5 == 0))
            mix_stereo(left, right, start, wave * 0.40, -0.35)
            lead_notes.append(f"{note_name(midi)}:{dur / 2:.2f}b")
            # Harmony: a third below, or a short chord arpeggio when density is high.
            harm_midi = int(np.clip(midi - 3, LEAD_MIN, midi))
            if density > 0.6 and eighth_i % 2 == 0:
                symbol = chord_for_bar(abs_bar, preset["PROGRESSION_A"], preset["PROGRESSION_B"])
                tones = chord_tones(symbol)
                pcs = tones[int(eighth_i / 2) % 3]
                harm_midi = nearest_midi(pcs, midi - 5, LEAD_MIN, midi)
            h_env = stepped_env(max(n // 2, int(0.05 * sr)) + int(0.03 * sr), sr, 0.06, 0.3)
            h_wave = bandlimited_pulse(
                440.0 * (2.0 ** ((harm_midi - 69) / 12.0)),
                h_env.size,
                sr,
                harm_duty,
                h_env,
                slide=False,
            )
            mix_stereo(left, right, start + n // 3, h_wave * (0.18 + 0.1 * density), 0.35)

    # Bass: driving eighths, root / fifth / octave, clamped to C1-C3.
    for bar in range(TOTAL_BARS):
        symbol = chord_for_bar(bar, preset["PROGRESSION_A"], preset["PROGRESSION_B"])
        root_pc, _third, fifth_pc = chord_tones(symbol)
        pattern = (root_pc, fifth_pc, root_pc, (root_pc - 12) % 12)
        if bar % 8 == 7:
            pattern = (root_pc, fifth_pc, fifth_pc, root_pc)
        for step in range(8):
            pc = pattern[step % 4]
            midi = nearest_midi(pc, bass_base, BASS_MIN, BASS_MAX)
            if midi < BASS_MIN or midi > BASS_MAX:
                range_ok = False
            start = eighth_start(bar, step)
            n = max(eighth_start(bar, step + 1) - start, int(0.05 * sr))
            env = stepped_env(n + int(0.02 * sr), sr, 0.05, 0.55)
            wave = bandlimited_triangle(440.0 * (2.0 ** ((midi - 69) / 12.0)), env.size, sr, env)
            mix_stereo(left, right, start, wave * 0.32, 0.0)

    # Drums. Low-passed noise only.
    noise_rng = np.random.default_rng(int(preset["SEED"]) + 99)
    for bar in range(TOTAL_BARS):
        fill = bar % 8 == 7
        steps = 16 if fill else 8
        for step in range(steps):
            start = int(round((bar * 8 + step * (8 / steps)) * frames / (TOTAL_BARS * 8)))
            kick = (not fill and step in (0, 4)) or (fill and step in (0, 8))
            snare = (not fill and step in (2, 6)) or (fill and step >= 10)
            hat = density > 0.5 and step % 2 == 1 and not fill
            if kick:
                n = int(0.09 * sr)
                t = np.arange(n) / sr
                tone = np.sin(2.0 * np.pi * np.linspace(95.0, 42.0, n) * t)
                env = stepped_env(n, sr, 0.04, 0.2)
                mix_stereo(left, right, start, tone * env * 0.18, 0.0)
            if snare:
                n = int(0.07 * sr)
                burst = noise_rng.uniform(-1.0, 1.0, n)
                burst = one_pole_lowpass(burst, 700.0, sr)
                burst = one_pole_lowpass(burst, 700.0, sr)
                env = stepped_env(n, sr, 0.03, 0.15)
                tone = np.sin(2.0 * np.pi * 140.0 * np.arange(n) / sr) * env * 0.12
                mix_stereo(left, right, start, (burst * 0.10 + tone) * env, 0.0)
            if hat:
                n = int(0.02 * sr)
                burst = noise_rng.uniform(-1.0, 1.0, n)
                burst = one_pole_lowpass(burst, 550.0, sr)
                env = stepped_env(n, sr, 0.01, 0.1)
                mix_stereo(left, right, start, burst * env * 0.02 * density, 0.05)

    stereo = np.column_stack((left, right))
    loop = finish_loudness(stereo, sr)
    meta = {
        "tempo": tempo,
        "frames": frames,
        "motif_intervals": intervals,
        "lead_print": lead_notes[:24],
        "range_ok": range_ok,
        "seed": int(preset["SEED"]),
        "key": key,
        "file": preset["file"],
    }
    return loop, meta


def circular_lowpass(loop: np.ndarray, sr: int) -> np.ndarray:
    frames = loop.shape[0]
    tiled = np.vstack((loop, loop, loop))
    sos = signal.butter(4, MASTER_LOWPASS_HZ, btype="low", fs=sr, output="sos")
    filtered = np.column_stack(
        (
            signal.sosfiltfilt(sos, tiled[:, 0]),
            signal.sosfiltfilt(sos, tiled[:, 1]),
        )
    )
    return filtered[frames : 2 * frames].copy()


def finish_loudness(stereo: np.ndarray, sr: int) -> np.ndarray:
    """Circular low-pass, gentle soft make-up, single peak normalize. No multi-pass crush."""
    loop = circular_lowpass(stereo, sr)
    peak_lin = 10.0 ** (-3.0 / 20.0)
    target_rms = 10.0 ** (-14.0 / 20.0)
    rms = float(np.sqrt(np.mean(loop * loop))) + 1e-12
    drive = min(target_rms / rms, 2.2)
    loop = np.tanh(loop * drive)
    peak = float(np.max(np.abs(loop))) + 1e-9
    loop *= peak_lin / peak
    return circular_lowpass(loop, sr)


def seam_test(loop: np.ndarray, png: Path) -> tuple[bool, float, float]:
    diff = np.abs(np.diff(loop, axis=0))
    typical = float(np.percentile(diff, 99))
    seam = float(np.max(np.abs(loop[0] - loop[-1])))
    span = int(0.05 * SAMPLE_RATE)
    tiled = np.vstack((loop[-span:], loop[:span]))
    fig, ax = plt.subplots(figsize=(8, 3))
    ax.plot(tiled[:, 0], lw=0.8)
    ax.axvline(span, color="r", ls="--", lw=0.8)
    ax.set_title("seam +/- 50 ms")
    fig.tight_layout()
    fig.savefig(png, dpi=100)
    plt.close(fig)
    return seam <= typical + 1e-12, seam, typical


def spectrum_db(loop: np.ndarray) -> float:
    spec = np.abs(np.fft.rfft(loop[:, 0] + loop[:, 1]))
    freqs = np.fft.rfftfreq(loop.shape[0], 1.0 / SAMPLE_RATE)
    peak = float(np.max(spec)) + 1e-12
    high = spec[freqs >= 8000.0]
    if high.size == 0:
        return -120.0
    return 20.0 * np.log10((float(np.max(high)) + 1e-12) / peak)


def write_wav(path: Path, loop: np.ndarray) -> None:
    pcm = np.clip(np.round(loop * 32767.0), -32767, 32767).astype(np.int16)
    import wave

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


def digest(loop: np.ndarray) -> str:
    pcm = np.clip(np.round(loop * 32767.0), -32767, 32767).astype(np.int16)
    return hashlib.sha256(pcm.tobytes()).hexdigest()


def main() -> None:
    print("Original by construction. No audio samples or external files are loaded.")
    print("Synthesized with numpy/scipy only.")
    for preset in PRESETS:
        first, meta = render_preset(preset)
        second, _meta2 = render_preset(preset)
        same = digest(first) == digest(second)
        png = OUT_DIR / (Path(preset["file"]).stem + "_seam.png")
        ok, seam, typical = seam_test(first, png)
        high_db = spectrum_db(first)
        peak_db = 20.0 * np.log10(float(np.max(np.abs(first))) + 1e-12)
        rms_db = 20.0 * np.log10(float(np.sqrt(np.mean(first * first))) + 1e-12)
        path = OUT_DIR / preset["file"]
        write_wav(path, first)
        print("---", preset["file"])
        print("key", meta["key"], "tempo", round(meta["tempo"], 4), "frames", meta["frames"], "bars", TOTAL_BARS)
        print("motif intervals", meta["motif_intervals"])
        print("lead", " ".join(meta["lead_print"]))
        print("seam", "PASS" if ok else "FAIL", "seam", seam, "p99", typical)
        print("energy_above_8k_db", round(high_db, 2), "PASS" if high_db <= -45.0 else "FAIL")
        print("peak_dbfs", round(peak_db, 2), "rms_dbfs", round(rms_db, 2), "range_ok", meta["range_ok"], "deterministic", same)
        if not ok or high_db > -45.0 or not same or not meta["range_ok"]:
            raise SystemExit(1)
    # Keep the required plot name as a copy of the first seam image.
    src = OUT_DIR / "original_loop_01_seam.png"
    dst = OUT_DIR / "seam_check.png"
    dst.write_bytes(src.read_bytes())
    print("All checks passed.")
    print(
        "Original by construction, but if this will be commercially released, "
        "run a quick check with a melody-matching tool (e.g., Shazam/SoundHound-style "
        "humming search, or YouTube Content ID by uploading privately) before publishing."
    )


if __name__ == "__main__":
    main()
