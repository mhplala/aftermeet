#!/usr/bin/env bash
# 从源码静态编译 whisper-server，产出到 Vendor/whisper/（打进 app bundle 用）。
# 固定 tag 保证可复现；Metal 着色器内嵌（无外部资源依赖）。
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="v1.8.2"
OUT="Vendor/whisper"
SRC=".build/whisper.cpp"

[ -x "$OUT/whisper-server" ] && { echo "✓ 已有 $OUT/whisper-server（删掉可重编）"; exit 0; }

echo "▸ 拉取 whisper.cpp $TAG"
rm -rf "$SRC"
git clone --depth 1 --branch "$TAG" https://github.com/ggerganov/whisper.cpp "$SRC" 2>&1 | tail -1

echo "▸ cmake 静态构建（arm64 + Metal 内嵌）"
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON >/dev/null
cmake --build "$SRC/build" --config Release -j --target whisper-server 2>&1 | tail -2

mkdir -p "$OUT"
cp "$SRC/build/bin/whisper-server" "$OUT/whisper-server"
chmod +x "$OUT/whisper-server"

echo "▸ 验证"
file "$OUT/whisper-server"
otool -L "$OUT/whisper-server" | grep -v "^/usr/lib\|System/Library\|:" | head -5 || true
"$OUT/whisper-server" --help >/dev/null 2>&1 && echo "✓ $OUT/whisper-server"
