"""开源 BGM 导入：config/bgm-oss.json → 下载原曲 → 统一响度 → assets/bgm/<source>.ogg + assets/bgm/tracks.json

用法（在 projects/kurumi-fx-rogue 下）：python scripts/import_oss_bgm.py
- 原曲下载到 output/bgm/oss/src/（不入库；zip 整包下载后取 member）。已有就不重下。
- 只做整体增益（目标 post.lufs，且真峰值不超过 post.true_peak），不淡入淡出、不裁剪——保留原曲的无缝循环。
- tracks.json：cues{曲目 id → 文件名}（src/ui/bgm.gd 按它找文件）+ sources{文件名 → 标题/作者/许可证/出处}。
需要 ffmpeg/ffprobe 在 PATH。
"""
from __future__ import annotations

import json
import subprocess
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "config" / "bgm-oss.json"
SRC = ROOT / "output" / "bgm" / "oss" / "src"
ASSETS = ROOT / "assets" / "bgm"


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)


def fetch(url: str) -> Path:
    SRC.mkdir(parents=True, exist_ok=True)
    dst = SRC / urllib.request.url2pathname(url.rsplit("/", 1)[-1]).replace("\\", "_")
    if not dst.is_file():
        print("下载", url)
        with urllib.request.urlopen(url, timeout=300) as r:
            dst.write_bytes(r.read())
    return dst


def source_file(s: dict) -> Path:
    f = fetch(s["url"])
    if "member" not in s:
        return f
    out = SRC / s["member"]
    if not out.is_file():
        with zipfile.ZipFile(f) as z:
            out.write_bytes(z.read(s["member"]))
    return out


def measure(path: Path) -> dict:
    err = run(["ffmpeg", "-v", "info", "-i", str(path), "-af", "loudnorm=print_format=json", "-f", "null", "-"]).stderr
    return json.loads(err[err.rindex("{"):err.rindex("}") + 1])


def duration(path: Path) -> float:
    return float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)]).stdout.strip())


def main() -> None:
    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    post = cfg["post"]
    ASSETS.mkdir(parents=True, exist_ok=True)
    used = sorted(set(cfg["cues"].values()))
    sources = {}
    for sid in used:
        s = cfg["sources"][sid]
        src = source_file(s)
        m = measure(src)
        gain = min(float(post["lufs"]) - float(m["input_i"]), float(post["true_peak"]) - float(m["input_tp"]))
        dst = ASSETS / f"{sid}.ogg"
        run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-map_metadata", "-1", "-af", f"volume={gain:.2f}dB",
             "-ar", str(post["sample_rate"]), "-ac", "2", "-c:a", "libvorbis", "-q:a", str(post["ogg_quality"]), str(dst)])
        sources[sid] = {k: s[k] for k in ("title", "author", "license", "page")}
        sources[sid].update({"seconds": round(duration(dst), 2), "input_lufs": float(m["input_i"]), "gain_db": round(gain, 2)})
        print(f"{sid:24s} {sources[sid]['seconds']:6.1f}s  {m['input_i']:>6} LUFS  {gain:+.1f} dB  {dst.stat().st_size // 1024} KiB")
    index = {"_doc": "由 scripts/import_oss_bgm.py 生成（来源 config/bgm-oss.json）。cues：曲目 id → assets/bgm/ 下的文件名（不含 .ogg）；sources：每个文件的出处与许可证。",
             "cues": cfg["cues"], "sources": sources}
    (ASSETS / "tracks.json").write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    for f in ASSETS.glob("*.ogg"):
        if f.stem not in sources:
            print("注意：未被 tracks.json 引用的文件", f.name)


if __name__ == "__main__":
    main()
