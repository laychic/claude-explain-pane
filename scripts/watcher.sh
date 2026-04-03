#!/usr/bin/env bash
# Claude Code Explain Pane - Interactive incognito terminal
# Reads main window transcript for context, answers via claude -p --no-session-persistence

set -euo pipefail

# ── paths ──────────────────────────────────────────────────────────────
WATCH_DIR="$HOME/.claude/tmp"
PID_FILE="$WATCH_DIR/explain-pane.pid"
PROJECT_DIR=""  # set via --project or auto-detected

# ── defaults ───────────────────────────────────────────────────────────
LANG_OVERRIDE="${EXPLAIN_LANG:-auto}"
MODEL="${EXPLAIN_MODEL:-haiku}"
CONTEXT_ROUNDS=5  # last N conversation rounds (with sliding window compression)
SESSION_LANG=""    # locked after first detection

# ── parse flags ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang)     LANG_OVERRIDE="$2"; shift 2 ;;
        --model|-m) MODEL="$2";         shift 2 ;;
        --project)  PROJECT_DIR="$2";   shift 2 ;;
        --rounds)   CONTEXT_ROUNDS="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: watcher.sh [--lang auto|zh|en|..] [--model haiku] [-r <question>] [--rounds 4]"
            exit 0 ;;
        *) shift ;;
    esac
done

# ── encoding ──────────────────────────────────────────────────────────
setup_encoding() {
    export LANG="${LANG:-en_US.UTF-8}"
    export LC_ALL="${LC_ALL:-en_US.UTF-8}"
    if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]]; then
        chcp.com 65001 &>/dev/null || true
    fi
}

# ── Windows: claude needs git-bash ────────────────────────────────────
setup_git_bash_env() {
    [[ "${OSTYPE:-}" != msys* && "${OSTYPE:-}" != mingw* ]] && return
    [[ -n "${CLAUDE_CODE_GIT_BASH_PATH:-}" ]] && return
    for p in "C:\\Program Files\\Git\\bin\\bash.exe" "D:\\Git\\Git\\bin\\bash.exe" "C:\\Git\\bin\\bash.exe"; do
        local upath
        upath=$(cygpath -u "$p" 2>/dev/null) || continue
        if [[ -f "$upath" ]]; then
            export CLAUDE_CODE_GIT_BASH_PATH="$p"
            return
        fi
    done
}

# ── find claude ───────────────────────────────────────────────────────
find_claude() {
    command -v claude &>/dev/null && echo "claude" && return
    for c in "$HOME/AppData/Roaming/npm/claude" "$HOME/.npm-global/bin/claude" "/usr/local/bin/claude"; do
        [[ -x "$c" ]] && echo "$c" && return
    done
    echo "claude"
}

# ── find project directory ────────────────────────────────────────────
find_project_dir() {
    if [[ -n "$PROJECT_DIR" ]]; then echo "$PROJECT_DIR"; return; fi
    # Find the most recently modified .jsonl transcript → that's the active project
    local latest
    latest=$(ls -t "$HOME/.claude/projects"/*/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        dirname "$latest"
    else
        echo ""
    fi
}

# ── extract last N rounds from transcript ─────────────────────────────
# Single awk pass: no per-line subprocesses (sed/grep), ~100x faster.
# Handles both content formats:
#   User direct input:  "content":"plain text"
#   Assistant text:     "content":[{"type":"text","text":"..."}]
extract_context() {
    local proj_dir="$1"
    local rounds="$2"

    if [[ -z "$proj_dir" ]]; then echo "(no project found)"; return; fi

    local transcript
    transcript=$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1)
    [[ -z "$transcript" ]] && { echo "(no transcript found)"; return; }

    local search_lines=$(( rounds * 40 ))
    local keep=$(( rounds * 8 ))

    tail -"$search_lines" "$transcript" 2>/dev/null | awk -v keep="$keep" '
    # ── unescape JSON string starting at pos in $0, return up to maxlen chars ──
    function json_str(pos,    maxlen, s, i, c, nc) {
        maxlen = 300
        s = ""
        for (i = pos; i <= length($0) && length(s) < maxlen; i++) {
            c = substr($0, i, 1)
            if (c == "\\") {
                i++; nc = substr($0, i, 1)
                if (nc == "n") s = s " "
                else if (nc == "t") s = s " "
                else s = s nc
            } else if (c == "\"") {
                break
            } else {
                s = s c
            }
        }
        return s
    }

    {
        # Skip noise
        if (index($0, "\"isMeta\":true"))    next
        if (index($0, "\"toolUseResult\""))  next
        if (index($0, "\"tool_result\""))    next
        if (index($0, "\"tool_use\""))       next

        role = ""; text = ""

        # ── User direct input: "content":"<string>" ──
        if (index($0, "\"role\":\"user\"")) {
            p = index($0, "\"content\":\"")
            if (p > 0) {
                after = p + 11  # length of "content":"
                fc = substr($0, after, 1)
                if (fc != "[" && fc != "{") {
                    text = json_str(after)
                    # Skip system messages
                    if (text ~ /^\[Request interrupted/ || text ~ /^<command-/ || \
                        text ~ /^Continue from where/ || text ~ /^This session is being continued/)
                        next
                    if (text != "") role = "User"
                }
            }
        }

        # ── Assistant text: "type":"text","text":"<string>" ──
        if (role == "" && index($0, "\"role\":\"assistant\"") && index($0, "\"type\":\"text\"")) {
            p = index($0, "\"type\":\"text\",\"text\":\"")
            if (p > 0) {
                after = p + 22  # length of "type":"text","text":"
                text = json_str(after)
                if (text != "") role = "Assistant"
            }
        }

        if (role != "" && text != "") {
            buf[++n] = "[" role "]: " text "\n"
        }
    }

    END {
        start = n - keep + 1
        if (start < 1) start = 1
        for (i = start; i <= n; i++) print buf[i]
    }
    '
}

# ── sliding window context compression ───────────────────────────────
# Progressive disclosure: recent rounds get full text, older ones get
# increasingly compressed. Keeps total under a character budget.
#
# Input:  raw context lines from extract_context (pairs of [User]/[Assistant])
# Output: compressed context fitting within budget
#
# Tiers (from newest to oldest):
#   Tier 1 (newest 2 rounds): full text, up to 300 chars/msg
#   Tier 2 (round 3):         light compress, ~150 chars/msg
#   Tier 3 (rounds 4-5):      summary, ~60 chars/msg
#
# If over budget, shrink tier sizes until it fits.
compress_context() {
    local budget="${1:-3000}"
    local raw_context="$2"

    [[ -z "$raw_context" ]] && return

    # Split into messages (separated by blank lines)
    local -a msgs=()
    local current=""
    while IFS= read -r line; do
        if [[ -z "$line" && -n "$current" ]]; then
            msgs+=("$current")
            current=""
        elif [[ -n "$line" ]]; then
            if [[ -n "$current" ]]; then
                current="$current $line"
            else
                current="$line"
            fi
        fi
    done <<< "$raw_context"
    [[ -n "$current" ]] && msgs+=("$current")

    local total=${#msgs[@]}
    [[ "$total" -eq 0 ]] && return

    # Tier thresholds (chars per message)
    local t1_len=300  # newest 2 rounds (4 msgs)
    local t2_len=150  # round 3 (2 msgs)
    local t3_len=60   # rounds 4-5 (4 msgs)

    # Build compressed output, try to fit within budget
    local attempt
    for attempt in 1 2 3 4; do
        local result=""
        local i
        for (( i=0; i<total; i++ )); do
            local msg="${msgs[$i]}"
            # Distance from end: 0=newest
            local dist=$(( total - 1 - i ))
            local max_len

            if [[ $dist -lt 4 ]]; then
                max_len=$t1_len   # tier 1: newest ~2 rounds
            elif [[ $dist -lt 6 ]]; then
                max_len=$t2_len   # tier 2: round 3
            else
                max_len=$t3_len   # tier 3: oldest
            fi

            # Truncate if needed
            if [[ ${#msg} -gt $max_len ]]; then
                msg="${msg:0:$max_len}..."
            fi
            result="${result}${msg}
"
        done

        # Check budget
        if [[ ${#result} -le $budget ]]; then
            printf '%s' "$result"
            return
        fi

        # Over budget: shrink all tiers
        t1_len=$(( t1_len * 2 / 3 ))
        t2_len=$(( t2_len * 2 / 3 ))
        t3_len=$(( t3_len * 2 / 3 ))
    done

    # Last resort: just truncate the whole thing
    printf '%s' "${result:0:$budget}"
}

# ── read MEMORY.md ────────────────────────────────────────────────────
read_memory() {
    local proj_dir="$1"
    local mem_file="$proj_dir/memory/MEMORY.md"
    if [[ -f "$mem_file" ]]; then
        cat "$mem_file"
    else
        echo "(no memory found)"
    fi
}

# ── language detection (UTF-8 byte patterns) ──────────────────────────
detect_lang() {
    local text="$1"
    if [[ -n "$LANG_OVERRIDE" && "$LANG_OVERRIDE" != "auto" ]]; then
        echo "$LANG_OVERRIDE"; return
    fi
    if printf '%s' "$text" | od -An -tx1 | grep -qE 'e3 (8[1-3])' 2>/dev/null; then
        echo "ja"; return
    fi
    if printf '%s' "$text" | LC_ALL=C grep -qc $'[\xea-\xed]' 2>/dev/null; then
        echo "ko"; return
    fi
    if printf '%s' "$text" | LC_ALL=C grep -qc $'[\xe4-\xe9]' 2>/dev/null; then
        echo "zh"; return
    fi
    echo "en"
}

lang_instruction() {
    case "$1" in
        zh) echo "Reply in Chinese." ;;
        en) echo "Reply in English." ;;
        ja) echo "Reply in Japanese." ;;
        ko) echo "Reply in Korean." ;;
        *)  echo "Reply in $1." ;;
    esac
}

# ── terminal width (always fresh, adapts to resize) ─────────────────
# tput cols / $COLUMNS are stale in non-interactive scripts on Windows.
# On Windows: use mode.com con (200ms, returns real current width).
# On others: tput cols works fine after SIGWINCH.
term_width() {
    local w=0

    # Windows: mode.com con → line 5 has column count
    if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]]; then
        w=$(mode.com con 2>/dev/null | sed -n '5p' | tr -dc '0-9') || w=0
    fi

    # Fallback: tput / COLUMNS
    [[ "$w" -lt 10 ]] && w=$(tput cols 2>/dev/null) || true
    [[ "$w" -lt 10 ]] && w="${COLUMNS:-50}"
    [[ "$w" -lt 10 ]] && w=50
    echo "$w"
}

# ── banner ────────────────────────────────────────────────────────────
print_banner() {
    local claude="$1" proj="$2"
    local w; w=$(term_width)

    echo ""
    if [[ "$w" -ge 30 ]]; then
        # Box banner (needs >=30 cols)
        local iw=$((w - 2))
        center_pad() {
            local text="$1" total="$2"
            local tlen=${#text}
            [[ $tlen -gt $total ]] && text="${text:0:$total}" && tlen=$total
            local pad=$(( (total - tlen) / 2 ))
            local rpad=$(( total - tlen - pad ))
            printf '%*s%s%*s' "$pad" "" "$text" "$rpad" ""
        }
        printf '\033[1;36m'
        printf '%s' "╔"; printf '═%.0s' $(seq 1 "$iw"); printf '╗\n'
        printf '║'; center_pad "Explain Pane" "$iw"; printf '║\n'
        printf '║'; center_pad "Incognito" "$iw"; printf '║\n'
        printf '%s' "╚"; printf '═%.0s' $(seq 1 "$iw"); printf '╝'
        printf '\033[0m\n'
    else
        # Narrow fallback
        printf '\033[1;36m── Explain Pane ──\033[0m\n'
    fi
    echo ""
    printf '  \033[1mModel\033[0m  %s\n' "$MODEL"
    printf '  \033[1mLang\033[0m   %s\n' "${LANG_OVERRIDE:-auto}"
    [[ -n "$proj" ]] && printf '  \033[1mProj\033[0m   %s\n' "$(basename "$proj")"
    echo ""
    printf '  \033[2mEnter twice to send | exit | r | lang:<code>\033[0m\n'
    echo ""
}

# ── cleanup ───────────────────────────────────────────────────────────
cleanup() {
    rm -f "$PID_FILE"
    printf '\n\033[2m  Explain pane closed.\033[0m\n'
}
trap cleanup EXIT INT TERM

# ── main ──────────────────────────────────────────────────────────────
main() {
    setup_encoding
    setup_git_bash_env
    mkdir -p "$WATCH_DIR"

    echo $$ > "$PID_FILE"

    local claude; claude=$(find_claude)
    local proj_dir; proj_dir=$(find_project_dir)

    print_banner "$claude" "$proj_dir"

    # ── Context cache with sliding window cycle ──────────────────────────
    # First question:  full extract + compress → cached as "base context"
    # Next 1-3 questions: reuse base + append local Q&A history (cheap)
    # After 3 questions: re-extract + compress, reset counter
    local ctx_cache=""          # compressed main-window context (base)
    local local_history=""      # Q&A pairs accumulated since last refresh
    local questions_since_refresh=0
    local CTX_REFRESH_INTERVAL=3  # re-compress every N questions
    local memory_cache=""

    refresh_context() {
        local raw_ctx; raw_ctx=$(extract_context "$proj_dir" "$CONTEXT_ROUNDS")
        ctx_cache=$(compress_context 3000 "$raw_ctx")
        memory_cache=$(read_memory "$proj_dir")
        local_history=""
        questions_since_refresh=0
    }

    # ── ask: send one question to claude ────────────────────────────────
    ask_claude() {
        local question="$1"
        local t0 t1 t2 t3

        # Language: detect once, lock for session
        if [[ -z "$SESSION_LANG" ]]; then
            SESSION_LANG=$(detect_lang "$question")
        fi
        local instruction; instruction=$(lang_instruction "$SESSION_LANG")

        t0=$(date +%s)

        # Sliding window cycle: refresh or reuse cache
        if [[ -z "$ctx_cache" ]] || [[ $questions_since_refresh -ge $CTX_REFRESH_INTERVAL ]]; then
            refresh_context
        fi
        t1=$(date +%s)

        # Build context: base (compressed main window) + local Q&A history
        local full_context="$ctx_cache"
        if [[ -n "$local_history" ]]; then
            full_context="${full_context}

Side-pane conversation since last context refresh:
${local_history}"
        fi
        t2=$(date +%s)

        # Build prompt — plain text output, no markdown
        local prompt
        prompt="You are a concise code explanation assistant. ${instruction}
This is an incognito side pane in a terminal. Do NOT suggest writing to memory or saving anything.

IMPORTANT formatting rules (terminal cannot render markdown):
- Do NOT use markdown: no **, no ## headings, no \`backticks\`, no bullet * or -
- Use plain text only. Use CAPS or indentation for emphasis.
- For code, just indent with 4 spaces. No fenced code blocks.
- Use numbered lists (1. 2. 3.) or plain dashes for lists.
- Keep it concise and readable in a narrow terminal.

Main window context (last ${CONTEXT_ROUNDS} rounds, compressed):
${full_context}

Project memory:
${memory_cache}

Question:
${question}

Give a clear, focused explanation based on the context above."

        # Prompt size (rough char count)
        local prompt_len=${#prompt}

        local w; w=$(term_width)
        printf '\n\033[2m%s\033[0m\n' "$(printf '─%.0s' $(seq 1 "$w"))"

        # Timing: show prep stats + cache status
        local cache_tag="fresh"
        [[ $questions_since_refresh -gt 0 ]] && cache_tag="cached+${questions_since_refresh}"
        printf '\033[2m  [prep:%ds %d chars %s %s]\033[0m\n' \
            "$(( t2 - t0 ))" "$prompt_len" "$MODEL" "$cache_tag"

        # Capture reply for local history
        local reply_file; reply_file=$(mktemp "$WATCH_DIR/explain-reply.XXXXXX" 2>/dev/null || echo "$WATCH_DIR/explain-reply.tmp")
        "$claude" -p "$prompt" --model "$MODEL" --no-session-persistence --max-turns 1 2>/dev/null | tee "$reply_file" || {
            echo "  Error calling claude. Check your setup."
        }
        t3=$(date +%s)

        # Accumulate local history (truncated)
        local reply_text
        reply_text=$(head -c 300 "$reply_file" 2>/dev/null | tr '\n' ' ')
        rm -f "$reply_file"
        local_history="${local_history}[Q]: ${question:0:200}
[A]: ${reply_text}
"
        questions_since_refresh=$(( questions_since_refresh + 1 ))

        # Fresh width for closing separator (terminal may have resized)
        w=$(term_width)
        printf '\033[2m%s\033[0m\n' "$(printf '─%.0s' $(seq 1 "$w"))"
        printf '\033[2m  [reply:%ds total:%ds %s]\033[0m\n\n' "$(( t3 - t2 ))" "$(( t3 - t0 ))" "$cache_tag"
    }

    # ── Inject file: initial question + questions from main window ──────
    local inject_file="$WATCH_DIR/explain-inject.txt"

    # Check and process injected question (from another /explain-e call)
    _check_inject() {
        [[ -f "$inject_file" ]] || return 1
        local q; q=$(cat "$inject_file" 2>/dev/null); rm -f "$inject_file"
        [[ -n "$q" ]] || return 1
        printf '\033[7m %s \033[0m\n' "$q"
        ask_claude "$q"
        return 0
    }

    # ── Main interactive loop ────────────────────────────────────────────
    # Submit on empty line (double-Enter). This lets pasted text with
    # trailing newlines be appended to before sending.
    while true; do
        # Check for injected question before prompting
        _check_inject && continue

        printf '\033[7m>\033[0m '
        local lines=""
        local line=""

        # Wait for first line (with timeout to poll inject file)
        while true; do
            if read -r -t 2 line; then
                break  # got input
            elif [[ $? -gt 128 ]]; then
                # Timeout — check for injected question
                _check_inject && line="__injected__" && break
                continue
            else
                lines="exit"; break  # EOF
            fi
        done
        [[ "$line" == "__injected__" ]] && continue

        # First line: check for single-line commands
        case "$line" in
            exit|quit|q) break ;;
            refresh|r)
                proj_dir=$(find_project_dir)
                ctx_cache=""
                local_history=""
                questions_since_refresh=0
                echo "  Context cache cleared. Will re-extract on next question."
                continue ;;
            lang:*)
                SESSION_LANG="${line#lang:}"
                SESSION_LANG="${SESSION_LANG# }"
                echo "  Language locked to: $SESSION_LANG"
                continue ;;
            "") continue ;;  # ignore blank
        esac

        lines="$line"
        printf '\033[2m  (blank line to send)\033[0m\n'

        # Read additional lines until blank line (double-Enter = submit)
        while true; do
            if read -r -t 2 line; then
                if [[ -z "$line" ]]; then
                    break  # blank line → submit
                fi
                lines="${lines} ${line}"
            elif [[ $? -gt 128 ]]; then
                # Timeout — check inject; if found, send current + inject separately
                if _check_inject; then
                    break  # also submit what we have so far
                fi
                continue
            else
                break  # EOF
            fi
        done

        [[ -z "$lines" ]] && continue
        ask_claude "$lines"
    done
}

main
