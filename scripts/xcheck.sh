#!/usr/bin/env bash
# Type/cfg checking only: Darwin C stubs do not produce a runnable macOS binary.
set -euo pipefail
cd "$(dirname "$0")/.."
export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/workspace/desknotes/target}"
cargo check --locked --manifest-path src-tauri/Cargo.toml --target x86_64-pc-windows-gnu
stub="${DARWIN_STUB_DIR:-/workspace/aienv/darwin-stub}"
test -x "$stub/fakecc"
test -x "$stub/fakear"
export CC_x86_64_apple_darwin="$stub/fakecc"
export CXX_x86_64_apple_darwin="$stub/fakecc"
export AR_x86_64_apple_darwin="$stub/fakear"
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$stub/fakecc"
cargo check --locked --manifest-path src-tauri/Cargo.toml --target x86_64-apple-darwin
