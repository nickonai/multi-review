#!/usr/bin/env bash
# Build a lightweight text-mode review pack for multi-review.
#
# Reviewers get absolute file paths and a prompt instructing them to open the
# files locally. The pack does not concatenate full artifacts. A capped excerpt
# is produced only as supplemental input for CLIs that may not read local files
# reliably.
#
# Usage:
#   build-text-review-pack.sh <content-type> <file> [<file>...]
#
#   <content-type> is one of: article spec plan prompt legal marketing generic
#
# No environment variables are read. Output is always written to
# /tmp/multi-review.

set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

WORKDIR="/tmp/multi-review"
TEXT_EXCERPT_LINES=220

if [ "$#" -lt 2 ]; then
  echo "Usage: build-text-review-pack.sh <content-type> <file> [<file>...]" >&2
  echo "  <content-type>: article | spec | plan | prompt | legal | marketing | generic" >&2
  exit 2
fi

CONTENT_TYPE="$1"
shift

case "$CONTENT_TYPE" in
  article|spec|plan|prompt|legal|marketing|generic) ;;
  *)
    echo "content-type must be one of: article spec plan prompt legal marketing generic (got: $CONTENT_TYPE)" >&2
    exit 2
    ;;
esac

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
WORKDIR=$(cd "$WORKDIR" && pwd)

echo "text" > "$WORKDIR/mode.txt"
echo "$CONTENT_TYPE" > "$WORKDIR/content_type.txt"

files_list="$WORKDIR/files.txt"
: > "$files_list"
for raw in "$@"; do
  f=$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -n "$f" ] || continue
  if [ ! -f "$f" ]; then
    echo "argument is not a regular file: $f" >&2
    exit 3
  fi
  abs=$(cd "$(dirname "$f")" && printf '%s/%s\n' "$(pwd)" "$(basename "$f")")
  echo "$abs" >> "$files_list"
done

if [ ! -s "$files_list" ]; then
  echo "no readable file was provided" >&2
  exit 2
fi

dirname "$(head -n1 "$files_list")" > "$WORKDIR/context_root.txt"

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

is_binary() {
  local file="$1"
  if command -v file >/dev/null 2>&1; then
    case "$(file --mime-encoding -b "$file" 2>/dev/null)" in
      binary) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 1
}

write_artifact_excerpt() {
  local excerpt="$WORKDIR/artifact-excerpt.txt"
  local total_size=0
  : > "$excerpt"

  while IFS= read -r f; do
    local size
    size=$(wc -c < "$f" | tr -d ' ')
    total_size=$((total_size + size))
    {
      echo "============================================================"
      echo "FILE: $f"
      echo "BYTES: $size"
      echo "EXCERPT: first $TEXT_EXCERPT_LINES lines"
      echo "============================================================"
      if is_binary "$f"; then
        echo "(binary file - content omitted)"
      else
        sed -n "1,${TEXT_EXCERPT_LINES}p" "$f"
      fi
      echo
    } >> "$excerpt"
  done < "$files_list"

  echo "$total_size" > "$WORKDIR/artifact_size.txt"
}

focus_for_content_type() {
  case "$CONTENT_TYPE" in
    article)
      cat <<'EOF'
Argument structure, factual accuracy, internal contradictions, audience fit,
pacing, section flow, missing context, unsupported claims, and places where
the author's voice slips into generic copy. Do not rewrite the voice.
EOF
      ;;
    spec)
      cat <<'EOF'
Missing requirements, contradictions, ambiguous requirements, untestable
acceptance criteria, unstated assumptions, missing failure modes, security and
privacy gaps, scalability concerns, and implicit out-of-scope dependencies.
EOF
      ;;
    plan)
      cat <<'EOF'
Missing steps, incorrect ordering, hidden dependencies, mismatched contracts,
missing tests, rollback gaps for risky changes, unrealistic effort, and tasks
that should be split or merged.
EOF
      ;;
    prompt)
      cat <<'EOF'
Ambiguity, missing failure-mode coverage, conflicting instructions, vague
triggers, missing examples for tricky cases, unnecessary verbosity, and
over-strict MUST/NEVER rules that fight reasonable user instructions.
EOF
      ;;
    legal)
      cat <<'EOF'
Risky or unenforceable clauses, ambiguous obligations, missing disclosures,
inconsistent definitions, contradictory rights/limits, jurisdiction gaps, and
unusually one-sided clauses. Flag legal risk; do not give legal advice.
EOF
      ;;
    marketing)
      cat <<'EOF'
Promise-vs-proof gaps, unclear CTA, audience-fit problems, claims needing
substantiation, CTA friction, missing objection handling, regulatory risk, and
anti-spam or channel compliance issues.
EOF
      ;;
    *)
      cat <<'EOF'
Clarity, completeness, internal consistency, audience fit, missing context,
factual or logical errors, structural problems, and failure to deliver on the
stated goal.
EOF
      ;;
  esac
}

write_prompt() {
  {
    echo "You are a senior independent reviewer."
    echo
    echo "ARTIFACT TYPE: $(cat "$WORKDIR/content_type.txt")"
    echo
    echo "FILES:"
    cat "$WORKDIR/files.txt"
    echo
    echo "REVIEW SCOPE:"
    echo "Open the files above locally and review their actual contents. Use read-only commands only. Do not edit files, run formatters, stage, commit, push, or change the working tree."
    echo "Do not invoke the multi-review skill, other skills, subagents, or additional external reviewers. You are one external reviewer inside an already-running multi-review workflow."
    echo "Verify quotes, line references, and cross-references against the files, not against memory or assumptions."
    echo
    echo "REVIEW FOCUS:"
    focus_for_content_type
    echo
    echo "REPORTING FORMAT:"
    echo "For each finding, output one block:"
    echo
    echo "ID: EXT-N"
    echo "Severity: Critical | High | Medium | Low"
    echo "Confidence: 0-100"
    echo "Area: clarity | correctness | completeness | structure | audience-fit | voice | accuracy | persuasion | legal-risk | ethics | accessibility | implementability"
    echo "Location: file basename:line, section heading, or short quote"
    echo "Impact:"
    echo "Evidence:"
    echo "Suggested fix or proof gap:"
    echo
    echo "RULES:"
    echo "- Do not propose a wholesale rewrite."
    echo "- Do not invent context, statistics, sources, or quotes that are not in the artifact."
    echo "- If you cannot verify a finding from the files, mark it SPECULATIVE and explain the proof gap."
    echo "- Do not flag stylistic preferences as High or Critical."
    echo "- Output findings only, no preamble and no closing summary."
  } > "$WORKDIR/prompt.md"
}

write_artifact_excerpt
write_prompt

redact_file "$WORKDIR/artifact-excerpt.txt"
redact_file "$WORKDIR/prompt.md"

echo "Text review pack written to $WORKDIR (content_type=$CONTENT_TYPE, files=$(wc -l < "$files_list" | tr -d ' '))"
