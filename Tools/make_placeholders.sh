#!/bin/bash
# 生成占位示范短片、糖色参考色块和 Simulator 合成样本。
# 全部为程序合成画面，非真实拍摄，仅用于验证流程；真实素材到位后替换同名文件。
set -euo pipefail
OUT="$(cd "$(dirname "$0")/.." && pwd)/Food/Resources/Media"
FONT="${FONT:-/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc}"
ENC="-c:v libx264 -pix_fmt yuv420p -profile:v high -crf 30 -r 24 -movflags +faststart -an -loglevel error -y"

demo() { # name title color
  ffmpeg -f lavfi -i "color=c=$3:s=960x540:d=5" \
    -vf "drawtext=fontfile=$FONT:text='占位示范 · $2':fontcolor=white:fontsize=54:x=(w-tw)/2:y=h/2-70,drawtext=fontfile=$FONT:text='程序合成 · 非真实拍摄 · 待替换':fontcolor=white@0.8:fontsize=30:x=(w-tw)/2:y=h/2+20" \
    $ENC "$OUT/$1.mp4"
}
demo demo_prep    "切块备料"     0x3A4A3F
demo demo_blanch  "冷水下锅焯水" 0x3A4658
demo demo_sear    "下肉调味加盖" 0x5A3A2E
demo demo_braise  "小火焖煮"     0x4A3A34
demo demo_reduce  "收汁挂肉"     0x4A2A1E

# 糖色示范：偏浅 → 目标，目标帧约在 4.0s
ffmpeg -f lavfi -i "color=c=0xEBC878:s=960x540:d=3" -f lavfi -i "color=c=0xAA5519:s=960x540:d=4" \
  -filter_complex "[0][1]xfade=transition=fade:duration=2:offset=2,drawtext=fontfile=$FONT:text='占位示范 · 炒糖色（合成色块）':fontcolor=white:fontsize=30:x=24:y=20" \
  $ENC "$OUT/demo_caramel.mp4"

# Simulator 观察样本：偏浅 → 目标 → 偏深 → 蒸汽遮挡（白）
ffmpeg -f lavfi -i "color=c=0xEBC878:s=640x480:d=6" -f lavfi -i "color=c=0xAA5519:s=640x480:d=7" \
  -f lavfi -i "color=c=0x461E0E:s=640x480:d=6" -f lavfi -i "color=c=0xE8E8E8:s=640x480:d=4" \
  -filter_complex "[0][1]xfade=transition=fade:duration=1:offset=5[a];[a][2]xfade=transition=fade:duration=1:offset=11[b];[b][3]xfade=transition=fade:duration=1:offset=16,drawtext=fontfile=$FONT:text='SIMULATOR 合成样本 · 非相机画面':fontcolor=white:fontsize=22:x=12:y=10" \
  $ENC "$OUT/sample_pot_caramel.mp4"

sw() { ffmpeg -f lavfi -i "color=c=$2:s=240x160" -frames:v 1 -loglevel error -y "$OUT/$1.png"; }
sw swatch_pale 0xEBC878
sw swatch_target 0xAA5519
sw swatch_dark 0x461E0E
ls -la "$OUT"
