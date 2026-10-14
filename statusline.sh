#!/usr/bin/env bash
set -u
INPUT="$(cat)"
export INPUT_JSON="$INPUT"

# Terminal width for flex-spacer math. Honors STATUSLINE_COLS env override
# (used by parity tests); otherwise tries tput, finally falls back to 80.
STATUSLINE_COLS=${STATUSLINE_COLS:-$(tput cols 2>/dev/null || echo 80)}

# Visible-character length: strip CSI SGR sequences then count chars.
# Wide glyphs (emoji, CJK) count as 1 column — same simplification as the
# interpret backend uses.
__visible_len() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' | awk '{ printf "%s", length($0) }'
}

__repeat_char() {
  local ch="$1" n="$2" out=""
  if [ "$n" -le 0 ]; then printf ''; return; fi
  local i=0
  while [ "$i" -lt "$n" ]; do out+="$ch"; i=$((i+1)); done
  printf '%s' "$out"
}

__sgr() { printf '\033[%sm' "$1"; }
__reset() { printf '\033[0m'; }

if command -v jq >/dev/null 2>&1; then
  __field() {
    printf '%s' "$INPUT_JSON" | jq -r --arg p "$1" '
      ($p | split(".")) as $parts
      | reduce $parts[] as $k (.; if type == "object" and has($k) then .[$k] else null end)
      | if . == null then "" else (if type == "string" then . else tostring end) end
    ' 2>/dev/null
  }
else
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    __PY=python3
  elif command -v python >/dev/null 2>&1; then
    __PY=python
  else
    __PY=""
  fi
  __field() {
    if [ -z "$__PY" ]; then printf ''; return; fi
    PATH_ARG="$1" "$__PY" - <<'PYEOF' 2>/dev/null
import json, os
d = json.loads(os.environ.get('INPUT_JSON','{}') or '{}')
p = os.environ.get('PATH_ARG','')
cur = d
for part in p.split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if cur is None:
    print('', end='')
elif isinstance(cur, bool):
    print('true' if cur else 'false', end='')
else:
    print(cur, end='')
PYEOF
  }
fi

__basename() { local s="$1"; printf '%s' "${s##*/}"; }
__compact() {
  local s="$1"
  if [ -z "$s" ]; then printf ''; return; fi
  # Use awk so we don't depend on bash arrays. Split on '/', take the first
  # char of every segment except the last; preserve a leading slash by
  # emitting an empty initial element when the path starts with '/'.
  printf '%s' "$s" | awk 'BEGIN{FS="/"} {
    out=""
    for (i=1; i<=NF; i++) {
      if (i==NF) { piece = $i }
      else if ($i == "") { piece = "" }
      else { piece = substr($i, 1, 1) }
      if (i==1) { out = piece } else { out = out "/" piece }
    }
    printf "%s", out
  }'
}
__tildify() {
  local s="$1"
  local home="${HOME%/}"
  if [ -n "$home" ] && [[ "$s" == "$home"* ]]; then
    printf '~%s' "${s#$home}"
    return
  fi
  if [[ "$s" =~ ^/(Users|home)/[^/]+(.*)$ ]]; then
    printf '~%s' "${BASH_REMATCH[2]}"
    return
  fi
  printf '%s' "$s"
}
__truncate() {
  local s="$1" n="$2"
  if [ "$n" -le 0 ] || [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  if [ "$n" -le 1 ]; then printf '%s' "${s:0:$n}"; return; fi
  printf '%s…' "${s:0:$((n-1))}"
}
__cost_fmt() { printf '$%.*f' "$2" "$1"; }
__dur_hms() {
  local ms="$1" total h m s
  total=$((ms/1000)); h=$((total/3600)); m=$(((total%3600)/60)); s=$((total%60))
  if [ "$h" -gt 0 ]; then printf '%d:%02d:%02d' "$h" "$m" "$s"
  else printf '%d:%02d' "$m" "$s"; fi
}
__dur_human() {
  local ms="$1" total m s h mm
  total=$((ms/1000))
  if [ "$total" -lt 60 ]; then printf '%ds' "$total"; return; fi
  m=$((total/60)); s=$((total%60))
  if [ "$m" -lt 60 ]; then
    if [ "$s" -gt 0 ]; then printf '%dm %ds' "$m" "$s"; else printf '%dm' "$m"; fi
    return
  fi
  h=$((m/60)); mm=$((m%60))
  if [ "$mm" -gt 0 ]; then printf '%dh %dm' "$h" "$mm"; else printf '%dh' "$h"; fi
}
__bar() {
  local pct="$1" width="$2" filled="$3" empty="$4"
  local p i n=0 e=0
  p=${pct%.*}
  [ -z "$p" ] && p=0
  if [ "$p" -lt 0 ]; then p=0; fi
  if [ "$p" -gt 100 ]; then p=100; fi
  n=$(( (p * width + 50) / 100 ))
  e=$((width - n))
  local out=""
  for ((i=0; i<n; i++)); do out+="$filled"; done
  for ((i=0; i<e; i++)); do out+="$empty"; done
  printf '%s' "$out"
}
__git_branch() {
  local cwd dir
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null
  else
    __field workspace.git_worktree
  fi
}
__git_dirty() {
  local cwd
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then printf '1'; else printf '0'; fi
  else
    printf '0'
  fi
}
# Number of files with uncommitted changes (staged, unstaged or untracked).
__git_changes() {
  local cwd n
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    n="$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  fi
  printf '%s' "$(__norm_int "${n:-0}")"
}
__emit() {
  local style="$1" text="$2"
  if [ -n "$style" ]; then __sgr "$style"; fi
  printf '%s' "$text"
  if [ -n "$style" ]; then __reset; fi
}
__norm_int() {
  # Coerce a possibly-decimal/empty/garbage field value to a non-negative
  # integer string. Used by token-display helpers.
  local v="$1"
  v="${v%%.*}"
  case "$v" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$v" ;;
  esac
}
__fmt_token_compact() {
  local n
  n="$(__norm_int "$1")"
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; return; fi
  if [ "$n" -lt 1000000 ]; then
    local whole=$((n / 1000))
    local rem=$((n - whole * 1000))
    local dec=$((rem / 100))
    if [ "$dec" -eq 0 ]; then printf '%dk' "$whole"; else printf '%d.%dk' "$whole" "$dec"; fi
    return
  fi
  local whole=$((n / 1000000))
  local rem=$((n - whole * 1000000))
  local dec=$((rem / 100000))
  if [ "$dec" -eq 0 ]; then printf '%dM' "$whole"; else printf '%d.%dM' "$whole" "$dec"; fi
}
__fmt_token_full() {
  local n
  n="$(__norm_int "$1")"
  printf '%s' "$n" | awk '{
    s=$0; out=""; n=length(s)
    while (n > 3) { out=","substr(s,n-2,3) out; n -= 3 }
    out=substr(s,1,n) out
    printf "%s", out
  }'
}
__tokens_used() { __field 'context_window.total_input_tokens'; }
__tokens_total() { __field 'context_window.context_window_size'; }
__tokens_remaining() {
  local u t
  u="$(__norm_int "$(__tokens_used)")"
  t="$(__norm_int "$(__tokens_total)")"
  local r=$((t - u))
  if [ "$r" -lt 0 ]; then r=0; fi
  printf '%d' "$r"
}
__tokens_pct_int() {
  local p="$(__field 'context_window.used_percentage')"
  __norm_int "$p"
}
__tick() {
  if [ -n "${STATUSLINE_CLOCK_OVERRIDE:-}" ]; then
    printf '%s' "$STATUSLINE_CLOCK_OVERRIDE"
  else
    date +%s
  fi
}
__rel_time() {
  local target="$1"
  if [ -z "$target" ]; then printf ''; return; fi
  case "$target" in
    ''|*[!0-9.-]*) printf ''; return ;;
  esac
  local t_int="${target%.*}"
  if [ -z "$t_int" ] || [ "$t_int" = "-" ]; then printf ''; return; fi
  local now diff h m s rem
  now=$(__tick)
  diff=$((t_int - now))
  if [ "$diff" -le 0 ]; then printf ''; return; fi
  if [ "$diff" -ge 86400 ]; then
    h=$(((diff%86400)/3600))
    if [ "$h" -gt 0 ]; then printf '%dd %dh' "$((diff/86400))" "$h"
    else printf '%dd' "$((diff/86400))"; fi
    return
  fi
  if [ "$diff" -lt 60 ]; then printf '%ds' "$diff"; return; fi
  if [ "$diff" -lt 3600 ]; then
    m=$((diff/60)); s=$((diff%60))
    printf '%dm%02ds' "$m" "$s"; return
  fi
  h=$((diff/3600)); rem=$(((diff%3600)/60))
  printf '%dh%02dm' "$h" "$rem"
}
# Format an epoch timestamp with date(1): BSD date first, then GNU date.
__date_fmt() {
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}
# Friendly reset time: "today 5:32am", "tomorrow 1:00am" or "Fri 11:08am".
__friendly_time() {
  local t="${1%.*}" now day clock
  case "$t" in ''|*[!0-9]*) printf ''; return ;; esac
  now="$(__tick)"
  case "$(__date_fmt "$t" '%Y%m%d')" in
    "$(__date_fmt "$now" '%Y%m%d')") day='today' ;;
    "$(__date_fmt "$((now + 86400))" '%Y%m%d')") day='tomorrow' ;;
    *) day="$(__date_fmt "$t" '%a')"
       # A week out lands on today's weekday; say "next Thu" to avoid confusion.
       if [ "$day" = "$(__date_fmt "$now" '%a')" ]; then day="next $day"; fi ;;
  esac
  clock="$(__date_fmt "$t" '%I:%M%p' | tr '[:upper:]' '[:lower:]')"
  printf '%s %s' "$day" "${clock#0}"
}
# Countdown plus reset time, e.g. "↻ 2d 7h → Fri 11:08am".
__reset_info() {
  local rel
  rel="$(__rel_time "$1")"
  [ -z "$rel" ] && return
  printf '↻ %s → %s' "$rel" "$(__friendly_time "$1")"
}
# Usage color: green below 50%, orange from 50%, red from 80%.
__pct_color() {
  local p
  p="$(__norm_int "$1")"
  if [ "$p" -ge 80 ]; then printf '38;2;255;72;72'
  elif [ "$p" -ge 50 ]; then printf '38;2;255;165;0'
  else printf '38;2;157;204;47'; fi
}
# Effort colors: low green, medium yellow, high red, xhigh/max rainbow.
# The rainbow shifts one step per second; with statusLine.refreshInterval=1
# in settings.json it appears to flow across the text.
__effort() {
  local lvl="$1" i c n off
  local rainbow=('255;72;72' '255;165;0' '255;230;0' '157;204;47' '0;190;255' '120;100;255' '220;90;255')
  n=${#rainbow[@]}
  off=$(( $(__tick) % n ))
  case "$(printf '%s' "$lvl" | tr '[:upper:]' '[:lower:]')" in
    low) __emit '3;38;2;157;204;47' "$lvl" ;;
    medium) __emit '3;38;2;255;230;0' "$lvl" ;;
    high) __emit '3;38;2;255;72;72' "$lvl" ;;
    xhigh|max)
      for ((i=0; i<${#lvl}; i++)); do
        c="${rainbow[$(( (i - off + n * 100) % n ))]}"
        __emit "1;3;38;2;$c" "${lvl:$i:1}"
      done ;;
    *) __emit '3' "$lvl" ;;
  esac
}
# One meter row: "<label>  <bar>  <pct>%  <reset info>".
# Args: label, percentage, bar char, color, reset timestamp (optional).
__meter() {
  local label="$1" pct="$2" ch="$3" color="$4" reset="${5:-}" info
  __emit "1;$color" "$(printf '%-8s' "$label")"
  __emit "$color" "$(__bar "$pct" 10 "$ch" '░')"
  __emit "$color" "$(printf '  %3s%%' "$(__norm_int "$pct")")"
  info="$(__reset_info "$reset")"
  if [ -n "$info" ]; then __emit "$color" "  $info"; fi
}

# Current folder name: "~" for the home folder, otherwise the last path
# segment, cut to 24 characters.
__folder() {
  local cwd
  cwd="$(__field workspace.current_dir)"
  if [ -z "$cwd" ]; then cwd="$(__field cwd)"; fi
  cwd="${cwd%/}"
  if [ -z "$cwd" ]; then return; fi
  if [ "$cwd" = "${HOME%/}" ]; then printf '~'; return; fi
  __truncate "$(__basename "$cwd")" 24
}

# Line 1: where you are. Model ▶ effort ▶ folder + git
__v="$(__field 'model.display_name')"
__emit '1;38;2;222;131;32;49' "$__v"
if [ "$(__field 'thinking.enabled')" = 'true' ]; then
  __emit '' ' ▶ '
  __effort "$(__field 'effort.level')"
fi
if [ "$(__field 'fast_mode')" = 'true' ]; then
  __emit '' ' '
  __emit '48;2;140;0;0' '⚡fast'
fi
__dir="$(__folder)"
__out="$(__git_branch)"
if [ -n "$__dir" ] || [ -n "$__out" ]; then __emit '' ' ▶'; fi
if [ -n "$__dir" ]; then __emit '1;38;2;0;190;255' " ⌂ $__dir"; fi
if [ -n "$__out" ]; then
  __emit '' " ⎇ $__out "
  __n="$(__git_changes)"
  if [ "$__n" -gt 0 ]; then
    if [ "$__n" -eq 1 ]; then __emit '38;2;255;165;0' '● 1 change'
    else __emit '38;2;255;165;0' "● $__n changes"; fi
  else
    __emit '38;2;157;204;47' '✓ clean'
  fi
fi

# Line 2: context meter ▶ session stats (lines changed, time, cost)
printf '\n'
__meter 'ctx' "$(__field 'context_window.used_percentage')" '█' '38;2;132;132;131'
__emit '' '  ▶ '
__emit '38;2;157;204;47' "+$(__norm_int "$(__field 'cost.total_lines_added')")"
__emit '38;2;255;72;72' " -$(__norm_int "$(__field 'cost.total_lines_removed')")"
__v="$(__field 'cost.total_duration_ms')"
__emit '2' " · $(__dur_human "$(__norm_int "${__v:-0}")")"
__v="$(__field 'cost.total_cost_usd')"
__emit '2' " · $(__cost_fmt "${__v:-0}" 2)"

# Lines 3-4: 5-hour and weekly limits. Skipped when Claude Code doesn't
# report them (e.g. API-key users).
__v="$(__field 'rate_limits.five_hour.used_percentage')"
if [ -n "$__v" ]; then
  printf '\n'
  __meter '5hr' "$__v" '▓' "$(__pct_color "$__v")" "$(__field 'rate_limits.five_hour.resets_at')"
fi
__v="$(__field 'rate_limits.seven_day.used_percentage')"
if [ -n "$__v" ]; then
  printf '\n'
  __meter 'weekly' "$__v" '█' "$(__pct_color "$__v")" "$(__field 'rate_limits.seven_day.resets_at')"
fi

exit 0
