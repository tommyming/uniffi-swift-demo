import SwiftUI
import TickerCore

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
