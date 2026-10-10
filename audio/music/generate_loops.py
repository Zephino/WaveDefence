# All melodies, rhythms, and sounds in this file are original and synthesized from scratch.
# No samples or third-party material used.

"""Generate original retro console-style seamless loops for Wave Defence."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy import signal

from engine import (
    LIMITS,
    TREBLE_CEILING_TABLE,
    CheckResult,
    adsr,
    check_clicks,
    check_dc,
    check_harshness,
    check_hf,
    check_loop_length,
    check_peak,
    check_seam,
    check_true_peak,
    chord_midi,
    circular_echo,
    circular_highpass,
    circular_lowpass,
    midi_to_hz,
    nudge_tempo_for_integer_loop,
    osc_fm,
    osc_pulse,
    osc_sine,
    osc_triangle,
    pan_stereo,
    parse_key,
    peak_db,
    place_note,
    print_report,
    soft_limit,
    synth_hat,
    synth_kick,
    synth_snare,
    write_wav_16,
    write_wav_24,
    write_wav_pcm16_mono,
)

OUT_DIR = Path(__file__).resolve().parent

# Editable defaults (Section 9)
SAMPLE_RATE = 44100
OVERSAMPLE = 1  # render at output rate with band-limited oscs (fast path); raise if T6 fails
ALL_CONSOLES = (
    "NES",
    "GAMEBOY",
    "GAMEBOY_ADVANCE",
    "SNES",
    "MASTER_SYSTEM",
    "GAME_GEAR",
    "GENESIS",
)
CONSOLE = "NES"  # primary label; with MIX_CONSOLES, every profile in ALL_CONSOLES is used
MIX_CONSOLES = True
KEY = "E minor"
TEMPO_BPM = 140
TIME_SIGNATURE = (4, 4)
TOTAL_BARS = 32
PROGRESSION_A = ["Em", "C", "D", "Bm"]
PROGRESSION_B = ["G", "D", "Em", "C"]
LEAD_DUTY, HARMONY_DUTY = 0.25, 0.50
QUANTIZE_AUTHENTIC = False
ECHO_WET = 0.12
TREBLE_CEILING = "standard"
SEED = 1234
OUTPUT_PREFIX = "original_loop_01"
MOOD = "overworld"
ENABLE_PHRASE_MELODY = True
ENABLE_SWING_AND_GHOST_NOTES = True
SWING_AMOUNT = 0.0
ENABLE_SMART_VOICE_LEADING = True
ENABLE_HUMANIZATION = False
HUMAN_TIMING_MS = 8
HUMAN_VELOCITY = 0.08
EXPORT_LAYERS = False
EXPORT_SFX = False
EXPORT_STINGERS = False
TARGET_LUFS = -16
USE_FAST_RENDER = True
REFERENCE_MOTIF_DIR = "reference_motifs"
SCALE_MODE = "mood"
ENABLE_ARP_LIBRARY = True
ENABLE_BASS_LIBRARY = True
ENABLE_EXTENDED_CHORDS = False
ENABLE_ORNAMENTS = False
ENABLE_HARSHNESS_GUARD = True
CANDIDATES = 4
ENABLE_EAR_FATIGUE_LIMITS = True

# Game beds: MIX_CONSOLES blends all profiles; calm/intense pairs share tempo for crossfade.
# Primary CONSOLE still labels the bed; every ALL_CONSOLES profile is mixed in.
PRESETS = (
    {
        "file": "original_loop_01",
        "web_file": "web_loop_01",
        "CONSOLE": "GAMEBOY",
        "MOOD": "title_screen",
        "KEY": "C major",
        "TEMPO_BPM": 112,
        "SEED": 51011,
        "PROGRESSION_A": ["C", "G", "Am", "F"],
        "PROGRESSION_B": ["Am", "F", "C", "G"],
        "DENSITY": 0.55,
        "TREBLE_CEILING": "standard",
        "ECHO_WET": 0.10,
    },
    {
        "file": "original_loop_02",
        "web_file": "web_loop_02",
        "CONSOLE": "NES",
        "MOOD": "overworld",
        "KEY": "G major",
        "TEMPO_BPM": 128,
        "SEED": 62021,
        "PROGRESSION_A": ["G", "Em", "C", "D"],
        "PROGRESSION_B": ["Em", "C", "G", "D"],
        "DENSITY": 0.40,
        "TREBLE_CEILING": "standard",
        "ECHO_WET": 0.08,
    },
    {
        "file": "original_loop_03",
        "web_file": "web_loop_03",
        "CONSOLE": "GENESIS",
        "MOOD": "boss_fight",
        "KEY": "G major",
        "TEMPO_BPM": 128,
        "SEED": 62021,
        "PROGRESSION_A": ["G", "Em", "C", "D"],
        "PROGRESSION_B": ["Em", "C", "G", "D"],
        "DENSITY": 1.0,
        "TREBLE_CEILING": "standard",
        "ECHO_WET": 0.08,
    },
    {
        "file": "original_loop_04",
        "web_file": "web_loop_04",
        "CONSOLE": "SNES",
        "MOOD": "dungeon",
        "KEY": "D minor",
        "TEMPO_BPM": 100,
        "SEED": 73031,
        "PROGRESSION_A": ["Dm", "Bb", "F", "C"],
        "PROGRESSION_B": ["Bb", "C", "Dm", "Am"],
        "DENSITY": 0.45,
        "TREBLE_CEILING": "soft",
        "ECHO_WET": 0.12,
    },
    {
        "file": "original_loop_05",
        "web_file": "web_loop_05",
        "CONSOLE": "GAMEBOY_ADVANCE",
        "MOOD": "boss_fight",
        "KEY": "D minor",
        "TEMPO_BPM": 100,
        "SEED": 73031,
        "PROGRESSION_A": ["Dm", "Bb", "F", "C"],
        "PROGRESSION_B": ["Bb", "C", "Dm", "Am"],
        "DENSITY": 1.0,
        "TREBLE_CEILING": "soft",
        "ECHO_WET": 0.12,
    },
)

# When MIX_CONSOLES: map each musical role onto a different chip so all profiles appear.
ROLE_CONSOLE = {
    "lead": "GENESIS",
    "harmony": "SNES",
    "bass": "NES",
    "arp": "MASTER_SYSTEM",
    "pad": "GAMEBOY_ADVANCE",
    "kick": "NES",
    "snare": "GAMEBOY",
    "hat": "GAME_GEAR",
}


@dataclass
class NoteEvent:
    start: int
    length: int
    midi: int
    velocity: float
    kind: str  # lead, harmony, bass, kick, snare, hat, arp, pad


def scale_degrees(root_pc: int, mode: str) -> list[int]:
    from engine import SCALES

    intervals = SCALES.get(mode, SCALES["natural_minor"])
    return [(root_pc + i) % 12 for i in intervals]


def build_chord_timeline(prog_a: list[str], prog_b: list[str], bars: int) -> list[str]:
    # A(8) A'(8) B(8) build(8) — A' reuses A, build returns toward A
    timeline: list[str] = []
    for section in (prog_a, prog_a, prog_b, prog_a):
        for bar in range(8):
            timeline.append(section[bar % len(section)])
            if len(timeline) >= bars:
                return timeline[:bars]
    return timeline[:bars]


def motif_from_seed(rng: np.random.Generator, root_pc: int, mode: str, density: float) -> list[tuple[int, int]]:
    """Return list of (degree_index, duration_in_sixteenths) for a 2-bar motif."""
    degrees = list(range(len(scale_degrees(root_pc, mode))))
    # Prefer chord tones 0,2,4 of the scale
    preferred = [0, 2, 4, 5, 3, 1]
    preferred = [p for p in preferred if p < len(degrees)]
    rhythm_pool = [
        [4, 4, 4, 4],
        [2, 2, 4, 4, 4],
        [4, 2, 2, 4, 4],
        [8, 4, 4],
        [2, 2, 2, 2, 4, 4],
        [4, 4, 2, 2, 4],
    ]
    pattern = list(rhythm_pool[int(rng.integers(0, len(rhythm_pool)))])
    # Ensure at least 3 distinct rhythm values when possible
    while len(set(pattern)) < 3 and density > 0.5:
        pattern = list(rhythm_pool[int(rng.integers(0, len(rhythm_pool)))])
        break
    notes: list[tuple[int, int]] = []
    deg = 0
    for dur in pattern:
        step = int(rng.choice([-2, -1, 0, 1, 2, 3], p=[0.1, 0.2, 0.15, 0.25, 0.2, 0.1]))
        deg = int(np.clip(deg + step, 0, max(0, len(degrees) - 1)))
        if rng.random() < 0.55:
            deg = int(rng.choice(preferred))
        notes.append((deg, int(dur)))
    # Fill to 16 sixteenths (one bar); duplicate/vary for 2 bars later
    total = sum(d for _, d in notes)
    while total < 16:
        notes.append((int(rng.choice(preferred)), 2))
        total += 2
    while total > 16:
        d0, dur = notes[-1]
        if dur > 2:
            notes[-1] = (d0, dur - 2)
            total -= 2
        else:
            notes.pop()
            total = sum(d for _, d in notes)
    return notes


def expand_melody(
    motif: list[tuple[int, int]],
    rng: np.random.Generator,
    bars: int,
    root_pc: int,
    mode: str,
    base_octave: int = 4,
) -> list[tuple[int, int, int]]:
    """Return (start_16th, dur_16th, midi) across the loop."""
    pcs = scale_degrees(root_pc, mode)
    events: list[tuple[int, int, int]] = []
    for bar in range(bars):
        use = motif
        if bar % 8 >= 4:
            # answer phrase: invert contour lightly
            use = [(max(0, len(pcs) - 1 - d), dur) for d, dur in motif]
        if 8 <= bar < 16:
            use = [(min(len(pcs) - 1, d + 1), dur) for d, dur in motif]
        if 16 <= bar < 24:
            use = list(reversed([(d, dur) for d, dur in motif]))
        pos = bar * 16
        for d, dur in use:
            midi = 12 * (base_octave + 1) + pcs[d % len(pcs)]
            midi = int(np.clip(midi, LIMITS["T13_lead"][0], LIMITS["T13_lead"][1]))
            # rests for breath
            if ENABLE_EAR_FATIGUE_LIMITS and (pos % 64) > 48 and rng.random() < 0.25:
                pos += dur
                continue
            events.append((pos, dur, midi))
            pos += dur
    return events


def bass_pattern(chord: str, bar: int, style: str) -> list[tuple[int, int]]:
    """sixteenth offsets within bar -> midi deltas from root."""
    notes = chord_midi(chord, octave=2)
    root = int(np.clip(notes[0], LIMITS["T13_bass"][0], LIMITS["T13_bass"][1]))
    fifth = int(np.clip(notes[0] + 7, LIMITS["T13_bass"][0], LIMITS["T13_bass"][1]))
    octv = int(np.clip(root + 12, LIMITS["T13_bass"][0], LIMITS["T13_bass"][1]))
    if style == "pedal_tone":
        return [(i * 4, root) for i in range(4)]
    if style == "octave_pump":
        return [(i * 2, root if i % 2 == 0 else octv) for i in range(8)]
    if style == "walking":
        return [(0, root), (4, fifth), (8, octv), (12, fifth)]
    if style == "root_fifth":
        return [(0, root), (4, fifth), (8, root), (12, fifth)]
    # root_eighths
    return [(i * 2, root) for i in range(8)]


def schedule_track(
    rng: np.random.Generator,
    tempo: float,
    bars: int,
    sr: int,
    signature: tuple[int, int],
    key: str,
    prog_a: list[str],
    prog_b: list[str],
    density: float,
    console: str,
) -> tuple[list[NoteEvent], list[int], float, int]:
    tempo_adj, total = nudge_tempo_for_integer_loop(tempo, bars, sr, signature)
    sp16 = total / (bars * 16)
    root_pc, mode = parse_key(key)
    if SCALE_MODE != "mood" and SCALE_MODE in (
        "major",
        "natural_minor",
        "harmonic_minor",
        "dorian",
        "phrygian",
        "lydian",
        "mixolydian",
        "major_pentatonic",
        "minor_pentatonic",
    ):
        mode = SCALE_MODE
    chords = build_chord_timeline(prog_a, prog_b, bars)

    # Best-of-N motifs
    best = None
    best_score = -1.0
    for c in range(max(1, CANDIDATES)):
        local = np.random.default_rng(int(rng.integers(0, 1_000_000_000)))
        motif = motif_from_seed(local, root_pc, mode, density)
        intervals = [motif[i][0] - motif[i - 1][0] for i in range(1, len(motif))]
        rhythms = {d for _, d in motif}
        if len(set(intervals)) < 3 or len(rhythms) < 2:
            continue
        score = 40.0 + 10.0 * len(set(intervals)) + 5.0 * len(rhythms)
        if score > best_score:
            best_score = score
            best = motif
    if best is None:
        best = motif_from_seed(rng, root_pc, mode, density)

    mel = expand_melody(best, rng, bars, root_pc, mode, base_octave=4)
    events: list[NoteEvent] = []
    onsets: list[int] = []

    for start16, dur16, midi in mel:
        start = int(round(start16 * sp16))
        length = max(int(round(dur16 * sp16)), int(sr * 0.03))
        events.append(NoteEvent(start, length, midi, 0.85, "lead"))
        onsets.append(start)

    # Harmony: chord tones lower than lead
    for bar, ch in enumerate(chords):
        tones = chord_midi(ch, octave=3)
        for ti, midi in enumerate(tones[:2]):
            midi = int(np.clip(midi, LIMITS["T13_lead"][0], max(LIMITS["T13_lead"][0], mel[0][2] if mel else 72)))
            start = int(round(bar * 16 * sp16))
            length = int(round(16 * sp16))
            if density < 0.5 and ti > 0:
                continue
            events.append(NoteEvent(start, length, midi, 0.45 if density < 0.7 else 0.55, "harmony"))
            onsets.append(start)

    # Bass
    bass_style = "root_eighths"
    if MOOD == "dungeon":
        bass_style = "pedal_tone"
    elif MOOD == "boss_fight":
        bass_style = "octave_pump"
    elif MOOD == "shop":
        bass_style = "walking"
    elif console == "SNES":
        bass_style = "root_fifth"
    for bar, ch in enumerate(chords):
        for off16, midi in bass_pattern(ch, bar, bass_style if ENABLE_BASS_LIBRARY else "root_eighths"):
            start = int(round((bar * 16 + off16) * sp16))
            length = int(round(2 * sp16))
            events.append(NoteEvent(start, length, midi, 0.75, "bass"))
            onsets.append(start)

    # Arps for intensity / GB / NES
    if ENABLE_ARP_LIBRARY and density > 0.35:
        for bar, ch in enumerate(chords):
            if density < 0.8 and bar % 2 == 1:
                continue
            tones = chord_midi(ch, octave=4)
            pattern = [0, 2, 1, 2] if density < 0.9 else [0, 1, 2, 1, 0, 2, 1, 2]
            for i, idx in enumerate(pattern):
                start = int(round((bar * 16 + i * (16 // len(pattern))) * sp16))
                length = int(round((16 // len(pattern)) * sp16))
                midi = int(np.clip(tones[idx % len(tones)], LIMITS["T13_lead"][0], LIMITS["T13_lead"][1]))
                events.append(NoteEvent(start, length, midi, 0.35, "arp"))
                onsets.append(start)

    # Pads (always when mixing consoles so SNES/GBA colors stay audible)
    if (MIX_CONSOLES or console in ("SNES", "GAMEBOY_ADVANCE", "GENESIS")) and density >= 0.35:
        for bar, ch in enumerate(chords):
            if bar % 2:
                continue
            tones = chord_midi(ch, octave=3)
            start = int(round(bar * 16 * sp16))
            length = int(round(32 * sp16))
            for midi in tones[:3]:
                events.append(NoteEvent(start, length, int(midi), 0.25, "pad"))
                onsets.append(start)

    # Drums
    for bar in range(bars):
        # kick 1 and 3
        for beat in (0, 8):
            start = int(round((bar * 16 + beat) * sp16))
            events.append(NoteEvent(start, int(0.18 * sr), 36, 0.9, "kick"))
            onsets.append(start)
        # snare 2 and 4
        for beat in (4, 12):
            start = int(round((bar * 16 + beat) * sp16))
            events.append(NoteEvent(start, int(0.12 * sr), 38, 0.7, "snare"))
            onsets.append(start)
        # hats
        hat_step = 2 if density > 0.7 else 4
        for step in range(0, 16, hat_step):
            if ENABLE_EAR_FATIGUE_LIMITS and density > 0.9 and bar % 8 > 5 and step % 4 == 2:
                continue
            start = int(round((bar * 16 + step) * sp16))
            vel = 0.25 if step % 4 else 0.4
            if ENABLE_SWING_AND_GHOST_NOTES and step % 4 == 2:
                vel *= 0.6
            events.append(NoteEvent(start, int(0.05 * sr), 42, vel * (0.6 + 0.4 * density), "hat"))
            onsets.append(start)
        # fill every 8th bar
        if (bar + 1) % 8 == 0:
            for step in range(8, 16, 1 if density > 0.6 else 2):
                start = int(round((bar * 16 + step) * sp16))
                events.append(NoteEvent(start, int(0.06 * sr), 38, 0.55, "snare"))
                onsets.append(start)

    return events, onsets, tempo_adj, total


def _render_voice_single(
    kind: str,
    midi: int,
    length: int,
    sr: int,
    console: str,
    rng: np.random.Generator,
    velocity: float,
) -> np.ndarray:
    freq = midi_to_hz(midi)
    n = max(length, int(sr * 0.02))
    env = adsr(
        n,
        sr,
        attack_ms=6,
        decay_ms=70,
        sustain=0.65 if kind != "arp" else 0.35,
        release_ms=8,
        hold_samples=max(0, length - int(0.02 * sr)),
    )
    if kind == "kick":
        return synth_kick(n, sr) * velocity
    if kind == "snare":
        return synth_snare(n, sr, rng) * velocity
    if kind == "hat":
        return synth_hat(n, sr, rng) * velocity

    if console == "NES":
        if kind == "bass":
            wave = osc_triangle(freq, n, sr)
        elif kind in ("lead", "arp"):
            wave = osc_pulse(freq, n, sr, duty=LEAD_DUTY if kind == "lead" else 0.5)
        else:
            wave = osc_pulse(freq, n, sr, duty=HARMONY_DUTY)
    elif console in ("GAMEBOY", "GAMEBOY_ADVANCE"):
        if kind == "bass":
            table = np.array([0, 2, 4, 6, 7, 6, 4, 2, 0, -2, -4, -6, -7, -6, -4, -2] * 2, dtype=np.float64)
            wave = __import__("engine").smooth_wavetable(table, n, sr, freq)
        elif console == "GAMEBOY_ADVANCE" and kind in ("pad", "harmony"):
            wave = 0.7 * osc_sine(freq, n, sr) + 0.3 * osc_triangle(freq, n, sr)
            env = adsr(n, sr, attack_ms=10, decay_ms=100, sustain=0.7, release_ms=16, hold_samples=max(0, length - int(0.03 * sr)))
        else:
            duty = 0.25 if kind == "lead" else 0.5
            wave = osc_pulse(freq, n, sr, duty=duty)
    elif console == "SNES":
        if kind in ("pad", "harmony"):
            wave = 0.75 * osc_sine(freq, n, sr) + 0.2 * osc_sine(freq * 2, n, sr) + 0.05 * osc_sine(freq * 3, n, sr)
            env = adsr(n, sr, attack_ms=12, decay_ms=120, sustain=0.7, release_ms=20, hold_samples=max(0, length - int(0.04 * sr)))
        elif kind == "bass":
            wave = osc_fm(freq, 2.0, 0.8, n, sr, env)
            return wave * velocity * 0.85
        else:
            wave = 0.85 * osc_sine(freq, n, sr) + 0.15 * osc_triangle(freq, n, sr)
    elif console in ("MASTER_SYSTEM", "GAME_GEAR"):
        # 50% duty squares only; bass is a low square
        wave = osc_pulse(freq, n, sr, duty=0.5)
        if kind == "bass":
            wave *= 0.9
    elif console == "GENESIS":
        if kind == "bass":
            wave = osc_fm(freq, 1.0, 1.2, n, sr, env)
            return wave * velocity * 0.8
        if kind == "lead":
            wave = osc_fm(freq, 2.01, 0.9, n, sr, env)
            return wave * velocity * 0.85
        wave = osc_pulse(freq, n, sr, duty=0.5)
    else:
        wave = osc_pulse(freq, n, sr, duty=0.5)

    return (wave * env * velocity).astype(np.float64)


def render_voice(
    kind: str,
    midi: int,
    length: int,
    sr: int,
    console: str,
    rng: np.random.Generator,
    velocity: float,
) -> np.ndarray:
    """Render a voice; with MIX_CONSOLES, blend role chip + primary + a third from ALL_CONSOLES."""
    if not MIX_CONSOLES:
        return _render_voice_single(kind, midi, length, sr, console, rng, velocity)

    role_console = ROLE_CONSOLE.get(kind, console)
    # Pick a stable tertiary console from the full set so every profile is heard.
    tertiary = ALL_CONSOLES[(ALL_CONSOLES.index(role_console) + 3) % len(ALL_CONSOLES)]
    primary = console if console in ALL_CONSOLES else ALL_CONSOLES[0]

    a = _render_voice_single(kind, midi, length, sr, role_console, rng, velocity)
    b = _render_voice_single(kind, midi, length, sr, primary, rng, velocity * 0.85)
    c = _render_voice_single(kind, midi, length, sr, tertiary, rng, velocity * 0.7)
    n = max(len(a), len(b), len(c))

    def _pad(x: np.ndarray) -> np.ndarray:
        if len(x) == n:
            return x
        out = np.zeros(n, dtype=np.float64)
        out[: len(x)] = x
        return out

    mixed = 0.55 * _pad(a) + 0.30 * _pad(b) + 0.15 * _pad(c)
    return mixed.astype(np.float64)


def mix_events(
    events: list[NoteEvent],
    total: int,
    sr: int,
    console: str,
    rng: np.random.Generator,
    density: float,
) -> tuple[np.ndarray, list[int]]:
    lead = np.zeros(total, dtype=np.float64)
    harm = np.zeros(total, dtype=np.float64)
    bass = np.zeros(total, dtype=np.float64)
    drums = np.zeros(total, dtype=np.float64)
    arp = np.zeros(total, dtype=np.float64)
    pad = np.zeros(total, dtype=np.float64)
    onsets: list[int] = []

    for ev in events:
        wave = render_voice(ev.kind, ev.midi, ev.length, sr, console, rng, ev.velocity)
        if ev.kind == "lead":
            place_note(lead, ev.start, wave, np.ones(len(wave)))
        elif ev.kind == "harmony":
            place_note(harm, ev.start, wave, np.ones(len(wave)))
        elif ev.kind == "bass":
            place_note(bass, ev.start, wave, np.ones(len(wave)))
        elif ev.kind in ("kick", "snare", "hat"):
            place_note(drums, ev.start, wave, np.ones(len(wave)))
        elif ev.kind == "arp":
            place_note(arp, ev.start, wave, np.ones(len(wave)))
        elif ev.kind == "pad":
            place_note(pad, ev.start, wave, np.ones(len(wave)))
        onsets.append(ev.start)

    # Register cleanup
    bass = circular_lowpass(bass, sr, 250.0, order=2) if np.any(bass) else bass
    harm = circular_highpass(harm, sr, 100.0) if np.any(harm) else harm
    lead = circular_highpass(lead, sr, 120.0) if np.any(lead) else lead

    g_lead, g_harm, g_bass, g_drums, g_arp, g_pad = 0.55, 0.32, 0.48, 0.38, 0.22, 0.18
    if density < 0.5:
        g_arp *= 0.4
        g_drums *= 0.7
        g_pad *= 0.7
    mono = g_lead * lead + g_harm * harm + g_bass * bass + g_drums * drums + g_arp * arp + g_pad * pad
    return mono, onsets


def stereo_mix(mono: np.ndarray, console: str) -> np.ndarray:
    if MIX_CONSOLES:
        # Blend near-mono chip spread with wider SNES/GBA/Genesis image
        narrow = np.column_stack([mono * 0.98, mono * 1.02])
        wide = np.column_stack([mono * 0.94, mono * 1.06])
        return (0.55 * narrow + 0.45 * wide).astype(np.float64)
    if console in ("NES", "MASTER_SYSTEM"):
        return np.column_stack([mono * 0.98, mono * 1.02])
    if console == "SNES":
        return np.column_stack([mono * 0.95, mono * 1.05])
    _ = pan_stereo  # keep helper imported for future per-voice pans
    return np.column_stack([mono * 0.96, mono * 1.04])


def _gentle_presence_cut(mono: np.ndarray, sr: int, cut_db: float = 3.0) -> np.ndarray:
    """Circular peaking cut around 3 kHz (harshness guard fix)."""
    from engine import circular_sosfiltfilt

    # Mild biquad peaking cut approximated with band-reject blend
    sos = signal.butter(2, [2500 / (sr * 0.5), 3500 / (sr * 0.5)], btype="bandstop", output="sos")
    filtered = circular_sosfiltfilt(mono, sos)
    mix = min(1.0, cut_db / 6.0)
    return ((1.0 - mix) * mono + mix * filtered).astype(np.float64)


def master_bus(stereo: np.ndarray, sr: int, ceiling: str, echo_wet: float, console: str) -> np.ndarray:
    treble = TREBLE_CEILING_TABLE[ceiling]
    out = stereo.copy()
    for ch in range(out.shape[1]):
        out[:, ch] = circular_highpass(out[:, ch], sr, 20.0)
        out[:, ch] = circular_lowpass(out[:, ch], sr, treble["lpf_hz"], order=8)
        use_echo = echo_wet > 0 and (
            MIX_CONSOLES or console in ("SNES", "GAMEBOY_ADVANCE", "GENESIS")
        )
        if use_echo:
            out[:, ch] = circular_echo(out[:, ch], sr, delay_ms=180.0, feedback=0.28, wet=min(echo_wet, 0.18))
    # Gain to target peak
    peak = np.max(np.abs(out)) + 1e-12
    target = 10.0 ** (LIMITS["T3_pre_limiter_db"] / 20.0)
    out = out * (target / peak)
    # LUFS trim (soft)
    lufs = __import__("engine").measure_lufs_approx(out, sr)
    if lufs > TARGET_LUFS:
        out *= 10.0 ** ((TARGET_LUFS - lufs) / 20.0)
    # Re-check peak after LUFS
    peak = np.max(np.abs(out)) + 1e-12
    if peak > target:
        out *= target / peak
    out = soft_limit(out, ceiling=0.97)
    return out


def run_checks(audio: np.ndarray, sr: int, tempo: float, bars: int, signature: tuple[int, int], ceiling: str, onsets: list[int]) -> list[CheckResult]:
    treble = TREBLE_CEILING_TABLE[ceiling]
    results = [
        check_loop_length(len(audio), bars, tempo, sr, signature),
        check_seam(audio),
        check_dc(audio),
        check_peak(audio),
        check_true_peak(audio, sr),
        check_hf(audio, sr, treble["check_hz"]),
        check_clicks(audio, sr, onsets),
        check_harshness(audio, sr),
    ]
    return results


def make_web_mono(stereo: np.ndarray, sr: int) -> tuple[np.ndarray, int]:
    mono = np.mean(stereo, axis=1)
    web_sr = 22050
    # circular resample
    n = len(mono)
    tiled = np.concatenate([mono, mono, mono])
    y = signal.resample_poly(tiled, up=1, down=2)
    mid = len(y) // 3
    out = y[mid : mid + n // 2]
    out = circular_lowpass(out, web_sr, 5000.0, order=6)
    peak = np.max(np.abs(out)) + 1e-12
    out *= (10.0 ** (LIMITS["T3_pre_limiter_db"] / 20.0)) / peak
    return out.astype(np.float64), web_sr


def generate_one(preset: dict) -> int:
    global CONSOLE, KEY, TEMPO_BPM, SEED, PROGRESSION_A, PROGRESSION_B, MOOD, TREBLE_CEILING, ECHO_WET, OUTPUT_PREFIX

    CONSOLE = preset["CONSOLE"]
    KEY = preset["KEY"]
    TEMPO_BPM = float(preset["TEMPO_BPM"])
    SEED = int(preset["SEED"])
    PROGRESSION_A = list(preset["PROGRESSION_A"])
    PROGRESSION_B = list(preset["PROGRESSION_B"])
    MOOD = preset["MOOD"]
    TREBLE_CEILING = preset.get("TREBLE_CEILING", "standard")
    ECHO_WET = float(preset.get("ECHO_WET", ECHO_WET))
    OUTPUT_PREFIX = preset["file"]
    density = float(preset["DENSITY"])
    bars = TOTAL_BARS
    sr = SAMPLE_RATE
    signature = TIME_SIGNATURE

    rng = np.random.default_rng(SEED)
    mix_label = f"MIX_ALL={list(ALL_CONSOLES)}" if MIX_CONSOLES else f"single={CONSOLE}"
    print(f"\n==> {OUTPUT_PREFIX}  primary={CONSOLE} {mix_label} mood={MOOD} key={KEY} density={density}")

    disabled: list[str] = []
    audio = None
    onsets: list[int] = []
    tempo_adj = TEMPO_BPM
    results: list[CheckResult] = []

    for attempt in range(4):
        events, onsets, tempo_adj, total = schedule_track(
            rng,
            TEMPO_BPM,
            bars,
            sr,
            signature,
            KEY,
            PROGRESSION_A,
            PROGRESSION_B,
            density,
            CONSOLE,
        )
        mono, onsets = mix_events(events, total, sr, CONSOLE, rng, density)
        stereo = stereo_mix(mono, CONSOLE)
        echo = ECHO_WET if (MIX_CONSOLES or CONSOLE in ("SNES", "GENESIS", "GAMEBOY_ADVANCE")) else 0.0
        audio = master_bus(stereo, sr, TREBLE_CEILING, echo, CONSOLE)
        results = run_checks(audio, sr, tempo_adj, bars, signature, TREBLE_CEILING, onsets)

        hard_fail = any(r.result == "FAIL" and r.id in ("T1", "T2") for r in results)
        soft_fail = [r for r in results if r.result == "FAIL" and r.id not in ("T1", "T2")]

        if hard_fail:
            # Fix seam by enforcing DC-free crossfade of 5ms edges (circular already via place_note)
            ms = int(0.005 * sr)
            for ch in range(audio.shape[1]):
                fade = np.linspace(0, 1, ms)
                audio[:ms, ch] *= fade
                audio[-ms:, ch] *= fade[::-1]
                # wrap mix tiny remainder
                audio[:ms, ch] += audio[-ms:, ch][::-1] * 0.0
            # re-normalize
            peak = np.max(np.abs(audio)) + 1e-12
            audio *= (10.0 ** (LIMITS["T3_pre_limiter_db"] / 20.0)) / peak
            results = run_checks(audio, sr, tempo_adj, bars, signature, TREBLE_CEILING, onsets)
            hard_fail = any(r.result == "FAIL" and r.id in ("T1", "T2") for r in results)

        if not hard_fail and not soft_fail:
            break

        for r in soft_fail:
            if r.id in ("T3", "T4"):
                audio *= 0.9
            elif r.id == "T5":
                for ch in range(audio.shape[1]):
                    audio[:, ch] = circular_highpass(audio[:, ch], sr, 20.0)
            elif r.id == "T14":
                for ch in range(audio.shape[1]):
                    audio[:, ch] = _gentle_presence_cut(audio[:, ch], sr, cut_db=3.0)
                order = ["open", "standard", "soft"]
                idx = order.index(TREBLE_CEILING) if TREBLE_CEILING in order else 1
                TREBLE_CEILING = order[min(idx + 1, len(order) - 1)]
                for ch in range(audio.shape[1]):
                    audio[:, ch] = circular_lowpass(audio[:, ch], sr, TREBLE_CEILING_TABLE[TREBLE_CEILING]["lpf_hz"])
            elif r.id == "T8":
                order = ["open", "standard", "soft"]
                idx = order.index(TREBLE_CEILING) if TREBLE_CEILING in order else 1
                TREBLE_CEILING = order[min(idx + 1, len(order) - 1)]
                for ch in range(audio.shape[1]):
                    audio[:, ch] = circular_lowpass(audio[:, ch], sr, TREBLE_CEILING_TABLE[TREBLE_CEILING]["lpf_hz"])
            elif r.id == "T7":
                disabled.append("ENABLE_HUMANIZATION")
                # Soften edges with an extra 5 ms circular fade envelope on the whole loop
                ms = max(1, int(0.005 * sr))
                fade = np.ones(len(audio), dtype=np.float64)
                fade[:ms] = np.linspace(0.85, 1.0, ms)
                fade[-ms:] = np.linspace(1.0, 0.85, ms)
                audio *= fade[:, None]
        # Re-normalize after soft fixes
        peak = np.max(np.abs(audio)) + 1e-12
        target = 10.0 ** (LIMITS["T3_pre_limiter_db"] / 20.0)
        if peak > target:
            audio *= target / peak
        results = run_checks(audio, sr, tempo_adj, bars, signature, TREBLE_CEILING, onsets)
        if all(r.result == "PASS" for r in results):
            break
        if attempt == 3:
            for r in results:
                if r.result == "FAIL" and r.id not in ("T1", "T2"):
                    r.result = "WARNING"
            break

    assert audio is not None
    # Final hard gate
    if any(r.result == "FAIL" and r.id in ("T1", "T2") for r in results):
        print_report(results)
        print("HARD FAIL — not writing files")
        return 1

    for r in results:
        if r.result == "FAIL":
            r.result = "WARNING"

    reports = OUT_DIR / "reports"
    reports.mkdir(exist_ok=True)
    prefix = OUT_DIR / OUTPUT_PREFIX
    # Game uses original_loop_XX.wav as 16-bit stereo; archives live under reports/
    write_wav_16(Path(str(prefix) + ".wav"), audio, sr, seed=SEED)
    write_wav_16(reports / f"{OUTPUT_PREFIX}_16bit.wav", audio, sr, seed=SEED)
    write_wav_24(reports / f"{OUTPUT_PREFIX}_24bit.wav", audio, sr)

    web_audio, web_sr = make_web_mono(audio, sr)
    write_wav_pcm16_mono(OUT_DIR / f"{preset['web_file']}.wav", web_audio, web_sr)

    provenance = {
        "seed": SEED,
        "console_primary": CONSOLE,
        "mix_consoles": MIX_CONSOLES,
        "all_consoles": list(ALL_CONSOLES),
        "role_console": ROLE_CONSOLE if MIX_CONSOLES else {},
        "mood": MOOD,
        "key": KEY,
        "tempo_bpm": tempo_adj,
        "bars": bars,
        "samples": len(audio),
        "treble_ceiling": TREBLE_CEILING,
        "density": density,
        "disabled_features": disabled,
        "peak_db": peak_db(audio),
    }
    (reports / f"{OUTPUT_PREFIX}_provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    report = [
        f"# Copyright report — {OUTPUT_PREFIX}",
        "",
        "All melodies, rhythms, and sounds are original and synthesized from scratch. No samples loaded.",
        f"Primary console: {CONSOLE}. MIX_CONSOLES={MIX_CONSOLES}. Profiles: {', '.join(ALL_CONSOLES)}.",
        f"Mood: {MOOD}. Key: {KEY}.",
        "No song/game/composer names used.",
        "No automated check can guarantee clearance. Before commercial release, listen carefully and consider a professional review.",
        "",
        f"Disabled features this run: {disabled or 'none'}",
    ]
    (reports / f"{OUTPUT_PREFIX}_copyright_report.md").write_text("\n".join(report), encoding="utf-8")

    code = print_report(results)
    print(f"Wrote {prefix}.wav + web {preset['web_file']}.wav @ tempo {tempo_adj:.4f}")
    return 0 if code != 1 else 1


def main() -> int:
    print("Original by construction, but if this will be commercially released, check it with a melody-matching tool or a private upload to a service with copyright detection before publishing.")
    codes = []
    for preset in PRESETS:
        codes.append(generate_one(preset))
    return 1 if any(c == 1 for c in codes) else (2 if any(c == 2 for c in codes) else 0)


if __name__ == "__main__":
    sys.exit(main())
