#!/usr/bin/env bash
# Install Claude Code Explain Pane

set -e

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
HOOKS_DIR="$CLAUDE_DIR/hooks"
TMP_DIR="$CLAUDE_DIR/tmp"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Claude Code Explain Pane..."

mkdir -p "$COMMANDS_DIR" "$HOOKS_DIR" "$TMP_DIR"

cp "$SCRIPT_DIR/commands/explain-e.md" "$COMMANDS_DIR/explain-e.md"
cp "$SCRIPT_DIR/scripts/watcher.sh"      "$HOOKS_DIR/explain-watcher.sh"
cp "$SCRIPT_DIR/scripts/open-pane.sh"    "$HOOKS_DIR/explain-open-pane.sh"
cp "$SCRIPT_DIR/scripts/explain-send.sh" "$HOOKS_DIR/explain-send.sh"
chmod +x "$HOOKS_DIR/explain-watcher.sh" "$HOOKS_DIR/explain-open-pane.sh" "$HOOKS_DIR/explain-send.sh"

echo ""
echo "Installed!"
echo ""
echo "  /explain-e  →  $COMMANDS_DIR/explain-e.md"
echo "  watcher     →  $HOOKS_DIR/explain-watcher.sh"
echo "  opener      →  $HOOKS_DIR/explain-open-pane.sh"
echo ""
echo "Usage:  /explain-e <your question>"
echo ""
echo "Config (env vars or flags):"
echo "  EXPLAIN_LANG=auto    auto-detect | zh | en | ja | ko | ..."
echo "  EXPLAIN_MODEL=haiku  haiku | sonnet | opus"
