#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'DeskNodes requires macOS 14+ and the Xcode Swift/macOS SDK toolchain.' >&2
    exit 1
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
export MACOSX_DEPLOYMENT_TARGET=14.0
xcrun --find swift >/dev/null
xcrun --sdk macosx --show-sdk-path >/dev/null
xcrun swift build --configuration release --product DeskNodes
binary_dir="$(xcrun swift build --configuration release --show-bin-path)"
# Stage only inside this repository; do not remove an existing user installation.
stage_dir="$(mktemp -d "$repo_root/build-stage.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app_path="$stage_dir/DeskNodes.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$repo_root/build"
cp "$binary_dir/DeskNodes" "$app_path/Contents/MacOS/DeskNodes"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
chmod 755 "$app_path/Contents/MacOS/DeskNodes"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
# Ad-hoc is the local default, not proof of SMAppService acceptance. An existing
# local signing identity can be selected explicitly; no account/certificate is installed.
signing_identity="${DESKNODES_SIGNING_IDENTITY:--}"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$app_path"
/usr/bin/codesign --verify --strict --verbose=2 "$app_path"
# ditto updates a build artifact only, leaving installed copies untouched.
if [[ -e "$repo_root/build/DeskNodes.app" ]]; then
    rm -rf "$repo_root/build/DeskNodes.app"
fi
/usr/bin/ditto "$app_path" "$repo_root/build/DeskNodes.app"
echo "Built: $repo_root/build/DeskNodes.app"
