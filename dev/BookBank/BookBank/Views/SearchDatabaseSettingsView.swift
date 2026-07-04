//
//  SearchDatabaseSettingsView.swift
//  BookBank
//
//  書籍検索に使うデータベース（楽天Books / NAVER）を選ぶ設定画面
//

import SwiftUI

/// 検索データベース設定画面
struct SearchDatabaseSettingsView: View {
    @AppStorage(SearchDatabase.storageKey) private var searchDatabaseRaw = SearchDatabase.deviceDefault.rawValue

    private var selected: SearchDatabase {
        SearchDatabase(rawValue: searchDatabaseRaw) ?? .deviceDefault
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(SearchDatabase.allCases.enumerated()), id: \.element.id) { index, database in
                    Button {
                        searchDatabaseRaw = database.rawValue
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(database.nameKey))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(database.displayProviderName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selected == database {
                                Image(systemName: "checkmark")
                                    .font(.body)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < SearchDatabase.allCases.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCardBackground)
            )
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("settings.search_database")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SearchDatabaseSettingsView()
    }
}
