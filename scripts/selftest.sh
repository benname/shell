#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

echo "[SELFTEST] bash -n"
bash -n xray.sh
for f in lib/*.sh; do
  bash -n "$f"
done

echo "[SELFTEST] doctor"
./xray.sh doctor >/tmp/xray-selftest-doctor.txt
echo "  doctor output saved to /tmp/xray-selftest-doctor.txt"

echo "[SELFTEST] render template"
PORT=12345 UUID="00000000-0000-0000-0000-000000000000" SERVER_NAME="example.com" DEST="example.com:443" REALITY_PRIVATE_KEY="privkey" REALITY_SHORT_ID="01234567" TAG="selftest" \
  ./xray.sh render templates/vless-reality-vision.json.tpl /tmp/xray-selftest-reality.json
echo "  rendered /tmp/xray-selftest-reality.json"

echo "[SELFTEST] done"
