#!/bin/bash
# Fetches the bundled note font, 霞鹜文楷 (LXGW WenKai, SIL OFL 1.1), into Resources/Fonts.
# The files are used unmodified; a pinned release and SHA-256 keep every build identical.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$repo_root/Resources/Fonts"
version="v1.530"
base="https://github.com/lxgw/LxgwWenKai/releases/download/$version"
files=(
    "LXGWWenKai-Regular.ttf|$base/LXGWWenKai-Regular.ttf|2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"
    "LXGWWenKai-Medium.ttf|$base/LXGWWenKai-Medium.ttf|f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"
    "OFL.txt|https://raw.githubusercontent.com/lxgw/LxgwWenKai/$version/OFL.txt|1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0"
)
mkdir -p "$dir"
for entry in "${files[@]}"; do
    IFS='|' read -r name url sha <<<"$entry"
    target="$dir/$name"
    if [[ -f "$target" ]] && [[ "$(shasum -a 256 "$target" | cut -d' ' -f1)" == "$sha" ]]; then continue; fi
    echo "Fetching $name ($version)…"
    curl --fail --location --retry 3 --silent --show-error --output "$target.partial" "$url"
    actual="$(shasum -a 256 "$target.partial" | cut -d' ' -f1)"
    if [[ "$actual" != "$sha" ]]; then
        rm -f "$target.partial"
        echo "Checksum mismatch for $name: expected $sha, got $actual" >&2
        exit 1
    fi
    mv "$target.partial" "$target"
done
