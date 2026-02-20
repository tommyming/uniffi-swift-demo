# Quick Start Guide for Codex

**Goal:** Build the Ticker Demo repo for the try! Swift Tokyo 2026 talk.

## What to build
A working iOS app (SwiftUI) that displays live crypto price updates, with all business logic in Rust and clean Swift-actor-based boundary using UniFFI bindings.

## Key architecture requirements
1. **Rust side:** Single `TickerEngine` that generates fake price updates and calls back to Swift via UniFFI callback interface
2. **Swift side:** 
   - One `actor` owns the Rust handle
   - Callback adapter bridges to `AsyncStream`
   - `@MainActor` ViewModel consumes stream
   - Explicit `cancel()` method (UniFFI doesn't support automatic cancellation)
3. **Build:** Automated script using `cargo xcframework` to generate XCFramework + Swift bindings

## File to follow
See `codex-project-spec.md` for complete implementation details including:
- Exact repo structure
- Full Rust API design (types, methods)
- Complete Swift code examples (TickerController, PriceAdapter, ViewModel, ContentView)
- Build script steps
- Acceptance criteria

## Critical constraints
- ✅ Use proc-macro UniFFI (not UDL)
- ✅ Enable `SWIFT_STRICT_CONCURRENCY = complete` in Xcode
- ✅ Only one file uses `@unchecked Sendable` (PriceAdapter)
- ✅ Must run on iOS simulator without manual Rust builds
- ✅ Script must be idempotent (safe to re-run)

## Technology stack
- **Rust:** uniffi (latest), tokio, rand
- **Swift:** iOS 15+, Swift 5.9+, SwiftUI
- **Tools:** cargo-xcframework, uniffi-bindgen

## Deliverable checklist
- [ ] `rust/ticker_core/` with Rust lib
- [ ] `apple/TickerDemo/` with Xcode project
- [ ] `scripts/make_ios_xcframework.sh` build script
- [ ] `README.md` with quick start (< 5 steps)
- [ ] App runs on simulator showing live updates
- [ ] Stop button triggers explicit cancellation
- [ ] No Swift concurrency warnings

## Start here
1. Read `codex-project-spec.md` for detailed requirements
2. Create repo structure
3. Implement Rust core with UniFFI exports
4. Write Swift actor boundary + UI
5. Create build script
6. Test on simulator
7. Write README

---

**This is for a conference talk demo - prioritize clarity and correctness over performance.**
