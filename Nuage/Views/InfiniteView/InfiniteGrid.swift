//
//  InfiniteGrid.swift
//  Nuage
//
//  Created by Laurin Brandner on 05.02.21.
//

import SwiftUI
import GridStack

struct InfiniteGrid<Element: Decodable&Identifiable&Filterable&Hashable, Item: View>: View {
    
    private var publisher: InfinitePublisher<Element>
    private var item: ([Element], Int) -> Item
    @State private var filter = ""
    @State private var isSearching = false
    
    @EnvironmentObject private var commands: CommandSubject
    
    var body: some View {
        if case let .page(publisher) = publisher {
            PageView(publisher: publisher, content: grid)
        }
        else if case let .array(arrayPublisher, pagePublisher) = publisher {
            ArrayView(arrayPublisher: arrayPublisher, pagePublisher: pagePublisher, content: grid)
        }
    }
    
    @ViewBuilder func grid(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
        let displayedElements = (filter.count > 0) ? elements.filter { $0.contains(filter) } : elements
        
        VStack(spacing: 0) {
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField(LocalizedStringKey("menu.filter"), text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onChange(of: filter, perform: { _ in
                            getNextPage()
                        })
                        .introspectTextField { field in
                            field.focusRingType = .none
                            if field.window?.firstResponder != field {
                                field.becomeFirstResponder()
                            }
                        }
                    
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onExitCommand(perform: stopFiltering)
            }
            
            GridStack(minCellWidth: 100, spacing: 20, numItems: displayedElements.count, alignment: .leading) { idx, width in
                item(displayedElements, idx)
                    .id(idx)
                    .onAppear {
                    if idx == elements.count/2 {
                        getNextPage()
                    }
                }
            }
            .onReceive(commands.filter) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSearching {
                        stopFiltering()
                    } else {
                        isSearching = true
                    }
                }
            }
            .onExitCommand(perform: stopFiltering)
        }
    }
    
    init(publisher: InfinitePublisher<Element>, @ViewBuilder item: @escaping ([Element], Int) -> Item) {
        self.publisher = publisher
        self.item = item
    }
    
    private func stopFiltering() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearching = false
            filter = ""
        }
    }
    
}
