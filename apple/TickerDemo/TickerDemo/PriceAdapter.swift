import Foundation
import TickerCore

// Bridge UniFFI callback to AsyncStream.
final class PriceAdapter: PriceListener, @unchecked Sendable {
    // @unchecked Sendable because:
    // - UniFFI invokes callbacks from arbitrary threads.
    // - Continuation is Sendable and set once before callbacks arrive.
    var continuation: AsyncStream<PriceUpdate>.Continuation?

    func onPrice(update: PriceUpdate) {
        continuation?.yield(update)
    }
}
