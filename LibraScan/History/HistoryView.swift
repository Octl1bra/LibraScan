//
//  HistoryView.swift
//  LibraScan
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]

    @State private var searchText = ""
    @State private var isClearConfirmationPresented = false

    private var filteredRecords: [ScanRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.content.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No Scans Yet", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("Codes you scan will show up here.")
                    }
                } else {
                    List {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                HistoryDetailView(record: record)
                            } label: {
                                HistoryRow(record: record)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .searchable(text: $searchText, prompt: "Search records")
                    .overlay {
                        if !searchText.isEmpty && filteredRecords.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(
                            item: RecordsExport(rows: records.map {
                                .init(content: $0.content, symbology: $0.symbology, scannedAt: $0.scannedAt)
                            }),
                            preview: SharePreview("Scan Records")
                        ) {
                            Label("Export Records", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", systemImage: "trash", role: .destructive) {
                            isClearConfirmationPresented = true
                        }
                    }
                }
            }
            .alert(
                "Clear all scan records?",
                isPresented: $isClearConfirmationPresented
            ) {
                Button("Clear All", role: .destructive) {
                    clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecords[index])
        }
    }

    private func clearAll() {
        for record in records {
            modelContext.delete(record)
        }
        searchText = ""
    }
}

private struct HistoryRow: View {
    let record: ScanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.content)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                SymbologyTag(name: record.symbology)
                if record.isURL {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.scannedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
