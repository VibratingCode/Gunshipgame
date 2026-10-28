#!/usr/bin/env python3
"""Procedural sound design for Gunship: Overwatch.

Pure Python (no numpy). Every sound in sfx/ is synthesised here from noise,
filters, oscillators and a Freeverb-style reverb, so the project ships with
no third-party audio. Re-run to regenerate:

    python tools/gen_sfx.py sfx

Drop a real recording with the same file name into sfx/ to override any of them.
"""
import array
import math
import os
import random
import sys
import wave

SR = 44100
TAU = 2.0 * math.pi
random.seed(20261002)
OUT = sys.argv[1] if len(sys.argv) > 1 else "sfx"


# ----------------------------------------------------------------- primitives
def n_of(sec, sr=SR):
    return int(sec * sr)


def white(n):
    r = random.random
    return [r() * 2.0 - 1.0 for _ in range(n)]


def decay(n, tau, sr=SR):
    k = math.exp(-1.0 / (tau * sr))
    out = [0.0] * n
    v = 1.0
    for i in range(n):
        out[i] = v
        v *= k
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def add(dst, src, at=0, g=1.0):
    start = max(at, 0)
    end = min(len(dst), at + len(src))
    for i in range(start, end):
        dst[i] += src[i - at] * g


def sat(x, drive):
    t = math.tanh
    return [t(v * drive) for v in x]


def normalize(x, peak=0.9):
    m = max(abs(v) for v in x) or 1.0
    g = peak / m
    return [v * g for v in x]


def fades(x, fin=0.0004, fout=0.03, sr=SR):
    a = max(1, int(fin * sr))
    b = max(1, int(fout * sr))
    for i in range(min(a, len(x))):
        x[i] *= i / a
    for i in range(min(b, len(x))):
        x[len(x) - 1 - i] *= i / b
    return x


def biquad(x, kind, f, q=0.707, sr=SR):
    f = min(f, sr * 0.45)
    w0 = TAU * f / sr
    cw, sw = math.cos(w0), math.sin(w0)
    al = sw / (2.0 * q)
    if kind == "lp":
        b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = b0
    elif kind == "hp":
        b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = b0
    else:  # band-pass, 0 dB peak
        b0 = al; b1 = 0.0; b2 = -al
    a0 = 1 + al
    a1 = -2 * cw / a0
    a2 = (1 - al) / a0
    b0 /= a0; b1 /= a0; b2 /= a0
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = xi; y2 = y1; y1 = yi
        y[i] = yi
    return y


def svf(x, fc_of_t, q=0.707, mode="lp", sr=SR, block=32):
    """Time-varying TPT state-variable filter; cutoff updated every block."""
    ic1 = ic2 = 0.0
    k = 1.0 / q
    out = [0.0] * len(x)
    for b in range(0, len(x), block):
        g = math.tan(math.pi * min(fc_of_t(b / sr), sr * 0.45) / sr)
        a1 = 1.0 / (1.0 + g * (g + k)); a2 = g * a1; a3 = g * a2
        for i in range(b, min(b + block, len(x))):
            v3 = x[i] - ic2
            v1 = a1 * ic1 + a2 * v3
            v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            if mode == "lp":
                out[i] = v2
            elif mode == "bp":
                out[i] = v1
            else:
                out[i] = x[i] - k * v1 - v2
    return out


def sine(n, f, phase=0.0, sr=SR):
    w = TAU * f / sr
    return [math.sin(w * i + phase) for i in range(n)]


def glide(n, f0, f1, tau, sr=SR):
    """Sine whose frequency glides exponentially from f0 to f1."""
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        f = f1 + (f0 - f1) * math.exp(-(i / sr) / tau)
        ph += TAU * f / sr
        out[i] = math.sin(ph)
    return out


def reverb(x, room=0.8, damp=0.4, wet=0.3, dry=1.0, sr=SR, tail=0.0):
    """Mono Freeverb: 8 damped combs into 4 all-passes."""
    x = list(x) + [0.0] * int(tail * sr)
    n = len(x)
    s = sr / 44100.0
    inp = [v * 0.015 for v in x]
    acc = [0.0] * n
    d1 = damp
    d2 = 1.0 - damp
    for L0 in (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617):
        L = int(L0 * s)
        buf = [0.0] * L
        idx = 0
        fs = 0.0
        for i in range(n):
            o = buf[idx]
            fs = o * d2 + fs * d1
            buf[idx] = inp[i] + fs * room
            idx += 1
            if idx == L:
                idx = 0
            acc[i] += o
    for L0 in (556, 441, 341, 225):
        L = int(L0 * s)
        buf = [0.0] * L
        idx = 0
        for i in range(n):
            bo = buf[idx]
            a = acc[i]
            buf[idx] = a + bo * 0.5
            acc[i] = bo - a
            idx += 1
            if idx == L:
                idx = 0
    w = wet * 3.0
    return [x[i] * dry + acc[i] * w for i in range(n)]


def metal(sec, partials, decays, amps, sr=SR, click=0.8):
    """Struck metal: inharmonic decaying partials plus a transient click."""
    n = n_of(sec, sr)
    out = [0.0] * n
    for f, tau, a in zip(partials, decays, amps):
        w = TAU * f / sr
        k = math.exp(-1.0 / (tau * sr))
        v = a
        ph = random.random() * TAU
        for i in range(n):
            out[i] += math.sin(w * i + ph) * v
            v *= k
    m = n_of(0.004, sr)
    add(out, biquad(mul(white(m), decay(m, 0.0008, sr)), "hp", 2000, 0.7, sr), 0, click)
    return out


def write(name, x, sr=SR, peak=None):
    if peak is not None:
        x = normalize(x, peak)
    path = os.path.join(OUT, name + ".wav")
    data = array.array("h", (int(max(-1.0, min(1.0, v)) * 32767.0) for v in x))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    print(f"  {name:<18} {len(x) / sr:5.2f}s @ {sr}")


def clicks(count, sr=SR):
    out = []
    for _ in range(count):
        m = n_of(0.003, sr)
        out.append(biquad(mul(white(m), decay(m, 0.0006, sr)), "hp", random.uniform(2600, 4200), 0.7, sr))
    return out


# --------------------------------------------------------------- GAU-8 30 mm
def shot30():
    """One 30x173 mm round as heard on the firing aircraft."""
    n = n_of(0.04)
    d1 = decay(n, 0.0011)
    d2 = decay(n, 0.006)
    d3 = decay(n, 0.012)
    d4 = decay(n, 0.005)
    crack = biquad(mul(white(n), d1), "hp", 1600)
    mid = biquad(mul(white(n), d2), "bp", random.uniform(420, 600), 1.1)
    w1 = TAU * random.uniform(80, 98) / SR
    w2 = TAU * random.uniform(170, 215) / SR
    return [crack[i] + mid[i] * 1.6 + math.sin(w1 * i) * d3[i] * 0.95
            + math.sin(w2 * i + 0.6) * d4[i] * 0.5 for i in range(n)]


def gau8_loop():
    """3,900 rounds/min = 65 Hz pulse train; exactly one second so it loops seamlessly."""
    shots = [shot30() for _ in range(10)]
    per = SR / 65.0
    pat = [(random.uniform(-0.00015, 0.00015), random.randrange(10), random.uniform(0.82, 1.08)) for _ in range(65)]
    total = n_of(3.0)
    x = [0.0] * total
    for k in range(65 * 3):
        j, s, g = pat[k % 65]
        add(x, shots[s], int(round(k * per + j * SR)), g)
    cl = clicks(4)
    cpat = [(random.uniform(-0.0004, 0.0004), random.randrange(4), random.uniform(0.1, 0.25)) for _ in range(130)]
    for k in range(130 * 3):
        j, s, g = cpat[k % 130]
        add(x, cl[s], int(round(k * SR / 130.0 + j * SR + per * 0.5)), g)
    for i in range(total):
        t = i / SR
        x[i] += 0.05 * math.sin(TAU * 455 * t) + 0.025 * math.sin(TAU * 910 * t + 1.0) + 0.02 * math.sin(TAU * 65 * t)
    x = sat(x, 1.6)
    x = biquad(x, "lp", 7000)
    x = biquad(x, "hp", 30)
    x = reverb(x, room=0.62, damp=0.5, wet=0.14)
    return normalize(x[n_of(1.0):n_of(2.0)], 0.8)


def gau8_spinup():
    dur = 0.5
    n = n_of(dur)
    x = [0.0] * n
    ph = 0.0
    for i in range(n):
        k = (i / SR) / dur
        ph += TAU * (120 + 335 * k ** 0.8) / SR
        x[i] = (0.02 + 0.06 * k) * (math.sin(ph) + 0.5 * math.sin(2 * ph + 1.0) + 0.2 * math.sin(3 * ph))
    cl = clicks(4)
    t = 0.0
    while t < dur:
        add(x, random.choice(cl), int(t * SR), 0.12 + 0.2 * t / dur)
        t += 1.0 / (10 + 120 * (t / dur) ** 1.5)
    x = biquad(x, "hp", 60)
    x = reverb(x, 0.5, 0.5, 0.1)
    return normalize(fades(x), 0.5)


def gau8_spindown():
    dur = 1.7
    n = n_of(dur)
    x = [0.0] * n
    for k in range(3):
        add(x, shot30(), int(k * SR / 65.0), 1.0 - k * 0.22)
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += TAU * (30 + 425 * math.exp(-t / 0.35)) / SR
        x[i] += 0.07 * math.exp(-t / 0.5) * (math.sin(ph) + 0.4 * math.sin(2 * ph))
    cl = clicks(4)
    t = 0.04
    while True:
        rate = 120 * math.exp(-t / 0.25)
        if rate < 4:
            break
        add(x, random.choice(cl), int(t * SR), 0.2 * math.exp(-t / 0.4))
        t += 1.0 / rate
    x = sat(x, 1.4)
    x = reverb(x, 0.84, 0.45, 0.32)
    return normalize(fades(x, fout=0.3), 0.8)


def distant_shot(sr):
    n = n_of(0.09, sr)
    d = decay(n, 0.016, sr)
    d2 = decay(n, 0.03, sr)
    nz = biquad(mul(white(n), d), "lp", 700, 0.7, sr)
    w = TAU * random.uniform(62, 75) / sr
    return [nz[i] * 1.3 + math.sin(w * i) * d2[i] * 0.9 for i in range(n)]


def gau8_distant():
    """The famous BRRRT as heard from a few kilometres away: impacts first, this later."""
    sr = 32000
    n = n_of(4.8, sr)
    x = [0.0] * n
    shots = [distant_shot(sr) for _ in range(8)]
    t = 0.05
    while t < 2.05:
        k = t - 0.05
        rate = 65.0 * (0.62 + 0.38 * k / 0.45) if k < 0.45 else 65.0
        add(x, random.choice(shots), int(t * sr), min(1.0, 0.5 + k * 2.5) * random.uniform(0.85, 1.05))
        t += 1.0 / rate
    x = sat(x, 2.2)
    x = biquad(x, "lp", 1300, 0.7, sr)
    dark = biquad(x, "lp", 650, 0.7, sr)
    y = list(x)
    for dl, g in ((0.11, 0.35), (0.27, 0.25), (0.52, 0.18), (0.9, 0.1)):
        add(y, dark, int(dl * sr), g)
    y = reverb(y, room=0.9, damp=0.55, wet=0.4, sr=sr)
    y = biquad(y, "hp", 28, 0.7, sr)
    return normalize(fades(y, fout=0.6, sr=sr), 0.9), sr


# ------------------------------------------------------------- 40 mm Bofors
def clank(scale=1.0, sec=0.5):
    p = [430, 1210, 2240, 3480, 5100]
    return metal(sec, [f * scale for f in p], [0.12, 0.09, 0.07, 0.05, 0.04], [1.0, 0.7, 0.5, 0.35, 0.2])


def bofors():
    n = n_of(1.8)
    x = [0.0] * n
    m = n_of(0.5)
    crack = biquad(mul(white(m), decay(m, 0.0016)), "hp", 1100)
    boom = biquad(mul(white(m), decay(m, 0.09)), "lp", 260)
    f1 = random.uniform(66, 78)
    f2 = random.uniform(130, 150)
    d1 = decay(m, 0.06)
    d2 = decay(m, 0.025)
    body = [math.sin(TAU * f1 * i / SR) * d1[i] + 0.55 * math.sin(TAU * f2 * i / SR + 0.3) * d2[i] for i in range(m)]
    add(x, crack, 0, 1.1)
    add(x, boom, 0, 1.6)
    add(x, body, 0, 1.2)
    x = sat(x, 2.0)
    add(x, clank(random.uniform(1.6, 1.9), 0.3), n_of(0.17), 0.18)
    x = reverb(x, 0.76, 0.45, 0.28)
    return normalize(fades(x), 0.92)


# ------------------------------------------------------------ 105 mm M102
def howitzer():
    n = n_of(3.6)
    x = [0.0] * n
    m = n_of(1.6)
    crack = biquad(mul(white(m), decay(m, 0.004)), "lp", 2600)
    sub = mul(glide(m, 64, 33, 0.25), decay(m, 0.42))
    mid = mul(sine(m, 115), decay(m, 0.07))
    rumble = biquad(mul(white(n), decay(n, 0.85)), "lp", 170)
    rat = biquad(white(n), "bp", 950, 2.0)
    dr = decay(n, 0.25)
    for i in range(n):
        rat[i] *= dr[i] * (0.5 + 0.5 * math.sin(TAU * 23 * i / SR))
    add(x, crack, 0, 1.3)
    add(x, sub, 0, 1.6)
    add(x, mid, 0, 0.7)
    add(x, rumble, 0, 1.4)
    add(x, rat, 0, 0.35)
    x = sat(x, 2.6)
    x = reverb(x, 0.86, 0.5, 0.33)
    x = biquad(x, "hp", 20)
    return normalize(fades(x, fout=0.4), 0.97)


def breech():
    n = n_of(0.9)
    x = [0.0] * n
    m = n_of(0.14)
    slide = biquad(white(m), "bp", 1500, 0.8)
    for i in range(m):
        slide[i] *= math.sin(math.pi * i / m)
    add(x, slide, 0, 0.3)
    add(x, clank(1.0, 0.6), n_of(0.12), 1.0)
    add(x, clank(1.12, 0.45), n_of(0.31), 0.55)
    x = reverb(x, 0.5, 0.5, 0.2)
    return normalize(fades(x), 0.7)


def clip_load():
    n = n_of(0.5)
    x = [0.0] * n
    add(x, clank(1.5, 0.3), 0, 0.8)
    add(x, clank(1.8, 0.25), n_of(0.09), 0.6)
    x = reverb(x, 0.45, 0.5, 0.18)
    return normalize(fades(x), 0.55)


def casing():
    n = n_of(1.4)
    x = [0.0] * n
    for t, a in ((0.0, 1.0), (0.21, 0.6), (0.37, 0.4), (0.49, 0.25), (0.57, 0.15), (0.62, 0.08)):
        s = random.uniform(0.97, 1.03)
        add(x, metal(0.6, [780 * s, 1960 * s, 3150 * s, 4720 * s, 6900 * s],
                     [0.25, 0.2, 0.15, 0.1, 0.07], [0.6, 1.0, 0.7, 0.4, 0.25]), n_of(t), a)
    x = reverb(x, 0.5, 0.4, 0.15)
    return normalize(fades(x), 0.5)


# ------------------------------------------------------------- Hellfire
def hellfire_launch():
    dur = 3.4
    n = n_of(dur)
    x = [0.0] * n
    m = n_of(0.3)
    add(x, biquad(mul(white(m), decay(m, 0.01)), "lp", 3000), 0, 1.0)
    add(x, mul(sine(m, 90), decay(m, 0.05)), 0, 0.8)
    roar = white(n)
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.04) * math.exp(-t / 1.1)
        crack = random.uniform(0.6, 2.6) if random.random() < 0.012 else 1.0
        roar[i] *= env * crack
    roar = svf(roar, lambda t: 650 + 4200 * math.exp(-t / 0.9), 0.9)
    add(x, roar, 0, 0.9)
    add(x, biquad(roar, "lp", 120), 0, 1.5)
    x = sat(x, 1.3)
    x = reverb(x, 0.7, 0.4, 0.22)
    return normalize(fades(x, fout=0.4), 0.85)


# ------------------------------------------------------ distant explosions
def exp_small(sr=32000):
    n = n_of(1.4, sr)
    m = n_of(0.5, sr)
    x = [0.0] * n
    add(x, biquad(mul(white(m), decay(m, 0.045, sr)), "lp", random.uniform(350, 480), 0.7, sr), 0, 1.2)
    d = decay(m, 0.08, sr)
    w = TAU * random.uniform(48, 62) / sr
    add(x, [math.sin(w * i) * d[i] for i in range(m)], 0, 0.9)
    add(x, biquad(mul(white(m), decay(m, 0.003, sr)), "lp", 1600, 0.7, sr), 0, 0.25)
    x = sat(x, 1.5)
    add(x, biquad(list(x), "lp", 300, 0.7, sr), int(0.13 * sr), 0.3)
    x = reverb(x, 0.78, 0.55, 0.3, sr=sr)
    return normalize(fades(x, fout=0.2, sr=sr), 0.85)


def exp_med(sr=32000):
    n = n_of(2.8, sr)
    m = n_of(1.2, sr)
    x = [0.0] * n
    add(x, biquad(mul(white(m), decay(m, 0.006, sr)), "lp", 1400, 0.7, sr), 0, 0.6)
    add(x, biquad(mul(white(m), decay(m, 0.11, sr)), "lp", 300, 0.7, sr), 0, 1.4)
    add(x, mul(glide(m, 55, 38, 0.15, sr), decay(m, 0.2, sr)), 0, 1.2)
    x = sat(x, 1.7)
    dark = biquad(list(x), "lp", 260, 0.7, sr)
    for dl, g in ((0.18, 0.3), (0.45, 0.2)):
        add(x, dark, int(dl * sr), g)
    x = reverb(x, 0.84, 0.55, 0.34, sr=sr)
    return normalize(fades(x, fout=0.4, sr=sr), 0.9)


def exp_large(sr=32000):
    n = n_of(6.5, sr)
    m = n_of(3.0, sr)
    x = [0.0] * n
    add(x, biquad(mul(white(m), decay(m, 0.01, sr)), "lp", 1200, 0.7, sr), 0, 1.0)
    add(x, mul(glide(m, 46, 27, 0.5, sr), decay(m, 0.8, sr)), 0, 1.4)
    # rolling thunder: low noise with slow random amplitude movement
    am = biquad(white(n), "lp", 3.0, 0.7, sr)
    am = normalize(am, 1.0)
    roll = biquad(white(n), "lp", 260, 0.7, sr)
    for i in range(n):
        t = i / sr
        env = min(1.0, t / 0.05) * math.exp(-t / 2.0)
        roll[i] *= env * (0.65 + 0.35 * am[i])
    add(x, roll, 0, 1.6)
    # debris crackle
    for _ in range(140):
        t = random.uniform(0.15, 2.6)
        k = n_of(0.004, sr)
        add(x, biquad(mul(white(k), decay(k, 0.001, sr)), "lp", 2600, 0.7, sr), int(t * sr), random.uniform(0.05, 0.18) * math.exp(-t / 1.4))
    x = sat(x, 1.6)
    dark = biquad(list(x), "lp", 220, 0.7, sr)
    for dl, g in ((0.4, 0.35), (0.95, 0.25), (1.6, 0.15)):
        add(x, dark, int(dl * sr), g)
    x = reverb(x, 0.9, 0.6, 0.4, sr=sr)
    x = biquad(x, "hp", 18, 0.7, sr)
    return normalize(fades(x, fout=1.0, sr=sr), 0.95)


# ------------------------------------------------------- airframe / ambience
def engine_loop():
    """Four T56 turboprops, slightly out of sync so they beat, plus cabin noise."""
    L = n_of(8.0)
    F = n_of(0.75)
    n = L + F
    TN = 4096
    x = [0.0] * n
    for f in (68.0, 68.31, 67.83, 68.47):
        tab = [0.0] * TN
        for h in range(1, 15):
            a = 1.0 / h ** 0.9 * (1.3 if h in (1, 2, 4) else 1.0)
            ph = random.random() * TAU
            for i in range(TN):
                tab[i] += a * math.sin(TAU * h * i / TN + ph)
        inc = f * TN / SR
        ph = random.random() * TN
        for i in range(n):
            x[i] += tab[int(ph)] * 0.06
            ph += inc
            if ph >= TN:
                ph -= TN
    cabin = biquad(white(n), "lp", 600)
    low = biquad(white(n), "lp", 140)
    hiss = biquad(white(n), "bp", 2500, 0.6)
    for i in range(n):
        t = i / SR
        x[i] += cabin[i] * 0.5 + low[i] * 0.9 + hiss[i] * 0.05 \
            + 0.02 * math.sin(TAU * 1092 * t + 0.3 * math.sin(TAU * 0.3 * t)) + 0.006 * math.sin(TAU * 3650 * t)
    x = biquad(x, "lp", 4000)
    x = sat(x, 1.1)
    loop = x[:L]
    for i in range(F):
        w = i / F
        loop[i] = x[i] * w + x[L + i] * (1.0 - w)
    return normalize(loop, 0.7)


def a10_flyby():
    dur = 7.0
    n = n_of(dur)
    tc = 3.0

    def dop(t):
        return 1.0 - 0.2 * math.tanh((t - tc) / 0.9)

    def amp(t):
        return math.exp(-((t - tc) / 1.4) ** 2) * 0.85 + 0.15 * math.exp(-((t - tc) / 3.0) ** 2)

    whine = [0.0] * n
    phs = [0.0, 0.0, 0.0]
    for i in range(n):
        t = i / SR
        d = dop(t)
        a = amp(t) ** 1.5
        v = 0.0
        for j, (f, g) in enumerate(((2800, 1.0), (3350, 0.6), (5600, 0.3))):
            phs[j] += TAU * f * d / SR
            v += math.sin(phs[j]) * g
        whine[i] = v * a
    roar = svf(white(n), lambda t: 500 + 2200 * amp(t), 0.7)
    for i in range(n):
        roar[i] *= amp(i / SR)
    x = [roar[i] + whine[i] * 0.22 for i in range(n)]
    x = reverb(x, 0.8, 0.5, 0.25)
    return normalize(fades(x, fout=0.5), 0.85)


# ------------------------------------------------------------- crew / UI
def radio_on():
    n = n_of(0.2)
    x = [0.0] * n
    add(x, metal(0.01, [3000], [0.002], [0.5]), 0, 1.0)
    b = biquad(white(n), "bp", 2200, 1.5)
    for i in range(n):
        b[i] *= math.exp(-i / (0.05 * SR))
    add(x, b, 0, 0.6)
    m = n_of(0.06)
    add(x, mul(sine(m, 1000), [math.sin(math.pi * i / m) for i in range(m)]), n_of(0.09), 0.25)
    return normalize(fades(x), 0.45)


def radio_off():
    n = n_of(0.35)
    b = biquad(white(n), "bp", 2500, 1.2)
    for i in range(n):
        t = i / SR
        b[i] *= min(1.0, t / 0.01) * math.exp(-t / 0.09)
    return normalize(fades(b), 0.4)


def tone(sec, f, partials=(1.0,), sr=SR):
    n = n_of(sec, sr)
    a = n_of(0.006, sr)
    out = [0.0] * n
    for h, g in enumerate(partials, 1):
        w = TAU * f * h / sr
        for i in range(n):
            out[i] += math.sin(w * i) * g
    for i in range(n):
        out[i] *= min(1.0, i / a, (n - i) / a)
    return out


def beep():
    return normalize(tone(0.12, 1200), 0.35)


def lock_tone():
    x = [0.0] * n_of(0.45)
    for k in range(3):
        add(x, tone(0.08, 1500, (1.0, 0.2)), n_of(k * 0.13))
    return normalize(x, 0.35)


def alarm():
    x = [0.0] * n_of(1.25)
    for k in range(8):
        add(x, tone(0.14, 950 if k % 2 == 0 else 720, (1.0, 0.3, 0.15)), n_of(k * 0.155))
    x = biquad(x, "lp", 3000)
    return normalize(x, 0.4)


def switch():
    n = n_of(0.18)
    x = [0.0] * n
    add(x, metal(0.05, [2400, 4100], [0.004, 0.003], [0.4, 0.3]), 0, 1.0)
    add(x, metal(0.05, [2700, 4500], [0.004, 0.003], [0.3, 0.2]), n_of(0.035), 0.8)
    add(x, mul(sine(n_of(0.06), 140), decay(n_of(0.06), 0.012)), 0, 0.5)
    return normalize(fades(x), 0.4)


def zoom_servo():
    n = n_of(0.38)
    x = [0.0] * n
    ph = 0.0
    for i in range(n):
        k = i / n
        ph += TAU * (900 + 500 * k) / SR
        x[i] = math.sin(math.pi * k) * (math.sin(ph) + 0.35 * math.sin(2 * ph) + 0.2 * math.sin(3 * ph))
    x = biquad(x, "hp", 400)
    return normalize(x, 0.12)


# ------------------------------------------------- progression arsenal
def m2_shot():
    """One round from an M2HB .50 cal heard inside the aircraft."""
    n = n_of(0.55)
    x = [0.0] * n
    m = n_of(0.12)
    add(x, biquad(mul(white(m), decay(m, 0.0008)), "hp", 2000), 0, 1.0)
    add(x, mul(sine(m, random.uniform(110, 135)), decay(m, 0.02)), 0, 0.8)
    add(x, biquad(mul(white(m), decay(m, 0.01)), "bp", random.uniform(600, 800), 1.0), 0, 1.3)
    add(x, metal(0.12, [1900, 3100], [0.03, 0.02], [0.4, 0.25], click=0.2), n_of(0.03), 0.18)
    x = sat(x, 1.8)
    x = reverb(x, 0.6, 0.5, 0.18)
    return normalize(fades(x), 0.75)


def shot25():
    n = n_of(0.035)
    d1 = decay(n, 0.0009)
    d2 = decay(n, 0.005)
    d3 = decay(n, 0.009)
    crack = biquad(mul(white(n), d1), "hp", 2200)
    mid = biquad(mul(white(n), d2), "bp", random.uniform(600, 800), 1.1)
    w1 = TAU * random.uniform(105, 130) / SR
    return [crack[i] * 1.1 + mid[i] * 1.4 + math.sin(w1 * i) * d3[i] * 0.8 for i in range(n)]


def gau12_loop():
    """GAU-12/U at 1,800 rounds/min: a 30 Hz train, lighter and snappier than the GAU-8."""
    shots = [shot25() for _ in range(8)]
    per = SR / 30.0
    pat = [(random.uniform(-0.0002, 0.0002), random.randrange(8), random.uniform(0.85, 1.08)) for _ in range(30)]
    total = n_of(3.0)
    x = [0.0] * total
    for k in range(30 * 3):
        j, s, g = pat[k % 30]
        add(x, shots[s], int(round(k * per + j * SR)), g)
    cl = clicks(4)
    cpat = [(random.uniform(-0.0004, 0.0004), random.randrange(4), random.uniform(0.1, 0.25)) for _ in range(60)]
    for k in range(60 * 3):
        j, s, g = cpat[k % 60]
        add(x, cl[s], int(round(k * SR / 60.0 + j * SR + per * 0.5)), g)
    for i in range(total):
        t = i / SR
        x[i] += 0.045 * math.sin(TAU * 380 * t) + 0.02 * math.sin(TAU * 760 * t + 1.0)
    x = sat(x, 1.5)
    x = biquad(x, "lp", 8000)
    x = biquad(x, "hp", 40)
    x = reverb(x, room=0.6, damp=0.5, wet=0.13)
    return normalize(x[n_of(1.0):n_of(2.0)], 0.75)


def bomb_release():
    n = n_of(1.3)
    x = [0.0] * n
    add(x, metal(0.6, [180, 410, 760, 1330], [0.15, 0.1, 0.07, 0.05], [1.0, 0.8, 0.5, 0.3], click=1.0), 0, 1.0)
    m = n_of(0.2)
    add(x, biquad(mul(white(m), decay(m, 0.03)), "lp", 300), 0, 1.4)
    h = n_of(0.5)
    hiss = biquad(white(h), "bp", 3000, 0.8)
    for i in range(h):
        hiss[i] *= math.exp(-i / (0.12 * SR))
    add(x, hiss, n_of(0.02), 0.35)
    x = reverb(x, 0.7, 0.5, 0.25)
    return normalize(fades(x), 0.8)


def cluster_pops(sr=32000):
    """Forty BLU-108 skeets going off across a grid square, heard from the orbit."""
    n = n_of(4.5, sr)
    x = [0.0] * n
    for _ in range(46):
        t = random.uniform(0.1, 1.9)
        m = n_of(0.35, sr)
        d = decay(m, 0.04, sr)
        th = biquad(mul(white(m), d), "lp", random.uniform(400, 900), 0.7, sr)
        w = TAU * random.uniform(55, 80) / sr
        d2 = decay(m, 0.06, sr)
        add(x, [th[i] * 1.2 + math.sin(w * i) * d2[i] * 0.7 for i in range(m)], int(t * sr), random.uniform(0.4, 1.0))
    x = sat(x, 1.6)
    add(x, biquad(list(x), "lp", 300, 0.7, sr), int(0.2 * sr), 0.3)
    x = reverb(x, 0.88, 0.55, 0.38, sr=sr)
    return normalize(fades(x, fout=0.8, sr=sr), 0.9)


def exp_huge(sr=32000):
    """2,000 lb class and up: a deep, long, rolling blast."""
    n = n_of(9.0, sr)
    m = n_of(5.0, sr)
    x = [0.0] * n
    add(x, biquad(mul(white(m), decay(m, 0.02, sr)), "lp", 900, 0.7, sr), 0, 1.2)
    add(x, mul(glide(m, 38, 20, 0.9, sr), decay(m, 1.6, sr)), 0, 1.6)
    am = normalize(biquad(white(n), "lp", 2.0, 0.7, sr), 1.0)
    roll = biquad(white(n), "lp", 200, 0.7, sr)
    for i in range(n):
        t = i / sr
        roll[i] *= min(1.0, t / 0.08) * math.exp(-t / 3.2) * (0.6 + 0.4 * am[i])
    add(x, roll, 0, 1.8)
    for _ in range(220):
        t = random.uniform(0.2, 4.0)
        k = n_of(0.005, sr)
        add(x, biquad(mul(white(k), decay(k, 0.0012, sr)), "lp", 2400, 0.7, sr), int(t * sr), random.uniform(0.04, 0.16) * math.exp(-t / 2.0))
    x = sat(x, 1.7)
    dark = biquad(list(x), "lp", 180, 0.7, sr)
    for dl, g in ((0.6, 0.35), (1.4, 0.25), (2.5, 0.18)):
        add(x, dark, int(dl * sr), g)
    x = reverb(x, 0.92, 0.6, 0.42, sr=sr)
    x = biquad(x, "hp", 16, 0.7, sr)
    return normalize(fades(x, fout=1.5, sr=sr), 0.97)


def nuke(sr=32000):
    """Sub-kiloton detonation heard from a few kilometres: crack, ground-shaking roar, afterwinds."""
    n = n_of(16.0, sr)
    x = [0.0] * n
    m = n_of(8.0, sr)
    add(x, biquad(mul(white(m), decay(m, 0.05, sr)), "lp", 800, 0.7, sr), 0, 1.4)
    add(x, mul(glide(m, 32, 15, 1.8, sr), decay(m, 3.0, sr)), 0, 1.8)
    am = normalize(biquad(white(n), "lp", 1.2, 0.7, sr), 1.0)
    roll = biquad(white(n), "lp", 150, 0.7, sr)
    for i in range(n):
        t = i / sr
        roll[i] *= min(1.0, t / 0.3) * math.exp(-t / 4.5) * (0.55 + 0.45 * am[i])
    add(x, roll, 0, 2.2)
    wind = white(n)
    for i in range(n):
        t = i / sr
        wind[i] *= math.exp(-((t - 6.0) / 3.0) ** 2) * (0.7 + 0.3 * am[i])
    wind = svf(wind, lambda t: 350 + 500 * math.exp(-((t - 6.0) / 3.0) ** 2), 0.8, sr=sr)
    add(x, wind, 0, 0.6)
    for _ in range(300):
        t = random.uniform(0.3, 6.0)
        k = n_of(0.006, sr)
        add(x, biquad(mul(white(k), decay(k, 0.0015, sr)), "lp", 2000, 0.7, sr), int(t * sr), random.uniform(0.03, 0.12) * math.exp(-t / 3.0))
    x = sat(x, 1.8)
    dark = biquad(list(x), "lp", 160, 0.7, sr)
    for dl, g in ((0.8, 0.35), (1.9, 0.28), (3.2, 0.2), (5.0, 0.12)):
        add(x, dark, int(dl * sr), g)
    x = reverb(x, 0.94, 0.6, 0.45, sr=sr)
    x = biquad(x, "hp", 14, 0.7, sr)
    return normalize(fades(x, fout=3.0, sr=sr), 0.99)


def buy():
    x = [0.0] * n_of(0.7)
    add(x, tone(0.18, 880, (1.0, 0.25, 0.1)), 0, 0.6)
    add(x, tone(0.35, 1320, (1.0, 0.25, 0.1)), n_of(0.12), 0.6)
    for i in range(len(x)):
        x[i] *= math.exp(-i / (0.3 * SR))
    add(x, metal(0.3, [300, 720, 1500], [0.08, 0.05, 0.03], [0.6, 0.4, 0.2]), 0, 0.5)
    x = reverb(x, 0.5, 0.5, 0.15)
    return normalize(fades(x), 0.45)


# ------------------------------------------------------ the psycho expansion
def minigun_loop():
    """M134 at 6,000 rounds/min: a 100 Hz buzz-saw of 7.62 mm reports plus the motor."""
    def shot():
        n = n_of(0.02)
        crack = biquad(mul(white(n), decay(n, 0.0006)), "hp", 2600)
        mid = biquad(mul(white(n), decay(n, 0.003)), "bp", random.uniform(850, 1100), 1.2)
        w = TAU * random.uniform(150, 180) / SR
        d = decay(n, 0.004)
        return [crack[i] + mid[i] * 1.2 + math.sin(w * i) * d[i] * 0.6 for i in range(n)]
    shots = [shot() for _ in range(8)]
    pat = [(random.uniform(-0.0001, 0.0001), random.randrange(8), random.uniform(0.8, 1.1)) for _ in range(100)]
    total = n_of(3.0)
    x = [0.0] * total
    for k in range(300):
        j, s, g = pat[k % 100]
        add(x, shots[s], int(round(k * SR / 100.0 + j * SR)), g)
    for i in range(total):
        t = i / SR
        x[i] += 0.05 * math.sin(TAU * 600 * t) + 0.02 * math.sin(TAU * 1200 * t)
    x = sat(x, 1.4)
    x = biquad(x, "lp", 9000)
    x = reverb(x, 0.55, 0.5, 0.12)
    return normalize(x[n_of(1.0):n_of(2.0)], 0.7)


def laser_loop():
    """High-energy laser: transformer hum, coolant whine and plasma crackle at the target."""
    n = n_of(1.0)
    x = [0.0] * n
    for i in range(n):
        t = i / SR
        hum = sum(math.sin(TAU * 120 * h * t) / h for h in range(1, 9))
        x[i] = hum * 0.25 * (0.85 + 0.15 * math.sin(TAU * 10 * t)) + 0.05 * math.sin(TAU * 3100 * t) + 0.03 * math.sin(TAU * 4650 * t)
    cr = white(n)
    for i in range(n):
        if random.random() > 0.004:
            cr[i] *= 0.08
    add(x, biquad(cr, "bp", 2500, 0.7), 0, 0.9)
    x = biquad(x, "hp", 60)
    x = sat(x, 1.3)
    return normalize(x, 0.6)


def charge():
    n = n_of(1.3)
    x = [0.0] * n
    ph = 0.0
    for i in range(n):
        k = i / n
        ph += TAU * (300 + 2100 * k * k) / SR
        x[i] = (0.1 + 0.9 * k) * (math.sin(ph) + 0.3 * math.sin(2 * ph))
    cr = white(n)
    for i in range(n):
        if random.random() > 0.01 * (i / n):
            cr[i] = 0.0
    add(x, biquad(cr, "hp", 3000), 0, 0.8)
    return normalize(fades(x), 0.45)


def railgun():
    n = n_of(2.6)
    x = [0.0] * n
    m = n_of(0.4)
    add(x, biquad(mul(white(m), decay(m, 0.004)), "hp", 900), 0, 1.4)
    add(x, mul(sine(m, 58), decay(m, 0.09)), 0, 1.3)
    add(x, mul(glide(m, 4200, 200, 0.05), decay(m, 0.12)), 0, 0.5)
    add(x, metal(1.2, [2100, 3700, 5200], [0.4, 0.3, 0.2], [0.4, 0.3, 0.2], click=0.0), 0, 0.5)
    x = sat(x, 2.0)
    x = reverb(x, 0.85, 0.45, 0.35)
    return normalize(fades(x, fout=0.5), 0.95)


def rocket():
    n = n_of(1.6)
    x = [0.0] * n
    m = n_of(0.05)
    add(x, biquad(mul(white(m), decay(m, 0.006)), "lp", 3000), 0, 1.0)
    roar = white(n)
    for i in range(n):
        t = i / SR
        roar[i] *= min(1.0, t / 0.02) * math.exp(-t / 0.45)
    add(x, svf(roar, lambda t: 800 + 2600 * math.exp(-t / 0.4), 0.8), 0, 1.0)
    x = reverb(x, 0.6, 0.4, 0.2)
    return normalize(fades(x, fout=0.3), 0.7)


def drone_launch():
    n = n_of(1.6)
    x = [0.0] * n
    m = n_of(0.2)
    add(x, biquad(mul(white(m), decay(m, 0.03)), "lp", 400), 0, 1.2)
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += TAU * (140 + 60 * min(1.0, t * 3)) / SR
        a = min(1.0, t * 6) * math.exp(-t / 0.7)
        x[i] += a * 0.35 * (math.sin(ph) + 0.6 * math.sin(2 * ph) + 0.4 * math.sin(3 * ph) + 0.25 * math.sin(5 * ph))
    x = reverb(x, 0.6, 0.5, 0.2)
    return normalize(fades(x, fout=0.3), 0.6)


def arty(sr=32000):
    """A 155 mm battery firing, kilometres away."""
    n = n_of(3.0, sr)
    x = [0.0] * n
    for k in range(3):
        m = n_of(0.8, sr)
        at = int(k * random.uniform(0.25, 0.45) * sr)
        add(x, biquad(mul(white(m), decay(m, 0.01, sr)), "lp", 700, 0.7, sr), at, 1.0)
        add(x, mul(glide(m, 50, 32, 0.2, sr), decay(m, 0.25, sr)), at, 1.2)
    x = sat(x, 1.6)
    x = reverb(x, 0.88, 0.6, 0.4, sr=sr)
    return normalize(fades(x, fout=0.6, sr=sr), 0.85)


def barrage(sr=32000):
    """TOS-1A ripple: two dozen heavy rockets leaving their tubes."""
    n = n_of(8.0, sr)
    x = [0.0] * n
    for k in range(24):
        t = 0.1 + k * 0.22 + random.uniform(-0.04, 0.04)
        m = n_of(1.2, sr)
        r = white(m)
        for i in range(m):
            tt = i / sr
            r[i] *= min(1.0, tt / 0.01) * math.exp(-tt / 0.35)
        add(x, biquad(r, "lp", random.uniform(700, 1100), 0.7, sr), int(t * sr), 1.0)
        add(x, mul(sine(m, random.uniform(45, 60), 0.0, sr), decay(m, 0.12, sr)), int(t * sr), 0.8)
    x = sat(x, 1.5)
    x = reverb(x, 0.9, 0.6, 0.4, sr=sr)
    return normalize(fades(x, fout=1.0, sr=sr), 0.9)


def napalm():
    """Mk-77: a soft WHUMP of ignition then a roaring sheet of fire."""
    n = n_of(4.5)
    x = [0.0] * n
    m = n_of(0.8)
    add(x, mul(glide(m, 70, 35, 0.2), decay(m, 0.25)), 0, 1.4)
    roar = white(n)
    am = normalize(biquad(white(n), "lp", 9.0), 1.0)
    for i in range(n):
        t = i / SR
        roar[i] *= min(1.0, t / 0.15) * math.exp(-t / 1.6) * (0.6 + 0.4 * am[i])
    add(x, biquad(roar, "lp", 900), 0, 1.6)
    add(x, biquad(roar, "bp", 2500, 0.7), 0, 0.25)
    x = sat(x, 1.4)
    x = reverb(x, 0.8, 0.5, 0.3)
    return normalize(fades(x, fout=0.8), 0.9)


def neutron(sr=32000):
    """Enhanced-radiation weapon: a flat crack, then a low beating drone that fades away."""
    n = n_of(11.0, sr)
    x = [0.0] * n
    m = n_of(1.5, sr)
    add(x, biquad(mul(white(m), decay(m, 0.03, sr)), "lp", 1100, 0.7, sr), 0, 1.3)
    add(x, mul(glide(m, 40, 22, 0.4, sr), decay(m, 0.6, sr)), 0, 1.4)
    for i in range(n):
        t = i / sr
        env = min(1.0, t / 1.5) * math.exp(-t / 4.0)
        x[i] += env * 0.35 * (math.sin(TAU * 41 * t) + math.sin(TAU * 42.6 * t) + 0.4 * math.sin(TAU * 83 * t))
    hiss = biquad(white(n), "bp", 5000, 0.6, sr)
    for i in range(n):
        t = i / sr
        hiss[i] *= 0.12 * math.exp(-((t - 4.0) / 2.5) ** 2)
    add(x, hiss, 0, 1.0)
    x = reverb(x, 0.92, 0.6, 0.4, sr=sr)
    return normalize(fades(x, fout=2.0, sr=sr), 0.9)


REGISTRY = {
    "minigun_loop": lambda: write("minigun_loop", minigun_loop()),
    "laser_loop": lambda: write("laser_loop", laser_loop()),
    "charge": lambda: write("charge", charge()),
    "railgun": lambda: write("railgun", railgun()),
    "rocket": lambda: write("rocket", rocket()),
    "drone_launch": lambda: write("drone_launch", drone_launch()),
    "arty": lambda: write("arty", arty(), 32000),
    "barrage": lambda: write("barrage", barrage(), 32000),
    "napalm": lambda: write("napalm", napalm()),
    "neutron": lambda: write("neutron", neutron(), 32000),
    "gau8_loop": lambda: write("gau8_loop", gau8_loop()),
    "gau8_spinup": lambda: write("gau8_spinup", gau8_spinup()),
    "gau8_spindown": lambda: write("gau8_spindown", gau8_spindown()),
    "gau8_distant": lambda: write("gau8_distant", *gau8_distant()),
    "bofors": lambda: [write(f"bofors_{i + 1}", bofors()) for i in range(3)],
    "howitzer": lambda: [write(f"howitzer_{i + 1}", howitzer()) for i in range(2)],
    "breech": lambda: write("breech", breech()),
    "clip": lambda: write("clip", clip_load()),
    "casing": lambda: write("casing", casing()),
    "hellfire_launch": lambda: write("hellfire_launch", hellfire_launch()),
    "exp_small": lambda: [write(f"exp_small_{i + 1}", exp_small(), 32000) for i in range(4)],
    "exp_med": lambda: [write(f"exp_med_{i + 1}", exp_med(), 32000) for i in range(3)],
    "exp_large": lambda: [write(f"exp_large_{i + 1}", exp_large(), 32000) for i in range(3)],
    "engine_loop": lambda: write("engine_loop", engine_loop()),
    "a10_flyby": lambda: write("a10_flyby", a10_flyby()),
    "radio_on": lambda: write("radio_on", radio_on()),
    "radio_off": lambda: write("radio_off", radio_off()),
    "beep": lambda: write("beep", beep()),
    "lock": lambda: write("lock", lock_tone()),
    "alarm": lambda: write("alarm", alarm()),
    "switch": lambda: write("switch", switch()),
    "zoom": lambda: write("zoom", zoom_servo()),
    "m2": lambda: [write(f"m2_{i + 1}", m2_shot()) for i in range(3)],
    "gau12_loop": lambda: write("gau12_loop", gau12_loop()),
    "bomb_release": lambda: write("bomb_release", bomb_release()),
    "cluster": lambda: write("cluster", cluster_pops(), 32000),
    "exp_huge": lambda: [write(f"exp_huge_{i + 1}", exp_huge(), 32000) for i in range(2)],
    "nuke": lambda: write("nuke", nuke(), 32000),
    "buy": lambda: write("buy", buy()),
}


def main():
    """python gen_sfx.py <out_dir> [names...]  (no names = regenerate everything)"""
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[2:] or list(REGISTRY)
    print("Synthesising sound effects into", OUT)
    for name in names:
        REGISTRY[name]()
    print("done")


if __name__ == "__main__":
    main()
