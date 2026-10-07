#!/usr/bin/env python3
"""PV 用的像素版关键帧与分层素材（只依赖 Pillow；抠图走 ComfyUI，复用 gen_assets.py 的 AI 蒙版）。

PV 里所有画面都按游戏的像素规格来：背景/CG 320×180、48 色（与 gen_assets.py 的 bg/cg 同一算法：BOX 缩小 + 中位切分限色）。
关键帧额外拆成两层，供 PV 做视差、把标题压在角色后面：
  assets/pv/px/<id>.png      整图（320×180）
  assets/pv/px/<id>_fg.png   角色层（同尺寸，透明底，与整图同一调色板）
  assets/pv/px/<id>_bg.png   背景层（角色所在区域用周边颜色补齐，略微外扩，平移几像素不露洞）

用法（在 projects/kurumi-fx-rogue 下）：
  python scripts/pv/prep_pv_pixels.py            # 全部
  python scripts/pv/prep_pv_pixels.py pv_key     # 只做一张
  python scripts/pv/prep_pv_pixels.py --rematte  # 重新跑 AI 抠图
蒙版缓存在 output/masks/<id>.png（不入库）；有缓存时不连 ComfyUI。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import gen_assets as ga  # noqa: E402

OUT = ROOT / "assets/pv/px"
PIXEL = (320, 180)
COLORS = 48

# id → 高清原图；layers=True 的才拆角色层
SOURCES = {
    "pv_key": (ROOT / "assets/pv/pv_key.png", True),
    "pv_rain": (ROOT / "assets/pv/pv_rain.png", True),
    "pv_resolve": (ROOT / "assets/pv/pv_resolve.png", True),
    "cg_win": (ROOT / "output/hires/cg_win.png", False),   # 蒙版把楼群和钞票都当成前景，不拆层
    "cg_shock": (ROOT / "output/hires/cg_shock.png", False),
}


def fill_holes(rgb: Image.Image, hole: Image.Image) -> Image.Image:
    """push-pull 补洞：hole=255 的像素用周围颜色由粗到细填上。"""
    rgba = rgb.convert("RGBA")
    rgba.putalpha(hole.point(lambda v: 0 if v >= 128 else 255))
    levels = [rgba.convert("RGBa")]
    while min(levels[-1].size) > 2:
        w, h = levels[-1].size
        levels.append(levels[-1].resize((max(1, w // 2), max(1, h // 2)), Image.BOX))
    filled = levels[-1].convert("RGBA").convert("RGB")
    for lv in reversed(levels[:-1]):
        up = filled.resize(lv.size, Image.BILINEAR)
        un = lv.convert("RGBA")
        known = un.getchannel("A").point(lambda v: 255 if v > 0 else 0)
        filled = Image.composite(un.convert("RGB"), up, known)
    return filled


def build(id_: str, src: Path, layers: bool, rematte: bool):
    hi = Image.open(src).convert("RGB")
    full = hi.resize(PIXEL, Image.BOX)
    q = full.quantize(COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    OUT.mkdir(parents=True, exist_ok=True)
    q.convert("RGBA").save(OUT / f"{id_}.png")
    print(f"→ {id_}.png")
    if not layers:
        return
    m = ga.load_manifest()
    comfy = ga.Comfy(m["comfy"]["base_url"], m["comfy"]["client_id"])
    mask = ga.get_matte(m, comfy, {"id": id_}, src, force=rematte)
    a = mask.resize(PIXEL, Image.BOX).point(lambda v: 255 if v >= 128 else 0)
    a = ga.drop_islands(a, 40 / (PIXEL[0] * PIXEL[1]))   # 飘在外面的金币/星星碎点
    fg = q.convert("RGBA")
    fg.putalpha(a)
    fg.save(OUT / f"{id_}_fg.png")
    # 背景层：角色区域外扩 2px 后补洞，再映射回同一调色板
    hole = a.filter(ImageFilter.MaxFilter(5))
    bg = fill_holes(full, hole).quantize(palette=q, dither=Image.Dither.NONE)
    bg.convert("RGBA").save(OUT / f"{id_}_bg.png")
    print(f"→ {id_}_fg.png / {id_}_bg.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--rematte", action="store_true")
    args = ap.parse_args()
    for id_ in args.ids or SOURCES:
        src, layers = SOURCES[id_]
        if not src.exists():
            raise SystemExit(f"缺原图 {src}（output/hires 的要先跑 python scripts/gen_assets.py）")
        build(id_, src, layers, args.rematte)


if __name__ == "__main__":
    main()
