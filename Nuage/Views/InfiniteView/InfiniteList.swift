//
//  InfiniteList.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI
import Combine
import Introspect
import AppKit
import SoundCloud

enum InfinitePublisher<Element: Decodable&Identifiable&Filterable&Hashable> {
    case page(AnyPublisher<Page<Element>, Error>)
    case array(AnyPublisher<[String], Error>, ([String]) -> AnyPublisher<[Element], Error>)
}

struct InfiniteList<Element: Decodable&Identifiable&Filterable&Hashable, Row: View>: View {
    
    private var publisher: InfinitePublisher<Element>
    private var row: (Element) -> Row
    
    @State private var filter = ""
    @State private var isSearching = false
    
    @Environment(\.header) private var header: AnyView
    @EnvironmentObject private var commands: CommandSubject
    
    var body: some View {
        if case let .page(publisher) = publisher {
            PageView(publisher: publisher, content: list)
        }
        else if case let .array(arrayPublisher, pagePublisher) = publisher {
            ArrayView(arrayPublisher: arrayPublisher, pagePublisher: pagePublisher, content: list)
        }
    }
    
    @ViewBuilder func list(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<displayedElements.count+1, id: \.self) {idx in
                        if idx == 0 {
                            header
                        }
                        else {
                            row(displayedElements[idx-1])
                                .id(idx)
                                .onAppear {
                                    if idx == elements.count/2 {
                                        getNextPage()
                                    }
                                }
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 16)
                .padding(.horizontal, 8)
            }
            .introspectScrollView { scrollView in
                scrollView.scrollerStyle = .overlay
                scrollView.verticalScroller?.controlSize = .small
            }
            .playbackContext(displayedElements)
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
    
    private func stopFiltering() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearching = false
            filter = ""
        }
    }
    
    init(publisher: InfinitePublisher<Element>, @ViewBuilder row: @escaping (Element) -> Row) {
        self.publisher = publisher
        self.row = row
    }

}

extension View {
    
    func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        self.environment(\.header, AnyView(content()))
    }
    
}

struct HeaderKey: EnvironmentKey {
    
    static let defaultValue = AnyView(EmptyView())
    
}

extension EnvironmentValues {
    
    var header: AnyView {
        get { self[HeaderKey.self] }
        set { self[HeaderKey.self] = newValue }
    }
    
}
