#!/usr/bin/env bash
# push-to-github.sh — Push exo-cuda to public GitHub fork, excluding sensitive files.
#
# Reads exclusion patterns from push-to-github.exclude (same directory).
# Creates a single-clean-commit clone of main without those files,
# then force-pushes to the 'fork' remote.
#
# Usage:
#   ./scripts/push-to-github.sh "commit message"
#   ./scripts/push-to-github.sh "feat: add frobnicator" --dry-run
#   ./scripts/push-to-github.sh -h
#   ./scripts/push2github "fix: resolve OOM"
#
# Symlink alias (at repo root):
#   ln -s scripts/push-to-github.sh push2github
#
set -euo pipefail

# --- Constants ---
FORK_REMOTE="fork"
FORK_BRANCH="fork_$(date +%Y%m%d_%H%M%S)"
DEFAULT_FORK_URL="git@github.com:grangec/exo-cuda.git"
DEFAULT_GITHUB_NAME="grangec"
DEFAULT_GITHUB_EMAIL="grangec@users.noreply.github.com"

# Resolve script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONF_FILE="$SCRIPT_DIR/push-to-github.exclude"

# --- Help ---
usage() {
  cat <<'HELP'
push-to-github.sh — Push exo-cuda to public GitHub fork, excluding sensitive files.

Reads exclusion patterns from push-to-github.exclude (same directory).
Creates a single-clean-commit clone of main without those files,
then force-pushes to the 'fork' remote.

Usage:
  ./scripts/push-to-github.sh "commit message"
  ./scripts/push-to-github.sh "feat: add frobnicator" --dry-run
  ./scripts/push-to-github.sh -h
  ./scripts/push2github "fix: resolve OOM on node-b"

Symlink alias (at repo root):
  ln -s scripts/push-to-github.sh push2github

HELP
  exit 0
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

if [ $# -lt 1 ]; then
  echo "Error: missing commit message" >&2
  echo "Usage: $0 \"commit message\" [--dry-run]" >&2
  exit 1
fi
MESSAGE="$1"
DRY_RUN=false
if [ "${2:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# --- Load exclusion patterns from conf file ---
if [ ! -f "$CONF_FILE" ]; then
  echo "Error: config file not found: $CONF_FILE" >&2
  exit 1
fi

# Build exclusion patterns for grep -E.
# Each line becomes a regex alternation matching a path component.
# Pattern: match either start-of-line or a / before the filename,
# then the filename, then end-of-line or / (for directories).
EXCLUDE_PATTERN="("
FIRST=true
while IFS= read -r line || [ -n "$line" ]; do
  # Strip leading/trailing whitespace, skip blank/comment lines
  trimmed="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$trimmed" ] && continue
  echo "$trimmed" | grep -q '^#' && continue

  # Escape dots for regex; remove trailing / (handled by anchor)
  escaped="$(echo "$trimmed" | sed 's/\./\\./g; s#/$##')"
  if $FIRST; then
    EXCLUDE_PATTERN="${EXCLUDE_PATTERN}(^|/)${escaped}(\$|/)"
    FIRST=false
  else
    EXCLUDE_PATTERN="${EXCLUDE_PATTERN}|(^|/)${escaped}(\$|/)"
  fi
done < "$CONF_FILE"
EXCLUDE_PATTERN="${EXCLUDE_PATTERN})"

# --- Pre-flight checks ---
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "Error: must be on 'main' branch (currently on '$BRANCH')" >&2
  exit 1
fi

FORK_URL=$(git remote get-url "$FORK_REMOTE" 2>/dev/null) || {
  echo "Remote '$FORK_REMOTE' not found. Creating it with default URL..."
  echo "  $DEFAULT_FORK_URL"
  git remote add "$FORK_REMOTE" "$DEFAULT_FORK_URL"
  FORK_URL="$DEFAULT_FORK_URL"
}

if ! git diff --quiet; then
  echo "Error: you have unstaged changes. Commit or stash them first." >&2
  exit 1
fi

# --- Build clean tree on top of fork/main ---
GITDIR=$(pwd)/.git
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Clone fork/main into tmpdir (shallow, single branch)
git clone --depth=1 --branch=main "$FORK_URL" "$TMPDIR" 2>/dev/null || {
  echo "Warning: could not clone fork/main. Creating empty repo instead."
  git init "$TMPDIR"
}

cd "$TMPDIR"
git config user.name "$DEFAULT_GITHUB_NAME"
git config user.email "$DEFAULT_GITHUB_EMAIL"

# Remove all tracked files (keep .git)
git rm -rfq --cached . 2>/dev/null || true
rm -rf -- * .github .circleci .gitattributes .gitignore .style.yapf 2>/dev/null || true

# Extract only non-excluded files from HEAD of parent repo
git --git-dir="$GITDIR" ls-tree -r HEAD --name-only |
  grep -v -E "$EXCLUDE_PATTERN" |
  while IFS= read -r f; do
    mkdir -p "$(dirname "$f")"
    git --git-dir="$GITDIR" show HEAD:"$f" > "$f"
  done

# Commit on top of fork/main history
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit. Nothing to push."
  exit 0
fi
git commit -m "$MESSAGE"

# --- Push or dry-run ---
if $DRY_RUN; then
  echo "=== DRY-RUN ==="
  echo "Clean repo at $TMPDIR"
  git log --oneline -3
  echo "Exclusions from: $CONF_FILE"
  echo "Would push to $FORK_REMOTE/$FORK_BRANCH ($FORK_URL)"
  echo "===================="
  exit 0
fi

git push origin main:"$FORK_BRANCH"
echo "Done. Pushed single commit to $FORK_REMOTE/$FORK_BRANCH"
