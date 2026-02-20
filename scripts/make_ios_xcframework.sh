#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
RUST_DIR="$ROOT_DIR/rust/ticker_core"
APPLE_DIR="$ROOT_DIR/apple/TickerDemo"
GENERATED_DIR="$APPLE_DIR/Generated"
FRAMEWORKS_DIR="$APPLE_DIR/Frameworks"

if ! command -v cargo-xcframework >/dev/null 2>&1; then
    echo "Installing cargo-xcframework..."
    cargo install cargo-xcframework
fi

if ! command -v uniffi-bindgen-swift >/dev/null 2>&1; then
    echo "Installing uniffi-bindgen..."
    cargo install uniffi-bindgen
fi

mkdir -p "$GENERATED_DIR" "$FRAMEWORKS_DIR"

cd "$RUST_DIR"

cargo xcframework --targets aarch64-apple-ios,aarch64-apple-ios-sim,x86_64-apple-ios

# Build a host library so uniffi-bindgen can read metadata.
cargo build --release

HOST_LIB="$RUST_DIR/target/release/libticker_core.dylib"
if [ ! -f "$HOST_LIB" ]; then
    echo "Host library not found at $HOST_LIB"
    exit 1
fi

uniffi-bindgen-swift \
  --library "$HOST_LIB" \
  --config "$RUST_DIR/uniffi.toml" \
  --out-dir "$GENERATED_DIR" \
  --swift-sources \
  --headers \
  --modulemap \
  --xcframework

if [ -d "$RUST_DIR/target/xcframework/TickerCore.xcframework" ]; then
    SRC_XCFRAMEWORK="$RUST_DIR/target/xcframework/TickerCore.xcframework"
elif [ -d "$RUST_DIR/target/xcframework/ticker_core.xcframework" ]; then
    SRC_XCFRAMEWORK="$RUST_DIR/target/xcframework/ticker_core.xcframework"
else
    echo "XCFramework not found in target/xcframework"
    exit 1
fi

rm -rf "$FRAMEWORKS_DIR/TickerCore.xcframework"
cp -R "$SRC_XCFRAMEWORK" "$FRAMEWORKS_DIR/TickerCore.xcframework"

echo "✅ Build complete! Open apple/TickerDemo/TickerDemo.xcodeproj"
