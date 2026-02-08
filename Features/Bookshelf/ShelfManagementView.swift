//
//  ShelfManagementView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfManagementView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: BookshelfViewModel
    @State private var newShelfName = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Shelves") {
                    ForEach(viewModel.shelves, id: \.name) { shelf in
                        Text(shelf.name)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteShelf(name: viewModel.shelves[index].name)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveShelves(from: source, to: destination)
                    }
                }
                
                Section("Add Shelf") {
                    HStack {
                        TextField("Shelf name", text: $newShelfName)
                        Button {
                            let name = newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                viewModel.createShelf(name: name)
                                newShelfName = ""
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(newShelfName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Manage Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
