#!/usr/bin/env bash

set -euo pipefail

# Post-entrypoint cleanup and finalization
# This script runs after the main entrypoint to clean up sensitive data

echo "::group::Post-build Cleanup"

# ============================================================================
# GPG Passphrase Cache Cleanup
# ============================================================================
# Forget all cached passphrases for security
if [[ -n "${GNUPGHOME:-}" ]] && [[ -d "$GNUPGHOME" ]]; then
  echo "==> Clearing GPG passphrase cache..."
  KEYGRIPS=$(gpg --with-colons --list-secret-keys "${GPG_KEY_ID}" | awk -F: '/^grp:/ {print $10}' || true)
  while read -r KEYGRIP; do
    /usr/lib/gnupg/gpg-preset-passphrase --forget "$KEYGRIP" 2>/dev/null || true
  done <<< "$KEYGRIPS"
else
  echo "==> No GNUPGHOME set, skipping GPG cleanup"
fi

# ============================================================================
# Additional Cleanup
# ============================================================================
# Clear any temporary sensitive files
if [[ -d "/tmp" ]]; then
  echo "==> Cleaning up temporary files..."
  shred -n 10 -s 4096 /dev/urandom > /dev/null 2>&1 || true
  rm -f /tmp/gpg-* /tmp/*.key /tmp/*.asc 2>/dev/null || true
fi

echo "::endgroup::"
echo "✓ Post-build cleanup completed"
