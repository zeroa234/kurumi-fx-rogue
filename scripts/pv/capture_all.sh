#!/usr/bin/env bash
# 录 PV 实机素材：每个片段一次 Godot Movie Maker 运行 → output/pv/raw/<片段>/f########.png（640×360，30fps）
# 用法：bash scripts/pv/capture_all.sh [片段名...]   （不带参数＝全部）
# 录制前备份本机存档，结束后还原（录制只改内存设置，这是保险）。
set -euo pipefail
cd "$(dirname "$0")/../.."
G="${G:-D:/godot/Godot_v4.7.2-stable_win64_console.exe}"
OUT="$(pwd -W 2>/dev/null || pwd)/output/pv/raw"
SAVE="$APPDATA/Godot/app_userdata/FX战士久留美 同人 · 2000万之路/save.json"

# 片段名:秒数
ALL="title:6 lehman:26 snb:24 trade:24 dialogue:13 map:6 meta:5 chapters:5"
want="${*:-}"

if [ -f "$SAVE" ]; then cp "$SAVE" "$SAVE.pvbak"; fi
restore() { if [ -f "$SAVE.pvbak" ]; then mv -f "$SAVE.pvbak" "$SAVE"; fi; }
trap restore EXIT

for item in $ALL; do
  name="${item%%:*}"; sec="${item##*:}"
  if [ -n "$want" ] && [[ " $want " != *" $name "* ]]; then continue; fi
  rm -rf "output/pv/raw/$name"; mkdir -p "output/pv/raw/$name"
  echo "== $name (${sec}s)"
  "$G" --path . --write-movie "$OUT/$name/f.png" --fixed-fps 30 --quit-after $((sec * 30)) \
    res://scripts/pv/pv_capture.tscn -- --clip="$name" 2>&1 | grep -E "ERROR|SCRIPT ERROR|frames at" || true
done
