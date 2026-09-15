import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

struct LiveCounterView: View {
    @ObservedObject var viewModel: LiveCounterViewModel
    let clientTitle: String

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Client identifier
                        Text(clientTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)

                        // Card container
                        VStack(spacing: 2) {
                            // Header
                            Text("Vote for your favorite Color")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 8)

                            // Vote options
                            VStack(spacing: 0) {
                                ForEach(Array(VoteColor.allCases.enumerated()), id: \.offset) { index, color in
                                    VoteRow(color: color, count: countForColor(color)) {
                                        viewModel.vote(for: color)
                                    }
                                    if index < VoteColor.allCases.count - 1 {
                                        Divider()
                                            .background(SwiftUI.Color.gray.opacity(0.3))
                                    }
                                }
                            }

                            // Reset button
                            Button(action: viewModel.resetAllCounters) {
                                Text("Reset")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .padding(.top, 6)
                        }
                        .padding(14)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                        .frame(maxWidth: 320)

                        // Error message
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(5)
                        }
                    }
                    .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thickMaterial)
            }
        }
    }

    private func countForColor(_ color: VoteColor) -> Int {
        switch color {
        case .red:
            Int(viewModel.redCount)
        case .green:
            Int(viewModel.greenCount)
        case .blue:
            Int(viewModel.blueCount)
        }
    }
}

struct VoteRow: View {
    let color: VoteColor
    let count: Int
    let onVote: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Color name
            Text(color.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color.swiftUIColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Count
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            // Vote button
            Button(action: onVote) {
                Text("Vote")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}
