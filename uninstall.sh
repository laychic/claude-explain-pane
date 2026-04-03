#!/usr/bin/env bash
# Uninstall Claude Code Explain Pane

CLAUDE_DIR="$HOME/.claude"

echo "Uninstalling Claude Code Explain Pane..."

if [[ -f "$CLAUDE_DIR/tmp/explain-pane.pid" ]]; then
    PID=$(cat "$CLAUDE_DIR/tmp/explain-pane.pid")
    kill "$PID" 2>/dev/null && echo "  Stopped watcher (PID $PID)"
    rm -f "$CLAUDE_DIR/tmp/explain-pane.pid"
fi

rm -f "$CLAUDE_DIR/commands/explain-e.md"
rm -f "$CLAUDE_DIR/hooks/explain-watcher.sh"
rm -f "$CLAUDE_DIR/hooks/explain-open-pane.sh"
rm -f "$CLAUDE_DIR/hooks/explain-send.sh"
rm -f "$CLAUDE_DIR/tmp/explain-request.txt"
rm -f "$CLAUDE_DIR/tmp/explain-inject.txt"
rm -f "$CLAUDE_DIR/tmp/explain-launcher.sh"

echo "Done."
