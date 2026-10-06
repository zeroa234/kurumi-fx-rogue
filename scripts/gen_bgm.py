"""BGM 生成管线：config/bgm-cues.json → YuE2-T8 本地服务 → output/bgm/raw/*.flac → assets/bgm/*.ogg

用法（在 projects/kurumi-fx-rogue 下）：
  python scripts/gen_bgm.py status                 # 每首的作业 / 原始音频 / 成品状态
  python scripts/gen_bgm.py submit [id ...]        # 提交生成（不写 id = 所有还没有成品的）；--seed 换种子（只能配单个 id）
  python scripts/gen_bgm.py fetch [id ...]         # 取回已完成作业的 audio.flac；--wait 阻塞等待
  python scripts/gen_bgm.py post [id ...]          # 后期：裁首尾静音 → 截到 max_seconds → 两遍 loudnorm → 淡入淡出 → OGG
  python scripts/gen_bgm.py qa [id ...]            # 用 YuE2 运行时（demucs + librosa）检查人声残留/节拍/静音 → output/bgm/qa.json

服务地址：环境变量 YUE2_API，否则 http://127.0.0.1:8189。需要 ffmpeg/ffprobe 在 PATH。
作业记录 output/bgm/jobs.json（不入库）；成品记录 assets/bgm/index.json（入库，含作业 id、种子、style、时长、响度、QA）。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CUES = ROOT / "config" / "bgm-cues.json"
OUT = ROOT / "output" / "bgm"
RAW = OUT / "raw"
JOBS = OUT / "jobs.json"
QA = OUT / "qa.json"
ASSETS = ROOT / "assets" / "bgm"
INDEX = ASSETS / "index.json"
API = os.environ.get("YUE2_API", "http://127.0.0.1:8189").rstrip("/")


def load_json(path: Path, default):
    if path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")


def api(method: str, path: str, body: dict | None = None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def cue_table() -> tuple[dict, dict, dict]:
    cfg = load_json(CUES, {})
    return cfg["defaults"], cfg["post"], {c["id"]: c for c in cfg["cues"]}


def pick(ids: list[str], cues: dict, missing_only=False) -> list[str]:
    for i in ids:
        if i not in cues:
            sys.exit(f"未知 cue: {i}")
    if ids:
        return ids
    if missing_only:
        return [i for i in cues if not (ASSETS / f"{i}.ogg").is_file()]
    return list(cues)


# ---------------------------------------------------------------- submit / fetch

def cmd_submit(args) -> None:
    defaults, _, cues = cue_table()
    ids = pick(args.ids, cues, missing_only=True)
    if args.seed is not None and len(ids) != 1:
        sys.exit("--seed 只能配单个 id")
    jobs = load_json(JOBS, {})
    for cid in ids:
        c = cues[cid]
        seed = args.seed if args.seed is not None else int(c["seed"])
        req = dict(defaults)
        req.update({"style": c["style"], "lyrics": "[instrumental]", "seed": seed})
        req.update(c.get("request", {}))
        res = api("POST", "/api/jobs", {"kind": "generate", "request": req, "source": "api",
                                        "client_request_id": uuid.uuid4().hex, "result_panel": "create"})
        job = res.get("job", res)
        jobs.setdefault(cid, []).append({"job_id": job["id"], "seed": seed, "style": c["style"],
                                         "submitted": time.strftime("%Y-%m-%d %H:%M:%S")})
        print(f"{cid}: {job['id']} seed={seed}")
    save_json(JOBS, jobs)


def latest_job(jobs: dict, cid: str) -> dict | None:
    hist = jobs.get(cid, [])
    return hist[-1] if hist else None


def cmd_fetch(args) -> None:
    _, _, cues = cue_table()
    jobs = load_json(JOBS, {})
    ids = [i for i in pick(args.ids, cues) if latest_job(jobs, i)]
    pending = set(ids)
    while pending:
        for cid in sorted(pending):
            rec = latest_job(jobs, cid)
            st = api("GET", f"/api/jobs/{rec['job_id']}")
            st = st.get("job", st)
            status = st.get("status")
            if status in ("failed", "cancelled"):
                print(f"{cid}: {status} {st.get('error', '')}")
                rec["status"] = status
                pending.discard(cid)
                continue
            if status != "complete":
                continue
            res = st.get("result") or {}
            cand = (res.get("candidates") or [{}])[0]
            rel = cand.get("audio") or res.get("audio") or "artifacts/song/audio.flac"
            rel = rel.replace("\\", "/")
            if ":" in rel or rel.startswith("/"):
                rel = rel.split(rec["job_id"] + "/", 1)[-1]
            RAW.mkdir(parents=True, exist_ok=True)
            dst = RAW / f"{cid}.flac"
            with urllib.request.urlopen(f"{API}/api/files/{rec['job_id']}/{rel}", timeout=300) as r, dst.open("wb") as f:
                shutil.copyfileobj(r, f)
            rec.update({"status": "complete", "audio_seconds": cand.get("audio_seconds"),
                        "truncated": res.get("truncated"), "identity": cand.get("identity"), "raw": dst.name})
            print(f"{cid}: {cand.get('audio_seconds', 0):.1f}s truncated={res.get('truncated')} → {dst.relative_to(ROOT)}")
            pending.discard(cid)
        save_json(JOBS, jobs)
        if not args.wait or not pending:
            break
        time.sleep(20)
    if pending:
        print("未完成：", " ".join(sorted(pending)))


# ---------------------------------------------------------------- post

def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)


def duration(path: Path) -> float:
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)]).stdout
    return float(out.strip())


def cmd_post(args) -> None:
    _, post, cues = cue_table()
    jobs = load_json(JOBS, {})
    index = load_json(INDEX, {"_doc": "由 scripts/gen_bgm.py post 生成：每首 BGM 的来源作业与后期参数。", "tracks": {}})
    ASSETS.mkdir(parents=True, exist_ok=True)
    tmp = OUT / "tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    for cid in pick(args.ids, cues):
        src = RAW / f"{cid}.flac"
        if not src.is_file():
            print(f"{cid}: 没有原始音频，跳过")
            continue
        sr = str(post["sample_rate"])
        # 1) 裁首尾静音（-50 dB），截到 max_seconds
        trimmed = tmp / f"{cid}.wav"
        trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,"
                "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse")
        run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-af", trim, "-t", str(post["max_seconds"]),
             "-ar", sr, "-c:a", "pcm_s16le", str(trimmed)])
        dur = duration(trimmed)
        # 2) loudnorm 第一遍测量
        ln = f"loudnorm=I={post['lufs']}:TP={post['true_peak']}:LRA=11"
        meas = run(["ffmpeg", "-v", "info", "-i", str(trimmed), "-af", ln + ":print_format=json", "-f", "null", "-"]).stderr
        m = json.loads(meas[meas.rindex("{"):meas.rindex("}") + 1])
        ln2 = (ln + f":measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
               f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
        fo = float(post["fade_out"])
        af = f"{ln2},afade=t=in:d={post['fade_in']},afade=t=out:st={max(0.0, dur - fo):.3f}:d={fo}"
        dst = ASSETS / f"{cid}.ogg"
        run(["ffmpeg", "-y", "-v", "error", "-i", str(trimmed), "-af", af, "-ar", sr,
             "-c:a", "libvorbis", "-q:a", str(post["ogg_quality"]), str(dst)])
        rec = latest_job(jobs, cid) or {}
        qa = load_json(QA, {}).get(cid, {})
        index["tracks"][cid] = {
            "label": cues[cid]["label"], "uses": cues[cid]["uses"], "style": rec.get("style", cues[cid]["style"]),
            "job_id": rec.get("job_id"), "seed": rec.get("seed"), "raw_seconds": rec.get("audio_seconds"),
            "seconds": round(duration(dst), 2), "input_lufs": float(m["input_i"]), "target_lufs": post["lufs"],
            "bytes": dst.stat().st_size, "qa": qa,
        }
        print(f"{cid}: {index['tracks'][cid]['seconds']}s  {m['input_i']} → {post['lufs']} LUFS  {dst.stat().st_size // 1024} KiB")
    save_json(INDEX, index)
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- qa / status

def yue2_python() -> Path:
    info = api("GET", "/api/health")
    root = Path(info.get("root") or info.get("install_root") or "")
    py = root / "runtime" / "python.exe"
    if not py.is_file():
        sys.exit(f"找不到 YuE2 运行时 python：{py}")
    return py


def cmd_qa(args) -> None:
    _, _, cues = cue_table()
    ids = [i for i in pick(args.ids, cues) if (RAW / f"{i}.flac").is_file()]
    if not ids:
        sys.exit("没有可检查的原始音频")
    py = yue2_python()
    cmd = [str(py), "-I", str(ROOT / "scripts" / "bgm_qa.py"), "--out", str(QA)]
    cmd += ["--device", args.device] + [str(RAW / f"{i}.flac") for i in ids]
    subprocess.run(cmd, check=True)


def cmd_status(args) -> None:
    _, _, cues = cue_table()
    jobs = load_json(JOBS, {})
    qa = load_json(QA, {})
    for cid in pick(args.ids, cues):
        rec = latest_job(jobs, cid) or {}
        q = qa.get(cid, {})
        flag = "ogg" if (ASSETS / f"{cid}.ogg").is_file() else ("raw" if (RAW / f"{cid}.flac").is_file() else "-")
        vr = f"vocal={q['vocal_ratio']:.3f}" if "vocal_ratio" in q else ""
        print(f"{cid:15s} {flag:4s} job={rec.get('job_id', '-'):26s} seed={rec.get('seed', '-')!s:9s} "
              f"{rec.get('status', '')!s:9s} {rec.get('audio_seconds') or 0:6.1f}s {vr}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("status", "submit", "fetch", "post", "qa"):
        p = sub.add_parser(name)
        p.add_argument("ids", nargs="*")
        if name == "submit":
            p.add_argument("--seed", type=int)
        if name == "fetch":
            p.add_argument("--wait", action="store_true")
        if name == "qa":
            p.add_argument("--device", default="cpu")
    args = ap.parse_args()
    {"status": cmd_status, "submit": cmd_submit, "fetch": cmd_fetch, "post": cmd_post, "qa": cmd_qa}[args.cmd](args)


if __name__ == "__main__":
    main()
