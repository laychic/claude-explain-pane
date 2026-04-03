---
description: Open the explain side pane (incognito terminal for asking questions about the current conversation)
---

Parse the ARGUMENTS string below for optional flags:
- If `-r <text>` or bare text (no flag) is present, that is the QUESTION.
- If `-m <model>` is present, that is the MODEL (default: haiku).

Build and run ONE bash command:

```
bash ~/.claude/hooks/explain-send.sh [-r "QUESTION"] [-m MODEL]
```

Examples:
- ARGUMENTS: `hello` → `bash ~/.claude/hooks/explain-send.sh -r "hello"`
- ARGUMENTS: `-r "what happened" -m sonnet` → `bash ~/.claude/hooks/explain-send.sh -r "what happened" -m sonnet`
- ARGUMENTS: (empty) → `bash ~/.claude/hooks/explain-send.sh`

Then reply ONLY with:

**Explain pane ready.** Ask questions directly in the right pane. Type `exit` to close, `r` to refresh context.

Do NOT use any other tools. Do NOT call Write, Read, or any other tool. Just the one Bash command above, then reply.
