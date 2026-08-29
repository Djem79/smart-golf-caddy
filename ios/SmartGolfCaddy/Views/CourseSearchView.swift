// ios/SmartGolfCaddy/Views/CourseSearchView.swift
import SwiftUI

struct CourseSearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @Environment(LocaleManager.self) private var lm
    @State private var model = CourseSearchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            searchField
            DSButton(
                title: model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? lm.t.courseSearch.manualEntry
                    : lm.t.courseSearch.useQuery(model.searchText.trimmingCharacters(in: .whitespaces)),
                style: .secondary
            ) {
                store.selectedCourse = nil
                let query = model.searchText.trimmingCharacters(in: .whitespaces)
                store.prefillCourseName = query.isEmpty ? nil : query
                router.push(.roundSetup)
            }
            .padding(.horizontal, DS.screenPadding)
            content
        }
        .background(DSColor.surface)
        .navigationTitle(lm.t.courseSearch.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DSColor.onSurfaceVariant)
            TextField(lm.t.courseSearch.searchPlaceholder, text: $model.searchText)
                .font(DSFont.bodyMD)
                .onChange(of: model.searchText) { _, _ in model.searchChanged() }
        }
        .padding(12)
        .background(DSColor.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage, model.visible.isEmpty {
            VStack(spacing: 12) {
                Text(message)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
                if !model.geoDenied {
                    DSButton(title: lm.t.common.retry, style: .secondary) {
                        model.start()
                    }
                    .padding(.horizontal, 64)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DS.screenPadding)
        } else if model.loading && model.visible.isEmpty {
            ProgressView(lm.t.courseSearch.searchingNearby)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visible.isEmpty {
            Text(lm.t.courseSearch.noResults)
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DS.screenPadding)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.visible) { course in
                        courseCard(course)
                    }
                }
                .padding(DS.screenPadding)
            }
        }
    }

    private func courseCard(_ course: CourseResult) -> some View {
        Button {
            store.selectedCourse = course
            store.prefillCourseName = nil
            router.push(.roundSetup)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(DSColor.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    Text(course.vicinity)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let rating = course.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Text("\(String(format: "%.1f", course.distanceKm)) \(lm.t.common.km)")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DSColor.primary)
            }
            .padding(12)
            .background(DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }
}
