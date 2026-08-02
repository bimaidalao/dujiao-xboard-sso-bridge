#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

pass() { printf '[ OK ] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; failed=1; }

while IFS= read -r file; do
  bash -n "$file" && pass "bash: ${file#"$ROOT_DIR"/}" || fail "bash: ${file#"$ROOT_DIR"/}"
done < <(find "$ROOT_DIR" -type f \( -name '*.sh' -o -path '*/bin/dx-bridge' \) -not -path '*/.git/*' | sort)

if command -v php >/dev/null 2>&1; then
  while IFS= read -r file; do
    php -l "$file" >/dev/null && pass "php: ${file#"$ROOT_DIR"/}" || fail "php: ${file#"$ROOT_DIR"/}"
  done < <(find "$ROOT_DIR/dujiao" -type f -name '*.php' | sort)
  if php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);'; then
    while IFS= read -r file; do
      php -l "$file" >/dev/null && pass "php8: ${file#"$ROOT_DIR"/}" || fail "php8: ${file#"$ROOT_DIR"/}"
    done < <(find "$ROOT_DIR/xboard" -type f -name '*.php' | sort)
  else
    printf '[SKIP] Xboard PHP files require PHP 8.2; validate them inside the Xboard container\n'
  fi
else
  printf '[SKIP] php is unavailable\n'
fi

if command -v node >/dev/null 2>&1; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  while IFS= read -r file; do
    target="$temporary/$(basename "${file%.tpl}")"
    cp "$file" "$target"
    node --check "$target" >/dev/null && pass "js: ${file#"$ROOT_DIR"/}" || fail "js: ${file#"$ROOT_DIR"/}"
  done < <(find "$ROOT_DIR/templates" -type f \( -name '*.js' -o -name '*.js.tpl' \) | sort)
else
  printf '[SKIP] node is unavailable\n'
fi

[[ -s "$ROOT_DIR/VERSION" ]] || fail 'VERSION is missing'
[[ -x "$ROOT_DIR/bin/dx-bridge" ]] || fail 'bin/dx-bridge is not executable'
[[ $failed -eq 0 ]] || exit 1
printf '\nAll repository checks passed.\n'
