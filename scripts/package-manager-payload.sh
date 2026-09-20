#!/bin/sh
# Package a manager payload.zip from a built module dir.
# Usage: package-manager-payload.sh [module-dir] [out-zip]
# Layout produced (universal, all ABIs):
#   bin/<abi>/zygiskd  lib/<abi>/{libzygisk.so,libzygisk_ptrace.so}
#   machikado.<arch>  sepolicy.rule  version
set -e
MODDIR="${1:-build/module/release}"
OUT="${2:-build/out/payload.zip}"
VER_NAME="${VER_NAME:-$(git rev-parse --verify --short HEAD 2>/dev/null || echo unknown)}"

rm -f "$OUT"
mkdir -p "$(dirname "$OUT")" /tmp/origin-payload-staging
STAGE=/tmp/origin-payload-staging
rm -rf "$STAGE"
mkdir -p "$STAGE"

for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  mkdir -p "$STAGE/bin/$abi" "$STAGE/lib/$abi"
  cp "$MODDIR/bin/$abi/zygiskd" "$STAGE/bin/$abi/zygiskd"
  cp "$MODDIR/lib/$abi/libzygisk.so" "$STAGE/lib/$abi/libzygisk.so"
  cp "$MODDIR/lib/$abi/libzygisk_ptrace.so" "$STAGE/lib/$abi/libzygisk_ptrace.so"
done
for m in arm arm64 x86 x86_64; do
  [ -f "$MODDIR/machikado.$m" ] && cp "$MODDIR/machikado.$m" "$STAGE/machikado.$m"
done
cp "$MODDIR/sepolicy.rule" "$STAGE/sepolicy.rule"
printf '%s\n' "v1.0.0-$VER_NAME" > "$STAGE/version"

cd "$STAGE" && zip -r9 "$OUT" . -x '*.DS_Store' > /dev/null
rm -rf "$STAGE"
echo "wrote $OUT"
unzip -l "$OUT" | head -n 25
