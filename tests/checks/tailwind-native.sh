#!/usr/bin/env bash
# The __tailwind__ starter must obey the tailwind-native CSS convention:
# no comment-only CSS files, every file imported, no stray directories.
set -euo pipefail

bin/tailwind-native-check.sh starter-theme/__tailwind__ >/dev/null \
  || { echo "FAIL: starter-theme/__tailwind__ violates the tailwind-native convention"; \
       bin/tailwind-native-check.sh starter-theme/__tailwind__ || true; exit 1; }

echo PASS
