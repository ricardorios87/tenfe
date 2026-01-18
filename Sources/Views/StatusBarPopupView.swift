import SwiftUI

struct StatusBarPopupView: View {
    @ObservedObject var trainService: TrainService
    @ObservedObject var settingsManager: SettingsManager
    let onSettingsClick: () -> Void
    let onQuitClick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tram.fill")
                    .foregroundColor(.secondary)
                Text("Next trains to \(settingsManager.settings.route.destination)")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Train list
            if trainService.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading trains...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else if let error = trainService.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error loading trains")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else if trainService.nextTrains.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No trains available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(trainService.nextTrains.prefix(3)) { train in
                        TrainRowView(train: train)
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Settings...") {
                    onSettingsClick()
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Refresh") {
                    trainService.refreshTrains()
                }
                .buttonStyle(.plain)

                Button("Quit") {
                    onQuitClick()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 300)
    }
}

struct TrainRowView: View {
    let train: Train

    var body: some View {
        HStack {
            Image(systemName: "tram.fill")
                .foregroundColor(.accentColor)
                .frame(width: 20)

            Text(train.departureTimeString)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            Spacer()

            Text(train.line)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(4)

            Text(train.timeUntilDeparture)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}