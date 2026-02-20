# Ticker Demo (UniFFI + Swift Actor Boundary)

A SwiftUI iOS demo where a Rust ticker engine streams fake crypto prices into Swift through a single actor boundary.

## Quick Start (<= 5 steps)
1. Install Rust toolchain and Xcode (iOS 15+).
2. Run `./scripts/make_all.sh` (installs `cargo-xcframework` and `uniffi-bindgen` if needed).
3. Open `apple/TickerDemo/TickerDemo.xcodeproj`.
4. Build and run on a simulator.
5. Tap Start to see BTC/ETH/SOL updates.

## 60-second architecture
- Rust `TickerEngine` generates fake prices ~2x/sec per symbol.
- UniFFI exposes `PriceUpdate`, `PriceListener`, and `TickerEngine`.
- Swift `TickerController` actor owns the Rust handle and serializes access.
- `PriceAdapter` bridges UniFFI callbacks into an `AsyncStream`.
- `TickerViewModel` (`@MainActor`) consumes the stream and updates the UI.
- Stream termination explicitly calls `engine.cancel()` (UniFFI does not provide automatic cancellation).

## Prerequisites
- Rust toolchain (stable)
- Xcode 15+
- `cargo-xcframework` and `uniffi-bindgen` (script installs if missing)

## Build + Run
- `./scripts/make_all.sh`
- Open Xcode project and build/run.
- Set `SWIFT_STRICT_CONCURRENCY = complete` in Xcode Build Settings.

## Troubleshooting
- Missing iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
- `module TickerCore not found`: rerun the build script and ensure `Generated/` + `Frameworks/` are added to the Xcode project.
- App does not stop: verify the Stop button cancels the task (stream termination triggers `engine.cancel()`).
