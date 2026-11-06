#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
Scripts/generate_project.sh
Scripts/verify.sh
Scripts/build_simulator.sh
Scripts/build_ipa.sh
echo ""
echo "全部完成。未签名 IPA：dist/GuestBookHelper-1.8-unsigned.ipa"
