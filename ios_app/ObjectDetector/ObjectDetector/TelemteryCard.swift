import SwiftUI

struct TelemetryCard: View {

    let title: String
    let value: String

    var body: some View {

        VStack(spacing: 4) {

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
