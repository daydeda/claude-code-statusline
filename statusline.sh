#!/usr/bin/env bash
# claude-code-statusline: https://github.com/daydeda/claude-code-statusline
#
# Claude Code pipes a JSON description of the session on stdin; this script
# prints a 4-line status line. Works with the bash 3.2 that ships on macOS.
set -u

# ---------------------------------------------------------------- settings
# Read STATUSLINE_* keys from the config file. Environment variables win.
# See statusline.conf.example for every option.
__CONF="${STATUSLINE_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.conf}"
if [ -f "$__CONF" ]; then
  while IFS= read -r __line || [ -n "$__line" ]; do
    __line="${__line%%#*}"
    __line="$(printf '%s' "$__line" | tr -d ' \t"'\''')"
    case "$__line" in
      STATUSLINE_THEME=*|STATUSLINE_BAR=*|STATUSLINE_CLOCK=*|STATUSLINE_ANIMATE=*|STATUSLINE_SHOW_*=*|STATUSLINE_ASCII=*|STATUSLINE_COLORS=*|STATUSLINE_COMPACT=*) ;;
      *) continue ;;
    esac
    __key="${__line%%=*}"
    case "$__key" in *[!A-Z_]*) continue ;; esac
    if [ -z "${!__key+x}" ]; then printf -v "$__key" '%s' "${__line#*=}"; fi
  done < "$__CONF"
fi
THEME="${STATUSLINE_THEME:-default}"
BAR_STYLE="${STATUSLINE_BAR:-blocks}"
CLOCK="${STATUSLINE_CLOCK:-12}"
ANIMATE="${STATUSLINE_ANIMATE:-1}"
SHOW_FOLDER="${STATUSLINE_SHOW_FOLDER:-1}"
SHOW_GIT="${STATUSLINE_SHOW_GIT:-1}"
SHOW_SESSION="${STATUSLINE_SHOW_SESSION:-1}"
SHOW_LIMITS="${STATUSLINE_SHOW_LIMITS:-1}"
SHOW_PACE="${STATUSLINE_SHOW_PACE:-1}"
SHOW_SESSION_LINES="${STATUSLINE_SHOW_SESSION_LINES:-0}"
ASCII="${STATUSLINE_ASCII:-0}"
COLORS="${STATUSLINE_COLORS:-truecolor}"
COMPACT="${STATUSLINE_COMPACT:-0}"

# Symbols. STATUSLINE_ASCII=1 swaps them for plain ASCII, for consoles and
# fonts that lack them.
if [ "$ASCII" = 1 ]; then
  G_SEP='>'; G_DIR='dir:'; G_BRANCH='git:'; G_CLEAN='ok'; G_DIRTY='*'
  G_RESET='reset in'; G_AT='at'; G_DOT='|'; G_OK='ok'; G_WARN='!'
  G_FULL='x'; G_FAST='FAST'; G_MORE='...'; G_ROUTE='->'
else
  G_SEP='▶'; G_DIR='⌂'; G_BRANCH='⎇'; G_CLEAN='✓ clean'; G_DIRTY='●'
  G_RESET='↻'; G_AT='→'; G_DOT='·'; G_OK='✓'; G_WARN='⚠'
  G_FULL='✗'; G_FAST='⚡fast'; G_MORE='…'; G_ROUTE='⇢'
fi

# ------------------------------------------------------------------ themes
# Colors are 24-bit "R;G;B". RAINBOW drives the xhigh/max effort animation.
case "$THEME" in
  catppuccin)
    C_MODEL='203;166;247'; C_FOLDER='116;199;236'; C_OK='166;227;161'
    C_MED='249;226;175';   C_WARN='250;179;135';   C_BAD='243;139;168'
    C_MUTED='127;132;156'
    RAINBOW=('243;139;168' '250;179;135' '249;226;175' '166;227;161' '137;220;235' '137;180;250' '203;166;247') ;;
  dracula)
    C_MODEL='189;147;249'; C_FOLDER='139;233;253'; C_OK='80;250;123'
    C_MED='241;250;140';   C_WARN='255;184;108';   C_BAD='255;85;85'
    C_MUTED='98;114;164'
    RAINBOW=('255;85;85' '255;184;108' '241;250;140' '80;250;123' '139;233;253' '189;147;249' '255;121;198') ;;
  nord)
    C_MODEL='136;192;208'; C_FOLDER='129;161;193'; C_OK='163;190;140'
    C_MED='235;203;139';   C_WARN='208;135;112';   C_BAD='191;97;106'
    C_MUTED='97;110;136'
    RAINBOW=('191;97;106' '208;135;112' '235;203;139' '163;190;140' '143;188;187' '129;161;193' '180;142;173') ;;
  gruvbox)
    C_MODEL='211;134;155'; C_FOLDER='142;192;124'; C_OK='184;187;38'
    C_MED='250;189;47';    C_WARN='254;128;25';    C_BAD='251;73;52'
    C_MUTED='146;131;116'
    RAINBOW=('251;73;52' '254;128;25' '250;189;47' '184;187;38' '142;192;124' '131;165;152' '211;134;155') ;;
  tokyonight)
    C_MODEL='187;154;247'; C_FOLDER='125;207;255'; C_OK='158;206;106'
    C_MED='224;175;104';   C_WARN='255;158;100';   C_BAD='247;118;142'
    C_MUTED='86;95;137'
    RAINBOW=('247;118;142' '255;158;100' '224;175;104' '158;206;106' '125;207;255' '122;162;247' '187;154;247') ;;
  *)
    C_MODEL='222;131;32';  C_FOLDER='0;190;255';   C_OK='157;204;47'
    C_MED='255;230;0';     C_WARN='255;165;0';     C_BAD='255;72;72'
    C_MUTED='132;132;131'
    RAINBOW=('255;72;72' '255;165;0' '255;230;0' '157;204;47' '0;190;255' '120;100;255' '220;90;255') ;;
esac

[ "$ASCII" = 1 ] && BAR_STYLE=ascii
case "$BAR_STYLE" in
  ascii) BAR_ON='#'; BAR_OFF='-' ;;
  shade) BAR_ON='▓'; BAR_OFF='░' ;;
  dots)  BAR_ON='●'; BAR_OFF='○' ;;
  slim)  BAR_ON='▰'; BAR_OFF='▱' ;;
  line)  BAR_ON='━'; BAR_OFF='─' ;;
  *)     BAR_ON='█'; BAR_OFF='░' ;;
esac

# ------------------------------------------------------------------- input
# Pull every field we need in a single jq (or python) call.
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  __vars="$(printf '%s' "$INPUT" | jq -r '
    def s: if . == null then "" else tostring end;
    "J_MODEL=\(.model.display_name | s | @sh)",
    "J_THINKING=\(.thinking.enabled | s | @sh)",
    "J_EFFORT=\(.effort.level | s | @sh)",
    "J_FAST=\(.fast_mode | s | @sh)",
    "J_DIR=\((.workspace.current_dir // .cwd) | s | @sh)",
    "J_CTX=\(.context_window.used_percentage | s | @sh)",
    "J_ADDED=\(.cost.total_lines_added | s | @sh)",
    "J_REMOVED=\(.cost.total_lines_removed | s | @sh)",
    "J_DURATION=\(.cost.total_duration_ms | s | @sh)",
    "J_COST=\(.cost.total_cost_usd | s | @sh)",
    "J_5H=\(.rate_limits.five_hour.used_percentage | s | @sh)",
    "J_5H_RESET=\(.rate_limits.five_hour.resets_at | s | @sh)",
    "J_7D=\(.rate_limits.seven_day.used_percentage | s | @sh)",
    "J_7D_RESET=\(.rate_limits.seven_day.resets_at | s | @sh)"
  ' 2>/dev/null)"
else
  # "python3" may be missing (Windows often has "python") or a stub that only
  # opens the Microsoft Store, so use the first one that actually runs.
  __PY=''; __vars=''
  for __p in python3 python; do
    if "$__p" -c 'import json, shlex' >/dev/null 2>&1; then __PY="$__p"; break; fi
  done
fi
if [ -n "${__PY:-}" ]; then
  __vars="$(INPUT_JSON="$INPUT" "$__PY" - <<'PYEOF' 2>/dev/null
import json, os, shlex
try:
    d = json.loads(os.environ.get('INPUT_JSON') or '{}')
except Exception:
    d = {}
def get(*path):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return ''
        cur = cur[k]
    if cur is None:
        return ''
    if isinstance(cur, bool):
        return 'true' if cur else 'false'
    return str(cur)
fields = {
    'J_MODEL': get('model', 'display_name'), 'J_THINKING': get('thinking', 'enabled'),
    'J_EFFORT': get('effort', 'level'), 'J_FAST': get('fast_mode'),
    'J_DIR': get('workspace', 'current_dir') or get('cwd'),
    'J_CTX': get('context_window', 'used_percentage'),
    'J_ADDED': get('cost', 'total_lines_added'), 'J_REMOVED': get('cost', 'total_lines_removed'),
    'J_DURATION': get('cost', 'total_duration_ms'), 'J_COST': get('cost', 'total_cost_usd'),
    'J_5H': get('rate_limits', 'five_hour', 'used_percentage'),
    'J_5H_RESET': get('rate_limits', 'five_hour', 'resets_at'),
    'J_7D': get('rate_limits', 'seven_day', 'used_percentage'),
    'J_7D_RESET': get('rate_limits', 'seven_day', 'resets_at'),
}
for k, v in fields.items():
    print('%s=%s' % (k, shlex.quote(v)))
PYEOF
)"
fi
J_MODEL='' J_THINKING='' J_EFFORT='' J_FAST='' J_DIR='' J_CTX='' J_ADDED='' J_REMOVED=''
J_DURATION='' J_COST='' J_5H='' J_5H_RESET='' J_7D='' J_7D_RESET=''
# jq and Python on Windows end lines with \r\n; drop the \r before eval.
eval "${__vars//$'\r'/}"

# STATUSLINE_CLOCK_OVERRIDE pins "now" for tests and preview rendering.
NOW="${STATUSLINE_CLOCK_OVERRIDE:-$(date +%s)}"

# ----------------------------------------------------------------- helpers
# Color escapes from "R;G;B". STATUSLINE_COLORS=256 maps to the nearest
# xterm-256 color for terminals without 24-bit color.
__color() {
  if [ "$COLORS" = 256 ]; then
    local r g b
    IFS=';' read -r r g b <<< "$2"
    printf '%s;5;%d' "$1" $(( 16 + 36 * ((r * 5 + 127) / 255) + 6 * ((g * 5 + 127) / 255) + (b * 5 + 127) / 255 ))
  else
    printf '%s;2;%s' "$1" "$2"
  fi
}
fg() { __color 38 "$1"; }
bg() { __color 48 "$1"; }
emit() {
  if [ -n "$1" ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}
# Coerce "62.4", "" or garbage to a non-negative integer.
int() {
  local v="${1%%.*}"
  case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}
bar() {
  local p n i out=''
  p="$(int "$1")"; [ "$p" -gt 100 ] && p=100
  n=$(( (p * 10 + 50) / 100 ))
  for ((i = 0; i < 10; i++)); do
    if [ "$i" -lt "$n" ]; then out+="$BAR_ON"; else out+="$BAR_OFF"; fi
  done
  printf '%s' "$out"
}
# Format an epoch timestamp with date(1): BSD date first, then GNU date.
date_fmt() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }
# Countdown to a timestamp: "44s", "12m05s", "1h56m", "2d 7h".
rel_time() {
  local diff=$(( $(int "$1") - NOW ))
  if [ "$diff" -le 0 ]; then return; fi
  if [ "$diff" -ge 86400 ]; then
    if [ $(( (diff % 86400) / 3600 )) -gt 0 ]; then
      printf '%dd %dh' $((diff / 86400)) $(( (diff % 86400) / 3600 ))
    else
      printf '%dd' $((diff / 86400))
    fi
  elif [ "$diff" -ge 3600 ]; then printf '%dh%02dm' $((diff / 3600)) $(( (diff % 3600) / 60 ))
  elif [ "$diff" -ge 60 ]; then printf '%dm%02ds' $((diff / 60)) $((diff % 60))
  else printf '%ds' "$diff"; fi
}
# "today 5:32am", "tomorrow 1:00am", "Fri 11:08am" or "next Thu 2:37am".
friendly_time() {
  local t day clock
  t="$(int "$1")"
  case "$(date_fmt "$t" '%Y%m%d')" in
    "$(date_fmt "$NOW" '%Y%m%d')") day='today' ;;
    "$(date_fmt $((NOW + 86400)) '%Y%m%d')") day='tomorrow' ;;
    *) day="$(date_fmt "$t" '%a')"
       # A week out lands on today's weekday; "next Thu" avoids confusion.
       if [ "$day" = "$(date_fmt "$NOW" '%a')" ]; then day="next $day"; fi ;;
  esac
  if [ "$CLOCK" = 24 ]; then
    clock="$(date_fmt "$t" '%H:%M')"
  else
    clock="$(date_fmt "$t" '%I:%M%p' | tr '[:upper:]' '[:lower:]')"
    clock="${clock#0}"
  fi
  printf '%s %s' "$day" "$clock"
}
duration() {
  local s=$(( $(int "$1") / 1000 ))
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm %ds' $((s / 60)) $((s % 60))
  else printf '%dh %dm' $((s / 3600)) $(( (s % 3600) / 60 )); fi
}
# Green below 50%, orange from 50%, red from 80%.
pct_color() {
  local p; p="$(int "$1")"
  if [ "$p" -ge 80 ]; then printf '%s' "$C_BAD"
  elif [ "$p" -ge 50 ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_OK"; fi
}
# From 90% the meter pulses: dim on odd seconds, bright on even ones.
pulse() {
  if [ "$ANIMATE" = 1 ] && [ "$(int "$1")" -ge 90 ] && [ $((NOW % 2)) -eq 1 ]; then
    printf '2;'
  fi
}
# Effort: low green, medium yellow, high red, xhigh/max a rainbow that
# shifts one step per second (statusLine.refreshInterval=1 animates it).
effort() {
  local lvl="$1" n=${#RAINBOW[@]} off=0 i
  [ "$ANIMATE" = 1 ] && off=$((NOW % n))
  case "$(printf '%s' "$lvl" | tr '[:upper:]' '[:lower:]')" in
    low)    emit "3;$(fg "$C_OK")" "$lvl" ;;
    medium) emit "3;$(fg "$C_MED")" "$lvl" ;;
    high)   emit "3;$(fg "$C_BAD")" "$lvl" ;;
    xhigh|max)
      for ((i = 0; i < ${#lvl}; i++)); do
        emit "1;3;$(fg "${RAINBOW[$(( (i - off + n * 100) % n ))]}")" "${lvl:$i:1}"
      done ;;
    *) emit '3' "$lvl" ;;
  esac
}
# Pace prediction for a rate-limit window. Projects the current burn rate
# to the reset time. Sets PACE_TXT and PACE_COL (empty when too early).
pace() {
  local p r w elapsed
  PACE_TXT=''; PACE_COL=''
  [ "$SHOW_PACE" = 1 ] || return
  p="$(int "$1")"; r="$(int "$2")"; w="$3"
  [ "$r" -gt "$NOW" ] || return
  elapsed=$(( NOW - (r - w) ))
  [ "$elapsed" -gt 0 ] || return
  [ "$elapsed" -gt "$w" ] && elapsed="$w"
  if [ "$p" -ge 100 ]; then PACE_TXT="$G_FULL limit reached"; PACE_COL="$C_BAD"; return; fi
  # Too early in the window for a stable estimate.
  if [ "$elapsed" -lt $((w / 20)) ] && [ "$p" -lt 25 ]; then return; fi
  if [ $((p * w)) -le $((100 * elapsed)) ]; then
    PACE_TXT="$G_OK on pace"; PACE_COL="$C_OK"
  else
    PACE_TXT="$G_WARN runs out $(friendly_time $(( NOW + (100 - p) * elapsed / p )))"
    PACE_COL="$C_BAD"
  fi
}
# One meter row: "<label>  <bar>  <pct>%  ↻ <countdown> → <time>  <pace>".
# Args: label, percentage, color, reset timestamp (optional), window seconds.
meter() {
  local label="$1" pct="$2" c="$3" reset="${4:-}" window="${5:-0}" st rel
  st="$(pulse "$pct")$(fg "$c")"
  emit "1;$(fg "$c")" "$(printf '%-8s' "$label")"
  emit "$st" "$(bar "$pct")"
  emit "$st" "$(printf '  %3s%%' "$(int "$pct")")"
  [ -n "$reset" ] || return 0
  rel="$(rel_time "$reset")"
  [ -n "$rel" ] || return 0
  emit "$(fg "$c")" "  $G_RESET $rel $G_AT $(friendly_time "$reset")"
  pace "$pct" "$reset" "$window"
  if [ -n "$PACE_TXT" ]; then emit "$(fg "$PACE_COL")" "  $PACE_TXT"; fi
}
# Branch and number of changed files from a single `git status` call.
git_info() {
  local out first
  GIT_BRANCH=''; GIT_CHANGES=0; GIT_ADDED=0; GIT_REMOVED=0
  [ -n "$J_DIR" ] && command -v git >/dev/null 2>&1 || return
  out="$(git -C "$J_DIR" status --porcelain=v1 -b 2>/dev/null)" || return
  first="${out%%$'\n'*}"; first="${first#\#\# }"
  case "$first" in
    'No commits yet on '*) GIT_BRANCH="${first#No commits yet on }" ;;
    'HEAD (no branch)'*) GIT_BRANCH="$(git -C "$J_DIR" rev-parse --short HEAD 2>/dev/null)" ;;
    *) GIT_BRANCH="${first%%...*}"; GIT_BRANCH="${GIT_BRANCH%% *}" ;;
  esac
  GIT_CHANGES=$(( $(printf '%s\n' "$out" | wc -l) - 1 ))
  # Uncommitted lines (staged + unstaged) in tracked files; they reset to 0 on
  # commit. Untracked files count as changes but have no line counts yet.
  GIT_ADDED=0; GIT_REMOVED=0
  [ "$GIT_CHANGES" -gt 0 ] || return 0
  local stats
  if git -C "$J_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    stats="$(git -C "$J_DIR" diff --numstat HEAD 2>/dev/null)"
  else
    stats="$(git -C "$J_DIR" diff --numstat --cached 2>/dev/null)"
  fi
  # Binary files report "-"; awk treats them as 0.
  read -r GIT_ADDED GIT_REMOVED <<< "$(printf '%s\n' "$stats" | awk '{a += $1; r += $2} END {printf "%d %d", a, r}')"
}
# "~" for the home folder, otherwise the last path segment (max 24 chars).
folder() {
  local d="${J_DIR%/}" name
  d="${d%\\}"
  [ -n "$d" ] || return
  # USERPROFILE: on Windows the JSON path is C:\Users\you, not $HOME.
  if [ "$d" = "${HOME%/}" ] || [ "$d" = "${USERPROFILE:-}" ]; then printf '~'; return; fi
  name="${d##*/}"; name="${name##*\\}"
  if [ "${#name}" -gt 24 ]; then name="${name:0:23}$G_MORE"; fi
  printf '%s' "$name"
}

# autoroute (daymods) writes its current route to autoroute.state; show it
# inline when present. Missing file means the mod is not installed: skip.
AR_MODEL=''; AR_EFFORT=''; AR_WARN=''; AR_OFF=''
__AR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/autoroute.state"
if [ -f "$__AR" ]; then
  while IFS='=' read -r __k __v || [ -n "$__k" ]; do
    case "$__k" in
      model) AR_MODEL="$__v" ;; effort) AR_EFFORT="$__v" ;;
      warn) AR_WARN="$__v" ;; off) AR_OFF=1 ;;
    esac
  done < "$__AR"
fi
# Compact meter: "<label> <5-cell bar> <pct>%", plus the countdown only when
# the window is over half used or its pace says you will run out.
mini() {
  local label="$1" pct="$2" c="$3" reset="${4:-}" window="${5:-0}" p n i out='' rel
  p="$(int "$pct")"; [ "$p" -gt 100 ] && p=100
  n=$(( (p * 5 + 50) / 100 ))
  for ((i = 0; i < 5; i++)); do
    if [ "$i" -lt "$n" ]; then out+="$BAR_ON"; else out+="$BAR_OFF"; fi
  done
  emit "$(fg "$C_MUTED")" "$label "
  emit "$(pulse "$pct")$(fg "$c")" "$out $p%"
  [ -n "$reset" ] && [ "$p" -ge 50 ] || return 0
  rel="$(rel_time "$reset")"
  [ -n "$rel" ] || return 0
  emit "$(fg "$c")" " $G_RESET$rel"
  pace "$pct" "$reset" "$window"
  case "$PACE_TXT" in "$G_WARN"*|"$G_FULL"*) emit "$(fg "$PACE_COL")" " $PACE_TXT" ;; esac
}

# ------------------------------------------------------------------ line 1
# Where you are: model ▶ effort ▶ folder + git
emit "1;$(fg "$C_MODEL")" "$J_MODEL"
if [ "$J_THINKING" = true ] && [ -n "$J_EFFORT" ]; then
  emit '' " $G_SEP "
  effort "$J_EFFORT"
fi
if [ "$J_FAST" = true ]; then
  emit '' ' '
  emit "$(bg '140;0;0')" "$G_FAST"
fi
if [ -n "$AR_MODEL" ] && [ -z "$AR_OFF" ] && [ "${J_MODEL#"$AR_MODEL"}" = "$J_MODEL" ]; then
  emit '' " $G_ROUTE "
  emit "$(fg "$C_MUTED")" "$AR_MODEL"
  [ -n "$AR_EFFORT" ] && emit "$(fg "$C_MUTED")" "$G_DOT$AR_EFFORT"
fi
if [ -n "$AR_WARN" ]; then emit "$(fg "$C_WARN")" " $G_WARN $AR_WARN"; fi
DIR_NAME=''
[ "$SHOW_FOLDER" = 1 ] && DIR_NAME="$(folder)"
GIT_BRANCH=''
[ "$SHOW_GIT" = 1 ] && git_info
if [ -n "$DIR_NAME" ] || [ -n "$GIT_BRANCH" ]; then emit '' " $G_SEP"; fi
if [ -n "$DIR_NAME" ]; then emit "1;$(fg "$C_FOLDER")" " $G_DIR $DIR_NAME"; fi
if [ -n "$GIT_BRANCH" ]; then
  emit '' " $G_BRANCH $GIT_BRANCH "
  if [ "$GIT_CHANGES" -eq 0 ]; then emit "$(fg "$C_OK")" "$G_CLEAN"
  elif [ "$GIT_CHANGES" -eq 1 ]; then emit "$(fg "$C_WARN")" "$G_DIRTY 1 change"
  else emit "$(fg "$C_WARN")" "$G_DIRTY $GIT_CHANGES changes"; fi
  if [ "$GIT_ADDED" -gt 0 ] || [ "$GIT_REMOVED" -gt 0 ]; then
    emit "$(fg "$C_OK")" " +$GIT_ADDED"
    emit "$(fg "$C_BAD")" " -$GIT_REMOVED"
  fi
fi

if [ "$COMPACT" = 1 ]; then
  # ----------------------------------------------------------- compact line 2
  # ctx, plan limits and session stats on a single row.
  printf '\n'
  __c="$C_MUTED"; [ "$(int "$J_CTX")" -ge 80 ] && __c="$C_BAD"
  mini 'ctx' "$J_CTX" "$__c"
  if [ "$SHOW_LIMITS" = 1 ]; then
    if [ -n "$J_5H" ]; then emit '' "  $G_DOT  "; mini '5h' "$J_5H" "$(pct_color "$J_5H")" "$J_5H_RESET" 18000; fi
    if [ -n "$J_7D" ]; then emit '' "  $G_DOT  "; mini 'wk' "$J_7D" "$(pct_color "$J_7D")" "$J_7D_RESET" 604800; fi
  fi
  if [ "$SHOW_SESSION" = 1 ]; then
    emit '2' "  $G_DOT  $(duration "$J_DURATION") $(printf '$%.2f' "${J_COST:-0}" 2>/dev/null || printf '$0.00')"
  fi
  exit 0
fi

# ------------------------------------------------------------------ line 2
# Context window ▶ session stats (time, cost; lines Claude changed if enabled)
printf '\n'
__c="$C_MUTED"; [ "$(int "$J_CTX")" -ge 80 ] && __c="$C_BAD"
meter 'ctx' "$J_CTX" "$__c"
if [ "$SHOW_SESSION" = 1 ]; then
  emit '' "  $G_SEP "
  if [ "$SHOW_SESSION_LINES" = 1 ]; then
    emit '2' 'session '
    emit "$(fg "$C_OK")" "+$(int "$J_ADDED")"
    emit "$(fg "$C_BAD")" " -$(int "$J_REMOVED")"
    emit '2' " $G_DOT "
  fi
  emit '2' "$(duration "$J_DURATION")"
  emit '2' " $G_DOT $(printf '$%.2f' "${J_COST:-0}" 2>/dev/null || printf '$0.00')"
fi

# --------------------------------------------------------------- lines 3-4
# Plan limits. Skipped when Claude Code doesn't report them (API-key users).
if [ "$SHOW_LIMITS" = 1 ]; then
  if [ -n "$J_5H" ]; then
    printf '\n'
    meter '5hr' "$J_5H" "$(pct_color "$J_5H")" "$J_5H_RESET" 18000
  fi
  if [ -n "$J_7D" ]; then
    printf '\n'
    meter 'weekly' "$J_7D" "$(pct_color "$J_7D")" "$J_7D_RESET" 604800
  fi
fi

exit 0
