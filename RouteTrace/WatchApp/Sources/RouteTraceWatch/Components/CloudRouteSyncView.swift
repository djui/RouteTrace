import RouteTraceShared
import SwiftData
import SwiftUI

struct CloudRouteSyncView: View {
    @Query(sort: \RouteEntity.importedAt, order: .reverse) private var cloudRoutes: [RouteEntity]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: syncToken) {
                await WatchCloudRouteSyncService.shared.applyCloudRoutes(cloudRoutes)
            }
    }

    private var syncToken: String {
        cloudRoutes.map { "\($0.id.uuidString):\($0.importedAt.timeIntervalSince1970)" }.joined(separator: "|")
    }
}
