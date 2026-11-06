#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 Scripts/generate_xcodeproj.py
echo "已生成 GuestBookHelper.xcodeproj"
