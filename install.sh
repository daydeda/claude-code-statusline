#!/usr/bin/env bash
set -euo pipefail
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; mkdir -p "$DIR"
SL="$DIR/statusline.sh"; CONF="$DIR/statusline.conf"; SETTINGS="$DIR/settings.json"
# Forks: point STATUSLINE_REPO at your own raw URL (file:// works for testing).
REPO="${STATUSLINE_REPO:-https://raw.githubusercontent.com/daydeda/claude-code-statusline/main}"
curl -fsSL "$REPO/statusline.sh" -o "$SL"
chmod +x "$SL"
# Starter config with every option; never overwrite an existing one.
[ -f "$CONF" ] || curl -fsSL "$REPO/statusline.conf.example" -o "$CONF"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
if command -v jq >/dev/null; then
  tmp=$(mktemp); jq --arg c "bash \"$SL\"" '.statusLine={type:"command",command:$c,refreshInterval:1}' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
else
  PY=python3; "$PY" -c 1 >/dev/null 2>&1 || PY=python
  CMD="bash \"$SL\"" S="$SETTINGS" "$PY" -c 'import json,os;p=os.environ["S"];d=json.load(open(p));d["statusLine"]={"type":"command","command":os.environ["CMD"],"refreshInterval":1};json.dump(d,open(p,"w"),indent=2)'
fi
echo "Installed. Restart Claude Code."
echo "Pick a theme, bar style and more in $CONF"
