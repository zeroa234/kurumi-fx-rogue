#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
kurumi-fx-rogue 美术素材生成管线（只依赖标准库 + Pillow）

- 读清单 config/asset-manifest.json，经 ComfyUI HTTP API（/prompt /history /view /upload/image）
  生成高清原图 → output/hires/（不入库）
- 本地 Pillow 像素化 → assets/sprites/{portraits,portraits_small,bg,icons,cg,chibi}/<id>.png
- 维护 assets/sprites/index.json（id → 文件/seed/prompt/尺寸/生成时间）

用法：
  python gen_assets.py                 # 生成全部缺失项
  python gen_assets.py kurumi_normal   # 只生成指定 id（可多个）
  python gen_assets.py kurumi_happy --reroll   # 换新随机种子并写回清单
  python gen_assets.py kurumi_happy --force    # 用清单里的原 seed 重画
  python gen_assets.py --pix-only kurumi_normal # 跳过生成，用已有 hires 重做像素化
  python gen_assets.py --contact       # 只重做总览拼图
  python gen_assets.py --status        # 列出缺失/已有
"""
import argparse
import io
import json
import random
import sys
import time
import urllib.parse
import urllib.request
import uuid
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------- 路径 ----------
SELF = Path(__file__).resolve()
PROJECT = SELF.parent.parent                # projects/kurumi-fx-rogue
REPO = PROJECT.parent.parent                # D:/agent
TEMPLATES = REPO / "data/comfyui/templates"
MANIFEST = PROJECT / "config/asset-manifest.json"
HIRES = PROJECT / "output/hires"
SPRITES = PROJECT / "assets/sprites"
INDEX = SPRITES / "index.json"
SHEET = PROJECT / "output/contact_sheet.png"
REF_DIR = REPO / "temp/kurumi-ref/official"

CFG = {}  # manifest 运行时缓存/回写


def load_manifest():
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def save_manifest(m):
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)


def load_index():
    if INDEX.exists():
        with open(INDEX, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_index(idx):
    SPRITES.mkdir(parents=True, exist_ok=True)
    with open(INDEX, "w", encoding="utf-8") as f:
        json.dump(idx, f, ensure_ascii=False, indent=2)


# ---------- HTTP ----------
class Comfy:
    def __init__(self, base, client_id):
        self.base = base.rstrip("/")
        self.client_id = client_id

    def _req(self, method, path, body=None, timeout=30):
        url = self.base + path
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()

    def ping(self):
        try:
            self._req("GET", "/system_stats", timeout=5)
            return True
        except Exception:
            return False

    def upload_image(self, path, name):
        boundary = uuid.uuid4().hex
        payload = bytearray()
        for key, val in [("image", (name, open(path, "rb").read())), ("overwrite", (None, b"true"))]:
            payload += f"--{boundary}\r\n".encode()
            if val[0] is None:
                payload += f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode()
                payload += val[1] + b"\r\n"
            else:
                payload += (
                    f'Content-Disposition: form-data; name="{key}"; filename="{val[0]}"\r\n'
                    "Content-Type: application/octet-stream\r\n\r\n"
                ).encode()
                payload += val[1] + b"\r\n"
        payload += f"--{boundary}--\r\n".encode()
        req = urllib.request.Request(
            self.base + "/upload/image",
            data=bytes(payload),
            method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            rsp = json.loads(r.read())
        return rsp["name"]

    def submit(self, graph):
        body = {"prompt": graph, "client_id": self.client_id}
        raw = self._req("POST", "/prompt", body, timeout=60)
        rsp = json.loads(raw)
        if "prompt_id" not in rsp:
            raise RuntimeError("submit 失败: " + json.dumps(rsp, ensure_ascii=False)[:800])
        return rsp["prompt_id"]

    def poll(self, prompt_id, timeout_s=900, quiet=True):
        t0 = time.time()
        while time.time() - t0 < timeout_s:
            time.sleep(2)
            try:
                raw = self._req("GET", f"/history/{prompt_id}", timeout=15)
            except Exception:
                continue
            hist = json.loads(raw)
            entry = hist.get(prompt_id)
            if not entry:
                continue
            st = entry.get("status", {})
            if st.get("status_str") == "error":
                msgs = json.dumps(st.get("messages", []), ensure_ascii=False)[:800]
                raise RuntimeError("ComfyUI 执行出错: " + msgs)
            outs = entry.get("outputs", {})
            images = []
            for node_out in outs.values():
                for img in node_out.get("images", []):
                    if img.get("type") == "output":
                        images.append(img)
            if images:
                return images
            if not quiet:
                elapsed = int(time.time() - t0)
                print(f"    ...等待中 {elapsed}s", flush=True)
        raise TimeoutError(f"等待超时 {timeout_s}s: {prompt_id}")

    def download(self, img):
        q = urllib.parse.urlencode(
            {"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")}
        )
        return self._req("GET", f"/view?{q}", timeout=120)


# ---------- 工作流组装 ----------
def _tpl(name):
    with open(TEMPLATES / name, encoding="utf-8") as f:
        return json.load(f)


def prompt_negative(m, a, kind):
    s = m["style"]
    parts = [s.get("quality", ""), a.get("tags", ""), kind.get("kind_tags", ""), a.get("nl", ""), kind.get("nl_auto", "")]
    if kind.get("pixel_tag_on") and s.get("pixel_tag"):
        parts.insert(1, s["pixel_tag"])
    prompt = ", ".join(p.strip().strip(",") for p in parts if p and p.strip())
    neg_parts = [s.get("negative", ""), kind.get("negativeExtra", "")]
    negative = ", ".join(p.strip().strip(",") for p in neg_parts if p and p.strip())
    return prompt, negative


def graph_t2i(m, a, kind, seed, comfy=None):
    g = _tpl(kind["template"] + ".json")
    prompt, negative = prompt_negative(m, a, kind)
    g["19"]["inputs"]["text"] = prompt
    g["47"]["inputs"]["text"] = negative
    g["32"]["inputs"]["width"] = kind["gen"][0]
    g["32"]["inputs"]["height"] = kind["gen"][1]
    g["10"]["inputs"]["seed"] = seed
    if "steps" in kind:
        g["10"]["inputs"]["steps"] = kind["steps"]
    if "cfg" in kind:
        g["10"]["inputs"]["cfg"] = kind["cfg"]
    # 填 LoRA 坑（重接链，未用的坑直接从图中删除，避免空名验证失败）
    lora = kind.get("lora") or {}
    if m["kinds"].get("_lora_pits"):
        chain = m["kinds"]["_lora_pits"]["chain"]
    else:
        chain = ["48", "49", "50", "51", "52"] if kind["template"] == "anima-t2i" else ["48", "29"]
    if lora and lora.get("pit") not in chain:
        raise ValueError(f"LoRA pit {lora.get('pit')} 不在模板链 {chain} 中")
    for pit in chain:
        if pit in g and lora.get("pit") == pit:
            g[pit]["inputs"]["lora_name"] = lora["name"]
            g[pit]["inputs"]["strength_model"] = lora.get("strength", 1.0)
    used = [p for p in chain if p in g and g[p]["inputs"].get("lora_name")]
    for p in chain:  # 未用的坑：断開并删除
        if p in g and p not in used:
            del g[p]
    if used:
        for i, p in enumerate(used):
            base = ["11", 0] if i == 0 else [used[i - 1], 0]
            g[p]["inputs"]["model"] = base
            if "clip" in g[p]["inputs"]:
                g[p]["inputs"]["clip"] = ["5", 0] if i == 0 else [used[i - 1], 1]
        last_clip = next((p for p in reversed(used) if "clip" in g[p]["inputs"]), None)
        g["10"]["inputs"]["model"] = [used[-1], 0]
        clip_out = [last_clip, 1] if last_clip else ["5", 0]
    else:
        g["10"]["inputs"]["model"] = ["11", 0]
        clip_out = ["5", 0]
    for cu in ("19", "47"):
        g[cu]["inputs"]["clip"] = clip_out
    g["3"]["inputs"]["filename_prefix"] = f"kurumi-fx-rogue/hi_{a['id']}"
    return g, prompt, negative


def graph_turbo(m, a, kind, seed):
    # anima-turbo-t2i 与 anima-t2i 的节点号一致（19/47/32/10/3）
    return graph_t2i(m, a, kind, seed)


def graph_ic(m, a, kind, seed, comfy):
    g = _tpl("anima-ic.json")
    ref_path = REF_DIR / f"main_{a['ref']}.png"
    if not ref_path.exists():
        raise FileNotFoundError(f"参考图缺失: {ref_path}（先从官网下载官方立绘）")
    up_name = comfy.upload_image(ref_path, f"kurumi_ref_{a['ref']}.png")
    prompt = a.get("nl", "")
    negative = m["style"].get("negative", "") + ", worst quality, low quality"
    g["21"]["inputs"]["value"] = prompt
    g["9"]["inputs"]["text"] = negative
    g["10"]["inputs"]["image"] = up_name
    g["29"]["inputs"]["seed"] = seed
    if "steps" in kind:
        g["13"]["inputs"]["steps"] = kind["steps"]
    if "cfg" in kind:
        g["13"]["inputs"]["cfg"] = kind["cfg"]
    g["41"]["inputs"]["filename_prefix"] = f"kurumi-fx-rogue/hi_{a['id']}"
    return g, prompt, negative


# ---------- Pillow 像素化 ----------
def remove_bg_white(im, tol=42):
    """从图像边缘泛洪去掉近白背景，返回 (rgb Image, alpha bytearray)。"""
    im = im.convert("RGB")
    w, h = im.size
    data = im.tobytes()
    hi = 255 - tol
    alpha = bytearray(b"\xff") * (w * h)
    visited = bytearray(w * h)
    stack = deque()

    def is_bg(i):
        p = i * 3
        return data[p] >= hi and data[p + 1] >= hi and data[p + 2] >= hi

    for x in range(w):
        for y in (0, h - 1):
            i = y * w + x
            if not visited[i] and is_bg(i):
                visited[i] = 1
                stack.append(i)
    for y in range(h):
        for x in (0, w - 1):
            i = y * w + x
            if not visited[i] and is_bg(i):
                visited[i] = 1
                stack.append(i)
    while stack:
        i = stack.popleft()
        alpha[i] = 0
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not visited[j] and is_bg(j):
                    visited[j] = 1
                    stack.append(j)
    return im, alpha


def to_rgba_with_alpha(im, alpha):
    rgba = im.convert("RGBA")
    rgba.putalpha(bytes(bytearray(alpha)))
    return rgba


def bbox_of(rgba):
    return rgba.getchannel("A").getbbox()


def chest_up_crop(rgba, pad_frac=0.03):
    """胸口以上方形裁切：全身材则取头顶下方一段；胸像则整框。"""
    bbox = bbox_of(rgba)
    if not bbox:
        raise ValueError("空白图（背景去除后无内容）")
    x0, y0, x1, y1 = bbox
    cw, ch = x1 - x0, y1 - y0
    if ch > 1.6 * cw:
        # 全身/大半身：找头顶，取头部水平中心的胸像方框
        w = rgba.width
        apx = rgba.getchannel("A").load()
        head_rows_y1 = y0 + max(8, int(ch * 0.12))
        cols = []
        for y in range(y0, min(head_rows_y1, y1)):
            for x in range(x0, x1):
                if apx[x, y][3]:
                    cols.append(x)
        cx = (min(cols) + max(cols)) // 2 if cols else (x0 + x1) // 2
        side = int(min(cw * 1.05, ch * 0.46))
        side = max(side, int(cw * 0.8))
        y0c = max(0, int(y0 - side * pad_frac))
        x0c = max(0, min(cx - side // 2, w - side))
        return rgba.crop((x0c, y0c, min(x0c + side, w), min(y0c + side, rgba.height)))
    side = int(max(cw, ch) * (1 + 2 * pad_frac))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    x0c = max(0, min(cx - side // 2, rgba.width - side))
    y0c = max(0, min(cy - side // 2, rgba.height - side))
    return rgba.crop((x0c, y0c, x0c + side, y0c + side))


def fit_canvas(rgba, size, inner_frac):
    inner = int(size * inner_frac)
    scale = inner / max(rgba.width, rgba.height)
    nw, nh = max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale))
    small = rgba.resize((nw, nh), Image.BOX)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(small, ((size - nw) // 2, (size - nh) // 2))
    return canvas


def quantize_colors(rgba, colors):
    """限色 + alpha 二值化。"""
    rgb = rgba.convert("RGB")
    a = rgba.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    q = rgb.quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = q.convert("RGBA")
    out.putalpha(a)
    return out


def add_outline(rgba, color=(24, 20, 28, 255)):
    w, h = rgba.size
    px = rgba.load()
    a = rgba.getchannel("A").load()
    edge = []
    for y in range(h):
        for x in range(w):
            if not a[x, y]:
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h and not a[nx, ny]:
                    edge.append((x, y))
                    break
    for x, y in edge:
        r, g, b, _ = px[x, y]
        px[x, y] = color
    return rgba, bool(edge)


def pixelize_portraitlike(hires_path, kind):
    im = Image.open(hires_path)
    im, alpha = remove_bg_white(im, tol=kind.get("tol", 42))
    rgba = to_rgba_with_alpha(im, alpha)
    crop = kind.get("crop")
    if crop == "chest_up":
        rgba = chest_up_crop(rgba)
    else:
        b = bbox_of(rgba)
        rgba = rgba.crop(b)
    return rgba


def pixelize(kind, hires_path):
    """返回 [(out_rel_path, Image)]。"""
    results = []
    pixel = kind["pixel"]
    if "bg_remove" in kind:
        rgba = pixelize_portraitlike(hires_path, kind)
        img = fit_canvas(rgba, pixel[0], kind.get("inner_frac", 0.9))
        img = quantize_colors(img, kind["colors"])
        if kind.get("outline"):
            img, _ = add_outline(img)
        results.append((img,))
        small = kind.get("small")
        if small:
            s = fit_canvas(rgba, small["pixel"][0], kind.get("inner_frac", 0.9))
            s = quantize_colors(s, small["colors"])
            if kind.get("outline"):
                s, _ = add_outline(s)
            results.append((s, "small"))
    else:
        im = Image.open(hires_path).convert("RGB")
        img = im.resize(tuple(pixel), Image.BOX)
        img = img.quantize(kind["colors"], method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
        results.append((img,))
    return results


def sprite_rel(a, kind, variant=None):
    sub = {"portrait": "portraits", "portrait_ref": "portraits", "portrait_sil": "portraits",
           "bg": "bg", "icon": "icons", "chibi": "chibi", "cg": "cg"}[a["kind"]]
    if variant == "small":
        sub += "_small"
    return f"{sub}/{a['id']}.png"


# ---------- 主流程 ----------
def generate_one(m, comfy, a, seed):
    kind = m["kinds"][a["kind"]]
    tpl = kind["template"]
    if tpl == "anima-ic":
        g, prompt, negative = graph_ic(m, a, kind, seed, comfy)
    elif tpl == "anima-turbo-t2i":
        g, prompt, negative = graph_turbo(m, a, kind, seed)
    else:
        g, prompt, negative = graph_t2i(m, a, kind, seed)
    prompt_id = comfy.submit(g)
    imgs = comfy.poll(prompt_id, timeout_s=kind.get("timeout", 900))
    big = imgs[0]
    raw = comfy.download(big)
    HIRES.mkdir(parents=True, exist_ok=True)
    hires_path = HIRES / f"{a['id']}.png"
    hires_path.write_bytes(raw)
    return hires_path, prompt, negative, tpl


def render_one(a, kind, hires_path):
    out = []
    for img in pixelize(kind, hires_path):
        if len(img) == 1:
            im = img[0]
            rel = sprite_rel(a, kind)
        else:
            im, variant = img
            rel = sprite_rel(a, kind, variant)
        p = SPRITES / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        im.save(p)
        out.append((rel, im.size))
    return out


def is_missing(a, kind, idx):
    rels = [sprite_rel(a, kind)]
    if kind.get("small"):
        rels.append(sprite_rel(a, kind, "small"))
    if a["id"] not in idx:
        return True
    if not (HIRES / f"{a['id']}.png").exists():
        return True
    return any(not (SPRITES / r).exists() for r in rels)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*", help="资产 id（缺省=全部缺失项）")
    ap.add_argument("--reroll", action="store_true", help="换新随机种子（写回清单）")
    ap.add_argument("--force", action="store_true", help="忽略已有结果，用清单 seed 重画")
    ap.add_argument("--pix-only", action="store_true", help="跳过生成，用已有 hires 重做像素化")
    ap.add_argument("--contact", action="store_true", help="只重做总览拼图")
    ap.add_argument("--status", action="store_true", help="只列出状态")
    args = ap.parse_args()

    m = load_manifest()
    idx = load_index()
    assets = {a["id"]: a for a in m["assets"]}

    if args.contact:
        make_contact_sheet()
        return
    if args.status:
        missing = [a["id"] for a in m["assets"] if is_missing(a, m["kinds"][a["kind"]], idx)]
        print(f"共 {len(m['assets'])} 项，缺失 {len(missing)} 项")
        if missing:
            print("  " + ", ".join(missing))
        return

    if args.ids:
        unknown = [x for x in args.ids if x not in assets]
        if unknown:
            sys.exit("未知 id: " + ", ".join(unknown))
        todo = [assets[x] for x in args.ids]
    else:
        todo = [a for a in m["assets"] if is_missing(a, m["kinds"][a["kind"]], idx)]

    if not todo:
        print("没有需要生成的资产。")
        make_contact_sheet()
        return

    comfy = Comfy(m["comfy"]["base_url"], m["comfy"]["client_id"])
    if not args.pix_only and not comfy.ping():
        sys.exit(f"ComfyUI 不可达: {comfy.base}（先启动 ComfyUI）")

    ok, failed = [], []
    for a in todo:
        kind = m["kinds"][a["kind"]]
        t0 = time.time()
        try:
            if args.reroll:
                a["seed"] = random.randint(0, 2**40)
            seed = a["seed"]
            if args.pix_only:
                hires_path = HIRES / f"{a['id']}.png"
                if not hires_path.exists():
                    raise FileNotFoundError(hires_path)
                prompt = idx.get(a["id"], {}).get("prompt", "")
                negative = idx.get(a["id"], {}).get("negative", "")
                tpl = kind["template"]
            else:
                hires_path, prompt, negative, tpl = generate_one(m, comfy, a, seed)
            outs = render_one(a, kind, hires_path)
            entry = idx.get(a["id"], {})
            idx[a["id"]] = {
                "file": outs[0][0],
                "files": {r: list(sz) for r, sz in outs},
                "seed": seed,
                "template": tpl,
                "prompt": prompt,
                "negative": negative,
                "pixel_size": kind["pixel"],
                "colors": kind["colors"],
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "rev": entry.get("rev", 0) + 1,
            }
            save_index(idx)
            if args.reroll:
                save_manifest(m)
            print(f"  ok {a['id']}  seed={seed}  {time.time()-t0:.0f}s", flush=True)
            ok.append(a["id"])
        except Exception as e:
            print(f"  FAIL {a['id']}: {e}", flush=True)
            failed.append((a["id"], str(e)))

    print(f"\n完成 {len(ok)}，失败 {len(failed)}")
    for fid, err in failed:
        print(f"  FAIL {fid}: {err[:200]}")
    make_contact_sheet()


def make_contact_sheet():
    idx = load_index()
    if not idx:
        print("index 为空，无法拼图")
        return
    m = load_manifest()
    kind_of = {a["id"]: a["kind"] for a in m["assets"]}
    order = ["portrait", "portrait_sil", "portrait_ref", "chibi", "icon", "bg", "cg"]
    groups = {}
    for aid in sorted(idx):
        groups.setdefault(kind_of.get(aid, "?"), []).append(aid)

    # 每类统一放大倍数：该类最大的边长放大到 ≤256 的最大整数倍
    def scale_for(items, target=256):
        sizes = [tuple(idx[i]["pixel_size"]) for i in items]
        mx = max(max(w, h) for w, h in sizes)
        return max(1, target // mx)

    try:
        label_font = ImageFont.truetype("C:/Windows/Fonts/uigothic.ttf", 14)
    except Exception:
        label_font = ImageFont.load_default(size=14)

    CELL_W, CELL_H, PAD = 264, 306, 8
    cols = 5
    sheet_w = cols * (CELL_W + PAD) + PAD

    rows = []
    for k in order:
        ids = groups.get(k)
        if not ids:
            continue
        sc = scale_for(ids)
        rows.append(("title", f"{k}  (x{sc})", sc))
        for aid in ids:
            rows.append(("cell", aid, sc))

    sheet = Image.new("RGB", (sheet_w, 40), (34, 34, 40))
    x, y = PAD, 40
    d = ImageDraw.Draw(sheet)
    for r_type, r_val, sc in rows:
        if r_type == "title":
            x = PAD
            y += CELL_H + PAD + 14
            if y + CELL_H > sheet.height:
                grown = Image.new("RGB", (sheet_w, y + CELL_H + PAD), (34, 34, 40))
                grown.paste(sheet, (0, 0))
                d = ImageDraw.Draw(grown)
                sheet = grown
            d.text((x + 2, y - 22), r_val, font=label_font, fill=(240, 220, 160))
            continue
        aid = r_val
        path = SPRITES / idx[aid]["file"]
        if not path.exists():
            continue
        if y + CELL_H > sheet.height:
            grown = Image.new("RGB", (sheet_w, y + CELL_H + PAD), (34, 34, 40))
            grown.paste(sheet, (0, 0))
            d = ImageDraw.Draw(grown)
            sheet = grown
        im = Image.open(path).convert("RGBA")
        if sc > 1:
            im = im.resize((im.width * sc, im.height * sc), Image.NEAREST)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (44, 44, 52, 255))
        if im.width > CELL_W - 4 or im.height > CELL_H - 30:
            f2 = min((CELL_W - 4) / im.width, (CELL_H - 30) / im.height)
            im = im.resize((int(im.width * f2), int(im.height * f2)), Image.NEAREST)
        cell.paste(im, ((CELL_W - im.width) // 2, (CELL_H - 30 - im.height) // 2), im)
        ImageDraw.Draw(cell).text((4, CELL_H - 26),
                                  f"{aid} {idx[aid]['pixel_size'][0]}x{idx[aid]['pixel_size'][1]}",
                                  font=label_font, fill=(230, 230, 230))
        sheet.paste(cell.convert("RGB"), (x, y))
        x += CELL_W + PAD
        if x + CELL_W + PAD > sheet_w:
            x = PAD
            y += CELL_H + PAD
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET)
    print(f"contact sheet → {SHEET} ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()