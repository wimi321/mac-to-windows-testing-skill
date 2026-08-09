#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/mac2win-pycache}"
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
bash -n "$ROOT/install.sh" "$ROOT/bin/mac2win-test" "$ROOT/tests/test_install.sh"
bash "$ROOT/tests/test_install.sh"
python3 -m py_compile \
  "$ROOT/skills/mac-to-windows-testing/scripts/mac2win_test.py" \
  "$ROOT/scripts/package_release.py" \
  "$ROOT/scripts/score_visual_review.py"
python3 "$ROOT/scripts/package_release.py" --version test --output-dir /tmp/mac2win-release-test >/dev/null
test -s /tmp/mac2win-release-test/mac-to-windows-testing-skill-test.zip
test -s /tmp/mac2win-release-test/SHA256SUMS
