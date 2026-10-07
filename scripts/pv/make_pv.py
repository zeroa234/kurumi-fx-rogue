#!/usr/bin/env python3
"""PV 合成器：按 config/pv-edit.json 逐帧渲染画面（Pillow）→ ffmpeg 编码 → 混入配乐与音效。

用法（在 projects/kurumi-fx-rogue 下）：
  python scripts/pv/make_pv.py                  # 出成片 output/pv/kurumi-fx-rogue-pv.mp4
  python scripts/pv/make_pv.py --preview        # 960×540 快速预览 output/pv/preview.mp4
  python scripts/pv/make_pv.py --stills 3,12.5  # 只渲染这几个时刻的单帧到 output/pv/stills/（看构图用）
  python scripts/pv/make_pv.py --from 20 --to 35 --preview   # 只渲染一段

素材：
  output/pv/raw/<片段>/f########.png  —— scripts/pv/capture_all.sh 录的实机画面（640×360，30fps）
  output/hires/*.png                  —— 游戏美术的 ComfyUI 高清原图（gen_assets.py 产出，不入库）
  assets/pv/*.png / *.ogg             —— PV 专用关键帧与配乐（入库，来源见 assets/pv/index.json）
  assets/sprites/、assets/sfx/、assets/fonts/ —— 游戏本体素材

镜头（shots[]）字段见 config/pv-edit.json 的 _doc。所有随机效果（抖动/故障）按帧号做种子，结果可复现。
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
W, H = 1920, 1080

PINK = (255, 93, 160)
CYAN = (110, 230, 255)
WHITE = (255, 255, 255)
DARK = (11, 8, 20)


def hexcol(s, default=WHITE):
    if not s:
        return default
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def ease(x: float, kind: str = "inout") -> float:
    x = max(0.0, min(1.0, x))
    if kind == "out":
        return 1 - (1 - x) ** 3
    if kind == "in":
        return x ** 3
    if kind == "linear":
        return x
    return x * x * (3 - 2 * x)


def lerp(a, b, k):
    return a + (b - a) * k


# ---------------------------------------------------------------- 素材缓存

def resolve(src: str) -> Path:
    """'hires:cg_win' → output/hires/cg_win.png；'pv:pv_key' → assets/pv/pv_key.png；其余按项目相对路径。"""
    if src.startswith("hires:"):
        return ROOT / "output/hires" / (src[6:] + ".png")
    if src.startswith("pv:"):
        return ROOT / "assets/pv" / (src[3:] + ".png")
    if src.startswith("portrait:"):
        return ROOT / "assets/sprites/portraits" / (src[9:] + ".png")
    if src.startswith("icon:"):
        return ROOT / "assets/sprites/icons" / (src[5:] + ".png")
    return ROOT / src


@lru_cache(maxsize=32)
def load_still(src: str) -> Image.Image:
    im = Image.open(resolve(src)).convert("RGB")
    # 统一铺满 16:9，并预放大到至少 1.5 倍输出尺寸，推拉时不再反复放大
    tw, th = int(W * 1.5), int(H * 1.5)
    s = max(tw / im.width, th / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x0, y0 = (im.width - tw) // 2, (im.height - th) // 2
    return im.crop((x0, y0, x0 + tw, y0 + th))


@lru_cache(maxsize=8)
def load_rgba(src: str) -> Image.Image:
    return Image.open(resolve(src)).convert("RGBA")


@lru_cache(maxsize=64)
def load_clip_frame(clip: str, idx: int) -> Image.Image:
    d = OUT / "raw" / clip
    p = d / f"f{idx:08d}.png"
    if not p.exists():
        frames = sorted(d.glob("f*.png"))
        if not frames:
            raise SystemExit(f"缺少实机素材 {d}，先跑 bash scripts/pv/capture_all.sh {clip}")
        p = frames[min(idx, len(frames) - 1)] if idx >= 0 else frames[0]
    # 像素画面先最近邻放大 3 倍（640×360 → 1920×1080），推拉再用平滑插值
    return Image.open(p).convert("RGB").resize((W, H), Image.NEAREST)


@lru_cache(maxsize=256)
def text_img(s: str, scale: int, color: tuple, outline: tuple | None = DARK, shadow: bool = True) -> Image.Image:
    """12px 像素字渲染后整数倍放大，保持像素颗粒。支持多行（\\n）。"""
    f = ImageFont.truetype(str(FONT), 12)
    lines = s.split("\n")
    lh = 15
    tmp = ImageDraw.Draw(Image.new("L", (1, 1)))
    wmax = max(max(1, round(tmp.textlength(ln, font=f))) for ln in lines)
    pad = 2
    im = Image.new("RGBA", (wmax + pad * 2 + 1, lh * len(lines) + pad * 2 + 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, ln in enumerate(lines):
        lw = tmp.textlength(ln, font=f)
        x = pad + (wmax - lw) / 2
        y = pad + i * lh - 2
        if shadow and outline:
            d.text((x + 1, y + 1), ln, font=f, fill=outline + (255,))
        if outline:
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                d.text((x + dx, y + dy), ln, font=f, fill=outline + (255,))
        d.text((x, y), ln, font=f, fill=color + (255,))
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


@lru_cache(maxsize=4)
def grid_bg(tint: str = "") -> Image.Image:
    """深紫底 + 行情网格 + 淡淡的 K 线，用作无图镜头的背景（比输出大一圈，方便平移）。"""
    bw, bh = W + 240, H + 240
    im = Image.new("RGB", (bw, bh), (14, 10, 28))
    d = ImageDraw.Draw(im)
    for x in range(0, bw, 60):
        d.line([(x, 0), (x, bh)], fill=(30, 24, 54), width=2)
    for y in range(0, bh, 60):
        d.line([(0, y), (bw, y)], fill=(30, 24, 54), width=2)
    rnd = random.Random(7)
    price = bh * 0.6
    for x in range(20, bw, 30):
        o = price
        price += rnd.gauss(-1.2, 18)
        price = max(bh * 0.2, min(bh * 0.85, price))
        c = (40, 120, 90) if price < o else (130, 50, 80)
        hi, lo = min(o, price) - rnd.uniform(5, 25), max(o, price) + rnd.uniform(5, 25)
        d.line([(x + 9, hi), (x + 9, lo)], fill=c, width=2)
        d.rectangle([x + 3, min(o, price), x + 15, max(o, price) + 2], fill=c)
    im = im.filter(ImageFilter.GaussianBlur(1.2))
    if tint:
        im = Image.blend(im, Image.new("RGB", im.size, hexcol(tint)), 0.15)
    return im


# ---------------------------------------------------------------- 镜头渲染

def kenburns(src_img: Image.Image, t: float, sh: dict) -> Image.Image:
    """src_img 已经是 16:9；zoom=[z0,z1]（1 = 刚好铺满），center=[[x,y],[x,y]]（0~1）。"""
    z = sh.get("zoom", [1.0, 1.08])
    c = sh.get("center", [[0.5, 0.5], [0.5, 0.5]])
    k = ease(t, sh.get("ease", "inout"))
    zz = lerp(z[0], z[1], k)
    cx, cy = lerp(c[0][0], c[1][0], k), lerp(c[0][1], c[1][1], k)
    sw, sh_ = src_img.width / zz, src_img.height / zz
    x0 = min(max(cx * src_img.width - sw / 2, 0), src_img.width - sw)
    y0 = min(max(cy * src_img.height - sh_ / 2, 0), src_img.height - sh_)
    return src_img.resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + sw, y0 + sh_), reducing_gap=None)


def grade(im: Image.Image, g: str | None) -> Image.Image:
    if not g:
        return im
    for part in g.split("+"):
        if part == "dark":
            im = ImageEnhance.Brightness(im).enhance(0.55)
        elif part == "dim":
            im = ImageEnhance.Brightness(im).enhance(0.78)
        elif part == "red":
            r = Image.new("RGB", im.size, (200, 20, 40))
            im = ImageChops.multiply(im, Image.blend(Image.new("RGB", im.size, WHITE), r, 0.35))
        elif part == "blue":
            im = Image.blend(im, Image.new("RGB", im.size, (20, 40, 110)), 0.18)
        elif part == "mono":
            im = ImageEnhance.Color(im).enhance(0.15)
        elif part == "vignette":
            im = ImageChops.multiply(im, vignette())
    return im


@lru_cache(maxsize=1)
def vignette() -> Image.Image:
    m = Image.new("L", (W // 8, H // 8), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([-W // 40, -H // 30, W // 8 + W // 40, H // 8 + H // 30], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(14)).resize((W, H), Image.BICUBIC)
    base = Image.new("RGB", (W, H), (70, 60, 80))
    return Image.composite(Image.new("RGB", (W, H), WHITE), base, m)


def render_base(sh: dict, lt: float, d: float, fno: int) -> Image.Image:
    typ = sh["type"]
    p = lt / d if d > 0 else 0.0
    if typ == "black":
        return Image.new("RGB", (W, H), hexcol(sh.get("color"), (0, 0, 0)))
    if typ == "still":
        return kenburns(load_still(sh["src"]), p, sh)
    if typ == "clip":
        idx = int(sh.get("from", 0) + lt * 30 * sh.get("speed", 1.0))
        fr = load_clip_frame(sh["clip"], idx)
        if "zoom" in sh or "center" in sh:
            fr = kenburns(fr, p, {"zoom": sh.get("zoom", [1, 1]), "center": sh.get("center", [[.5, .5], [.5, .5]]), "ease": sh.get("ease", "inout")})
        if "inset" in sh:
            # 画中画：游戏画面缩小放在网格背景上，粉色细边框，下方留字幕位
            k = sh["inset"]
            iw, ih = int(W * k), int(H * k)
            bg = grid_bg(sh.get("tint", ""))
            ox = int(lerp(0, 160, p))
            base = bg.crop((ox, 120, ox + W, 120 + H))
            x0, y0 = (W - iw) // 2, int(sh.get("inset_y", 0.035) * H)
            d = ImageDraw.Draw(base)
            d.rectangle([x0 - 6, y0 - 6, x0 + iw + 5, y0 + ih + 5], fill=PINK)
            base.paste(fr.resize((iw, ih), Image.LANCZOS), (x0, y0))
            return base
        return fr
    if typ == "grid":
        bg = grid_bg(sh.get("tint", ""))
        ox = int(lerp(0, 240, p))
        return bg.crop((ox, 120, ox + W, 120 + H))
    raise SystemExit(f"未知镜头类型 {typ}")


def paste_center(base: Image.Image, im: Image.Image, cx: float, cy: float, alpha: float = 1.0):
    if alpha <= 0:
        return
    if alpha < 1:
        a = im.getchannel("A").point(lambda v: int(v * alpha))
        im = im.copy()
        im.putalpha(a)
    base.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def draw_layers(base: Image.Image, sh: dict, lt: float, d: float):
    """叠加层：文字、立绘排、图标格、计数器、片尾。base 为 RGBA。"""
    if "counter" in sh:
        c = sh["counter"]
        t0, t1 = c.get("in", 0.3), c.get("out_at", d - 1.0)
        k = ease((lt - t0) / max(0.01, t1 - t0), c.get("ease", "in"))
        v = lerp(c["from"], c["to"], k)
        s = c.get("fmt", "{:,.0f}円").format(v)
        col = hexcol(c.get("color"), (255, 220, 90))
        im = text_img(s, c.get("scale", 10), col, DARK)
        if c.get("band", True):
            band = Image.new("RGBA", (W, im.height + 160), (8, 6, 16, 160))
            base.alpha_composite(band, (0, int(c.get("y", 0.5) * H - im.height / 2 - 120)))
        pop = 1.0
        if lt >= t1:
            pop = 1 + 0.12 * max(0.0, 1 - (lt - t1) / 0.3)
            if pop > 1:
                im = im.resize((int(im.width * pop), int(im.height * pop)), Image.NEAREST)
        paste_center(base, im, W / 2, c.get("y", 0.5) * H)

    for tx in sh.get("text", []):
        t0, t1 = tx.get("in", 0.0), tx.get("out", d)
        if not (t0 <= lt < t1):
            continue
        s = tx["s"]
        if tx.get("typewriter"):
            n = int((lt - t0) * tx.get("cps", 14))
            s = s[:max(0, n)]
            if not s:
                continue
        fade = tx.get("fade", 0.25)
        a = min(1.0, (lt - t0) / fade if fade else 1.0, (t1 - lt) / fade if fade else 1.0)
        im = text_img(s, tx.get("scale", 4), hexcol(tx.get("color")), hexcol(tx.get("outline"), DARK))
        pos = tx.get("pos", "bottom")
        x, y = {"bottom": (W / 2, H - 150), "center": (W / 2, H / 2), "top": (W / 2, 150),
                "upper": (W / 2, H * 0.33), "lower": (W / 2, H * 0.68)}.get(pos, (W / 2, H - 150)) if isinstance(pos, str) else (pos[0] * W, pos[1] * H)
        if tx.get("rise", True):
            y += (1 - ease(min(1.0, (lt - t0) / 0.35), "out")) * 24
        if tx.get("band"):
            # 横贯全宽的半透明暗带，压住亮背景
            bh = im.height + 40
            band = Image.new("RGBA", (W, bh), (8, 6, 16, int(170 * a)))
            base.alpha_composite(band, (0, int(y - bh / 2)))
        if tx.get("box"):
            pad = 22
            box = Image.new("RGBA", (im.width + pad * 2, im.height + pad), (8, 6, 16, int(190 * a)))
            bd = ImageDraw.Draw(box)
            bd.rectangle([0, 0, 7, box.height], fill=PINK + (int(255 * a),))
            paste_center(base, box, x, y)
        paste_center(base, im, x, y, a)

    if "portraits" in sh:
        items = sh["portraits"]
        n = len(items)
        span = W / n
        for i, it in enumerate(items):
            t0 = 0.12 + i * sh.get("stagger", 0.35)
            k = ease((lt - t0) / 0.4, "out")
            if k <= 0:
                continue
            p = load_rgba("portrait:" + it["id"])
            sc = it.get("scale", 4)
            p = p.resize((p.width * sc, p.height * sc), Image.NEAREST)
            cx = span * (i + 0.5)
            cy = H * 0.47 + (1 - k) * 80
            paste_center(base, p, cx, cy, k)
            lbl = text_img(it["name"], 4, hexcol(it.get("color")), DARK)
            paste_center(base, lbl, cx, cy + p.height / 2 + 40, k)

    if "icons" in sh:
        ids = sh["icons"]
        cols = sh.get("cols", 6)
        sc = sh.get("icon_scale", 5)
        cell = 32 * sc + 40
        rows = math.ceil(len(ids) / cols)
        x0 = W / 2 - cols * cell / 2 + cell / 2
        y0 = sh.get("icons_y", H * 0.44) - rows * cell / 2 + cell / 2
        for i, iid in enumerate(ids):
            t0 = 0.05 + i * sh.get("stagger", 0.06)
            k = ease((lt - t0) / 0.25, "out")
            if k <= 0:
                continue
            ic = load_rgba("icon:" + iid)
            s2 = max(1, round(sc * (0.6 + 0.4 * k)))
            ic = ic.resize((ic.width * s2, ic.height * s2), Image.NEAREST)
            paste_center(base, ic, x0 + (i % cols) * cell, y0 + (i // cols) * cell, k)


def fx_post(im: Image.Image, sh: dict, lt: float, d: float, fno: int) -> Image.Image:
    fx = sh.get("fx", {})
    for sk in fx.get("shake", []):
        t0, t1, amp = sk
        if t0 <= lt < t1:
            r = random.Random(fno * 7919)
            k = 1 - (lt - t0) / (t1 - t0)
            dx, dy = int(r.uniform(-amp, amp) * k), int(r.uniform(-amp, amp) * k)
            im = ImageChops.offset(im, dx, dy)
    for gl in fx.get("glitch", []):
        t0, t1, amt = gl
        if t0 <= lt < t1:
            im = glitch(im, fno, amt)
    for fl in fx.get("flash", []):
        t0, dur = fl[0], fl[1]
        col = hexcol(fl[2]) if len(fl) > 2 else WHITE
        if t0 <= lt < t0 + dur:
            a = 1 - (lt - t0) / dur
            im = Image.blend(im, Image.new("RGB", im.size, col), a * 0.9)
    fi, fo = sh.get("fade_in", 0.0), sh.get("fade_out", 0.0)
    a = 1.0
    if fi and lt < fi:
        a = lt / fi
    if fo and lt > d - fo:
        a = min(a, (d - lt) / fo)
    if a < 1:
        im = Image.blend(Image.new("RGB", im.size, (0, 0, 0)), im, max(0.0, a))
    return im


def glitch(im: Image.Image, fno: int, amt: float) -> Image.Image:
    r = random.Random(fno * 104729)
    rch, g, b = im.split()
    sh = int(18 * amt)
    rch = ImageChops.offset(rch, sh, 0)
    b = ImageChops.offset(b, -sh, 0)
    im = Image.merge("RGB", (rch, g, b))
    for _ in range(int(6 * amt) + 1):
        y = r.randrange(0, H - 40)
        h = r.randrange(8, 60)
        dx = r.randrange(-int(80 * amt) - 1, int(80 * amt) + 2)
        band = im.crop((0, y, W, y + h))
        im.paste(ImageChops.offset(band, dx, 0), (0, y))
    return im


def render_shot(sh: dict, lt: float, fno: int) -> Image.Image:
    d = sh["d"]
    im = render_base(sh, lt, d, fno)
    im = grade(im, sh.get("grade"))
    if sh.get("text") or sh.get("portraits") or sh.get("icons") or sh.get("counter"):
        im = im.convert("RGBA")
        draw_layers(im, sh, lt, d)
        im = im.convert("RGB")
    return fx_post(im, sh, lt, d, fno)


# ---------------------------------------------------------------- 时间线

def build_timeline(cfg: dict):
    """返回 [(start, shot)]；shot.xfade>0 时与上一个镜头重叠交叉淡化。"""
    out, t = [], 0.0
    for sh in cfg["shots"]:
        xf = sh.get("xfade", 0.0)
        start = max(0.0, t - xf)
        out.append((start, sh))
        t = start + sh["d"]
    return out, t


def frame_at(tl, t: float, fno: int) -> Image.Image:
    act = [(s, sh) for s, sh in tl if s <= t < s + sh["d"]]
    if not act:
        return Image.new("RGB", (W, H))
    s, sh = act[-1]
    im = render_shot(sh, t - s, fno)
    xf = sh.get("xfade", 0.0)
    if len(act) > 1 and xf and t - s < xf:
        ps, psh = act[-2]
        prev = render_shot(psh, t - ps, fno)
        im = Image.blend(prev, im, ease((t - s) / xf))
    return im


# ---------------------------------------------------------------- 音频

def mix_audio(cfg: dict, total: float, t_from: float, dst: Path):
    m = cfg["music"]
    inputs = ["-ss", str(m["offset"] + t_from), "-i", str(ROOT / m["src"])]
    # 配乐在 fade_out_end（PV 秒数，默认片尾）前 fade_out 秒内淡出；之后由 apad 补静音
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
    ap.add_argument("--preview", action="store_true", help="960×540、快速编码")
    ap.add_argument("--stills", default="", help="逗号分隔的秒数，只出单帧 PNG")
    ap.add_argument("--from", dest="t_from", type=float, default=0.0)
    ap.add_argument("--to", dest="t_to", type=float, default=None)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    fps = cfg.get("fps", 30)
    tl, total = build_timeline(cfg)
    print(f"时长 {total:.2f}s，{len(tl)} 个镜头")
    for s, sh in tl:
        print(f"  {s:6.2f}  {sh['d']:5.2f}  {sh.get('id', sh['type'])}")

    if args.stills:
        d = OUT / "stills"
        d.mkdir(parents=True, exist_ok=True)
        for x in args.stills.split(","):
            t = float(x)
            im = frame_at(tl, t, int(t * fps))
            p = d / f"t{t:06.2f}.png"
            im.save(p)
            print("→", p)
        return

    t_to = min(args.t_to or total, total)
    n0, n1 = int(args.t_from * fps), int(t_to * fps)
    OUT.mkdir(parents=True, exist_ok=True)
    out = Path(args.out) if args.out else OUT / ("preview.mp4" if args.preview else "kurumi-fx-rogue-pv.mp4")
    wav = OUT / "_mix.wav"
    mix_audio(cfg, t_to, args.t_from, wav)
    vw, vh = (960, 540) if args.preview else (W, H)
    venc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "26"] if args.preview else \
           ["-c:v", "libx264", "-preset", "slow", "-crf", "16", "-tune", "animation"]
    cmd = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{vw}x{vh}", "-r", str(fps),
           "-i", "-", "-i", str(wav), *venc, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k",
           "-movflags", "+faststart", "-shortest", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(n0, n1):
        im = frame_at(tl, f / fps, f)
        if args.preview:
            im = im.resize((vw, vh), Image.BILINEAR)
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
