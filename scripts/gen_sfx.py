"""合成 8-bit 风格音效到 assets/sfx/*.wav（只用标准库）。

    python scripts/gen_sfx.py

每个音效由若干段「波形 + 频率滑动 + 音量包络」拼成，参数在 SFX 表里，改了重跑即可。
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def osc(kind, phase):
    p = phase % 1.0
    if kind == "square":
        return 1.0 if p < 0.5 else -1.0
    if kind == "pulse":
        return 1.0 if p < 0.25 else -1.0
    if kind == "tri":
        return 4.0 * abs(p - 0.5) - 1.0
    if kind == "saw":
        return 2.0 * p - 1.0
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    return 0.0


def segment(kind, f0, f1, dur, vol=0.5, attack=0.005, release=0.05, vibrato=0.0, noise=False):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    rnd = random.Random(int(f0 * 1000 + dur * 100))
    hold = 0.0
    hold_n = 0
    for i in range(n):
        t = i / RATE
        k = i / max(1, n - 1)
        f = f0 + (f1 - f0) * k
        if vibrato:
            f *= 1.0 + 0.02 * math.sin(2 * math.pi * vibrato * t)
        phase += f / RATE
        if noise:
            # 采样保持噪声，频率越高越“沙”
            if hold_n <= 0:
                hold = rnd.uniform(-1, 1)
                hold_n = max(1, int(RATE / max(f, 1)))
            hold_n -= 1
            s = hold
        else:
            s = osc(kind, phase)
        env = 1.0
        if t < attack:
            env = t / attack
        rem = dur - t
        if rem < release:
            env *= max(0.0, rem / release)
        out.append(s * env * vol)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


SFX = {
    "click":  lambda: segment("square", 880, 880, 0.03, 0.25, release=0.02),
    "ok":     lambda: segment("square", 660, 660, 0.05, 0.3) + segment("square", 990, 990, 0.08, 0.3),
    "error":  lambda: segment("square", 220, 180, 0.12, 0.3) + silence(0.03) + segment("square", 180, 150, 0.12, 0.3),
    "open":   lambda: segment("pulse", 520, 780, 0.07, 0.3),
    "buy":    lambda: segment("square", 988, 988, 0.05, 0.3) + segment("square", 1319, 1319, 0.12, 0.3, release=0.1),
    "win":    lambda: segment("square", 784, 784, 0.06, 0.28) + segment("square", 988, 988, 0.06, 0.28) + segment("square", 1319, 1319, 0.14, 0.28, release=0.12),
    "lose":   lambda: segment("tri", 392, 330, 0.12, 0.45) + segment("tri", 311, 247, 0.22, 0.45, release=0.15),
    "alarm":  lambda: (segment("square", 1200, 1200, 0.08, 0.3) + silence(0.04)) * 3,
    "crash":  lambda: mix(segment("saw", 440, 55, 0.6, 0.35, release=0.3), segment("", 3000, 400, 0.6, 0.25, release=0.4, noise=True)),
    "news":   lambda: segment("sine", 1047, 1047, 0.09, 0.4) + segment("sine", 1397, 1397, 0.09, 0.4) + segment("sine", 1047, 1047, 0.18, 0.4, release=0.15),
    "page":   lambda: segment("", 6000, 2000, 0.12, 0.18, release=0.1, noise=True),
    "unlock": lambda: segment("square", 523, 523, 0.07, 0.28) + segment("square", 659, 659, 0.07, 0.28) + segment("square", 784, 784, 0.07, 0.28) + segment("square", 1047, 1047, 0.2, 0.28, release=0.18),
    "title":  lambda: mix(
        segment("pulse", 523, 523, 0.15, 0.22) + segment("pulse", 659, 659, 0.15, 0.22) + segment("pulse", 784, 784, 0.15, 0.22) + segment("pulse", 1047, 1047, 0.45, 0.22, release=0.35, vibrato=6),
        segment("tri", 131, 131, 0.9, 0.35, release=0.4)),
    "coin":   lambda: segment("square", 1319, 1319, 0.04, 0.25) + segment("square", 1760, 1760, 0.12, 0.25, release=0.1),
}


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    return path


if __name__ == "__main__":
    for k, fn in SFX.items():
        print("sfx", write(k, fn()))
