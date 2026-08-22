//
//  LibraScanApp.swift
//  LibraScan
//
//  Created by Libra Hu on 2026-06-10 19:39.
//

import SwiftUI
import SwiftData

@main
struct LibraScanApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScanRecord.self,
        ])
#if DEBUG
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: LibraScanDemoMode.isEnabled
        )
#else
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
#endif

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
#if DEBUG
            LibraScanDemoMode.seed(container)
#endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
