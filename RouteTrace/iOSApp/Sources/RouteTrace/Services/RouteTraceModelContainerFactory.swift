import Foundation
import os
import SwiftData

enum RouteTraceSchema {
    static let models: [any PersistentModel.Type] = [
        RouteEntity.self,
        ActivityEntity.self,
        AppSettingsEntity.self
    ]
}

enum RouteTraceCloudConstants {
    static let containerIdentifier = "iCloud.com.uwe.RouteTrace"
    static let storeName = "RouteTraceCloud"
}

enum RouteTraceModelContainerFactory {
    private static let logger = Logger(subsystem: "com.uwe.RouteTrace", category: "ModelContainer")

    static func make() -> ModelContainer {
        let schema = Schema(RouteTraceSchema.models)

        let cloudConfiguration = ModelConfiguration(
            RouteTraceCloudConstants.storeName,
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            logger.error("CloudKit ModelContainer failed, falling back to local store: \(error.localizedDescription, privacy: .public)")
        }

        let localConfiguration = ModelConfiguration(
            RouteTraceCloudConstants.storeName,
            schema: schema,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            fatalError("Failed to create RouteTrace model container: \(error)")
        }
    }
}
