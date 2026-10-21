#!/system/bin/sh
# OriginZygisk module action: print the current status and engine state.

MODDIR=${0%/*}
STATE=/data/adb/rezygisk/state.json
PROP=/data/adb/ksu/originzygisk/module.prop
[ -f "$PROP" ] || PROP="$MODDIR/module.prop"

echo "OriginZygisk status"
echo

if [ -f "$PROP" ]; then
  VERSION=$(sed -n 's/^version=//p' "$PROP" | head -n 1)
  [ -n "$VERSION" ] && echo "Version: $VERSION"
  sed -n 's/^description=//p' "$PROP" | head -n 1
fi

if pgrep -f '[z]ygisk-ptrace' >/dev/null 2>&1; then
  echo "Monitor process: running"
else
  echo "Monitor process: not running"
fi

if [ -f "$STATE" ]; then
  echo
  echo "Engine state:"
  cat "$STATE"
else
  echo
  echo "Engine state: unavailable (monitor has not started)"
fi

exit 0
