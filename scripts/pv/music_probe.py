"""PV 配乐候选的旁证检查（用 YuE2 运行时 python 跑：需要 demucs、librosa、torch、transformers）。

  D:/YuE2-T8-Local-v1.4.17-CSD-Trained-20260915/runtime/python.exe -I scripts/pv/music_probe.py --out output/pv/music/probe.json output/pv/music/c*.flac

对每个候选输出：
  asr        —— demucs 分出的 vocals 声部送 whisper-small 识别（按 30 秒一段）。合成器 lead 也会被分到 vocals，
                所以看的是「识别出的是不是成句的词」：只有零散音节/重复乱码/空 = 大概率是乐器；成句歌词 = 有人声。
  energy     —— 整首每 1 秒的 RMS（dB），用来找安静的前奏和「爆发点」
  beats      —— librosa 节拍时间（秒），剪辑点对齐用
  tempo      —— 估计 BPM
这只是旁证，最终仍需人耳试听。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import librosa
import numpy as np
import torch

YUE = Path(__file__).resolve()
WHISPER = Path("D:/YuE2-T8-Local-v1.4.17-CSD-Trained-20260915/models/Seed-VC/whisper-small")


def separate_vocals(path: Path, device: str) -> tuple[np.ndarray, int]:
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from bgm_qa import load_separator  # 复用 BGM QA 的离线 demucs 加载
    sep = load_separator(device)
    _, stems = sep.separate_audio_file(str(path))
    v = stems["vocals"].mean(0).cpu().numpy()
    return v, sep.samplerate


def asr(vocals: np.ndarray, sr: int, device: str) -> list[dict]:
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    proc = WhisperProcessor.from_pretrained(str(WHISPER))
    model = WhisperForConditionalGeneration.from_pretrained(str(WHISPER)).to(device).eval()
    y = librosa.resample(vocals, orig_sr=sr, target_sr=16000)
    out = []
    for i in range(0, len(y), 16000 * 30):
        seg = y[i:i + 16000 * 30]
        rms_db = 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9)
        feats = proc(seg, sampling_rate=16000, return_tensors="pt").input_features.to(device)
        with torch.no_grad():
            ids = model.generate(feats, max_new_tokens=120)
        txt = proc.batch_decode(ids, skip_special_tokens=True)[0].strip()
        out.append({"start": i / 16000, "vocal_rms_db": round(float(rms_db), 1), "text": txt})
    return out


def main():
    import sys
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    a = ap.parse_args()
    res = {}
    for f in a.files:
        p = Path(f)
        y, sr = librosa.load(str(p), sr=22050, mono=True)
        rms = librosa.feature.rms(y=y, frame_length=22050, hop_length=22050)[0]
        tempo, beats = librosa.beat.beat_track(y=y, sr=sr, units="time")
        v, vsr = separate_vocals(p, a.device)
        r = {
            "tempo": round(float(np.atleast_1d(tempo)[0]), 1),
            "energy_db": [round(float(20 * np.log10(x + 1e-9)), 1) for x in rms],
            "beats": [round(float(b), 3) for b in beats],
            "asr": asr(v, vsr, a.device),
        }
        res[p.stem] = r
        print(p.stem, "tempo", r["tempo"])
        print("  energy", " ".join(f"{e:.0f}" for e in r["energy_db"]))
        for s in r["asr"]:
            print(f"  asr@{s['start']:.0f}s ({s['vocal_rms_db']} dB): {s['text'][:100]}")
    Path(a.out).write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
