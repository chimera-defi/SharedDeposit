#!/bin/sh
# Pre-commit hook installer - CI-safe version
# This script NEVER fails, even if everything goes wrong

# Check if we're in CI and skip entirely
[ "${CI}" = "true" ] && exit 0
[ -n "${GITHUB_ACTIONS}" ] && exit 0
[ -n "${CONTINUOUS_INTEGRATION}" ] && exit 0

# Check if .git exists
[ ! -d ".git" ] && exit 0

# Check if source script exists
[ ! -f "scripts/pre-commit-check.sh" ] && exit 0

# Try to install (all errors ignored)
mkdir -p .git/hooks 2>/dev/null
cp scripts/pre-commit-check.sh .git/hooks/pre-commit 2>/dev/null
chmod +x .git/hooks/pre-commit 2>/dev/null

# Always succeed
exit 0
