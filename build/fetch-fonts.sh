#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$root/src/DeskNodes.App/Resources/Fonts"
mkdir -p "$destination"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
curl --fail --location --retry 3 "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf" -o "$staging/LXGWWenKai-Regular.ttf"
printf '%s  %s\n' '2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b' "$staging/LXGWWenKai-Regular.ttf" | sha256sum --check --status
curl --fail --location --retry 3 "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf" -o "$staging/LXGWWenKai-Medium.ttf"
printf '%s  %s\n' 'f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a' "$staging/LXGWWenKai-Medium.ttf" | sha256sum --check --status
curl --fail --location --retry 3 "https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/OFL.txt" -o "$staging/OFL.txt"
printf '%s  %s\n' '1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0' "$staging/OFL.txt" | sha256sum --check --status
mv "$staging/LXGWWenKai-Regular.ttf" "$destination/LXGWWenKai-Regular.ttf"
mv "$staging/LXGWWenKai-Medium.ttf" "$destination/LXGWWenKai-Medium.ttf"
mv "$staging/OFL.txt" "$destination/OFL.txt"
echo "LXGW WenKai v1.530: SHA-256 verified."
