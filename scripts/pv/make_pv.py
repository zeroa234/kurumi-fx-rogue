#!/usr/bin/env python3
"""PV 合成器 v2：按 config/pv-edit.json 在 640×360 像素画布上逐帧合成（Pillow）→ 最近邻放大 3 倍 → ffmpeg 编码 → 混音。

和游戏画面同一套像素规格：实机录像原生 640×360，背景/CG 320×180 与立绘 128×128 以 2 倍贴上，
像素字 12px 整数倍。所有位移取整到画布像素，缩放只用整数倍，半透明一律用 4×4 Bayer 抖动，
所以成片里每个像素都落在同一张 3×3 网格上，不会出现模糊的插值像素。

用法（在 projects/kurumi-fx-rogue 下）：
  python scripts/pv/make_pv.py                       # 成片 output/pv/kurumi-fx-rogue-pv.mp4（1920×1080）
  python scripts/pv/make_pv.py --preview             # 1280×720 快速预览 output/pv/preview.mp4
  python scripts/pv/make_pv.py --stills 3,12.5       # 单帧 PNG → output/pv/stills/
  python scripts/pv/make_pv.py --sheet 1,2,3,4       # 多个时刻拼一张总览 → output/pv/sheet.png
  python scripts/pv/make_pv.py --from 20 --to 35 --preview   # 只渲染一段

素材前缀（src）：bg:/cg:/portrait:/icon:/chibi:/anim: → assets/sprites/<类别>/；px: → assets/pv/px/（像素版关键帧，
scripts/pv/prep_pv_pixels.py 生成）；其余按项目相对路径。实机片段在 output/pv/raw/<片段>/（scripts/pv/capture_all.sh）。
剪辑表字段见 config/pv-edit.json 的 _doc。随机效果都按帧号或固定种子，结果可复现。
"""
from __future__ import annotations

import argparse
import json
import math
import random
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "config/pv-edit.json"
OUT = ROOT / "output/pv"
FONT = ROOT / "assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
CW, CH, UP = 640, 360, 3
W, H = CW * UP, CH * UP
FPS = 30
DARK = (26, 8, 32)
WHITE = (255, 255, 255)


def hexcol(s, default=WHITE):
    if s is None:
        return default
    if isinstance(s, (list, tuple)):
        return tuple(s)
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def ease(x: float, kind: str = "inout") -> float:
    x = clamp(x)
    if kind == "out":
        return 1 - (1 - x) ** 3
    if kind == "in":
        return x ** 3
    if kind == "linear":
        return x
    if kind == "step":
        return 0.0 if x < 1 else 1.0
    if kind == "back":  # 冲过头再回弹
        c1 = 1.70158
        return 1 + (c1 + 1) * (x - 1) ** 3 + c1 * (x - 1) ** 2
    return x * x * (3 - 2 * x)


def kv(spec, t, default=0.0):
    """数值或关键帧 [[t, v], [t, v, ease], ...]（ease 写在终点上，表示从上一点到这一点的缓动）。"""
    if spec is None:
        return default
    if isinstance(spec, (int, float)):
        return spec
    if t <= spec[0][0]:
        return spec[0][1]
    for a, b in zip(spec, spec[1:]):
        if t < b[0]:
            k = (t - a[0]) / max(1e-6, b[0] - a[0])
            return a[1] + (b[1] - a[1]) * ease(k, b[2] if len(b) > 2 else "inout")
    return spec[-1][1]


# ---------------------------------------------------------------- 抖动

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


@lru_cache(maxsize=1)
def bayer_tile() -> Image.Image:
    row = [bytes(BAYER4[y][x % 4] * 16 + 8 for x in range(CW)) for y in range(4)]
    return Image.frombytes("L", (CW, CH), b"".join(row[y % 4] for y in range(CH)))


@lru_cache(maxsize=17)
def dither_mask(level: int) -> Image.Image:
    """level 0..16：Bayer 阈值掩码，255 的比例 = level/16。"""
    return bayer_tile().point(lambda v: 255 if v < level * 16 else 0)


def dither_level(a: float) -> int:
    return int(round(clamp(a) * 16))


def dither_from_gray(g: Image.Image) -> Image.Image:
    """连续灰度（0~255 表示不透明度）→ 抖动后的二值掩码。"""
    return ImageChops.subtract(g, bayer_tile()).point(lambda v: 255 if v > 0 else 0)


def comp(base: Image.Image, surf: Image.Image, alpha: float = 1.0, mask: Image.Image | None = None):
    """把画布大小的 RGBA 图层 surf 合到 base 上：alpha 二值化 × 抖动透明度。"""
    lvl = dither_level(alpha)
    if lvl <= 0:
        return
    a = surf.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    if lvl < 16:
        a = ImageChops.multiply(a, dither_mask(lvl))
    if mask is not None:
        a = ImageChops.multiply(a, mask)
    base.paste(surf if base.mode == "RGBA" else surf.convert("RGB"), (0, 0), a)


# ---------------------------------------------------------------- 素材

PREFIX = {"bg": "assets/sprites/bg", "cg": "assets/sprites/cg", "portrait": "assets/sprites/portraits",
          "icon": "assets/sprites/icons", "chibi": "assets/sprites/chibi", "anim": "assets/sprites/anim",
          "px": "assets/pv/px"}


def resolve(src: str) -> Path:
    if ":" in src and src.split(":", 1)[0] in PREFIX:
        k, name = src.split(":", 1)
        return ROOT / PREFIX[k] / (name + ".png")
    return ROOT / src


@lru_cache(maxsize=64)
def load_rgba(src: str) -> Image.Image:
    p = resolve(src)
    if not p.exists():
        raise SystemExit(f"缺素材 {p}")
    return Image.open(p).convert("RGBA")


@lru_cache(maxsize=48)
def load_clip_frame(clip: str, idx: int) -> Image.Image:
    d = OUT / "raw" / clip
    p = d / f"f{idx:08d}.png"
    if not p.exists():
        frames = sorted(d.glob("f*.png"))
        if not frames:
            raise SystemExit(f"缺少实机素材 {d}，先跑 bash scripts/pv/capture_all.sh {clip}")
        p = frames[min(max(idx, 0), len(frames) - 1)]
    return Image.open(p).convert("RGBA")


@lru_cache(maxsize=1)
def font():
    return ImageFont.truetype(str(FONT), 12)


@lru_cache(maxsize=512)
def text_img(s: str, color: tuple, outline: tuple | None, shadow: bool, vertical: bool) -> Image.Image:
    """12px 像素字（1px 描边 + 右下投影），未放大。支持 \\n 多行与竖排。"""
    f = font()
    lines = list(s) if vertical else s.split("\n")
    lh = 13 if vertical else 15
    tmp = ImageDraw.Draw(Image.new("L", (1, 1)))
    wmax = max(max(1, round(tmp.textlength(ln, font=f))) for ln in lines)
    pad = 2
    im = Image.new("RGBA", (wmax + pad * 2 + 1, lh * len(lines) + pad * 2 + 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, ln in enumerate(lines):
        x = pad + (wmax - tmp.textlength(ln, font=f)) / 2
        y = pad + i * lh - 2
        if outline:
            if shadow:
                d.text((x + 1, y + 1), ln, font=f, fill=outline + (255,))
                d.text((x + 2, y + 2), ln, font=f, fill=outline + (255,))
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)):
                d.text((x + dx, y + dy), ln, font=f, fill=outline + (255,))
        d.text((x, y), ln, font=f, fill=color + (255,))
    # 像素字体抗锯齿边缘二值化，保持硬边
    a = im.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
    im.putalpha(a)
    return im


def scaled(im: Image.Image, s: int) -> Image.Image:
    s = max(1, int(s))
    return im if s == 1 else im.resize((im.width * s, im.height * s), Image.NEAREST)


def place(im: Image.Image, x: float, y: float, anchor: str = "c"):
    """按锚点返回左上角整数坐标。anchor：c 中心 / b 底边中点 / t 顶边中点 / l 左边中点 / r 右边中点 / tl 左上。"""
    w, h = im.size
    ax = {"l": 0, "tl": 0, "r": w, "tr": w}.get(anchor, w / 2)
    ay = {"b": h, "t": 0, "tl": 0, "tr": 0}.get(anchor, h / 2)
    return int(round(x - ax)), int(round(y - ay))


# ---------------------------------------------------------------- 背景图案

@lru_cache(maxsize=4)
def grid_pattern(tint: str = "") -> Image.Image:
    """深紫行情网格 + 暗色 K 线（比画布宽 160，用来横向卷动）。"""
    bw, bh = CW + 160, CH
    im = Image.new("RGB", (bw, bh), (14, 10, 28))
    d = ImageDraw.Draw(im)
    for x in range(0, bw, 20):
        d.line([(x, 0), (x, bh)], fill=(26, 20, 46))
    for y in range(0, bh, 20):
        d.line([(0, y), (bw, y)], fill=(26, 20, 46))
    rnd = random.Random(7)
    price = bh * 0.55
    for x in range(4, bw, 10):
        o = price
        price = clamp(price + rnd.gauss(-0.2, 6), bh * 0.2, bh * 0.85)
        c = (34, 92, 74) if price < o else (104, 40, 70)
        hi, lo = min(o, price) - rnd.uniform(2, 8), max(o, price) + rnd.uniform(2, 8)
        d.line([(x + 3, hi), (x + 3, lo)], fill=c)
        d.rectangle([x + 1, min(o, price), x + 5, max(o, price) + 1], fill=c)
    if tint:
        im = Image.blend(im, Image.new("RGB", im.size, hexcol(tint)), 0.12)
    return im


@lru_cache(maxsize=8)
def vignette_mask(strength: float) -> Image.Image:
    g = Image.new("L", (CW // 4, CH // 4), 255)
    ImageDraw.Draw(g).ellipse([-CW // 16, -CH // 14, CW // 4 + CW // 16, CH // 4 + CH // 14], fill=0)
    g = g.filter(ImageFilter.GaussianBlur(10)).resize((CW, CH), Image.BILINEAR)
    g = g.point(lambda v: int(v * strength))
    return dither_from_gray(g)


@lru_cache(maxsize=8)
def vgrad_mask(h0: int, h1: int) -> Image.Image:
    """竖向抖动渐变：y<h0 全 0，y>h1 全 255。"""
    g = Image.new("L", (1, CH))
    for y in range(CH):
        g.putpixel((0, y), int(255 * clamp((y - h0) / max(1, h1 - h0))))
    return dither_from_gray(g.resize((CW, CH)))


# ---------------------------------------------------------------- 图层

def grade(im: Image.Image, g: str | None) -> Image.Image:
    if not g:
        return im
    a = im.getchannel("A") if im.mode == "RGBA" else None
    rgb = im.convert("RGB")
    for part in g.split("+"):
        if part == "dark":
            rgb = ImageEnhance.Brightness(rgb).enhance(0.5)
        elif part == "dim":
            rgb = ImageEnhance.Brightness(rgb).enhance(0.75)
        elif part == "mono":
            rgb = ImageEnhance.Color(rgb).enhance(0.1)
        elif part == "red":
            rgb = ImageChops.multiply(rgb, Image.new("RGB", rgb.size, (255, 120, 130)))
        elif part == "blue":
            rgb = ImageChops.multiply(rgb, Image.new("RGB", rgb.size, (150, 170, 255)))
        elif part == "bright":
            rgb = ImageEnhance.Brightness(rgb).enhance(1.25)
    if a is not None:
        rgb = rgb.convert("RGBA")
        rgb.putalpha(a)
    return rgb


def draw_img(surf, L, lt, d, fno):
    src = load_rgba(L["src"])
    if "frames" in L:  # 横排序列帧
        n = L["frames"]
        fw = src.width // n
        i = (int(lt * L.get("anim_fps", 12)) + L.get("frame0", 0)) % n
        src = src.crop((i * fw, 0, i * fw + fw, src.height))
    if "crop" in L:
        x, y, w, h = L["crop"]
        src = src.crop((x, y, x + w, y + h))
    if L.get("flip"):
        src = src.transpose(Image.FLIP_LEFT_RIGHT)
    if "silhouette" in L:
        sil = Image.new("RGBA", src.size, hexcol(L["silhouette"]) + (255,))
        sil.putalpha(src.getchannel("A"))
        src = sil
    src = grade(src, L.get("grade"))
    im = scaled(src, round(kv(L.get("scale", 2), lt, 2)))
    anchor = L.get("anchor", "c")
    xs, ys = L.get("x", CW / 2), L.get("y", CH / 2)
    ghost = L.get("ghost")
    if ghost:  # 残影：之前几个时刻的位置，透明度递减
        n, dt = ghost
        for k in range(n, 0, -1):
            tt = lt - k * dt
            g = Image.new("RGBA", surf.size, (0, 0, 0, 0))
            g.alpha_composite(im, place(im, kv(xs, tt), kv(ys, tt), anchor))
            comp(surf, g, 0.55 * (1 - k / (n + 1)))
    surf.alpha_composite(im, place(im, kv(xs, lt), kv(ys, lt), anchor))


def draw_clip(surf, L, lt, d, fno):
    idx = int(L.get("from", 0) + lt * FPS * L.get("speed", 1.0))
    fr = load_clip_frame(L["clip"], idx)
    punch = L.get("punch")
    if punch:  # 阶梯式整数倍推近 [[t, cx, cy, 倍数], ...]
        cur = punch[0]
        for p in punch:
            if lt >= p[0]:
                cur = p
        _, cx, cy, s = cur
        if s > 1:
            w, h = CW // s, CH // s
            x0 = int(clamp(cx - w / 2, 0, CW - w))
            y0 = int(clamp(cy - h / 2, 0, CH - h))
            fr = scaled(fr.crop((x0, y0, x0 + w, y0 + h)), s)
    fr = grade(fr, L.get("grade"))
    if "crop" in L:
        x, y, w, h = L["crop"]
        fr = fr.crop((x, y, x + w, y + h))
        surf.alpha_composite(fr, place(fr, kv(L.get("x", CW / 2), lt), kv(L.get("y", CH / 2), lt), L.get("anchor", "c")))
    else:
        surf.alpha_composite(fr)


def draw_fill(surf, L, lt, d, fno):
    if "grad" in L:  # 两色抖动渐变（竖向）
        c0, c1 = (hexcol(c) for c in L["grad"])
        h0, h1 = L.get("grad_y", [0, CH])
        surf.paste(c0 + (255,), (0, 0, CW, CH))
        surf.paste(Image.new("RGBA", (CW, CH), c1 + (255,)), (0, 0), vgrad_mask(h0, h1))
    else:
        surf.paste(hexcol(L.get("color", "#000000")) + (255,), (0, 0, CW, CH))


def draw_stripes(surf, L, lt, d, fno):
    a, b = (hexcol(c) for c in L.get("colors", ["#140c22", "#1c1230"]))
    w = L.get("w", 12)
    surf.paste(a + (255,), (0, 0, CW, CH))
    dr = ImageDraw.Draw(surf)
    off = int(lt * L.get("speed", 40)) % (2 * w)
    for x0 in range(-CH - 2 * w + off, CW + 2 * w, 2 * w):
        dr.polygon([(x0 + CH, 0), (x0 + CH + w, 0), (x0 + w, CH), (x0, CH)], fill=b + (255,))


def draw_grid(surf, L, lt, d, fno):
    g = grid_pattern(L.get("tint", ""))
    ox = int(lt * L.get("speed", 24)) % 160
    surf.paste(g.crop((ox, 0, ox + CW, CH)).convert("RGBA"), (0, 0))


def draw_speedlines(surf, L, lt, d, fno):
    """横向流线（向左飞）。"""
    col = hexcol(L.get("color", "#ffffff")) + (255,)
    rnd = random.Random(L.get("seed", 3))
    dr = ImageDraw.Draw(surf)
    y0, y1 = L.get("band", [0, CH])
    sp = L.get("speed", 800)
    for _ in range(L.get("n", 30)):
        y = rnd.randrange(y0, y1)
        ln = rnd.randrange(*L.get("len", [30, 140]))
        v = sp * rnd.uniform(0.6, 1.4)
        span = CW + ln + 40
        x = (rnd.uniform(0, span) - lt * v) % span - ln
        dr.rectangle([int(x), y, int(x + ln), y + rnd.choice((0, 0, 1))], fill=col)


def draw_focus(surf, L, lt, d, fno):
    """集中线：从画面外指向中心的细三角，每 2 帧换一次（一拍二）。"""
    col = hexcol(L.get("color", "#ffffff")) + (255,)
    cx, cy = L.get("cx", CW / 2), L.get("cy", CH / 2)
    rnd = random.Random(L.get("seed", 5) * 1000 + fno // 2)
    dr = ImageDraw.Draw(surf)
    r_out = 500
    for _ in range(L.get("n", 60)):
        a = rnd.uniform(0, 2 * math.pi)
        wa = rnd.uniform(0.006, 0.02)
        r_in = L.get("r", 120) * rnd.uniform(0.85, 1.6)
        p0 = (cx + math.cos(a) * r_in, cy + math.sin(a) * r_in)
        p1 = (cx + math.cos(a - wa) * r_out, cy + math.sin(a - wa) * r_out)
        p2 = (cx + math.cos(a + wa) * r_out, cy + math.sin(a + wa) * r_out)
        dr.polygon([p0, p1, p2], fill=col)


def draw_burst(surf, L, lt, d, fno):
    """放射光芒（两色扇形交替，缓慢旋转）。"""
    a_col, b_col = (hexcol(c) for c in L.get("colors", ["#ff5da0", "#ff8cc0"]))
    cx, cy = L.get("cx", CW / 2), L.get("cy", CH / 2)
    n = L.get("n", 16)
    rot = math.radians(lt * L.get("speed", 20))
    surf.paste(a_col + (255,), (0, 0, CW, CH))
    dr = ImageDraw.Draw(surf)
    for i in range(n):
        a0 = rot + i * 2 * math.pi / n
        a1 = a0 + math.pi / n
        dr.polygon([(cx, cy), (cx + math.cos(a0) * 800, cy + math.sin(a0) * 800),
                    (cx + math.cos(a1) * 800, cy + math.sin(a1) * 800)], fill=b_col + (255,))


def draw_particles(surf, L, lt, d, fno):
    kind = L.get("kind", "dust")
    rnd = random.Random(L.get("seed", 11))
    dr = ImageDraw.Draw(surf)
    col = hexcol(L.get("color", "#ffffff")) + (255,)
    n = L.get("n", 40)
    if kind == "rain":
        vx, vy = L.get("vel", [-60, 520])
        ln = L.get("len", 8)
        k = ln / math.hypot(vx, vy)
        for _ in range(n):
            x0, y0 = rnd.uniform(0, CW + 200), rnd.uniform(0, CH)
            s = rnd.uniform(0.8, 1.2)
            x = (x0 + vx * s * lt) % (CW + 200) - 100
            y = (y0 + vy * s * lt) % (CH + 40) - 20
            dr.line([(int(x), int(y)), (int(x - vx * k), int(y - vy * k))], fill=col)
    elif kind == "dust":
        for _ in range(n):
            x0, y0 = rnd.uniform(0, CW), rnd.uniform(0, CH)
            vx, vy = rnd.uniform(-6, 6), rnd.uniform(-10, -3)
            if (fno // 3 + rnd.randrange(8)) % 8 == 0:
                continue  # 偶尔闪烁
            dr.point((int((x0 + vx * lt) % CW), int((y0 + vy * lt) % CH)), fill=col)
    elif kind == "sparkle":
        for _ in range(n):
            x, y = int(rnd.uniform(0, CW)), int(rnd.uniform(0, CH * L.get("ymax", 1.0)))
            ph = rnd.uniform(0, 1)
            k = (lt * L.get("rate", 1.5) + ph) % 1.0
            if k < 0.25:
                dr.point((x, y), fill=col)
                dr.line([(x - 1, y), (x + 1, y)], fill=col)
                dr.line([(x, y - 1), (x, y + 1)], fill=col)
            elif k < 0.4:
                dr.line([(x - 2, y), (x + 2, y)], fill=col)
                dr.line([(x, y - 2), (x, y + 2)], fill=col)
    elif kind in ("coins_fall", "coins_burst"):
        sheet = load_rgba("anim:coin")
        nf = 8
        fw = sheet.width // nf
        sc = L.get("scale", 1)
        for i in range(n):
            if kind == "coins_fall":
                x0 = rnd.uniform(-10, CW + 10)
                v = rnd.uniform(*L.get("speed", [60, 140]))
                y0 = rnd.uniform(-CH, 0)
                x, y = x0, (y0 + v * lt) % (CH + 60) - 30
            else:
                ox, oy = L.get("origin", [CW / 2, CH + 20])
                t0 = rnd.uniform(0, L.get("spread_t", 0.3))
                tt = lt - t0
                if tt < 0:
                    continue
                ang = math.radians(rnd.uniform(-90 - L.get("cone", 60), -90 + L.get("cone", 60)))
                sp = rnd.uniform(*L.get("speed", [260, 520]))
                x = ox + math.cos(ang) * sp * tt
                y = oy + math.sin(ang) * sp * tt + 0.5 * L.get("gravity", 500) * tt * tt
            fi = (int(lt * 14) + i) % nf
            fr = scaled(sheet.crop((fi * fw, 0, fi * fw + fw, sheet.height)), sc)
            surf.alpha_composite(fr, (int(x - fr.width / 2), int(y - fr.height / 2))) if -40 < x < CW + 40 and -40 < y < CH + 40 else None


def draw_text(surf, L, lt, d, fno):
    s = L["s"]
    t0 = L.get("t", [0, d])[0]
    if L.get("typewriter"):
        s = s[:max(0, int((lt - t0) * L.get("cps", 14)))]
        if not s:
            return
    outline = None if L.get("outline", "x") is None else hexcol(L.get("outline"), DARK)
    im = text_img(s, hexcol(L.get("color")), outline, L.get("shadow", True), L.get("vertical", False))
    sc = L.get("scale", 1)
    if "slam" in L:  # 从大号逐级缩到目标字号（整数倍）
        s0, dur = L["slam"] if isinstance(L["slam"], list) else (L["slam"], 0.12)
        k = clamp((lt - t0) / dur)
        sc = round(s0 + (sc - s0) * k)
    im = scaled(im, sc)
    x, y = kv(L.get("x", CW / 2), lt), kv(L.get("y", CH / 2), lt)
    anchor = {"c": "c", "l": "l", "r": "r"}[L.get("align", "c")]
    if L.get("box"):
        bx = L["box"] if isinstance(L["box"], dict) else {}
        pad = bx.get("pad", 4)
        bw, bh = im.width + pad * 2 + 4, im.height + pad
        box = Image.new("RGBA", (bw, bh), hexcol(bx.get("color"), (8, 6, 16)) + (255,))
        if bx.get("bar", "#ff5da0"):
            ImageDraw.Draw(box).rectangle([0, 0, 2, bh], fill=hexcol(bx.get("bar", "#ff5da0")) + (255,))
        bxy = place(box, x - (pad + 4 if anchor == "l" else 0) + (pad if anchor == "r" else 0), y, anchor)
        g = Image.new("RGBA", surf.size, (0, 0, 0, 0))
        g.alpha_composite(box, bxy)
        comp(surf, g, bx.get("alpha", 0.85))
    surf.alpha_composite(im, place(im, x, y, anchor))


def draw_rect(surf, L, lt, d, fno):
    x, y, w, h = L["rect"]
    dr = ImageDraw.Draw(surf)
    dr.rectangle([x, y, x + w - 1, y + h - 1], fill=hexcol(L.get("color", "#000000")) + (255,))


def draw_icons(surf, L, lt, d, fno):
    ids = L["icons"]
    cols = L.get("cols", 4)
    sc = L.get("scale", 2)
    cell = L.get("cell", 32 * sc + 8)
    rows = math.ceil(len(ids) / cols)
    x0 = L.get("x", CW / 2) - cols * cell / 2 + cell / 2
    y0 = L.get("y", CH / 2) - rows * cell / 2 + cell / 2
    t_in = L.get("t", [0, d])[0]
    for i, iid in enumerate(ids):
        tt = lt - t_in - i * L.get("stagger", 0.05)
        if tt < 0:
            continue
        ic = load_rgba("icon:" + iid)
        s2 = sc + 1 if tt < 0.06 else sc  # 弹出时先大一号
        ic = scaled(ic, s2)
        surf.alpha_composite(ic, place(ic, x0 + (i % cols) * cell, y0 + (i // cols) * cell))


def draw_counter(surf, L, lt, d, fno):
    t0, t1 = L.get("t_in", 0.2), L.get("out_at", d - 1.0)
    k = ease((lt - t0) / max(0.01, t1 - t0), L.get("ease", "in"))
    v = L["from"] + (L["to"] - L["from"]) * k
    im = text_img(L.get("fmt", "{:,.0f}円").format(v), hexcol(L.get("color"), (255, 220, 90)), DARK, True, False)
    sc = L.get("scale", 4)
    if lt >= t1 and lt < t1 + 0.1:
        sc += 1
    im = scaled(im, sc)
    surf.alpha_composite(im, place(im, L.get("x", CW / 2), L.get("y", CH / 2)))


def draw_vignette(surf, L, lt, d, fno):
    surf.paste(hexcol(L.get("color", "#000000")) + (255,), (0, 0), vignette_mask(L.get("strength", 0.8)))


def draw_letterbox(surf, L, lt, d, fno):
    h = int(kv(L.get("h", 36), lt))
    if h > 0:
        dr = ImageDraw.Draw(surf)
        col = hexcol(L.get("color", "#000000")) + (255,)
        dr.rectangle([0, 0, CW, h - 1], fill=col)
        dr.rectangle([0, CH - h, CW, CH], fill=col)


def draw_group(surf, L, lt, d, fno):
    for sub in L["layers"]:
        draw_layer(surf, sub, lt, d, fno)


DRAW = {"img": draw_img, "clip": draw_clip, "fill": draw_fill, "stripes": draw_stripes, "grid": draw_grid,
        "speedlines": draw_speedlines, "focus": draw_focus, "burst": draw_burst, "particles": draw_particles,
        "text": draw_text, "rect": draw_rect, "icons": draw_icons, "counter": draw_counter,
        "vignette": draw_vignette, "letterbox": draw_letterbox, "group": draw_group}


def draw_layer(base: Image.Image, L: dict, lt: float, d: float, fno: int):
    """通用外壳：时间窗 t、整体偏移 ox/oy、多边形遮罩 poly + 描边 border、透明度 alpha / 淡入 fi / 淡出 fo。"""
    # 没写结束时间的图层一直显示：转场时上一个镜头会演到 d 之后，不能在 d 处消失
    t0, t1 = L.get("t", [0, None])
    t1 = math.inf if t1 is None else t1
    if not (t0 <= lt < t1):
        return
    surf = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    DRAW[L["type"]](surf, L, lt, d, fno)
    ox, oy = int(round(kv(L.get("ox"), lt))), int(round(kv(L.get("oy"), lt)))
    if ox or oy:
        moved = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        moved.paste(surf, (ox, oy))
        surf = moved
    if "poly" in L:
        pts = [(x + ox, y + oy) for x, y in L["poly"]]
        m = Image.new("L", (CW, CH), 0)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        surf.putalpha(ImageChops.multiply(surf.getchannel("A"), m))
        if "border" in L:
            ImageDraw.Draw(surf).polygon(pts, outline=hexcol(L["border"]) + (255,), width=L.get("bw", 2))
    a = kv(L.get("alpha", 1.0), lt)
    fi, fo = L.get("fi", 0), L.get("fo", 0)
    if fi:
        a *= clamp((lt - t0) / fi)
    if fo and t1 != math.inf:
        a *= clamp((t1 - lt) / fo)
    comp(base, surf, a)


# ---------------------------------------------------------------- 镜头特效与转场

def glitch(im: Image.Image, fno: int, amt: float) -> Image.Image:
    r = random.Random(fno * 104729)
    rch, g, b = im.split()
    sh = max(1, int(6 * amt))
    im = Image.merge("RGB", (ImageChops.offset(rch, sh, 0), g, ImageChops.offset(b, -sh, 0)))
    for _ in range(int(6 * amt) + 1):
        y = r.randrange(0, CH - 14)
        h = r.randrange(3, 20)
        dx = r.randrange(-int(28 * amt) - 1, int(28 * amt) + 2)
        band = im.crop((0, y, CW, y + h))
        im.paste(ImageChops.offset(band, dx, 0), (0, y))
    return im


def impact(im: Image.Image, mode: str) -> Image.Image:
    """冲击帧：按亮度二值化成双色（neg = 白底黑线反相，red = 黑红，white = 黑白）。"""
    lum = im.convert("L")
    thr = 96 if mode == "neg" else 110
    m = lum.point(lambda v: 255 if v > thr else 0)
    lo, hi = {"neg": ((245, 240, 250), (12, 8, 18)), "red": ((14, 0, 6), (255, 48, 80)),
              "white": ((10, 6, 16), (255, 255, 255))}[mode]
    out = Image.new("RGB", im.size, lo)
    out.paste(hi, (0, 0), m)
    return out


def fx_post(im: Image.Image, sh: dict, lt: float, d: float, fno: int) -> Image.Image:
    fx = sh.get("fx", {})
    for t0, t1, mode in fx.get("impact", []):
        if t0 <= lt < t1:
            im = impact(im, mode)
    for t0, t1, amp in fx.get("shake", []):
        if t0 <= lt < t1:
            r = random.Random(fno * 7919)
            k = 1 - (lt - t0) / (t1 - t0)
            dx, dy = int(round(r.uniform(-amp, amp) * k)), int(round(r.uniform(-amp, amp) * k))
            moved = Image.new("RGB", im.size, (0, 0, 0))
            moved.paste(im, (dx, dy))
            im = moved
    for t0, t1, amt in fx.get("glitch", []):
        if t0 <= lt < t1:
            im = glitch(im, fno, amt)
    for fl in fx.get("flash", []):
        t0, dur = fl[0], fl[1]
        if t0 <= lt < t0 + dur:
            lvl = dither_level(0.95 * (1 - (lt - t0) / dur))
            im.paste(hexcol(fl[2]) if len(fl) > 2 else WHITE, (0, 0, CW, CH), dither_mask(lvl))
    fi, fo = sh.get("fade_in", 0.0), sh.get("fade_out", 0.0)
    a = 1.0
    if fi and lt < fi:
        a = lt / fi
    if fo and lt > d - fo:
        a = min(a, (d - lt) / fo)
    if a < 1:
        im.paste((0, 0, 0), (0, 0, CW, CH), dither_mask(16 - dither_level(a)))
    return im


def render_shot(sh: dict, lt: float, fno: int) -> Image.Image:
    base = Image.new("RGB", (CW, CH), hexcol(sh.get("bg", "#000000")))
    for L in sh.get("layers", []):
        draw_layer(base, L, lt, sh["d"], fno)
    return fx_post(base, sh, lt, sh["d"], fno)


def trans_mask(tr: dict, k: float) -> tuple[Image.Image, Image.Image | None]:
    """返回（新镜头可见的掩码，转场边缘色带掩码或 None）。"""
    typ = tr["type"]
    m = Image.new("L", (CW, CH), 0)
    dr = ImageDraw.Draw(m)
    edge = None
    if typ == "dither":
        return dither_mask(dither_level(k)), None
    if typ == "slash":  # 左下→右上斜切
        sl = 0.5 * CH
        e = -sl - 16 + (CW + sl + 32) * ease(k, "out")
        dr.polygon([(-10, -10), (e + sl, -10), (e, CH + 10), (-10, CH + 10)], fill=255)
        em = Image.new("L", (CW, CH), 0)
        ImageDraw.Draw(em).polygon([(e + sl, -10), (e + sl + 8, -10), (e + 8, CH + 10), (e, CH + 10)], fill=255)
        edge = em
    elif typ == "diamond":  # 菱形格从左往右长出来
        s = 32
        for cy in range(0, CH + s, s):
            for cx in range(0, CW + s, s):
                kk = clamp((k - 0.5 * cx / CW) / 0.5)
                r = kk * s
                if r > 0:
                    dr.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=255)
    elif typ == "shutter":  # 横向百叶，交替方向
        hh = 20
        for i, y in enumerate(range(0, CH, hh)):
            kk = clamp((k - i * 0.02) / 0.6)
            w = int(CW * ease(kk, "out"))
            if i % 2:
                dr.rectangle([CW - w, y, CW, y + hh - 1], fill=255)
            else:
                dr.rectangle([0, y, w, y + hh - 1], fill=255)
    elif typ == "iris":
        cx, cy = tr.get("center", [CW / 2, CH / 2])
        r = ease(k, "in") * 760
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    else:
        raise SystemExit(f"未知转场 {typ}")
    return m, edge


def mosaic(im: Image.Image, block: int) -> Image.Image:
    if block <= 1:
        return im
    return im.resize((max(1, CW // block), max(1, CH // block)), Image.BOX).resize((CW, CH), Image.NEAREST)


# ---------------------------------------------------------------- 时间线

def build_timeline(cfg: dict):
    """shots 依次首尾相接；写了 at（绝对秒）的镜头从该时刻开始，上一个镜头的 d 自动补齐。"""
    shots = cfg["shots"]
    t = 0.0
    out = []
    for i, sh in enumerate(shots):
        start = sh.get("at", t)
        if out and "at" in sh:
            out[-1][1]["d"] = round(start - out[-1][0], 4)
        out.append([start, sh])
        if "d" not in sh:
            nxt = next((s["at"] for s in shots[i + 1:] if "at" in s), None)
            if nxt is None:
                raise SystemExit(f"镜头 {sh.get('id')} 缺 d")
            sh["d"] = nxt - start
        t = start + sh["d"]
    return out, t


def frame_at(tl, t: float, fno: int, up: int = UP) -> Image.Image:
    """up=1 直接返回 640×360 画布（游戏内开场用），默认 ×3 最近邻放大。"""
    idx = max((i for i, (s, _) in enumerate(tl) if s <= t), default=0)
    s, sh = tl[idx]
    if t >= s + sh["d"]:
        return Image.new("RGB", (CW * up, CH * up))
    lt = t - s
    im = render_shot(sh, lt, fno)
    tr = sh.get("in")
    if tr and idx > 0 and lt < tr["d"]:
        ps, psh = tl[idx - 1]
        prev = render_shot(psh, t - ps, fno)  # 上一个镜头继续往后演
        k = lt / tr["d"]
        if tr["type"] == "pixelate":
            blk = int(round(1 + 15 * (1 - abs(2 * k - 1))))
            im = mosaic(prev if k < 0.5 else im, blk)
        elif tr["type"] == "flash":
            col = hexcol(tr.get("color"), WHITE)
            src = prev if k < 0.5 else im
            src = src.copy()
            src.paste(col, (0, 0, CW, CH), dither_mask(dither_level(1 - abs(2 * k - 1))))
            im = src
        else:
            m, edge = trans_mask(tr, k)
            out = prev.copy()
            out.paste(im, (0, 0), m)
            if edge is not None:
                out.paste(hexcol(tr.get("color"), WHITE), (0, 0), edge)
            im = out
    return im if up == 1 else im.resize((CW * up, CH * up), Image.NEAREST)


# ---------------------------------------------------------------- 音频

def mix_audio(cfg: dict, total: float, t_from: float, dst: Path):
    m = cfg["music"]
    inputs = ["-ss", str(m["offset"] + t_from), "-i", str(ROOT / m["src"])]
    end = min(m.get("fade_out_end", total), total)
    fin = m.get("fade_in", 0.5) if t_from == 0 else 0.05
    filt = [f"[0:a]aresample=48000,volume={m.get('gain_db', 0)}dB,afade=t=in:st=0:d={fin},"
            f"afade=t=out:st={max(0.0, end - t_from - m.get('fade_out', 3))}:d={m.get('fade_out', 3)},apad[m]"]
    labels = ["[m]"]
    n = 1
    for i, s in enumerate(cfg.get("sfx", [])):
        if s["t"] < t_from or s["t"] >= total:
            continue
        inputs += ["-i", str(ROOT / s["src"])]
        ms = int((s["t"] - t_from) * 1000)
        filt.append(f"[{n}:a]aresample=48000,aformat=channel_layouts=stereo,volume={s.get('gain_db', -6)}dB,adelay={ms}|{ms}[s{i}]")
        labels.append(f"[s{i}]")
        n += 1
    filt.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,"
                f"atrim=0:{total - t_from},alimiter=limit=0.75:level=false[a]")
    cmd = ["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(filt), "-map", "[a]",
           "-ac", "2", "-c:a", "pcm_s16le", str(dst)]
    subprocess.run(cmd, check=True)


# ---------------------------------------------------------------- 主程序

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="1280×720、快速编码")
    ap.add_argument("--game", action="store_true",
                    help="游戏内开场：640×360 画布原样 → Theora(yuv444p)+Vorbis → assets/video/opening.ogv")
    ap.add_argument("--stills", default="", help="逗号分隔的秒数，各出一张 1920×1080 PNG")
    ap.add_argument("--sheet", default="", help="逗号分隔的秒数，拼成一张 4 列总览（每格 640×360）")
    ap.add_argument("--from", dest="t_from", type=float, default=0.0)
    ap.add_argument("--to", dest="t_to", type=float, default=None)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    tl, total = build_timeline(cfg)
    print(f"时长 {total:.2f}s，{len(tl)} 个镜头")
    for s, sh in tl:
        print(f"  {s:6.2f}  {sh['d']:5.2f}  {sh.get('id', '')}")

    if args.stills or args.sheet:
        ts = [float(x) for x in (args.stills or args.sheet).split(",")]
        ims = [frame_at(tl, t, int(round(t * FPS))) for t in ts]
        OUT.mkdir(parents=True, exist_ok=True)
        if args.stills:
            (OUT / "stills").mkdir(exist_ok=True)
            for t, im in zip(ts, ims):
                p = OUT / "stills" / f"t{t:06.2f}.png"
                im.save(p)
                print("→", p)
        else:
            cols = 4
            sheet = Image.new("RGB", (cols * CW, math.ceil(len(ims) / cols) * CH))
            for i, im in enumerate(ims):
                sheet.paste(im.resize((CW, CH), Image.NEAREST), ((i % cols) * CW, (i // cols) * CH))
            p = Path(args.out) if args.out else OUT / "sheet.png"
            sheet.save(p)
            print("→", p)
        return

    t_to = min(args.t_to or total, total)
    n0, n1 = int(round(args.t_from * FPS)), int(round(t_to * FPS))
    OUT.mkdir(parents=True, exist_ok=True)
    if args.game:
        out = Path(args.out) if args.out else ROOT / "assets/video/opening.ogv"
        out.parent.mkdir(parents=True, exist_ok=True)
    else:
        out = Path(args.out) if args.out else OUT / ("preview.mp4" if args.preview else "kurumi-fx-rogue-pv.mp4")
    wav = OUT / "_mix.wav"
    mix_audio(cfg, t_to, args.t_from, wav)
    vw, vh = (1280, 720) if args.preview else (CW, CH) if args.game else (W, H)
    if args.game:
        # 画布原生分辨率；4:4:4 免得 2×2 色度块让像素边缘串色。Godot 只能原生播放 Ogg Theora。
        # q3 约 15 MB：q2 文字开始糊，q5 体积翻倍、肉眼看不出差别（抖动纹理很难压）
        enc = ["-c:v", "libtheora", "-q:v", "3", "-pix_fmt", "yuv444p", "-c:a", "libvorbis", "-q:a", "4"]
    else:
        venc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "24"] if args.preview else \
               ["-c:v", "libx264", "-preset", "slow", "-crf", "16", "-tune", "animation"]
        enc = [*venc, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart"]
    cmd = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{vw}x{vh}", "-r", str(FPS),
           "-i", "-", "-i", str(wav), *enc, "-shortest", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(n0, n1):
        im = frame_at(tl, f / FPS, f, 1 if args.game else UP)
        if args.preview:
            im = im.resize((vw, vh), Image.NEAREST)
        proc.stdin.write(im.tobytes())
        if (f - n0) % 150 == 0:
            print(f"  帧 {f}/{n1}", flush=True)
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit("ffmpeg 失败")
    wav.unlink(missing_ok=True)
    print("→", out)


if __name__ == "__main__":
    sys.exit(main())
