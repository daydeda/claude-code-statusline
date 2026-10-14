---
name: pace-statusline
description: Turn the claude-code-statusline status line on or off, switch its theme, or show its status.
argument-hint: "[setup|remove|theme <name>|status]"
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/manage.sh":*)
---

Run this command with the Bash tool, exactly as written, passing the user's arguments: `$ARGUMENTS`

```bash
bash "${CLAUDE_SKILL_DIR}/manage.sh" $ARGUMENTS
```

If the arguments are empty, run it with `status`. Then relay the script's output to the user in one or two short sentences. Don't edit any files yourself.

Themes: default, catppuccin, dracula, nord, gruvbox, tokyonight. Settings live in `~/.claude/statusline.conf`.
