#!/bin/sh

# Simple script to install git pre-commit hook
# Copies the hook script to .git/hooks/pre-commit
#
# This script is automatically run via postinstall when you run 'npm install'
# It ensures the hook is installed for all developers cloning the repo.
#
# This script is designed to be CI-safe and will never fail the build.

# Wrap everything in error handling to ensure we never fail
(
  # Use sh instead of bash for maximum compatibility
  # Don't exit on error - we want to gracefully handle CI environments
  set +e

  # Check if we're in a CI environment (GitHub Actions sets CI=true)
  if [ "${CI}" = "true" ] || [ -n "${GITHUB_ACTIONS}" ] || [ -n "${CONTINUOUS_INTEGRATION}" ]; then
    # Skip hook installation in CI - it's not needed and can cause issues
    exit 0
  fi

  # Only install if .git exists (we're in a git repo)
  if [ ! -d ".git" ]; then
    # Silently exit if not in a git repo (e.g., npm pack scenario)
    exit 0
  fi

  # Verify hook source exists
  if [ ! -f "scripts/pre-commit-check.sh" ]; then
    # Silently exit if script doesn't exist (e.g., during npm pack)
    exit 0
  fi

  # Install the hook (suppress errors if mkdir/cp/chmod fail)
  mkdir -p .git/hooks 2>/dev/null || true
  cp scripts/pre-commit-check.sh .git/hooks/pre-commit 2>/dev/null || true
  chmod +x .git/hooks/pre-commit 2>/dev/null || true

  # Only print if we actually installed something (avoid noise in CI)
  if [ -f ".git/hooks/pre-commit" ]; then
    echo "? Pre-commit hook installed"
  fi
) || true

# Always exit successfully to avoid breaking npm install/ci
exit 0
