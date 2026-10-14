#!/usr/bin/env bash
set -euo pipefail
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; mkdir -p "$DIR"
SL="$DIR/statusline.sh"; SETTINGS="$DIR/settings.json"
curl -fsSL https://raw.githubusercontent.com/daydeda/claude-code-statusline/main/statusline.sh -o "$SL"
chmod +x "$SL"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
if command -v jq >/dev/null; then
  tmp=$(mktemp); jq --arg c "$SL" '.statusLine={type:"command",command:$c}' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
else
  SL="$SL" S="$SETTINGS" python3 -c 'import json,os;p=os.environ["S"];d=json.load(open(p));d["statusLine"]={"type":"command","command":os.environ["SL"]};json.dump(d,open(p,"w"),indent=2)'
fi
echo "Installed. Restart Claude Code."
