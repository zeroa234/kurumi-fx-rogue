"""把 Blender 渲染的序列帧（透明底 PNG）像素化并拼成横向精灵表。

    python scripts/pixelize_frames.py output/blender/coin_*.png assets/sprites/anim/coin.png --size 24 --colors 16

Blender 源文件：output/blender/coin.blend（8 帧绕竖轴旋转的 ¥ 金币，Eevee、正交相机、透明背景）。
"""
import argparse
import glob

from PIL import Image, ImageEnhance


SAT = 2.2
CONTRAST = 1.35


def pixelize(path, size, colors):
    im = Image.open(path).convert("RGBA")
    bbox = im.getchannel("A").getbbox() or (0, 0, im.width, im.height)
    # 以所有帧共享的画布居中缩放：保持原图比例，不按单帧 bbox 裁切（否则旋转时会忽大忽小）
    small = im.resize((size, size), Image.BOX)
    alpha = small.getchannel("A").point(lambda a: 255 if a >= 110 else 0)
    rgb = small.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(SAT)
    rgb = ImageEnhance.Contrast(rgb).enhance(CONTRAST)
    rgb = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    # 1px 深色外描边
    px = out.load()
    a = alpha.load()
    w, h = out.size
    edge = []
    for y in range(h):
        for x in range(w):
            if a[x, y] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and a[x + dx, y + dy] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for x, y in edge:
        px[x, y] = (60, 30, 10, 255)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pattern")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=24)
    ap.add_argument("--colors", type=int, default=16)
    a = ap.parse_args()
    frames = sorted(glob.glob(a.pattern))
    sheet = Image.new("RGBA", (a.size * len(frames), a.size), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(pixelize(f, a.size, a.colors), (i * a.size, 0))
    sheet.save(a.out)
    print(f"{len(frames)} 帧 → {a.out} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
