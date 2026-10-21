#!/system/bin/sh
# OriginZygisk control CLI. Installed as <runtime>/bin/originzygiskctl.
#
# Commands:
#   status | info | integrity | modules | telemetry
#   start | stop | exit            control the monitor's injection state
#   skip list|add|remove <pkg>     per-app Zygisk skip policy
#   module list|disable|enable|quarantine|restore <id>
#   diagnostics                    print a support summary

DIR=${ORIGIN_ZYGISK_DIR:-/data/adb/ksu/originzygisk}
STATE=/data/adb/rezygisk/state.json
ABI=64
case "$(getprop ro.product.cpu.abilist 2>/dev/null)" in
  *arm64-v8a*|*x86_64*) ABI=64 ;;
  *) ABI=32 ;;
esac
BIN="$DIR/bin/zygisk-ptrace$ABI"

usage() {
  cat <<'EOF'
OriginZygisk control

  originzygiskctl status
  originzygiskctl info
  originzygiskctl integrity
  originzygiskctl modules
  originzygiskctl telemetry [lines]
  originzygiskctl start|stop|exit
  originzygiskctl skip list
  originzygiskctl skip add <package>
  originzygiskctl skip remove <package>
  originzygiskctl module list
  originzygiskctl module disable <id>
  originzygiskctl module enable <id>
  originzygiskctl module quarantine <id>
  originzygiskctl module restore <id>
  originzygiskctl diagnostics
EOF
}

add_line() {
  file=$1
  line=$2
  [ -f "$file" ] || : > "$file"
  grep -qxF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
  chmod 0644 "$file" 2>/dev/null || true
}

remove_line() {
  file=$1
  line=$2
  [ -f "$file" ] || return 0
  grep -vxF "$line" "$file" > "$file.tmp" 2>/dev/null || true
  mv -f "$file.tmp" "$file"
  chmod 0644 "$file" 2>/dev/null || true
}

list_modules() {
  for d in /data/adb/modules/*; do
    [ -d "$d" ] || continue
    id=${d##*/}
    [ -f "$d/module.prop" ] || continue
    libs=
    for lib in "$d/zygisk"/*.so; do
      [ -f "$lib" ] || continue
      libs="$libs ${lib##*/}"
    done
    [ -n "$libs" ] || continue
    name=$(sed -n 's/^name=//p' "$d/module.prop" | head -n 1)
    module_state=loaded
    if [ -f "$d/disable" ]; then module_state=module-disabled; fi
    if grep -qxF "$id" "$DIR/disabled_modules.txt" 2>/dev/null; then
      module_state=zygisk-disabled
    fi
    if grep -qxF "$id" "$DIR/quarantine.txt" 2>/dev/null; then
      module_state=quarantined
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$module_state" "$libs"
  done
}

case "$1" in
  status)
    echo "OriginZygisk"
    echo "  runtime:  $DIR"
    echo "  version:  $(cat "$DIR/payload/version" 2>/dev/null || echo unknown)"
    if [ -f "$DIR/enable" ]; then echo "  enabled:  yes"; else echo "  enabled:  no"; fi
    if pgrep -f '[z]ygisk-ptrace' >/dev/null 2>&1; then
      echo "  monitor:  running"
    else
      echo "  monitor:  not running"
    fi
    echo
    if [ -f "$STATE" ]; then cat "$STATE"; else echo "state: unavailable"; fi
    ;;
  info)
    [ -x "$BIN" ] || { echo "monitor binary not found: $BIN" >&2; exit 1; }
    exec "$BIN" info
    ;;
  integrity)
    [ -f "$DIR/deployed.sha256" ] || { echo "checksum manifest missing" >&2; exit 1; }
    cd "$DIR" && sha256sum -c deployed.sha256
    ;;
  modules)
    list_modules
    ;;
  telemetry)
    tail -n "${2:-50}" "$DIR/telemetry.jsonl" 2>/dev/null || true
    ;;
  start|stop|exit)
    [ -x "$BIN" ] || { echo "monitor binary not found: $BIN" >&2; exit 1; }
    exec "$BIN" ctl "$1"
    ;;
  skip)
    case "$2" in
      list)
        cat "$DIR/skip_packages.txt" 2>/dev/null || true
        ;;
      add)
        [ -n "$3" ] || { echo "package name required" >&2; exit 1; }
        add_line "$DIR/skip_packages.txt" "$3"
        echo "Zygisk skip added: $3"
        ;;
      remove)
        [ -n "$3" ] || { echo "package name required" >&2; exit 1; }
        remove_line "$DIR/skip_packages.txt" "$3"
        echo "Zygisk skip removed: $3"
        ;;
      *) usage; exit 1 ;;
    esac
    ;;
  module)
    case "$2" in
      list)
        list_modules
        ;;
      disable)
        [ -n "$3" ] || { echo "module id required" >&2; exit 1; }
        add_line "$DIR/disabled_modules.txt" "$3"
        echo "Zygisk module disabled: $3 (takes effect next boot)"
        ;;
      enable)
        [ -n "$3" ] || { echo "module id required" >&2; exit 1; }
        remove_line "$DIR/disabled_modules.txt" "$3"
        echo "Zygisk module enabled: $3 (takes effect next boot)"
        ;;
      quarantine)
        [ -n "$3" ] || { echo "module id required" >&2; exit 1; }
        add_line "$DIR/quarantine.txt" "$3"
        echo "Zygisk module quarantined: $3 (takes effect next boot)"
        ;;
      restore)
        [ -n "$3" ] || { echo "module id required" >&2; exit 1; }
        remove_line "$DIR/quarantine.txt" "$3"
        echo "Zygisk module restored: $3 (takes effect next boot)"
        ;;
      *) usage; exit 1 ;;
    esac
    ;;
  diagnostics)
    if [ -f "$DIR/enable" ]; then enabled_state=yes; else enabled_state=no; fi
    if [ -f "$DIR/unmount" ]; then umount_state=yes; else umount_state=no; fi
    if pgrep -f '[z]ygisk-ptrace' >/dev/null 2>&1; then
      monitor_state=running
    else
      monitor_state=stopped
    fi
    echo "time=$(date)"
    echo "runtime=$DIR"
    echo "version=$(cat "$DIR/payload/version" 2>/dev/null || echo unknown)"
    echo "enabled=$enabled_state"
    echo "umount=$umount_state"
    echo "monitor=$monitor_state"
    echo "integrity:"
    (
      cd "$DIR" || exit 1
      sha256sum -c deployed.sha256 2>&1 || true
    )
    echo
    echo "policies:"
    echo "  skip_packages:"; sed 's/^/    /' "$DIR/skip_packages.txt" 2>/dev/null || true
    echo "  skip_uids:"; sed 's/^/    /' "$DIR/skip_uids.txt" 2>/dev/null || true
    echo "  disabled_modules:"; sed 's/^/    /' "$DIR/disabled_modules.txt" 2>/dev/null || true
    echo "  quarantine:"; sed 's/^/    /' "$DIR/quarantine.txt" 2>/dev/null || true
    echo
    echo "modules:"
    list_modules | sed 's/^/  /'
    echo
    echo "state:"
    cat "$STATE" 2>/dev/null || true
    ;;
  version)
    cat "$DIR/payload/version" 2>/dev/null || echo unknown
    ;;
  *)
    usage
    exit 1
    ;;
esac
