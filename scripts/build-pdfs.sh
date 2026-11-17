#!/usr/bin/env bash
# Render the HTML sources in assets/pdf-src/ to PDFs in examples/ and RIPs/ with headless Chrome or Brave.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/assets/pdf-src"

browser="${BROWSER_BIN:-}"
if [ -z "$browser" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
    "$(command -v google-chrome || true)" \
    "$(command -v chromium || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then browser="$candidate"; break; fi
  done
fi
if [ -z "$browser" ]; then
  echo "No Chrome, Brave or Chromium found; set BROWSER_BIN." >&2
  exit 1
fi

profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT

for target in examples/synthetic-book examples/contract-accounts RIPs/the-two-asks; do
  name="$(basename "$target")"
  "$browser" --headless=new --disable-gpu --no-first-run --user-data-dir="$profile" \
    --no-pdf-header-footer --print-to-pdf="$root/$target.pdf" "file://$src/$name.html" 2>/dev/null
  echo "wrote $target.pdf"
done
