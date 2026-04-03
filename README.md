# Claude Code Explain Pane

**English** | [简体中文](../main/README-zh.md) 
An incognito side-pane for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — ask questions about your current conversation in a separate terminal, without polluting the main session.

```
+---------------------------+----------------------+
|                           |                      |
|   Claude Code (main)      |  > what just happened |
|                           |                      |
|   Working on your code    |  Based on context,   |
|   normally...             |  you just refactored |
|                           |  the auth module...  |
|                           |                      |
|                           |  > why that approach? |
|                           |  Because the old...  |
+---------------------------+----------------------+
```

## Features

- **Incognito mode** — no session history, no memory writes, zero trace
- **Auto context** — reads your main conversation transcript (last 5 rounds, compressed)
- **Sliding window** — recent rounds keep full text, older rounds auto-summarized to stay under 3000 chars
- **Context caching** — only re-extracts every 3 questions; reuses cache in between
- **Language lock** — detects language from first question, stays consistent
- **Multi-line paste** — blank line (Enter twice) to submit; paste won't trigger early
- **Inject from main** — re-run `/explain-e <question>` to send questions to existing pane
- **Pure bash** — no Python, no Node.js, no jq, no dependencies
- **Cross-platform** — Windows Terminal / tmux / iTerm2 / Terminal.app

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Bash (Git Bash on Windows, native on Linux/macOS)
- One of: Windows Terminal / tmux / iTerm2

## Install

```bash
git clone https://github.com/laychic/claude-explain-pane.git
cd claude-explain-pane
bash install.sh
```

Windows (cmd/PowerShell): run `install.bat` instead.

## Usage

In Claude Code, type:

```
/explain-e              # open the pane
/explain-e what is this # open + auto-ask a question
/explain-e -m sonnet    # use a specific model
```

If the pane is already open, `/explain-e <question>` sends the question to it directly.

### In the pane

Type your question, then press Enter twice (blank line) to send:

```
> what did the last change do?
>                                  <- blank line sends it
```

### Commands

| Command | Action |
|---------|--------|
| `exit` / `q` / Ctrl+C | Close the pane |
| `r` | Clear cache, re-read transcript |
| `lang:zh` | Lock language (zh/en/ja/ko/...) |

### Language auto-detection

The pane detects language from your first question and locks it for the session:

```
> explain the auth flow            -> English for this session
> lang:zh                          -> switch to Chinese
```

## Configuration

| Env variable | Default | Options |
|-------------|---------|---------|
| `EXPLAIN_LANG` | `auto` | `auto`/`zh`/`en`/`ja`/`ko`/... |
| `EXPLAIN_MODEL` | `haiku` | `haiku`/`sonnet`/`opus` |

## How it works

```
/explain-e  ->  explain-send.sh  ->  open-pane.sh  ->  watcher.sh (interactive)
                  |                                       |
                  |  (inject file for                     |  reads transcript .jsonl
                  |   existing pane)                      |  compresses with sliding window
                  +-----> ~/.claude/tmp/explain-inject.txt |  calls claude -p --no-session-persistence
                                                          |  caches context for 3 questions
```

**Context pipeline:**
1. Reads main session `.jsonl` transcript (single awk pass, <0.2s)
2. Filters out tool calls, skill expansions, system messages
3. Sliding window compression: newest 2 rounds full, round 3 light, rounds 4-5 summary
4. Caches result; reuses for next 2 questions, then re-extracts

**Security:** User input is never embedded in shell commands. Questions pass through files, not string interpolation. No eval, no source, no remote code.

## Platform support

| Platform | Terminal | Split method |
|----------|----------|-------------|
| Windows | Windows Terminal | `wt.exe sp -V -s 0.3` |
| Linux | tmux | `tmux split-window -h -l 30%` |
| macOS | iTerm2 | AppleScript vertical split |
| macOS | Terminal.app | New window (no split) |
| Any | Other | Manual launch instructions |

## Timing display

Each response shows performance metrics:

```
[prep:0s 2800 chars haiku cached+2]     <- using cached context
───────────────────────────────────
[reply:8s total:8s cached+2]            <- response time
```

## Uninstall

```bash
bash uninstall.sh
```

## License

MIT
