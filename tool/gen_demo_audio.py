"""Generates the two ORIGINAL demo tracks bundled with SAHBI.

They are synthesised from scratch (sine/FM tones + noise percussion), so there
is no third-party material. Dedicated to the public domain under CC0 1.0 by
the SAHBI project. Run: python3 tool/gen_demo_audio.py
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def env(n, a=0.01, r=0.3):
    t = np.arange(n) / SR
    e = np.minimum(1, t / a) * np.exp(-t / r)
    return e


def tone(freq, dur, kind="pluck", vol=0.3):
    n = int(SR * dur)
    t = np.arange(n) / SR
    if kind == "pluck":  # oud-like FM pluck
        mod = np.sin(2 * np.pi * freq * 2 * t) * 1.5 * np.exp(-t * 6)
        s = np.sin(2 * np.pi * freq * t + mod) * env(n, 0.004, 0.35)
    elif kind == "bass":
        s = np.sin(2 * np.pi * freq * t) * env(n, 0.01, 0.5)
    else:  # pad
        s = (np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2.01 * t)) * np.minimum(1, t / 0.4) * np.exp(-t / 2)
    return s * vol


def krakeb(dur, vol=0.12):
    """Metallic double-click (inspired by castanet rhythm, synthesised)."""
    n = int(SR * dur)
    rng = np.random.default_rng(7)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    ring = np.sin(2 * np.pi * 3100 * t) * 0.5 + np.sin(2 * np.pi * 4700 * t) * 0.3
    return (noise * 0.4 + ring) * np.exp(-t * 60) * vol


def render(path, bpm, scale, melody, bars, seed):
    beat = 60 / bpm
    total = int(SR * beat * 4 * bars) + SR
    mix = np.zeros(total)
    rng = np.random.default_rng(seed)

    def add(sig, at):
        i = int(at * SR)
        j = min(total, i + len(sig))
        mix[i:j] += sig[: j - i]

    root = scale[0]
    for bar in range(bars):
        t0 = bar * 4 * beat
        # 6/8-ish swing pattern: heavy-light-light
        for k, w in enumerate([1, 0.6, 0.8, 1, 0.6, 0.9, 0.6, 0.8]):
            add(krakeb(0.12, 0.1 * w), t0 + k * beat / 2)
        add(tone(root / 2, beat * 2, "bass", 0.35), t0)
        add(tone(scale[2] / 2, beat * 2, "bass", 0.3), t0 + 2 * beat)
        add(tone(root, beat * 4, "pad", 0.06), t0)
        for k, deg in enumerate(melody[bar % len(melody)]):
            if deg is None:
                continue
            f = scale[deg % len(scale)] * (2 if deg >= len(scale) else 1)
            add(tone(f * (1 + rng.normal(0, 0.001)), beat * 0.9, "pluck", 0.22), t0 + k * beat / 2)
    mix /= np.max(np.abs(mix)) + 1e-9
    fade = int(SR * 0.8)
    mix[-fade:] *= np.linspace(1, 0, fade)
    data = (mix * 0.85 * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


os.makedirs(OUT, exist_ok=True)
# D Hijaz-like and A minor pentatonic-like scales (Hz)
hijaz = [293.66, 311.13, 369.99, 392.0, 440.0, 466.16, 523.25]
penta = [220.0, 261.63, 293.66, 329.63, 392.0]
render(os.path.join(OUT, "sahbi_demo_atlas_breeze.wav"), 96, penta,
       [[0, None, 2, 3, 4, None, 3, 2], [1, 2, None, 4, 5, 4, 2, None], [0, 2, 4, None, 3, 2, 1, 0], [4, None, 3, 2, 1, None, 0, None]], bars=8, seed=1)
render(os.path.join(OUT, "sahbi_demo_medina_steps.wav"), 108, hijaz,
       [[0, 1, 2, None, 3, 2, 1, None], [2, 3, 4, 5, 4, None, 2, 1], [0, None, 1, 2, 3, 4, 3, 2], [1, 2, 1, None, 0, None, 0, None]], bars=8, seed=2)
for f in sorted(os.listdir(OUT)):
    print(f, os.path.getsize(os.path.join(OUT, f)))
