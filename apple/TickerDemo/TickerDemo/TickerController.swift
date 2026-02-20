import Foundation
import TickerCore

// Actor boundary that owns the Rust handle and serializes access.
public actor TickerController {
    private let engine: TickerEngine

    public init() {
        self.engine = TickerEngine()
    }

    public func stream(symbols: [String]) -> AsyncStream<PriceUpdate> {
        AsyncStream { continuation in
            let adapter = PriceAdapter()
            adapter.continuation = continuation

            engine.startTracking(symbols: symbols, listener: adapter)

            // UniFFI does not support automatic cancellation, so we signal cancel explicitly.
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
