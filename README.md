# claude-code-statusline

A colorful, information-dense status line for [Claude Code](https://claude.com/claude-code): see your model, effort, context window, rate limits and session cost at a glance, without leaving the terminal.

```
Opus 5.5 ▶ high ▶ ⌂ claude-code-statusline ⎇ main ● 3 changes
ctx     █░░░░░░░░░   12%  ▶ +120 -8 · 15m 5s · $1.23
5hr     ▓▓▓▓▓▓░░░░   55%  ↻ 1h56m → today 5:32am
weekly  ███░░░░░░░   30%  ↻ 2d 7h → Fri 11:08am
```

Just four lines, so it stays out of the way of your conversation.

## Features

- **Effort at a glance:** `low` is green, `medium` yellow and `high` red. `xhigh` and `max` get an animated rainbow that flows across the text.
- **Rate limits that warn you:** the 5-hour and weekly bars turn orange at 50% and red at 80%, so you see trouble coming before you hit the wall.
- **Human-friendly reset times:** each limit shows a countdown and when it resets, in plain words: `↻ 1h56m → today 5:32am`, `↻ 20h10m → tomorrow 1:00am`, `↻ 2d 7h → Fri 11:08am`.
- **Context window bar:** how full the current conversation is.
- **Where you are:** the current folder name (`⌂ my-project`, or `~` in your home folder; long names are shortened with `…`).
- **Git awareness:** the current branch (`⎇ main`) and its state in plain words: `✓ clean` in green, or `● 3 changes` in orange when files are uncommitted. Hidden outside a git repo.
- **Session summary:** lines added and removed, elapsed time and cost.
- **Fast mode badge:** a `⚡fast` tag when fast mode is on.
- **Lightweight:** one plain Bash script; a full render takes about 0.1s.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/daydeda/claude-code-statusline/main/install.sh | bash
```

Then restart Claude Code. The installer:

1. downloads `statusline.sh` to `~/.claude/statusline.sh`,
2. backs up your `settings.json` as `settings.json.bak.<timestamp>`,
3. sets `statusLine` to run the script, refreshing every second (needed for the rainbow animation).

**Requirements:** `bash`, plus `jq` or `python3`. `git` is optional and only used for the branch display.

Prefer to read before you run? Open [`install.sh`](install.sh); it's about 15 lines.

## Make it yours: fork it

This status line is meant to be remixed. Everything lives in a single, readable file, [`statusline.sh`](statusline.sh), so you can change it in minutes:

1. Click **Fork** at the top of this page.
2. Clone your fork and point Claude Code at it:
   ```bash
   git clone https://github.com/<you>/claude-code-statusline.git
   ln -sf "$PWD/claude-code-statusline/statusline.sh" ~/.claude/statusline.sh
   ```
   Because it's a symlink, every edit shows up in your status line on the next refresh. No reinstall needed.
3. Tweak away. Some ideas:
   - **Colors:** every color is a 24-bit `R;G;B` value passed to `__emit`. Change `__pct_color` for the limit thresholds or `__effort` for the effort palette.
   - **Reset time format:** edit `__friendly_time` (e.g. swap `%I:%M%p` for `%H:%M` to get a 24-hour clock) and `__rel_time` for the countdown.
   - **Layout:** line 1 is built at the bottom of the script; each meter row is one `__meter` call. Reorder, remove or add rows there.
   - **New fields:** Claude Code passes a JSON object on stdin. Read any field with `__field 'path.to.value'` and print it with `__emit '<style>' "$value"`.
   - **Test without Claude Code:** pipe in sample JSON:
     ```bash
     echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42}}' | ./statusline.sh
     ```

Made something cool? Open a pull request or share a screenshot in an issue. I'd love to see it.

## Uninstall

Remove the `statusLine` entry from `~/.claude/settings.json` (or restore one of the `.bak` files) and delete `~/.claude/statusline.sh`.

## License

[MIT](LICENSE). Use it, fork it, ship it.
