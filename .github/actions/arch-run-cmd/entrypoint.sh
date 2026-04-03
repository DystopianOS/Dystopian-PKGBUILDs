#!/bin/bash

set -euo pipefail

# Error handling with context
trap 'echo "ERROR: Script failed on line $LINENO (command: $BASH_COMMAND)" >&2; exit 1' ERR

IS_GITHUB_ACTIONS="${GITHUB_ACTIONS:-false}"
IS_CI="${CI:-false}"

# Logging helpers — adapt to GitHub Actions vs standalone
_notice() { [[ "$IS_GITHUB_ACTIONS" == "true" ]] && echo "::notice::$*" || echo "==> $*"; }
_warn()   { [[ "$IS_GITHUB_ACTIONS" == "true" ]] && echo "::warning::$*" || echo "WARNING: $*" >&2; }
_group()  { [[ "$IS_GITHUB_ACTIONS" == "true" ]] && echo "::group::$*" || echo "--- $* ---"; }
_endgrp() { [[ "$IS_GITHUB_ACTIONS" == "true" ]] && echo "::endgroup::" || true; }

# ============================================================================
# Docker Container Path Setup
# ============================================================================
# GitHub Actions mounts host workspace at /github/workspace inside Docker
# container actions and sets GITHUB_WORKSPACE=/github/workspace automatically.
# Input env vars may contain host paths that don't exist in the container —
# use GITHUB_WORKSPACE as the canonical base and auto-discover directories.

_WS="${GITHUB_WORKSPACE:-/github/workspace}"

# Fallback if workspace directory doesn't exist (standalone docker run)
if [[ ! -d "$_WS" ]]; then
  _WS="/home/${USER:-runner}/work"
  [[ ! -d "$_WS" ]] && _WS="$(pwd)"
fi

# GH_TOKEN fallback to GITHUB_TOKEN (auto-set by GitHub inside containers)
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# Working directory: use input if it's a valid container path, else workspace
if [[ -n "${WORKING_DIR:-}" && -d "${WORKING_DIR:-}" ]]; then
  : # keep as-is
else
  WORKING_DIR="$_WS"
fi

# Docker action passes command as $1 (single arg via args:)
COMMAND="${1:-}"
shift || true

# Resolve GNUPGHOME: input path is a host path and won't exist in the
# container. Auto-discover .gnupg* directory under the mounted workspace.
if [[ -z "${GNUPGHOME:-}" || ! -d "${GNUPGHOME:-}" ]]; then
  found=$(find "$_WS" -maxdepth 1 -name '.gnupg*' -type d 2>/dev/null | head -1 || true)
  if [[ -n "$found" ]]; then
    export GNUPGHOME="$found"
  else
    export GNUPGHOME="${_WS}/.gnupg"
  fi
fi
export GNUPGHOME

# Resolve CCACHE_DIR
if [[ -z "${CCACHE_DIR:-}" || ! -d "${CCACHE_DIR:-}" ]]; then
  CCACHE_DIR="${WORKING_DIR}/.ccache"
fi
export CCACHE_DIR

# Preset GPG passphrase in agent cache if configured
if [[ -d "$GNUPGHOME" && -n "${GPG_KEY_ID:-}" && -n "${GPG_PASSPHRASE:-}" && "${PRESET_CACHE:-false}" == "true" ]]; then
  KEYGRIPS=$(gpg --batch --with-colons --list-secret-keys "$GPG_KEY_ID" 2>/dev/null | awk -F: '/^grp:/ {print $10}')
  while read -r GRIP; do
    [[ -z "$GRIP" ]] && continue
    printf '%s' "$GPG_PASSPHRASE" | /usr/lib/gnupg/gpg-preset-passphrase --preset "$GRIP" 2>/dev/null || true
  done <<< "$KEYGRIPS"
  _notice "Preset GPG passphrase in gpg-agent cache"
fi



if [[ ! -d "$WORKING_DIR" ]]; then
  if [[ "$(id -u)" == "0" ]]; then
    mkdir -p "$WORKING_DIR"
  else
    echo "WARNING: Cannot create work directory: $WORKING_DIR (no permission, not root)" >&2
    if [[ -d "/home/runner/work" && -w "/home/runner/work" ]]; then
      echo "Falling back to /home/runner/work as work directory." >&2
      WORKING_DIR="/home/runner/work"
    else
      echo "ERROR: /home/runner/work is not available or not writable. Aborting." >&2
      exit 1
    fi
  fi
fi
cd "$WORKING_DIR" || {
  echo "ERROR: Cannot change to work directory: $WORKING_DIR" >&2
  exit 1
}

# ============================================================================
# Environment Detection & Setup
# ============================================================================
export USER="${USER:-runner}"
export LANG=C.UTF-8
export TERM=xterm-256color
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"
export PACKAGER="${PACKAGER:-Unknown Packager <packager@example.com>}"
export GPGSIGN_KEY="${GPGSIGN_KEY:-}"

# Makepkg-specific optimization
export CCACHE_MAXSIZE="2G"

# In GitHub Actions, be less verbose (save logs, faster)
if [ "$IS_GITHUB_ACTIONS" = "true" ]; then
  export VERBOSE=0
  export QUIET=1
fi

# For GitHub Actions: reduce startup verbosity
if [ "$IS_GITHUB_ACTIONS" != "true" ] && [ $# -eq 0 ]; then
  echo "==> No arguments provided. Starting interactive shell for makepkg..."
fi

# Ensure work directory exists (create if needed for makepkg)
if ! [ -d "$WORKING_DIR" ]; then
  mkdir -p "$WORKING_DIR" || {
    echo "ERROR: Cannot create work directory: $WORKING_DIR" >&2
    exit 1
  }
fi

# Only show setup messages if not in automated CI
if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
  _notice "Initializing GPG environment at: $GNUPGHOME"
fi

# Initialize GPG if needed (idempotent)
if ! gpg --list-keys > /dev/null 2>&1; then
  gpg --list-keys > /dev/null 2>&1 || true
fi

# Check if keys are available (warn if empty)
if [[ -z "$(gpg --list-keys 2>/dev/null)" && "$IS_CI" = "true" ]]; then
  _warn "No GPG keys found in $GNUPGHOME - signing may fail"
fi



# ============================================================================
# Makepkg Configuration Check
# ============================================================================
if [ -f /etc/makepkg.conf ]; then
  if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
    _notice "makepkg.conf detected"
  fi

  # Verify PACKAGER is set (required for AUR) - warn quietly in CI
  if ! grep -q "^PACKAGER=" /etc/makepkg.conf; then
    _warn "PACKAGER not set in /etc/makepkg.conf - set via env var PACKAGER"
  fi
fi

# Show environment only if not in GitHub Actions
if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
  _group "Environment ready"
  echo "    User: $USER"
  echo "    Work directory: $(pwd)"
  echo "    GPG home: $GNUPGHOME"
  echo "    Make flags: $MAKEFLAGS"
  _endgrp
fi

# ============================================================================
# Command Execution with CI-Aware Logging and Timeout Support
# ============================================================================
_RUN_WITH_SUDO="${RUN_WITH_SUDO:-false}"
ENV_VARS=(
  "GNUPGHOME=$GNUPGHOME"
  "LANG=$LANG"
  "TERM=$TERM"
)

[[ -n "$MAKEFLAGS" ]] && ENV_VARS+=("MAKEFLAGS=$MAKEFLAGS")
[[ -n "$PACKAGER" ]] && ENV_VARS+=("PACKAGER=$PACKAGER")
[[ -n "$GPGSIGN_KEY" ]] && ENV_VARS+=("GPGSIGN_KEY=$GPGSIGN_KEY")

if [[ -n "$COMMAND" ]]; then
  if [ "$_RUN_WITH_SUDO" = "true" ]; then
    exec sudo -u runner env "${ENV_VARS[@]}" bash -c "$COMMAND"
  else
    exec bash -c "$COMMAND"
  fi
else
  if [ "$IS_GITHUB_ACTIONS" != "true" ]; then
    _notice "No command provided, starting interactive shell..."
  fi
  echo "Starting interactive shell..."
  exec bash -l || { echo "ERROR: Failed to start interactive shell" >&2; exit 99; }
fi

