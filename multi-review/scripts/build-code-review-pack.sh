#!/usr/bin/env bash
# Build a lightweight code-mode review pack for multi-review.
#
# The pack is repository-native: external reviewers get the project root,
# scope, changed files, repo guidance, and a prompt instructing them to inspect
# the local repository with read-only commands. The full diff is never stored
# in the final pack or pasted into Codex/Claude prompts. A trimmed diff is
# produced only as optional supplemental input for CLIs that may not read local
# files reliably.
#
# Usage:
#   build-code-review-pack.sh [base-ref]
#
#   [base-ref]  Base ref for branch comparison (default: main). Ignored when
#               the working tree has no branch to compare against.
#
# No environment variables are read. The project root is the current git
# repository, the scope is auto-detected, and output is always written to
# /tmp/multi-review.

set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

WORKDIR="/tmp/multi-review"
TRIM_DIFF_THRESHOLD=51200
BASE="${1:-main}"

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
SCOPE_MODE=""

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
WORKDIR=$(cd "$WORKDIR" && pwd)
cd "$PROJECT_ROOT"

FULL_DIFF_FILE="$WORKDIR/.diff-full.tmp"

echo "code" > "$WORKDIR/mode.txt"
echo "$PROJECT_ROOT" > "$WORKDIR/project_root.txt"
echo "$PROJECT_ROOT" > "$WORKDIR/context_root.txt"

current_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

resolve_base_ref() {
  if git rev-parse --verify "$BASE^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  if git rev-parse --verify "origin/$BASE^{commit}" >/dev/null 2>&1; then
    BASE="origin/$BASE"
  fi
}

base_ref_exists() {
  git rev-parse --verify "$BASE^{commit}" >/dev/null 2>&1
}

has_uncommitted() {
  ! git diff --quiet HEAD 2>/dev/null || \
    [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]
}

autodetect_scope_mode() {
  local cur
  cur=$(current_branch)
  if [ -z "$cur" ] || [ "$cur" = "$BASE" ] || ! base_ref_exists; then
    echo "working-tree"
    return
  fi
  if has_uncommitted; then
    echo "branch-with-uncommitted"
  else
    echo "branch"
  fi
}

resolve_base_ref

SCOPE_MODE=$(autodetect_scope_mode)

echo "$SCOPE_MODE" > "$WORKDIR/scope_mode.txt"

write_agents_excerpts() {
  : > "$WORKDIR/agents_excerpts.md"

  find "$PROJECT_ROOT" \
      \( -path '*/node_modules' -o -path '*/.venv' -o -path '*/venv' \
         -o -path '*/vendor' -o -path '*/.git' -o -path '*/dist' \
         -o -path '*/build' -o -path '*/.next' -o -path '*/.nuxt' \
         -o -path '*/target' -o -path '*/__pycache__' \) -prune -o \
      \( -name AGENTS.md -o -name CLAUDE.md -o -name GEMINI.md \) -print 2>/dev/null \
    | sort \
    | while IFS= read -r file; do
      [ -f "$file" ] || continue
      {
        echo
        echo "## $file"
        sed -n '1,220p' "$file"
      } >> "$WORKDIR/agents_excerpts.md"
    done
}

is_binary() {
  local file="$1"
  [ -f "$file" ] || return 0
  if command -v file >/dev/null 2>&1; then
    case "$(file --mime-encoding -b "$file" 2>/dev/null)" in
      binary) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 1
}

dump_untracked_text() {
  local file="$1"
  local rc=0
  git diff --no-index --no-color -- /dev/null "$file" 2>/dev/null || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo
    echo "diff --git a/$file b/$file"
    echo "--- /dev/null"
    echo "+++ b/$file"
    sed -n '1,260p' "$file" | sed 's/^/+/'
  fi
}

write_untracked_files() {
  local untracked_list="$WORKDIR/untracked_files.txt"
  : > "$untracked_list"

  git ls-files --others --exclude-standard \
    | while IFS= read -r file; do
      case "$PROJECT_ROOT/$file" in
        "$WORKDIR"/*) ;;
        *) echo "$file" ;;
      esac
    done > "$untracked_list"

  if [ ! -s "$untracked_list" ]; then
    return 0
  fi

  cat "$untracked_list" >> "$WORKDIR/changed_files.txt"
  sort -u "$WORKDIR/changed_files.txt" -o "$WORKDIR/changed_files.txt"

  {
    echo
    echo "--- UNTRACKED FILES ---"
    while IFS= read -r file; do
      [ -f "$file" ] || continue
      if is_binary "$file"; then
        echo
        echo "diff --git a/$file b/$file"
        echo "+++ b/$file"
        echo "(binary file, $(wc -c < "$file" | tr -d ' ') bytes - content omitted)"
        continue
      fi
      dump_untracked_text "$file"
    done < "$untracked_list"
  } >> "$FULL_DIFF_FILE"
}

redact_file() {
  local target="$1"
  [ -f "$target" ] || return 0
  if ! command -v perl >/dev/null 2>&1; then
    echo "WARNING: perl not found - secret redaction skipped for $(basename "$target")" >&2
    return 0
  fi
  perl -0pi -e '
    s/(api[_-]?key\s*[:=]\s*)["'\''"]?[^"'\''\s]+/${1}[REDACTED]/ig;
    s/(secret\s*[:=]\s*)["'\''"]?[^"'\''\s]+/${1}[REDACTED]/ig;
    s/(\btoken\s*[:=]\s*)["'\''"]?[^"'\''\s]+/${1}[REDACTED]/ig;
    s/(password\s*[:=]\s*)["'\''"]?[^"'\''\s]+/${1}[REDACTED]/ig;
    s/(authorization:\s*bearer\s+)[A-Za-z0-9._~+\/=-]+/${1}[REDACTED]/ig;
    s/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED-ANTHROPIC]/g;
    s/sk-[A-Za-z0-9_-]{12,}/[REDACTED-OPENAI]/g;
    s/AIza[A-Za-z0-9_-]{20,}/[REDACTED-GOOGLE]/g;
    s/ghp_[A-Za-z0-9_]{20,}/[REDACTED-GITHUB-PAT]/g;
    s/github_pat_[A-Za-z0-9_]{20,}/[REDACTED-GITHUB-PAT]/g;
    s/glpat-[A-Za-z0-9_-]{20,}/[REDACTED-GITLAB-PAT]/g;
    s/xox[abp]-[A-Za-z0-9-]{10,}/[REDACTED-SLACK]/g;
    s/(?:sk|rk|pk)_live_[A-Za-z0-9]{12,}/[REDACTED-STRIPE]/g;
    s/AKIA[0-9A-Z]{16}/[REDACTED-AWS-ACCESS-KEY]/g;
    s/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[REDACTED-JWT]/g;
    s{((?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis|rediss|amqp|amqps)://)[^:\s/]+:[^@\s]+@}{${1}[REDACTED]:[REDACTED]@}g;
    s/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/[REDACTED-PRIVATE-KEY]/g;
  ' "$target"
}

write_branch_scope() {
  echo "$BASE...HEAD" > "$WORKDIR/base.txt"
  git diff "$BASE...HEAD" --name-only | sort -u > "$WORKDIR/changed_files.txt"
  git diff "$BASE...HEAD" > "$FULL_DIFF_FILE"
}

write_branch_with_uncommitted_scope() {
  echo "$BASE...HEAD (plus uncommitted)" > "$WORKDIR/base.txt"
  {
    git diff "$BASE...HEAD" --name-only
    git diff HEAD --name-only
  } | sort -u > "$WORKDIR/changed_files.txt"

  {
    git diff "$BASE...HEAD"
    if ! git diff --quiet HEAD 2>/dev/null; then
      echo
      echo "--- UNCOMMITTED CHANGES ON TOP OF HEAD ---"
      git diff HEAD
    fi
  } > "$FULL_DIFF_FILE"

  write_untracked_files
}

working_tree_diff_target() {
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "HEAD"
  else
    git hash-object -t tree /dev/null
  fi
}

write_working_tree_scope() {
  echo "(none - working tree only)" > "$WORKDIR/base.txt"
  local target
  target=$(working_tree_diff_target)
  git diff "$target" --name-only | sort -u > "$WORKDIR/changed_files.txt"
  git diff "$target" > "$FULL_DIFF_FILE"
  write_untracked_files
}

write_trimmed_diff() {
  local diff_size
  local working_tree_target=""
  diff_size=$(wc -c < "$FULL_DIFF_FILE")
  echo "$diff_size" > "$WORKDIR/diff_size.txt"

  if [ "$diff_size" -lt "$TRIM_DIFF_THRESHOLD" ]; then
    return 0
  fi

  {
    echo "Scoped diff is large: $diff_size bytes (threshold: $TRIM_DIFF_THRESHOLD)"
    echo
    echo "--- Scoped diff stat ---"
    case "$SCOPE_MODE" in
      branch) git diff "$BASE...HEAD" --stat ;;
      branch-with-uncommitted)
        git diff "$BASE...HEAD" --stat
        git diff HEAD --stat
        ;;
      working-tree)
        working_tree_target=$(working_tree_diff_target)
        git diff "$working_tree_target" --stat
        ;;
    esac
    echo
    echo "--- Focused excerpts from top changed files ---"
  } > "$WORKDIR/diff-trimmed.txt"

  local numstat_file="$WORKDIR/numstat.txt"
  case "$SCOPE_MODE" in
    branch) git diff "$BASE...HEAD" --numstat > "$numstat_file" ;;
    branch-with-uncommitted)
      {
        git diff "$BASE...HEAD" --numstat
        git diff HEAD --numstat
      } > "$numstat_file"
      ;;
    working-tree)
      [ -n "$working_tree_target" ] || working_tree_target=$(working_tree_diff_target)
      git diff "$working_tree_target" --numstat > "$numstat_file"
      ;;
  esac

  sort -k1,1nr -k2,2nr "$numstat_file" \
    | head -10 \
    | cut -f3- \
    | while IFS= read -r file; do
      [ -n "$file" ] || continue
      {
        echo
        echo "--- $file ---"
        case "$SCOPE_MODE" in
          branch) git diff "$BASE...HEAD" -- "$file" ;;
          branch-with-uncommitted)
            git diff "$BASE...HEAD" -- "$file"
            git diff HEAD -- "$file"
            ;;
          working-tree) git diff "$working_tree_target" -- "$file" ;;
        esac
      } >> "$WORKDIR/diff-trimmed.txt"
    done
}

default_review_focus() {
  cat <<'EOF'
Bugs, security vulnerabilities, performance regressions, broken cross-file
contracts, test gaps proportional to risk, docs/contracts drift, and
unnecessary complexity introduced by the reviewed scope.
EOF
}

write_prompt() {
  {
    echo "You are a senior code reviewer."
    echo
    echo "PROJECT ROOT: $(cat "$WORKDIR/project_root.txt")"
    echo "SCOPE MODE: $(cat "$WORKDIR/scope_mode.txt")"
    echo "BASE: $(cat "$WORKDIR/base.txt")"
    echo
    echo "CHANGED FILES:"
    cat "$WORKDIR/changed_files.txt"
    echo
    echo "APPLICABLE PROJECT GUIDANCE:"
    cat "$WORKDIR/agents_excerpts.md"
    echo
    echo "REVIEW SCOPE:"
    echo "Review the requested scope from the local repository. Use read-only commands only. Do not edit files, run formatters, stage, commit, push, or change the working tree."
    echo "Do not invoke the multi-review skill, other skills, subagents, or additional external reviewers. You are one external reviewer inside an already-running multi-review workflow."
    echo
    echo "Use these scope rules:"
    echo "- branch: review BASE...HEAD"
    echo "- branch-with-uncommitted: review BASE...HEAD plus uncommitted and untracked files"
    echo "- working-tree: review uncommitted and untracked files only"
    echo
    echo "Start by running the appropriate read-only git commands for the scope:"
    echo "- git status --short"
    echo "- git diff --stat"
    echo "- git diff --name-only"
    echo "- git diff BASE...HEAD --stat and git diff BASE...HEAD --name-only when a base ref is present"
    echo
    echo "Then open touched files and relevant callers, tests, migrations, generated clients, shared types, config, and public contracts before reporting a non-trivial finding."
    echo
    echo "REVIEW FOCUS:"
    default_review_focus
    echo
    echo "REPORTING FORMAT:"
    echo "For each finding, output one block:"
    echo
    echo "ID: EXT-N"
    echo "Severity: Critical | High | Medium | Low"
    echo "Confidence: 0-100"
    echo "Area: code | security | tests | performance | compatibility | docs-contracts | simplification"
    echo "File:line or missing artifact:"
    echo "Impact:"
    echo "Evidence:"
    echo "Suggested fix or proof gap:"
    echo
    echo "RULES:"
    echo "- Do not report style nitpicks, formatter-only issues, or speculative issues below confidence 80."
    echo "- Do not inflate severity."
    echo "- Do not propose new abstractions, defensive validation at internal boundaries, compatibility shims, or broad rewrites unless the code evidence requires them and project guidance allows them."
    echo "- If you cannot verify a finding from code, mark it SPECULATIVE and explain the proof gap."
    echo "- Prefer concrete repository evidence over generalized best-practice advice."
    echo "- Output findings only, no preamble and no closing summary."
  } > "$WORKDIR/prompt.md"
}

case "$SCOPE_MODE" in
  branch) write_branch_scope ;;
  branch-with-uncommitted) write_branch_with_uncommitted_scope ;;
  working-tree) write_working_tree_scope ;;
esac

write_agents_excerpts
write_trimmed_diff
write_prompt

redact_file "$WORKDIR/diff-trimmed.txt"
redact_file "$WORKDIR/prompt.md"
rm -f "$FULL_DIFF_FILE"

echo "Code review pack written to $WORKDIR (mode=$SCOPE_MODE, base=$(cat "$WORKDIR/base.txt"))"
