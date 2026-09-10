#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${1:?Usage: test-recognition.sh APP_PATH}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/glance-recognition.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

# Public-domain NASA test photo distributed by scikit-image. Its published
# SHA-256 is pinned so an upstream change cannot silently change the test.
curl --fail --location --silent --show-error --retry 2 --max-time 60 \
    'https://raw.githubusercontent.com/scikit-image/scikit-image/v0.24.0/skimage/data/astronaut.png' \
    --output "$test_dir/face.png"
python3 - "$test_dir/face.png" <<'PY'
from pathlib import Path
import hashlib
import sys
expected = '88431cd9653ccd539741b555fb0a46b61558b301d4110412b5bc28b5e3ea6cb5'
actual = hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('Face test fixture checksum mismatch')
PY

xcrun swiftc -O -warnings-as-errors -target x86_64-apple-macos14.8.9 \
    -o "$test_dir/recognition-smoke-test" \
    "$repo_dir/glance/RecognitionRuntime.swift" \
    "$repo_dir/glance/FaceDetector.swift" \
    "$repo_dir/glance/FaceAligner.swift" \
    "$repo_dir/glance/FaceEmbedder.swift" \
    "$repo_dir/glance/ArcFaceEmbedder.swift" \
    "$repo_dir/glance/Liveness/LandmarkGeometry.swift" \
    "$repo_dir/support/recognition-smoke-test.swift"
"$test_dir/recognition-smoke-test" "$app_path" "$test_dir/face.png"
