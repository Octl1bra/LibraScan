//
//  RootTabView.swift
//  LibraScan
//

import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case scan
    case history
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .scan

    init() {
#if DEBUG
        if LibraScanDemoMode.isEnabled, LibraScanDemoMode.screen == .history {
            _selectedTab = State(initialValue: .history)
        }
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Scan", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                ScanView(isActive: selectedTab == .scan)
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
