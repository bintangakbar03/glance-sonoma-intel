#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_version="14.8.9"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Kompilasi memerlukan macOS dan Xcode 26. Script ini tidak dapat membangun aplikasi macOS di Linux." >&2
    exit 1
fi

if ! xcode_version="$(xcodebuild -version 2>/dev/null)"; then
    echo "Pilih instalasi Xcode lengkap melalui DEVELOPER_DIR. Command Line Tools saja tidak cukup." >&2
    exit 1
fi
xcode_major="$(printf '%s\n' "$xcode_version" | awk '/^Xcode / {split($2,v,"."); print v[1]}')"
if [[ ! "$xcode_major" =~ ^[0-9]+$ ]] || (( xcode_major < 26 )); then
    echo "Kode sumber ini memerlukan compiler Swift 6.2 di Xcode 26 atau lebih baru." >&2
    echo "Xcode 26 dijalankan pada Mac dengan macOS 15.6+, tetapi hasilnya ditargetkan ke Sonoma 14.8.9 Intel." >&2
    exit 1
fi

mkdir -p "$repo_dir/build/sonoma" "$repo_dir/build/artifacts"
run_dir="$(mktemp -d "$repo_dir/build/sonoma/run.XXXXXX")"
printf '%s\n' "$xcode_version" | tee "$run_dir/toolchain.txt"
echo "Target: Intel x86_64, macOS $target_version"
echo "Folder hasil: $run_dir"

xcodebuild \
    -project "$repo_dir/glance.xcodeproj" \
    -scheme Glance-Sonoma \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$run_dir/DerivedData" \
    ARCHS=x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    MACOSX_DEPLOYMENT_TARGET="$target_version" \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_ENTITLEMENTS="$repo_dir/support/sonoma.entitlements" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp=none \
    build 2>&1 | tee "$run_dir/build.log"

app_path="$run_dir/DerivedData/Build/Products/Release/glance.app"
python3 "$repo_dir/support/verify-built-app.py" "$app_path" "$target_version" \
    | tee "$run_dir/verification.json"
codesign --verify --deep --strict --verbose=2 "$app_path"
bash "$repo_dir/support/test-recognition.sh" "$app_path" \
    2>&1 | tee "$run_dir/recognition-smoke.log"

stage_dir="$run_dir/dmg-content"
mkdir -p "$stage_dir"
ditto "$app_path" "$stage_dir/Glance.app"
ln -s /Applications "$stage_dir/Applications"
cp "$repo_dir/LICENSE" "$stage_dir/LICENSE.txt"
cat > "$stage_dir/BACA-DULU.txt" <<'INFO'
Glance — build komunitas untuk Intel dan macOS Sonoma 14.8.9.
Salin Glance.app ke Applications sebelum membukanya.
Build ini memakai tanda tangan lokal (ad-hoc), bukan Developer ID atau notarization Apple.
Pemeriksaan paket dan kompilasi tidak membuktikan fitur kamera, Keychain,
dan face unlock sudah bekerja di Mac Sonoma Anda. Fitur tersebut perlu diuji di perangkat.
Pembaruan otomatis dinonaktifkan karena rilis upstream memakai target macOS yang berbeda.
INFO

dmg_name="Glance-Sonoma-Intel-macOS14.8.9.dmg"
hdiutil create -volname 'Glance Sonoma' -srcfolder "$stage_dir" \
    -format UDZO "$run_dir/$dmg_name"
cp "$run_dir/$dmg_name" "$repo_dir/build/artifacts/$dmg_name"
cp "$run_dir/verification.json" "$repo_dir/build/artifacts/verification.json"
cp "$run_dir/toolchain.txt" "$repo_dir/build/artifacts/toolchain.txt"
cp "$run_dir/recognition-smoke.log" "$repo_dir/build/artifacts/recognition-smoke.log"
shasum -a 256 "$repo_dir/build/artifacts/$dmg_name"
echo "Kompilasi dan pemeriksaan paket selesai. Pengujian di macOS Sonoma masih diperlukan."
echo "DMG: $repo_dir/build/artifacts/$dmg_name"
