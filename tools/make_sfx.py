"""Synthesizes the game's sound effects into assets/sfx (no third-party audio, no licensing).

Run: python3 tools/make_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def sweep(f0, f1, dur, vol=0.5, decay=6.0, wave_shape="square"):
    """Pitch slide from f0 to f1 (exponential), with a decaying envelope."""
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        if wave_shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
            s *= 0.6
        elif wave_shape == "saw":
            s = ((phase / math.pi) % 2) - 1
        else:
            s = math.sin(phase)
        env = min(1.0, t / 0.003) * math.exp(-decay * t)
        out.append(vol * env * s)
    return out


def noise(dur, vol=0.3, decay=30.0, seed=1, lowpass=0.0):
    rng = random.Random(seed)
    out, prev = [], 0.0
    for i in range(int(RATE * dur)):
        v = rng.uniform(-1, 1)
        prev = prev * lowpass + v * (1 - lowpass)
        out.append(vol * prev * math.exp(-decay * i / RATE))
    return out


def mix(*tracks):
    """tracks: (start_seconds, samples)"""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    buf = [0.0] * length
    for start, s in tracks:
        o = int(start * RATE)
        for i, v in enumerate(s):
            buf[o + i] += v
    return buf


def save(name, samples):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in samples))


OUT.mkdir(parents=True, exist_ok=True)

# Calm, rounded sounds: mostly sines, short and soft.
# Shot: airy upward "fwip".
save("shoot", mix((0, sweep(380, 900, 0.09, vol=0.3, decay=22, wave_shape="sine")), (0, noise(0.06, vol=0.06, decay=50, lowpass=0.85))))
# Wall bounce: tiny wooden tick.
save("bounce", sweep(1200, 1000, 0.035, vol=0.25, decay=90, wave_shape="sine"))
# Bubble sticks without popping: soft muted thud.
save("stick", mix((0, sweep(260, 180, 0.09, vol=0.4, decay=35, wave_shape="sine")), (0, noise(0.03, vol=0.08, decay=120, lowpass=0.9))))
# Pop: classic bubble bloop, a quick upward blip.
save("pop", mix((0, sweep(500, 1300, 0.07, vol=0.45, decay=40, wave_shape="sine")), (0.03, sweep(900, 1700, 0.06, vol=0.25, decay=50, wave_shape="sine"))))
# Bubbles dropping off: a gentle descending glissando of plinks.
save("fall", mix(*[(i * 0.045, sweep(f, f * 0.98, 0.14, vol=0.22, decay=22, wave_shape="sine")) for i, f in enumerate([1318.5, 1174.7, 987.8, 880.0, 784.0, 659.3])]))
# Bomb: soft boom.
save("bomb", mix((0, noise(0.45, vol=0.45, decay=9, seed=2, lowpass=0.8)), (0, sweep(160, 45, 0.35, vol=0.45, decay=8, wave_shape="sine"))))
# Ice thaws: glassy crack.
save("thaw", mix((0, noise(0.05, vol=0.25, decay=70, seed=5)), (0, sweep(2600, 2200, 0.22, vol=0.18, decay=14, wave_shape="sine")), (0.03, sweep(3300, 2900, 0.18, vol=0.12, decay=16, wave_shape="sine"))))
# Ceiling drops: low two-note thunk.
save("drop", mix((0, sweep(150, 110, 0.25, vol=0.5, decay=10, wave_shape="sine")), (0.12, sweep(110, 80, 0.3, vol=0.45, decay=9, wave_shape="sine")), (0, noise(0.2, vol=0.15, decay=18, seed=6, lowpass=0.9))))
# Boss core hit: deep wobble with a sparkle.
save("bossHit", mix((0, sweep(300, 120, 0.3, vol=0.45, decay=9, wave_shape="saw")), (0, noise(0.15, vol=0.2, decay=25, seed=7, lowpass=0.7)), (0.05, sweep(1600, 1500, 0.2, vol=0.12, decay=15, wave_shape="sine"))))
# Shield blocks a shot: glassy ping.
save("shield", mix((0, sweep(1800, 1200, 0.3, vol=0.3, decay=10, wave_shape="sine")), (0.02, sweep(2400, 1600, 0.25, vol=0.2, decay=12, wave_shape="sine"))))
# Boss regrows: soft rising bubbling.
save("regrow", mix(*[(i * 0.06, sweep(f, f * 1.5, 0.08, vol=0.2, decay=30, wave_shape="sine")) for i, f in enumerate([300, 360, 420, 500])]))
# Boss down: long soft rumble with a bright major tail.
save("bossDown", mix((0, noise(1.4, vol=0.45, decay=2.5, seed=4, lowpass=0.85)), (0, sweep(140, 35, 1.0, vol=0.45, decay=3, wave_shape="sine")),
                     *[(0.4 + i * 0.09, sweep(f, f, 0.7, vol=0.16, decay=4, wave_shape="sine")) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Level clear: warm major arpeggio.
save("levelClear", mix(*[(i * 0.1, sweep(f, f, 0.5 if i < 3 else 1.0, vol=0.3, decay=4 if i < 3 else 2.2, wave_shape="sine")) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Game over: slow, soft descending minor.
save("gameOver", mix(*[(i * 0.22, sweep(f, f * 0.98, 0.7, vol=0.3, decay=3.5, wave_shape="sine")) for i, f in enumerate([392.0, 311.13, 261.63, 196.0])]))
# Swap: two quick notes.
save("swap", mix((0, sweep(700, 700, 0.06, vol=0.2, decay=40, wave_shape="sine")), (0.05, sweep(940, 940, 0.07, vol=0.2, decay=40, wave_shape="sine"))))
print("written:", sorted(p.name for p in OUT.glob("*.wav")))
