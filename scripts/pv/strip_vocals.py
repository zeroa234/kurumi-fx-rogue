"""用 demucs（YuE2 内置的 htdemucs）去掉人声声部：drums + bass + other → <名字>_inst.wav（48 kHz 立体声）。

YuE2 的 instrumental 模式只是文字引导，生成结果仍可能有人声；PV 配乐用这个脚本兜底。
  D:/YuE2-T8-Local-v1.4.17-CSD-Trained-20260915/runtime/python.exe -I scripts/pv/strip_vocals.py output/pv/music/c1.flac …
处理完再用 music_probe.py 检查 *_inst.wav（人声声部应只剩乱码/空）。
"""
from __future__ import annotations

import sys
from pathlib import Path

import soundfile as sf
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bgm_qa import load_separator  # noqa: E402


def main():
    import sys
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    files = [Path(f) for f in sys.argv[1:]]
    sep = load_separator("cuda" if torch.cuda.is_available() else "cpu")
    for p in files:
        _, stems = sep.separate_audio_file(str(p))
        inst = sum(stems[k] for k in stems if k != "vocals")
        dst = p.with_name(p.stem + "_inst.wav")
        sf.write(str(dst), inst.T.cpu().numpy(), sep.samplerate, subtype="PCM_24")
        print("→", dst)


if __name__ == "__main__":
    main()
