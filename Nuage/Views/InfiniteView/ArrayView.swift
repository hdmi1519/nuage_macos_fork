//
//  ArrayView.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import Combine
import SwiftUI

private let idSubcription = -1

struct ArrayView<ID, Element: Decodable&Identifiable, ContentView: View>: View {
    
    @State private var ids = [ID]()
    @State private var elements = [Element]()
    @State private var elementRange = 0..<16
    
    private var arrayPublisher: AnyPublisher<[ID], Error>
    private var pagePublisher: ([ID]) -> AnyPublisher<[Element], Error>
    @State private var subscriptions = [Int: AnyCancellable]()
    
    private var content: ([Element], @escaping () -> ()) -> ContentView
    
    var body: some View {
        Group {
            if elements.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                content(elements, getNextPage)
            }
        }
        .onAppear {
            arrayPublisher.receive(on: RunLoop.main)
                .replaceError(with: [])
                .sink { elementIDs in
                    ids = elementIDs
                    getNextPage()
                }
                .store(in: &subscriptions, key: idSubcription)
            
            getNextPage()
        }
    }
    
    init(arrayPublisher: AnyPublisher<[ID], Error>,
         pagePublisher: @escaping ([ID]) -> AnyPublisher<[Element], Error>,
         @ViewBuilder content: @escaping ([Element], @escaping () -> ()) -> ContentView) {
        self.arrayPublisher = arrayPublisher
        self.pagePublisher = pagePublisher
        self.content = content
    }
    
    private func getNextPage() {
        guard !ids.isEmpty else { return }
        let clampedStart = max(0, min(elementRange.lowerBound, ids.count))
        let clampedEnd = max(clampedStart, min(elementRange.upperBound, ids.count))
        let range = clampedStart..<clampedEnd
        guard range.count > 0 else { return }
        guard subscriptions[elements.count] == nil else { return }
        
        let page = Array(ids[range])
        
        pagePublisher(page)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { page in
                elements.insert(contentsOf: page, at: range.startIndex)
                let nextStart = min(range.endIndex, ids.count)
                let nextEnd = min(ids.count, nextStart + min(range.count * 2, 50))
                elementRange = nextStart..<max(nextStart, nextEnd)
            })
            .store(in: &subscriptions, key: elements.count)
    }
    
}
