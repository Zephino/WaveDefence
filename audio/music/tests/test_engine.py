# Engine unit tests (Section 0.4) — must pass before music generation.

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import engine as eng


def test_sine_loop_seam():
    sr = 44100
    n = 44100  # 1 second exact
    t = np.arange(n) / sr
    # Integer cycles so seam is perfect
    y = np.sin(2.0 * np.pi * 440.0 * t)
    r = eng.check_seam(y)
    assert r.result == "PASS"


def test_circular_filter_matches_convolution():
    from scipy import signal

    rng = np.random.default_rng(0)
    x = rng.standard_normal(2048)
    b, a = signal.butter(4, 0.2)
    y1 = eng.circular_filter(x, b, a)
    tiled = np.concatenate([x, x, x])
    y2 = signal.lfilter(b, a, tiled)[len(x) : 2 * len(x)]
    assert np.max(np.abs(y1 - y2)) < 1e-9


def test_bandlimited_vs_naive_aliasing_probe():
    sr = 44100
    n = 16384
    freq = 1500.0
    bl = eng.osc_pulse(freq, n, sr, duty=0.5)
    t = np.arange(n) / sr
    naive = np.sign(np.sin(2.0 * np.pi * freq * t))

    def energy_above(x, hz: float) -> float:
        spec = np.abs(np.fft.rfft(x)) ** 2
        freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
        return float(np.sum(spec[freqs > hz]))

    assert energy_above(naive, 16000.0) > energy_above(bl, 16000.0) * 2.0


def test_loop_math_integer_and_nudge():
    tempo, n = eng.nudge_tempo_for_integer_loop(140.0, 8, 44100, (4, 4))
    assert n == int(n)
    assert abs(eng.samples_per_bar(tempo, 44100, (4, 4)) * 8 - n) < 1e-6
    for sig in ((4, 4), (3, 4), (6, 8), (7, 8)):
        tempo2, n2 = eng.nudge_tempo_for_integer_loop(123.456, 8, 44100, sig)
        assert n2 == int(n2)


def test_limiter_lufs_dither():
    x = np.sin(2.0 * np.pi * 440.0 * np.arange(44100) / 44100.0) * 0.5
    limited = eng.soft_limit(x * 2.0)
    assert np.max(np.abs(limited)) <= 0.98 + 1e-6
    lufs = eng.measure_lufs_approx(x, 44100)
    assert np.isfinite(lufs)
    d = eng.tpdf_dither(x.reshape(-1, 1), 16, np.random.default_rng(1))
    assert d.shape == (44100, 1)


def test_click_detector():
    sr = 44100
    y = np.sin(2.0 * np.pi * 220.0 * np.arange(sr) / sr) * 0.2
    clean = eng.check_clicks(y, sr, onset_samples=[])
    assert clean.result == "PASS"
    y2 = y.copy()
    y2[10000] += 1.0
    bad = eng.check_clicks(y2, sr, onset_samples=[])
    assert bad.result == "FAIL"
    ok = eng.check_clicks(y2, sr, onset_samples=[10000])
    assert ok.result == "PASS"
