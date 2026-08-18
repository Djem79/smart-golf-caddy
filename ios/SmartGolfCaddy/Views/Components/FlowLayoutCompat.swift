// ios/SmartGolfCaddy/Views/Components/FlowLayoutCompat.swift
import SwiftUI

// Простейший flow-layout для чипов серии (перенос по строкам).
struct FlowLayoutCompat<Item, Content: View>: View {
    let items: [(offset: Int, element: Item)]
    let spacing: CGFloat
    @ViewBuilder let content: (Int, Item) -> Content

    init(items: [(offset: Int, element: Item)], spacing: CGFloat,
         @ViewBuilder content: @escaping (Int, Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        // LazyVGrid c adaptive-колонками даёт перенос чипов без ручной геометрии.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: spacing)], spacing: spacing) {
            ForEach(items, id: \.offset) { pair in
                content(pair.offset, pair.element)
            }
        }
    }
}
