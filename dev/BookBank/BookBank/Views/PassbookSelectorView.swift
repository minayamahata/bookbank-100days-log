//
//  PassbookSelectorView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

/// 口座選択画面
struct PassbookSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    @Binding var selectedPassbook: Passbook?
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        List {
            // 総合口座
            Section {
                Button(action: {
                    selectedPassbook = nil
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("総合口座")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Text("すべての口座の合計")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedPassbook == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            // カスタム口座
            Section(header: Text("マイ口座")) {
                ForEach(customPassbooks) { passbook in
                    Button(action: {
                        selectedPassbook = passbook
                        dismiss()
                    }) {
                        HStack {
                            Text(passbook.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedPassbook?.persistentModelID == passbook.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            // 新しい口座を追加
            Section {
                NavigationLink(destination: AddPassbookView()) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("新しい口座を追加")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("口座を選択")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook1 = Passbook(name: "プライベート", type: .custom, sortOrder: 1)
    let passbook2 = Passbook(name: "漫画", type: .custom, sortOrder: 2)
    
    container.mainContext.insert(passbook1)
    container.mainContext.insert(passbook2)
    
    return PassbookSelectorView(selectedPassbook: .constant(nil))
        .modelContainer(container)
}
