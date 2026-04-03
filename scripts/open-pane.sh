#!/usr/bin/env bash
# Open the explain pane in a side split.
# Auto-detects: Windows Terminal / tmux / iTerm2 / fallback.

WATCHER="$HOME/.claude/hooks/explain-watcher.sh"
LANG_FLAG="${EXPLAIN_LANG:-auto}"
MODEL="${EXPLAIN_SEND_MODEL:-${EXPLAIN_MODEL:-haiku}}"

# ── Windows Terminal ───────────────────────────────────────────────────
# Key: do NOT use `bash -c "..."` — that closes stdin.
# Instead, write a launcher script and pass it as a file argument to bash.
if command -v wt.exe &>/dev/null; then
    GIT_BASH=""
    for candidate in \
        "/c/Program Files/Git/bin/bash.exe" \
        "/d/Git/Git/bin/bash.exe" \
        "/c/Git/bin/bash.exe"; do
        if [[ -x "$candidate" ]]; then
            GIT_BASH="$(cygpath -w "$candidate" 2>/dev/null || echo "$candidate")"
            break
        fi
    done

    # Launcher script keeps stdin open (no -c flag)
    mkdir -p "$HOME/.claude/tmp"
    local_launcher="$HOME/.claude/tmp/explain-launcher.sh"
    # Question is passed via inject file (written by explain-send.sh),
    # NOT embedded in the launcher script (avoids shell injection).
    cat > "$local_launcher" << LAUNCHER_EOF
#!/usr/bin/env bash
exec bash "$WATCHER" --lang $LANG_FLAG --model $MODEL
LAUNCHER_EOF
    chmod +x "$local_launcher"

    # Convert to Windows path for wt.exe
    local_launcher_win="$(cygpath -w "$local_launcher" 2>/dev/null || echo "$local_launcher")"

    if [[ -n "$GIT_BASH" ]]; then
        wt.exe -w 0 sp -V -s 0.3 -- "$GIT_BASH" --login "$local_launcher_win"
    else
        wt.exe -w 0 sp -V -s 0.3 -- bash --login "$local_launcher_win"
    fi
    exit 0
fi

# ── tmux ───────────────────────────────────────────────────────────────
if [[ -n "${TMUX:-}" ]]; then
    tmux split-window -h -l 30% "bash '$WATCHER' --lang $LANG_FLAG --model $MODEL"
    exit 0
fi

# ── iTerm2 (macOS) ────────────────────────────────────────────────────
if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    osascript -e "
        tell application \"iTerm2\"
            tell current session of current window
                set newSession to (split vertically with default profile)
                tell newSession
                    write text \"bash '$WATCHER' --lang $LANG_FLAG --model $MODEL\"
                end tell
            end tell
        end tell
    " 2>/dev/null
    exit 0
fi

# ── macOS Terminal.app ────────────────────────────────────────────────
if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
    osascript -e "
        tell application \"Terminal\"
            do script \"bash '$WATCHER' --lang $LANG_FLAG --model $MODEL\"
            activate
        end tell
    " 2>/dev/null
    echo "Opened in new Terminal window."
    exit 0
fi

# ── Fallback ──────────────────────────────────────────────────────────
echo "Open a new terminal and run:"
echo "  bash $WATCHER --lang $LANG_FLAG --model $MODEL"
exit 1
