#!/usr/bin/env bash
# Plugin helper for claude-code-statusline.
#
#   manage.sh setup          copy the status line out of the plugin and turn it on
#   manage.sh remove         put back the status line you had before setup
#   manage.sh theme <name>   switch theme in statusline.conf
#   manage.sh status         say whether it's on and which theme is set
#   manage.sh sync           (SessionStart hook) refresh the copy after an update
#
# Plugins can't register a status line, so setup points settings.json at a
# copy in the config dir; the plugin's own folder changes with every version.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL="$DIR/statusline.sh"
CONF="$DIR/statusline.conf"
SETTINGS="$DIR/settings.json"
MARKER="$DIR/statusline.plugin"          # exists while the plugin manages $SL
PREVIOUS="$DIR/statusline.previous.json" # the statusLine before setup
THEMES="default catppuccin dracula nord gruvbox tokyonight"

# Read or write settings.json with jq, falling back to python3.
current_command() {
  [ -f "$SETTINGS" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null || true
  else
    S="$SETTINGS" python3 -c 'import json,os;print((json.load(open(os.environ["S"])).get("statusLine") or {}).get("command",""))' 2>/dev/null || true
  fi
}
save_previous() {
  if command -v jq >/dev/null 2>&1; then
    jq '.statusLine // null' "$SETTINGS" > "$PREVIOUS"
  else
    S="$SETTINGS" python3 -c 'import json,os;print(json.dumps(json.load(open(os.environ["S"])).get("statusLine")))' > "$PREVIOUS"
  fi
}
# set_status_line '<json value or null>'
set_status_line() {
  local tmp; tmp="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    jq --argjson v "$1" 'if $v == null then del(.statusLine) else .statusLine = $v end' "$SETTINGS" > "$tmp"
  else
    S="$SETTINGS" V="$1" python3 -c 'import json,os
d=json.load(open(os.environ["S"]));v=json.loads(os.environ["V"])
d.pop("statusLine",None) if v is None else d.__setitem__("statusLine",v)
print(json.dumps(d,indent=2))' > "$tmp"
  fi
  mv "$tmp" "$SETTINGS"
}
is_on() { [ -f "$MARKER" ] && [ "$(current_command)" = "$SL" ]; }

install_copy() {
  # rm first so a symlink at $SL is replaced, never written through.
  rm -f "$SL"
  cp "$ROOT/statusline.sh" "$SL"
  chmod +x "$SL"
}

setup() {
  mkdir -p "$DIR"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if is_on; then
    install_copy
    echo "claude-code-statusline is already on. Its script is up to date."
    return
  fi
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  save_previous
  # Keep any other status line script that sits where ours goes; the marker
  # remembers the backup so remove can put it back.
  local backup=''
  if [ -e "$SL" ] || [ -L "$SL" ]; then backup="$SL.bak.$(date +%s)"; mv "$SL" "$backup"; fi
  install_copy
  [ -f "$CONF" ] || cp "$ROOT/statusline.conf.example" "$CONF"
  set_status_line "{\"type\":\"command\",\"command\":$(printf '%s' "$SL" | json_string),\"refreshInterval\":1}"
  printf '%s' "$backup" > "$MARKER"
  echo "claude-code-statusline is on. It shows up after Claude's next reply."
  echo "Settings: $CONF"
  echo "Your previous status line was saved; /pace-statusline remove puts it back."
}

remove() {
  if ! is_on; then
    rm -f "$MARKER"
    echo "claude-code-statusline isn't the active status line. Nothing changed."
    return
  fi
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  if [ -f "$PREVIOUS" ]; then set_status_line "$(cat "$PREVIOUS")"; else set_status_line null; fi
  # Put back the script setup moved aside, if there was one.
  local backup; backup="$(cat "$MARKER")"
  if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
    rm -f "$SL"; mv "$backup" "$SL"
  fi
  rm -f "$MARKER" "$PREVIOUS"
  echo "claude-code-statusline removed. Your previous status line is back."
  echo "(Your settings in $CONF were left in place.)"
}

theme() {
  local name="${1:-}"
  case " $THEMES " in
    *" $name "*) ;;
    *) echo "Pick a theme: $THEMES"; return ;;
  esac
  [ -f "$CONF" ] || cp "$ROOT/statusline.conf.example" "$CONF"
  if grep -q '^[[:space:]]*STATUSLINE_THEME[[:space:]]*=' "$CONF"; then
    local tmp; tmp="$(mktemp)"
    sed "s/^[[:space:]]*STATUSLINE_THEME[[:space:]]*=.*/STATUSLINE_THEME=$name/" "$CONF" > "$tmp" && mv "$tmp" "$CONF"
  else
    printf '\nSTATUSLINE_THEME=%s\n' "$name" >> "$CONF"
  fi
  echo "Theme set to $name. It applies on the next refresh."
}

status() {
  local t=default
  [ -f "$CONF" ] && t="$(sed -n 's/^[[:space:]]*STATUSLINE_THEME[[:space:]]*=[[:space:]]*//p' "$CONF" | tr -d ' "'\''' | tail -1)"
  if is_on; then echo "claude-code-statusline is on (theme: ${t:-default})."
  else echo "claude-code-statusline is off. /pace-statusline setup turns it on."; fi
  echo "Themes: $THEMES"
}

# After a plugin update, refresh the copy setup made. Silent and best-effort.
sync() {
  is_on || return 0
  [ -L "$SL" ] && return 0 # someone linked their own checkout; leave it
  cmp -s "$ROOT/statusline.sh" "$SL" || install_copy
}

json_string() {
  if command -v jq >/dev/null 2>&1; then jq -Rs .
  else python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; fi
}

case "${1:-status}" in
  setup) setup ;;
  remove) remove ;;
  theme) theme "${2:-}" ;;
  status) status ;;
  sync) sync 2>/dev/null || true ;;
  *) echo "Usage: /pace-statusline [setup|remove|theme <name>|status]" ;;
esac
