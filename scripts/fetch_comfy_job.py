"""把 ComfyUI 某个任务的输出图下载为 output/hires/<asset_id>.png，供 gen_assets.py --pix-only 像素化。

用于 anima-ic（官方人设参考图生图）：该模板在 comfyui-contract MCP 里提交（会正确绕过
ControlNet 组），结果以预览(temp)形式保存，gen_assets.py 自己的轮询拿不到，所以单独取回。

    python scripts/fetch_comfy_job.py <job_id> <asset_id> [node_id=24]
    python scripts/gen_assets.py --pix-only <asset_id>
"""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8188"
HIRES = Path(__file__).resolve().parent.parent / "output" / "hires"


def main():
    job, asset = sys.argv[1], sys.argv[2]
    node = sys.argv[3] if len(sys.argv) > 3 else "24"
    hist = json.load(urllib.request.urlopen(f"{BASE}/history/{job}", timeout=30))
    entry = hist.get(job)
    if not entry:
        sys.exit(f"任务未完成或不存在：{job}")
    outs = entry.get("outputs", {})
    imgs = outs.get(node, {}).get("images", [])
    if not imgs:
        sys.exit(f"节点 {node} 没有图片输出；可用节点：{list(outs)}")
    img = imgs[0]
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "temp")})
    data = urllib.request.urlopen(f"{BASE}/view?{q}", timeout=60).read()
    HIRES.mkdir(parents=True, exist_ok=True)
    out = HIRES / f"{asset}.png"
    out.write_bytes(data)
    print(f"{asset} <- {img['filename']} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
