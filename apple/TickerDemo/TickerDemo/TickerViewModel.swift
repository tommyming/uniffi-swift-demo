import Foundation
import SwiftUI
import TickerCore

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
