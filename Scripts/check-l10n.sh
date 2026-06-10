#!/bin/bash
# Verifies the two Localizable.strings stay key-identical and that every L("key")
# used in source code actually exists. Run by CI; exits non-zero on any mismatch.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

EN=Sources/PhotoFilter/Resources/en.lproj/Localizable.strings
ZH=Sources/PhotoFilter/Resources/zh-Hans.lproj/Localizable.strings

keys() { grep -o '^"[^"]*"' "$1" | tr -d '"' | sort; }

EN_KEYS=$(keys "$EN")
ZH_KEYS=$(keys "$ZH")

if ! diff <(echo "$EN_KEYS") <(echo "$ZH_KEYS") > /dev/null; then
  echo "FAIL: en and zh-Hans key sets differ:" >&2
  diff <(echo "$EN_KEYS") <(echo "$ZH_KEYS") >&2 || true
  exit 1
fi

# Every literal L("...") in source must exist in the English table.
MISSING=0
while IFS= read -r key; do
  if ! grep -q "^\"$key\"" "$EN"; then
    echo "FAIL: L(\"$key\") used in source but missing from $EN" >&2
    MISSING=1
  fi
done < <(grep -rhoE 'L\("[^"]+"' Sources/PhotoFilter --include='*.swift' | sed -E 's/L\("([^"]+)"/\1/' | sort -u)

[ "$MISSING" = 0 ] && echo "OK: $(echo "$EN_KEYS" | wc -l | tr -d ' ') keys, en/zh in sync, all source keys present."
exit "$MISSING"
