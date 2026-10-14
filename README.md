# claude-code-statusline

My custom status line for [Claude Code](https://claude.com/claude-code).

Shows: model, effort, fast mode, git branch + dirty state, context usage bar, 5-hour and weekly rate-limit bars, lines added/removed, session duration and cost.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/daydeda/claude-code-statusline/main/install.sh | bash
```

Then restart Claude Code. Your previous `settings.json` is backed up as `settings.json.bak.<timestamp>`.

Requires `bash` and `jq` (or `python3`). `git` is optional.
