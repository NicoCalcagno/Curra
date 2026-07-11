import SwiftData
import SwiftUI

struct OfflineMapsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var offline = OfflineMapService.shared
    @Query private var routes: [Route]

    var body: some View {
        let _ = offline.packsVersion
        let stored = offline.storedPacks()

        Form {
            Section {
                LabeledContent(
                    "Used",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(offline.totalBytes),
                        countStyle: .file
                    )
                )
                LabeledContent(
                    "Limit",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(OfflineMapService.maxTotalBytes),
                        countStyle: .file
                    )
                )
            } header: {
                Text("Storage")
            } footer: {
                Text("Each saved route can keep its map tiles on device for offline use. Remove downloads here to free space.")
            }

            if !stored.isEmpty {
                Section("Downloads") {
                    ForEach(stored, id: \.routeID) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routeName(for: item.routeID))
                                Text(ByteCountFormatter.string(
                                    fromByteCount: Int64(item.bytes),
                                    countStyle: .file
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                remove(item.routeID)
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("Offline maps")
    }

    private func routeName(for routeID: UUID) -> String {
        routes.first { $0.id == routeID }?.name ?? "Deleted route"
    }

    private func remove(_ routeID: UUID) {
        Task {
            await offline.removeDownload(routeID: routeID)
            if let route = routes.first(where: { $0.id == routeID }) {
                route.isOfflineAvailable = false
                try? modelContext.save()
            }
        }
    }
}
