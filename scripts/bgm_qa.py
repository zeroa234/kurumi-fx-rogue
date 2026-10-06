"""BGM 客观检查（由 gen_bgm.py qa 用 YuE2 运行时 python 调用：需要 demucs、librosa、torch、soundfile）。

对每个原始音频输出：
  seconds            时长
  vocal_ratio        demucs htdemucs 分离出的 vocals 声部能量 / 原混音能量（0~1）
  vocal_active       vocals 声部比混音低不到 12 dB 的 0.5 秒帧所占比例
  tempo / tempo_alt  librosa 节拍估计（以及半速/倍速解释）
  silent_frac        低于 -45 dBFS 的帧比例；longest_gap 最长连续静音秒数
  peak_db            峰值

注意：这些只是旁证。合成主旋律（小提琴、合成器 lead）也常被 demucs 归到 vocals 声部，
vocal_ratio 高 ≠ 一定有人声；要结论请人耳试听。用法：python -I bgm_qa.py --out qa.json [--device cpu] a.flac b.flac …
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf


def load_separator(device: str):
    import yaml
    from demucs.api import Separator
    from demucs.apply import BagOfModels
    from demucs.hf import load_safetensors_model

    import torch  # noqa: F401  (demucs 需要)
    root = None
    for parent in Path(__import__("demucs").__file__).resolve().parents:
        if (parent / "models" / "Demucs" / "htdemucs.yaml").is_file():
            root = parent / "models" / "Demucs"
            break
    if root is None:
        raise SystemExit("找不到 models/Demucs（应位于 YuE2 安装目录）")
    cfg = yaml.safe_load((root / "htdemucs.yaml").read_text(encoding="utf-8"))
    weights = sorted(root.glob("*.safetensors"))[0]
    bag = BagOfModels([load_safetensors_model(weights)], cfg.get("weights"), cfg.get("segment"))
    sep = Separator.__new__(Separator)
    sep._model = bag
    sep._audio_channels = bag.audio_channels
    sep._samplerate = bag.samplerate
    sep.update_parameter(device=device, shifts=1, overlap=0.25, split=True, segment=None,
                         jobs=0, progress=False, callback=None, callback_arg=None)
    return sep


def frame_db(x: np.ndarray, sr: int, hop_s=0.5) -> np.ndarray:
    hop = int(sr * hop_s)
    n = len(x) // hop
    if n == 0:
        return np.array([-120.0])
    fr = x[: n * hop].reshape(n, hop)
    return 10 * np.log10(np.mean(fr ** 2, axis=1) + 1e-12)


def analyze(path: Path, sep) -> dict:
    import librosa

    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1).astype(np.float32)
    res = {"seconds": round(len(mono) / sr, 2), "peak_db": round(float(20 * np.log10(np.abs(audio).max() + 1e-12)), 2)}
    db = frame_db(mono, sr)
    silent = db < -45
    res["silent_frac"] = round(float(silent.mean()), 3)
    gap = best = 0
    for s in silent:
        gap = gap + 1 if s else 0
        best = max(best, gap)
    res["longest_gap"] = best * 0.5

    y = librosa.resample(mono, orig_sr=sr, target_sr=22050)
    tempo, _ = librosa.beat.beat_track(y=y, sr=22050)
    t = float(np.atleast_1d(tempo)[0])
    res["tempo"] = round(t, 1)
    res["tempo_alt"] = [round(t / 2, 1), round(t * 2, 1)]

    if sep is not None:
        origin, stems = sep.separate_audio_file(path)
        voc = stems["vocals"].detach().float().cpu().numpy().mean(axis=0)
        mix = origin.detach().float().cpu().numpy().mean(axis=0)
        res["vocal_ratio"] = round(float(np.sum(voc ** 2) / (np.sum(mix ** 2) + 1e-12)), 4)
        sr2 = sep._samplerate
        vdb, mdb = frame_db(voc, sr2), frame_db(mix, sr2)
        loud = mdb > -45
        res["vocal_active"] = round(float(np.mean((vdb - mdb > -12) & loud)), 3)
    return res


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--no-sep", action="store_true")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    out = Path(a.out)
    data = json.loads(out.read_text(encoding="utf-8")) if out.is_file() else {}
    sep = None if a.no_sep else load_separator(a.device)
    for f in a.files:
        p = Path(f)
        r = analyze(p, sep)
        data[p.stem] = r
        print(p.stem, json.dumps(r, ensure_ascii=False), flush=True)
        out.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
