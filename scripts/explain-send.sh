#!/usr/bin/env bash
# Open the explain pane if not already running.
# Usage: explain-send.sh [-r "question"] [-m model]

PID_FILE="$HOME/.claude/tmp/explain-pane.pid"
OPENER="$HOME/.claude/hooks/explain-open-pane.sh"

QUESTION=""
MODEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--question) QUESTION="$2"; shift 2 ;;
        -m|--model)    MODEL="$2";    shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$HOME/.claude/tmp"

INJECT_FILE="$HOME/.claude/tmp/explain-inject.txt"

# Check if watcher is alive
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    if [[ -n "$QUESTION" ]]; then
        printf '%s' "$QUESTION" > "$INJECT_FILE"
        echo "Question sent to explain pane."
    else
        echo "Explain pane is already running."
    fi
else
    rm -f "$PID_FILE"
    # Write initial question to inject file BEFORE starting pane
    # (watcher will pick it up on first poll — no shell injection risk)
    [[ -n "$QUESTION" ]] && printf '%s' "$QUESTION" > "$INJECT_FILE"
    export EXPLAIN_SEND_MODEL="$MODEL"
    nohup bash "$OPENER" > /dev/null 2>&1 &
    for _ in 1 2 3 4 5 6; do
        [[ -f "$PID_FILE" ]] && break
        sleep 0.5
    done
    if [[ -f "$PID_FILE" ]]; then
        echo "Explain pane opened."
    else
        echo "Pane may take a moment to start."
    fi
fi
