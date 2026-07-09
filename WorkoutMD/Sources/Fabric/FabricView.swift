import SwiftUI

/// Small read-only list of the fabric channel's recent kind:9 traffic — reachable from Settings'
/// "Coach fabric" section. Not a chat composer (outbound posting happens automatically from session
/// finishes and notable coach plan changes, not free typing here) — just visibility into what the
/// user's other tenex-edge agents have said, the same buffer `FabricController.contextSnippet` folds
/// into the coach's grounding context.
struct FabricView: View {
    let fabric: FabricController

    var body: some View {
        List {
            Section {
                if fabric.messages.isEmpty {
                    Text("No messages yet. Once the fabric is enabled and another agent posts to this channel, it shows up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fabric.messages.reversed()) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.authorShort)
                                    .font(.caption.weight(.semibold).monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(message.createdAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(message.body)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text(fabric.channelLabel.isEmpty ? "Channel" : "Channel: \(fabric.channelLabel)")
            } footer: {
                Text("Shows the whole channel's recent kind:9 traffic, including the coach's own posts.")
            }
        }
        .navigationTitle("Fabric")
        .navigationBarTitleDisplayMode(.inline)
    }
}
