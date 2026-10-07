"""README 视频封面：底图压暗 + 像素风播放按钮 + 标签条（640×360 画布，×2 最近邻放大）。

用法：python scripts/make_video_cover.py docs/images/pv-kurumi.png assets/fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2 docs/images/pv-cover.png
"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
src, font_path, out = sys.argv[1:4]
W, H = 640, 360
im = Image.open(src).convert("RGB").resize((W, H), Image.NEAREST)
im = ImageEnhance.Brightness(im).enhance(0.62)          # 压暗，突出按钮
d = ImageDraw.Draw(im)
# 像素风圆形按钮：逐像素画圆（无抗锯齿），白描边 + 粉色底 + 白三角
cx, cy, r = W // 2, H // 2 - 8, 44
for y in range(cy - r - 3, cy + r + 4):
    for x in range(cx - r - 3, cx + r + 4):
        dd = (x - cx) ** 2 + (y - cy) ** 2
        if dd <= r * r:
            im.putpixel((x, y), (255, 111, 165))
        elif dd <= (r + 3) ** 2:
            im.putpixel((x, y), (255, 255, 255))
# 三角（略右移视觉居中）
tx = cx - 14
d.polygon([(tx, cy - 22), (tx, cy + 22), (tx + 38, cy)], fill=(255, 255, 255))
# 底部标签条
font = ImageFont.truetype(font_path, 24)
label = "▶ 在 bilibili 观看"
bb = d.textbbox((0, 0), label, font=font)
tw, th = bb[2] - bb[0], bb[3] - bb[1]
bx0, by0 = (W - tw) // 2 - 14, cy + r + 18
d.rectangle([bx0, by0, bx0 + tw + 28, by0 + th + 16], fill=(22, 14, 36), outline=(90, 209, 232), width=2)
d.text((bx0 + 14 - bb[0], by0 + 8 - bb[1]), label, font=font, fill=(255, 255, 255))
im.resize((W * 2, H * 2), Image.NEAREST).save(out, optimize=True)
print(out, im.size)
