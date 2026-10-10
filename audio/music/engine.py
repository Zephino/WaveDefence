# All melodies, rhythms, and sounds in this file are original and synthesized from scratch.
# No samples or third-party material used.

"""Shared seamless-loop audio engine for retro console-style music."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from scipy import signal
from scipy.io import wavfile

# ---------------------------------------------------------------------------
# Single source of truth for numeric limits (Section 0.1)
# ---------------------------------------------------------------------------
LIMITS: dict = {
    "T1_integer_samples": True,
    "T2_seam_vs_p99": True,
    "T3_pre_limiter_db": -3.0,
    "T4_true_peak_db": -1.0,
    "T5_dc": 1e-4,
    "T6_alias_db": 60.0,
    "T7_click_outside_onset_ms": 10.0,
    "T8_hf_db": 45.0,
    "T10_echo_wet_max": 0.20,
    "T10_echo_tail_db": -80.0,
    "T12_stem_diff": 1e-9,
    "T13_lead": (48, 81),  # C3..A5 MIDI
    "T13_bass": (24, 48),  # C1..C3
    "T14_harsh_db": 6.0,
    "T14_window_ms": 50.0,
    "T15_human_ms_max": 10.0,
    "T16_env_ms_min": 5.0,
}

TREBLE_CEILING_TABLE = {
    "soft": {"lpf_hz": 5000.0, "check_hz": 7000.0},
    "standard": {"lpf_hz": 6000.0, "check_hz": 8000.0},
    "open": {"lpf_hz": 7000.0, "check_hz": 9000.0},
}

NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
SCALES = {
    "major": (0, 2, 4, 5, 7, 9, 11),
    "natural_minor": (0, 2, 3, 5, 7, 8, 10),
    "harmonic_minor": (0, 2, 3, 5, 7, 8, 11),
    "dorian": (0, 2, 3, 5, 7, 9, 10),
    "phrygian": (0, 1, 3, 5, 7, 8, 10),
    "lydian": (0, 2, 4, 6, 7, 9, 11),
    "mixolydian": (0, 2, 4, 5, 7, 9, 10),
    "major_pentatonic": (0, 2, 4, 7, 9),
    "minor_pentatonic": (0, 3, 5, 7, 10),
}


@dataclass
class CheckResult:
    id: str
    name: str
    measured: float | str
    limit: float | str
    result: str  # PASS, FIXED, FEATURE DISABLED, WARNING, FAIL


def midi_to_hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((float(midi) - 69.0) / 12.0))


def note_name(midi: int) -> str:
    return f"{NOTE_NAMES[int(midi) % 12]}{int(midi) // 12 - 1}"


def parse_key(key: str) -> tuple[int, str]:
    parts = key.strip().split()
    root = parts[0]
    mode = "natural_minor" if len(parts) > 1 and "minor" in parts[1].lower() else "major"
    if len(parts) > 1:
        token = parts[1].lower()
        if token in SCALES:
            mode = token
        elif token in ("min", "minor"):
            mode = "natural_minor"
        elif token in ("maj", "major"):
            mode = "major"
    sharp = root.endswith("#")
    flat = root.endswith("b") and len(root) > 1
    letter = root[0].upper()
    base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[letter]
    if sharp:
        base += 1
    if flat:
        base -= 1
    return base % 12, mode


def chord_midi(symbol: str, octave: int = 3) -> list[int]:
    """Parse a simple chord symbol into MIDI pitches."""
    s = symbol.strip()
    i = 1
    if len(s) > 1 and s[1] in "#b":
        i = 2
    root_name = s[:i]
    quality = s[i:]
    root_pc, _ = parse_key(f"{root_name} major")
    root = 12 * (octave + 1) + root_pc
    if quality in ("", "maj"):
        intervals = (0, 4, 7)
    elif quality in ("m", "min"):
        intervals = (0, 3, 7)
    elif quality == "dim":
        intervals = (0, 3, 6)
    elif quality == "7":
        intervals = (0, 4, 7, 10)
    elif quality == "m7":
        intervals = (0, 3, 7, 10)
    elif quality == "sus2":
        intervals = (0, 2, 7)
    elif quality == "sus4":
        intervals = (0, 5, 7)
    elif quality == "6":
        intervals = (0, 4, 7, 9)
    elif quality == "add9":
        intervals = (0, 4, 7, 14)
    else:
        intervals = (0, 4, 7)
    return [root + iv for iv in intervals]


# ---------------------------------------------------------------------------
# Loop math
# ---------------------------------------------------------------------------
def samples_per_beat(tempo_bpm: float, sample_rate: int, signature: tuple[int, int]) -> float:
    beat_unit = signature[1]
    return (60.0 / tempo_bpm) * sample_rate * (4.0 / beat_unit)


def samples_per_bar(tempo_bpm: float, sample_rate: int, signature: tuple[int, int]) -> float:
    return samples_per_beat(tempo_bpm, sample_rate, signature) * signature[0]


def nudge_tempo_for_integer_loop(
    tempo_bpm: float,
    bars: int,
    sample_rate: int,
    signature: tuple[int, int] = (4, 4),
) -> tuple[float, int]:
    """Return (adjusted_tempo, total_samples) so the loop is an integer sample count."""
    spb = samples_per_bar(tempo_bpm, sample_rate, signature)
    total = spb * bars
    if abs(total - round(total)) < 1e-6:
        return float(tempo_bpm), int(round(total))
    target = int(round(total))
    # samples = bars * beats * (60/tempo) * sr * (4/denom)
    beats = bars * signature[0]
    denom = signature[1]
    new_tempo = (beats * 60.0 * sample_rate * (4.0 / denom)) / target
    return float(new_tempo), target


# ---------------------------------------------------------------------------
# Oscillators (band-limited)
# ---------------------------------------------------------------------------
def _polyblep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    out = np.zeros_like(t)
    mask1 = t < dt
    t1 = np.where(mask1, t / np.maximum(dt, 1e-12), 0.0)
    out = np.where(mask1, t1 + t1 - t1 * t1 - 1.0, out)
    mask2 = t > 1.0 - dt
    t2 = np.where(mask2, (t - 1.0) / np.maximum(dt, 1e-12), 0.0)
    out = np.where(mask2, t2 * t2 + t2 + t2 + 1.0, out)
    return out


def osc_pulse(freq: np.ndarray | float, n: int, sr: int, duty: float = 0.5, phase0: float = 0.0) -> np.ndarray:
    """Band-limited pulse via additive Fourier series (no naive edges)."""
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), n)
    phase = phase0 + np.cumsum(freq / sr)
    y = np.zeros(n, dtype=np.float64)
    nyquist = sr * 0.5 * 0.92
    # DC term for asymmetric duty + harmonics
    y += 2.0 * duty - 1.0
    max_h = int(nyquist / (float(np.max(freq)) + 1e-9))
    max_h = max(1, min(max_h, 64))
    for h in range(1, max_h + 1):
        # Fourier coefficients for a pulse wave of given duty
        coeff = (2.0 / (h * np.pi)) * np.sin(h * np.pi * duty)
        if abs(coeff) < 1e-12:
            continue
        y += coeff * np.sin(2.0 * np.pi * h * phase)
    peak = np.max(np.abs(y)) + 1e-12
    return (y / peak).astype(np.float64)


def osc_saw(freq: np.ndarray | float, n: int, sr: int, phase0: float = 0.0) -> np.ndarray:
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), n)
    phase = phase0 + np.cumsum(freq / sr)
    phase = phase - np.floor(phase)
    dt = freq / sr
    y = 2.0 * phase - 1.0
    y = y - _polyblep(phase, dt)
    return y.astype(np.float64)


def osc_triangle(freq: np.ndarray | float, n: int, sr: int, phase0: float = 0.0) -> np.ndarray:
    # Additive band-limited triangle (odd harmonics, 1/n^2)
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), n)
    t = np.arange(n, dtype=np.float64) / sr
    y = np.zeros(n, dtype=np.float64)
    nyquist = sr * 0.5
    for k in range(1, 32, 2):
        amp = ((-1) ** ((k - 1) // 2)) / (k * k)
        f = freq * k
        mask = f < (nyquist * 0.95)
        y += amp * np.sin(2.0 * np.pi * (phase0 + np.cumsum(np.where(mask, f, 0.0) / sr)))
    peak = np.max(np.abs(y)) + 1e-12
    return (y / peak).astype(np.float64)


def osc_sine(freq: np.ndarray | float, n: int, sr: int, phase0: float = 0.0) -> np.ndarray:
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), n)
    phase = phase0 + np.cumsum(freq / sr)
    return np.sin(2.0 * np.pi * phase).astype(np.float64)


def osc_fm(
    carrier_hz: float,
    mod_ratio: float,
    index: float,
    n: int,
    sr: int,
    amp_env: np.ndarray | None = None,
) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / sr
    mod = np.sin(2.0 * np.pi * carrier_hz * mod_ratio * t)
    y = np.sin(2.0 * np.pi * carrier_hz * t + index * mod)
    if amp_env is not None:
        y *= amp_env
    return y.astype(np.float64)


def smooth_wavetable(table: np.ndarray, n: int, sr: int, freq: float) -> np.ndarray:
    """Interpolate a small periodic wavetable without stair-steps."""
    table = np.asarray(table, dtype=np.float64)
    # periodic cubic-ish via FFT upsample
    up = np.fft.irfft(np.fft.rfft(table), n=max(len(table) * 16, 256))
    up /= np.max(np.abs(up)) + 1e-12
    phase = np.cumsum(np.full(n, freq / sr))
    idx = (phase % 1.0) * len(up)
    i0 = np.floor(idx).astype(int) % len(up)
    i1 = (i0 + 1) % len(up)
    frac = idx - np.floor(idx)
    return (up[i0] * (1.0 - frac) + up[i1] * frac).astype(np.float64)


# ---------------------------------------------------------------------------
# Envelopes
# ---------------------------------------------------------------------------
def adsr(
    n: int,
    sr: int,
    attack_ms: float = 5.0,
    decay_ms: float = 80.0,
    sustain: float = 0.7,
    release_ms: float = 5.0,
    hold_samples: int | None = None,
) -> np.ndarray:
    attack_ms = max(attack_ms, LIMITS["T16_env_ms_min"])
    release_ms = max(release_ms, LIMITS["T16_env_ms_min"])
    a = max(1, int(sr * attack_ms / 1000.0))
    d = max(1, int(sr * decay_ms / 1000.0))
    r = max(1, int(sr * release_ms / 1000.0))
    if hold_samples is None:
        hold_samples = max(0, n - a - d - r)
    else:
        hold_samples = max(0, hold_samples)
    env = np.zeros(n, dtype=np.float64)
    pos = 0
    a_len = min(a, n - pos)
    if a_len > 0:
        env[pos : pos + a_len] = np.linspace(0.0, 1.0, a_len, endpoint=False)
        pos += a_len
    d_len = min(d, n - pos)
    if d_len > 0:
        env[pos : pos + d_len] = np.linspace(1.0, sustain, d_len, endpoint=False)
        pos += d_len
    h_len = min(hold_samples, n - pos)
    if h_len > 0:
        env[pos : pos + h_len] = sustain
        pos += h_len
    r_len = min(r, n - pos)
    if r_len > 0:
        start = env[pos - 1] if pos > 0 else sustain
        env[pos : pos + r_len] = np.linspace(start, 0.0, r_len, endpoint=True)
        pos += r_len
    if pos < n:
        env[pos:] = 0.0
    return env


def place_note(
    buf: np.ndarray,
    start: int,
    wave: np.ndarray,
    env: np.ndarray,
) -> None:
    """Mix wave*env into buf with circular wrap for release tails."""
    n = len(buf)
    sig = wave * env
    length = len(sig)
    start = int(start) % n
    end = start + length
    if end <= n:
        buf[start:end] += sig
    else:
        first = n - start
        buf[start:] += sig[:first]
        buf[: length - first] += sig[first:]


# ---------------------------------------------------------------------------
# Circular DSP
# ---------------------------------------------------------------------------
def circular_filter(x: np.ndarray, b: np.ndarray, a: np.ndarray) -> np.ndarray:
    n = len(x)
    tiled = np.concatenate([x, x, x])
    y = signal.lfilter(b, a, tiled)
    return y[n : 2 * n].astype(np.float64)


def circular_sosfiltfilt(x: np.ndarray, sos: np.ndarray) -> np.ndarray:
    n = len(x)
    tiled = np.concatenate([x, x, x])
    y = signal.sosfiltfilt(sos, tiled)
    return y[n : 2 * n].astype(np.float64)


def circular_lowpass(x: np.ndarray, sr: int, cutoff_hz: float, order: int = 8) -> np.ndarray:
    sos = signal.butter(order, cutoff_hz / (sr * 0.5), btype="low", output="sos")
    return circular_sosfiltfilt(x, sos)


def circular_highpass(x: np.ndarray, sr: int, cutoff_hz: float, order: int = 4) -> np.ndarray:
    sos = signal.butter(order, cutoff_hz / (sr * 0.5), btype="high", output="sos")
    return circular_sosfiltfilt(x, sos)


def circular_bandpass(x: np.ndarray, sr: int, low_hz: float, high_hz: float, order: int = 4) -> np.ndarray:
    sos = signal.butter(order, [low_hz / (sr * 0.5), high_hz / (sr * 0.5)], btype="band", output="sos")
    return circular_sosfiltfilt(x, sos)


def circular_echo(x: np.ndarray, sr: int, delay_ms: float, feedback: float, wet: float) -> np.ndarray:
    wet = min(wet, LIMITS["T10_echo_wet_max"])
    delay = max(1, int(sr * delay_ms / 1000.0))
    n = len(x)
    out = x.copy()
    tap = np.zeros(n, dtype=np.float64)
    # Feedback delay line, circular, low-passed lightly each bounce
    state = x.copy()
    for bounce in range(8):
        state = np.roll(state, delay) * feedback
        state = circular_lowpass(state, sr, 3500.0, order=2)
        tap += state
        if 20.0 * np.log10(np.max(np.abs(state)) + 1e-12) < LIMITS["T10_echo_tail_db"]:
            break
    return ((1.0 - wet) * out + wet * tap).astype(np.float64)


def oversample_decimate(x: np.ndarray, oversample: int) -> np.ndarray:
    if oversample <= 1:
        return x.astype(np.float64)
    # x is already at oversampled rate; decimate with polyphase (zero-phase via filtfilt path)
    # Use resample_poly on tiled signal for circularity
    n = len(x)
    tiled = np.concatenate([x, x, x])
    y = signal.resample_poly(tiled, up=1, down=oversample)
    mid = len(y) // 3
    return y[mid : mid + n // oversample].astype(np.float64)


# ---------------------------------------------------------------------------
# Mixer / loudness / writers
# ---------------------------------------------------------------------------
def pan_stereo(mono: np.ndarray, pan: float) -> np.ndarray:
    """pan -1 left .. +1 right."""
    pan = float(np.clip(pan, -1.0, 1.0))
    left = np.cos((pan + 1.0) * 0.25 * np.pi)
    right = np.sin((pan + 1.0) * 0.25 * np.pi)
    return np.column_stack([mono * left, mono * right])


def soft_limit(x: np.ndarray, ceiling: float = 0.98) -> np.ndarray:
    return (ceiling * np.tanh(x / ceiling)).astype(np.float64)


def peak_db(x: np.ndarray) -> float:
    return 20.0 * np.log10(np.max(np.abs(x)) + 1e-12)


def apply_global_gain(x: np.ndarray, gain: float) -> np.ndarray:
    return (x * gain).astype(np.float64)


def measure_lufs_approx(x: np.ndarray, sr: int) -> float:
    """Rough K-weighted integrated loudness approximation (not a certified meter)."""
    if x.ndim == 1:
        mono = x
    else:
        mono = np.mean(x, axis=1)
    # Simplified K-weight: high shelf + highpass
    sos_hp = signal.butter(2, 60.0 / (sr * 0.5), btype="high", output="sos")
    y = circular_sosfiltfilt(mono, sos_hp)
    # Mean square -> LUFS-ish
    ms = np.mean(y * y) + 1e-12
    return -0.691 + 10.0 * np.log10(ms)


def true_peak_db(x: np.ndarray, sr: int) -> float:
    if x.ndim == 1:
        mono = x
    else:
        mono = np.max(np.abs(x), axis=1)
    up = signal.resample_poly(mono, up=4, down=1)
    return 20.0 * np.log10(np.max(np.abs(up)) + 1e-12)


def tpdf_dither(x: np.ndarray, nbits: int = 16, rng: np.random.Generator | None = None) -> np.ndarray:
    rng = rng or np.random.default_rng(0)
    lsb = 2.0 / (2**nbits)
    noise = (rng.random(x.shape) - 0.5 + rng.random(x.shape) - 0.5) * lsb
    return x + noise


def write_wav_16(path: Path, audio: np.ndarray, sr: int, seed: int = 0) -> None:
    x = np.clip(audio, -1.0, 1.0)
    x = tpdf_dither(x, 16, np.random.default_rng(seed))
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    wavfile.write(str(path), sr, pcm)


def write_wav_24(path: Path, audio: np.ndarray, sr: int) -> None:
    x = np.clip(audio, -1.0, 1.0)
    # scipy wavfile writes int32; pack 24-bit into high bytes
    pcm = np.clip(np.round(x * (2**23 - 1)), -(2**23), 2**23 - 1).astype(np.int32) << 8
    wavfile.write(str(path), sr, pcm)


def write_wav_pcm16_mono(path: Path, mono: np.ndarray, sr: int) -> None:
    x = np.clip(mono, -1.0, 1.0)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    wavfile.write(str(path), sr, pcm)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def check_loop_length(total_samples: int, bars: int, tempo: float, sr: int, signature: tuple[int, int]) -> CheckResult:
    expected = samples_per_bar(tempo, sr, signature) * bars
    ok = abs(expected - total_samples) < 1e-6 and total_samples == int(total_samples)
    return CheckResult("T1", "Loop length integer samples+bars", float(total_samples), "integer", "PASS" if ok else "FAIL")


def check_seam(x: np.ndarray) -> CheckResult:
    if x.ndim == 2:
        mono = np.mean(x, axis=1)
    else:
        mono = x
    diffs = np.abs(np.diff(mono))
    p99 = float(np.percentile(diffs, 99)) if len(diffs) else 0.0
    seam = abs(float(mono[0] - mono[-1]))
    # Also compare first-order jump across wrap using tiled endpoint
    wrap_jump = abs(float(mono[0] - mono[-1]))
    limit = max(p99, 1e-6)
    ok = wrap_jump <= limit * 1.05
    return CheckResult("T2", "Seam jump vs p99", wrap_jump, limit, "PASS" if ok else "FAIL")


def check_dc(x: np.ndarray) -> CheckResult:
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    v = float(np.abs(np.mean(mono)))
    return CheckResult("T5", "DC offset", v, LIMITS["T5_dc"], "PASS" if v < LIMITS["T5_dc"] else "FAIL")


def check_peak(x: np.ndarray) -> CheckResult:
    v = peak_db(x)
    return CheckResult("T3", "Pre-limiter peak dBFS", v, LIMITS["T3_pre_limiter_db"], "PASS" if v <= LIMITS["T3_pre_limiter_db"] + 1e-6 else "FAIL")


def check_true_peak(x: np.ndarray, sr: int) -> CheckResult:
    v = true_peak_db(x, sr)
    return CheckResult("T4", "True-peak dBFS", v, LIMITS["T4_true_peak_db"], "PASS" if v <= LIMITS["T4_true_peak_db"] + 1e-6 else "FAIL")


def check_hf(x: np.ndarray, sr: int, check_hz: float) -> CheckResult:
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    spec = np.abs(np.fft.rfft(mono))
    freqs = np.fft.rfftfreq(len(mono), 1.0 / sr)
    peak = np.max(spec) + 1e-12
    band = spec[freqs >= check_hz]
    hf = np.max(band) if len(band) else 0.0
    db = 20.0 * np.log10(hf / peak + 1e-12)
    # measured is how far below peak (positive = good)
    below = -db
    return CheckResult("T8", f"HF energy below peak @{check_hz:.0f}Hz", below, LIMITS["T8_hf_db"], "PASS" if below >= LIMITS["T8_hf_db"] else "FAIL")


def check_clicks(x: np.ndarray, sr: int, onset_samples: Iterable[int] | None = None) -> CheckResult:
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    d2 = np.diff(mono, n=2)
    thr = 8.0 * (np.std(d2) + 1e-9)
    hits = np.where(np.abs(d2) > thr)[0]
    protect = int(sr * LIMITS["T7_click_outside_onset_ms"] / 1000.0)
    onsets = set()
    if onset_samples:
        for o in onset_samples:
            for k in range(-protect, protect + 1):
                onsets.add(int(o) + k)
    bad = [h for h in hits if h not in onsets]
    return CheckResult("T7", "Click detector outside onsets", float(len(bad)), 0.0, "PASS" if len(bad) == 0 else "FAIL")


def check_harshness(x: np.ndarray, sr: int) -> CheckResult:
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    # A-weight approx via band energy 2-5 kHz
    sos = signal.butter(4, [2000 / (sr * 0.5), 5000 / (sr * 0.5)], btype="band", output="sos")
    band = circular_sosfiltfilt(mono, sos)
    win = max(1, int(sr * LIMITS["T14_window_ms"] / 1000.0))
    energies = []
    for i in range(0, len(band) - win, win):
        energies.append(np.mean(band[i : i + win] ** 2) + 1e-12)
    if not energies:
        return CheckResult("T14", "Harshness windows", 0.0, 0.0, "PASS")
    energies = np.asarray(energies)
    med = np.median(energies)
    flagged = np.sum(10.0 * np.log10(energies / med) > LIMITS["T14_harsh_db"])
    return CheckResult("T14", "Harshness flagged windows", float(flagged), 0.0, "PASS" if flagged == 0 else "FAIL")


def save_seam_plot(path: Path, x: np.ndarray, sr: int) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    ms = int(0.05 * sr)
    left = mono[-ms:]
    right = mono[:ms]
    y = np.concatenate([left, right])
    t = (np.arange(len(y)) - ms) / sr * 1000.0
    fig, ax = plt.subplots(figsize=(8, 3))
    ax.plot(t, y, lw=0.8)
    ax.axvline(0.0, color="r", ls="--", lw=0.8)
    ax.set_xlabel("ms around seam")
    ax.set_title("Seam check")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def print_report(results: list[CheckResult]) -> int:
    print("\n=== Check report ===")
    print(f"{'ID':<4} {'Name':<36} {'Measured':>12} {'Limit':>12} {'Result':<16}")
    exit_code = 0
    for r in results:
        print(f"{r.id:<4} {r.name:<36} {str(r.measured)[:12]:>12} {str(r.limit)[:12]:>12} {r.result:<16}")
        if r.result == "FAIL" and r.id in ("T1", "T2"):
            exit_code = 1
        elif r.result in ("WARNING", "FAIL") and exit_code == 0:
            exit_code = 2
    return exit_code


# ---------------------------------------------------------------------------
# Drum helpers (clean, filtered)
# ---------------------------------------------------------------------------
def synth_kick(n: int, sr: int) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / sr
    freq = 150.0 * (50.0 / 150.0) ** np.clip(t / 0.08, 0, 1)
    body = np.sin(2.0 * np.pi * np.cumsum(freq) / sr)
    env = np.exp(-t * 28.0)
    env[: max(1, int(0.005 * sr))] *= np.linspace(0, 1, max(1, int(0.005 * sr)))
    y = body * env
    y[-max(1, int(0.005 * sr)) :] *= np.linspace(1, 0, max(1, int(0.005 * sr)))
    return y.astype(np.float64)


def synth_snare(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / sr
    tone = np.sin(2.0 * np.pi * 210.0 * t) * np.exp(-t * 35.0)
    noise = rng.standard_normal(n)
    noise = circular_bandpass(noise, sr, 800.0, 4000.0)
    noise *= np.exp(-t * 45.0)
    y = 0.55 * tone + 0.45 * noise
    a = max(1, int(0.005 * sr))
    y[:a] *= np.linspace(0, 1, a)
    y[-a:] *= np.linspace(1, 0, a)
    return y.astype(np.float64)


def synth_hat(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / sr
    noise = rng.standard_normal(n)
    noise = circular_bandpass(noise, sr, 2000.0, 5500.0)
    y = noise * np.exp(-t * 90.0) * 0.35
    a = max(1, int(0.005 * sr))
    y[:a] *= np.linspace(0, 1, a)
    y[-a:] *= np.linspace(1, 0, a)
    return y.astype(np.float64)
