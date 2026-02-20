# Project Spec: Ticker Demo (UniFFI + Swift Actor Boundary)

## Project Goal
Build a demo repo showing a **Swift-first interop architecture**: a Rust "ticker core" exposed to Swift via UniFFI, integrated into a SwiftUI iOS app through a single Swift `actor` boundary, converting UniFFI callbacks into `AsyncStream`, and handling shutdown via an explicit `cancel()` channel (since UniFFI async doesn't directly support cancellation).

---

## Deliverables (must exist in repo)

### 1. Rust library crate (`rust/ticker_core/`)
- Builds as a `staticlib` and exposes UniFFI bindings
- Exports:
  - `PriceUpdate` struct (symbol, price, timestamp)
  - `PriceListener` trait (callback interface)
  - `TickerEngine` struct with methods:
    - `new()` constructor
    - `start_tracking(symbols, listener)` - spawns background loop, emits ~2 updates/sec/symbol
    - `cancel()` - signals loop to stop (idempotent)
    - Optional: `next_price()` or `drain_updates()` for pull-based API (alternative to callbacks)

### 2. iOS SwiftUI app (`apple/TickerDemo/`)
- Xcode project that imports generated Swift bindings and links Rust library/XCFramework
- Swift architecture:
  - `TickerController` actor - owns `TickerEngine` handle, exposes `AsyncStream<PriceUpdate>`
  - `PriceAdapter` class - implements `PriceListener` callback, bridges to `AsyncStream.Continuation`
  - `TickerViewModel` - `@MainActor` observable object, consumes stream via `for await`
  - `ContentView` - SwiftUI list showing symbol + price + timestamp, start/stop controls
- Implements explicit cancellation: stream termination calls `engine.cancel()`
- Uses `@unchecked Sendable` only in adapter class (documented why)

### 3. Build automation (`scripts/`)
- Script that produces **XCFramework + Swift bindings** in one command
- Uses `cargo xcframework` tool (include install instructions in README)
- Generates and places:
  - `TickerCore.xcframework` → `apple/TickerDemo/Frameworks/`
  - Swift binding sources → `apple/TickerDemo/Generated/`
  - Headers/modulemap for Xcode import
- Script should regenerate bindings (outputs ignored in git, but script is committed)

### 4. Documentation (`README.md`)
- "How to build/run" steps
- 60-second architecture explanation
- Prerequisites (Rust toolchain, cargo-xcframework, Xcode)
- Known issues/troubleshooting section

---

## Repo Structure (recommended)

```
ticker-demo/
├── rust/
│   └── ticker_core/
│       ├── Cargo.toml (staticlib + uniffi dependencies)
│       ├── src/
│       │   ├── lib.rs (UniFFI exports)
│       │   ├── api.rs (public types)
│       │   └── engine.rs (ticker loop implementation)
│       ├── build.rs (if needed for UniFFI scaffolding)
│       └── uniffi.toml (optional config)
├── apple/
│   └── TickerDemo/
│       ├── TickerDemo.xcodeproj
│       ├── TickerDemo/
│       │   ├── TickerController.swift
│       │   ├── PriceAdapter.swift
│       │   ├── TickerViewModel.swift
│       │   ├── ContentView.swift
│       │   └── TickerDemoApp.swift
│       ├── Generated/ (ignored in git, created by build script)
│       │   ├── TickerCore.swift
│       │   ├── TickerCoreFFI.h
│       │   └── module.modulemap
│       └── Frameworks/ (ignored in git)
│           └── TickerCore.xcframework/
├── scripts/
│   ├── make_ios_xcframework.sh (builds Rust + generates bindings)
│   └── make_all.sh (convenience wrapper)
└── README.md
```

---

## Rust API Design

### Types to export (via UniFFI)

```rust
// Simple value type (uniffi::Record)
pub struct PriceUpdate {
    pub symbol: String,
    pub price: f64,
    pub timestamp_ms: i64,
}

// Callback interface (uniffi::Trait)
pub trait PriceListener: Send + Sync {
    fn on_price(&self, update: PriceUpdate);
}

// Main engine (uniffi::Object)
pub struct TickerEngine {
    // Internal state: Arc<Mutex<...>> for shared cancellation flag
}

impl TickerEngine {
    pub fn new() -> Self;
    
    // Spawns background task that:
    // - Generates random prices for given symbols
    // - Calls listener.on_price() ~2x/sec per symbol
    // - Respects cancellation flag
    pub fn start_tracking(
        &self,
        symbols: Vec<String>,
        listener: Arc<dyn PriceListener>,
    );
    
    // Sets cancellation flag (idempotent)
    pub fn cancel(&self);
    
    // Alternative API shapes for Slide 12 (implement at least one):
    pub fn next_price(&self) -> Option<PriceUpdate>; // Pull model
    // OR:
    pub fn drain_updates(&self, max: u32) -> Vec<PriceUpdate>; // Batch pull
}
```

### Implementation notes
- Use `tokio` or `async-std` for async runtime
- Use `Arc<AtomicBool>` or `tokio::sync::watch` for cancellation signaling
- Random price generation: pick a base price per symbol, add small random deltas
- UniFFI callback interfaces are marked "soft deprecated" - demo should work but also show alternative

---

## Swift Architecture

### 1. Actor boundary (TickerController.swift)

```swift
import Foundation

public actor TickerController {
    private let engine: TickerEngine
    
    public init() {
        self.engine = TickerEngine()
    }
    
    public func stream(symbols: [String]) -> AsyncStream<PriceUpdate> {
        AsyncStream { continuation in
            let adapter = PriceAdapter()
            adapter.continuation = continuation
            
            // Start tracking with callback
            engine.startTracking(symbols: symbols, listener: adapter)
            
            // Explicit cancellation on stream termination
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.cancel()
                }
            }
        }
    }
    
    private func cancel() {
        engine.cancel()
    }
}
```

### 2. Callback adapter (PriceAdapter.swift)

```swift
import Foundation

// Bridge UniFFI callback to AsyncStream
final class PriceAdapter: PriceListener, @unchecked Sendable {
    // @unchecked Sendable because:
    // - Continuation is Sendable
    // - UniFFI calls onPrice from arbitrary threads
    // - We never mutate continuation after setup
    var continuation: AsyncStream<PriceUpdate>.Continuation?
    
    func onPrice(update: PriceUpdate) {
        continuation?.yield(update)
    }
}
```

### 3. ViewModel (TickerViewModel.swift)

```swift
import Foundation
import SwiftUI

@MainActor
final class TickerViewModel: ObservableObject {
    @Published private(set) var prices: [String: PriceUpdate] = [:]
    @Published private(set) var isRunning = false
    
    private let controller = TickerController()
    private var streamTask: Task<Void, Never>?
    
    func start(symbols: [String]) async {
        guard !isRunning else { return }
        isRunning = true
        
        let stream = await controller.stream(symbols: symbols)
        
        streamTask = Task { @MainActor in
            for await update in stream {
                prices[update.symbol] = update
            }
            isRunning = false
        }
    }
    
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
    }
}
```

### 4. SwiftUI View (ContentView.swift)

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TickerViewModel()
    
    private let symbols = ["BTC", "ETH", "SOL"]
    
    var body: some View {
        VStack {
            List {
                ForEach(symbols, id: \.self) { symbol in
                    if let update = viewModel.prices[symbol] {
                        HStack {
                            Text(update.symbol)
                                .font(.headline)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("$\(update.price, specifier: "%.2f")")
                                    .font(.title2)
                                Text(formatTimestamp(update.timestampMs))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(symbol)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Button(viewModel.isRunning ? "Stop" : "Start") {
                Task {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        await viewModel.start(symbols: symbols)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle("Ticker Demo")
    }
    
    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
```

---

## Build Pipeline (scripts/make_ios_xcframework.sh)

### Steps the script must perform:

1. **Install prerequisites check**
   ```bash
   # Check for cargo-xcframework
   if ! command -v cargo-xcframework &> /dev/null; then
       echo "Installing cargo-xcframework..."
       cargo install cargo-xcframework
   fi
   ```

2. **Build Rust XCFramework**
   ```bash
   cd rust/ticker_core
   cargo xcframework --targets aarch64-apple-ios,aarch64-apple-ios-sim,x86_64-apple-ios
   # Output: target/xcframework/TickerCore.xcframework
   ```

3. **Generate Swift bindings**
   ```bash
   # Use uniffi-bindgen-swift (installed via cargo install uniffi-bindgen)
   uniffi-bindgen-swift \
     src/ticker_core.udl \
     --out-dir ../../apple/TickerDemo/Generated \
     --swift-sources \
     --headers \
     --modulemap --xcframework
   ```

4. **Copy XCFramework to Xcode project**
   ```bash
   cp -R target/xcframework/TickerCore.xcframework \
     ../../apple/TickerDemo/Frameworks/
   ```

5. **Print success message**
   ```bash
   echo "✅ Build complete! Open apple/TickerDemo/TickerDemo.xcodeproj"
   ```

### Important notes:
- UniFFI's Xcode integration docs note that configuring Xcode to build Rust is out of scope
- Recommended approach: use scripts to build Rust, then link artifacts into Xcode
- Generated files should be in `.gitignore` but scripts committed
- Script should be idempotent (safe to run multiple times)

---

## Acceptance Criteria (what "done" looks like)

✅ **Build succeeds**
- Running `./scripts/make_all.sh` completes without errors
- XCFramework and Swift bindings are generated
- Xcode project links successfully

✅ **App runs on simulator**
- Open Xcode project, build and run
- Tap "Start" button
- See BTC, ETH, SOL prices updating ~2x per second
- Prices are randomized but stable (small deltas)
- Timestamp shows current time

✅ **Cancellation works**
- Tap "Stop" button or navigate away
- Background Rust loop stops (verify via logs/print statements)
- No crashes or memory leaks

✅ **Swift concurrency safety**
- Enable `SWIFT_STRICT_CONCURRENCY = complete` in Xcode build settings
- Project compiles without concurrency warnings
- Only `PriceAdapter` uses `@unchecked Sendable` (one place, documented)
- ViewModel is `@MainActor`, all UI updates on main thread

✅ **Code quality**
- README includes clear "Quick Start" section (< 5 steps)
- Code includes inline comments explaining:
  - Why adapter uses `@unchecked Sendable`
  - How actor serializes foreign handle access
  - Why explicit `cancel()` is needed
- Rust code includes basic error handling

---

## Technology Preferences

### UniFFI approach (choose one):
**Option A: Proc-macro (recommended for this demo)**
```rust
use uniffi::prelude::*;

#[derive(uniffi::Record)]
pub struct PriceUpdate { /* ... */ }

#[uniffi::export]
pub trait PriceListener: Send + Sync {
    fn on_price(&self, update: PriceUpdate);
}

#[derive(uniffi::Object)]
pub struct TickerEngine { /* ... */ }

#[uniffi::export]
impl TickerEngine { /* ... */ }

uniffi::setup_scaffolding!();
```

**Option B: UDL-based**
```
// ticker_core.udl
namespace ticker_core {};

dictionary PriceUpdate {
    string symbol;
    double price;
    i64 timestamp_ms;
};

callback interface PriceListener {
    void on_price(PriceUpdate update);
};

interface TickerEngine {
    constructor();
    void start_tracking(sequence<string> symbols, PriceListener listener);
    void cancel();
};
```

**Codex should use proc-macro approach** (simpler, less boilerplate).

### Dependencies
- **Rust:** `uniffi` (latest), `tokio` or `async-std`, `rand`
- **Swift:** iOS 15+ (for AsyncStream), Swift 5.9+ (for strict concurrency)

---

## Optional Enhancements (nice-to-have, not required)

- [ ] Alternative API demo: add a second tab showing pull-based API (`next_price()`)
- [ ] Unit tests: Swift tests for ViewModel, Rust tests for engine
- [ ] CI: GitHub Actions workflow that builds XCFramework
- [ ] Logging: structured logging in Rust (via `tracing`), surfaced to Swift
- [ ] Error handling: show what happens when engine fails to start

---

## References
- UniFFI User Guide: https://mozilla.github.io/uniffi-rs/
- cargo-xcframework: https://github.com/terhechte/uniffi-swift-async-example
- Swift concurrency docs: https://swift.org/documentation/concurrency/
- UniFFI callback interfaces caveat: https://mozilla.github.io/uniffi-rs/0.27/udl/callback_interfaces.html
