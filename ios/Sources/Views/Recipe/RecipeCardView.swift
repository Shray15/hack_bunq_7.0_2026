import SwiftUI

struct RecipeCardView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImageView(url: recipe.imageURL, cornerRadius: 24) {
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.18), AppTheme.accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title2)
                            .foregroundStyle(AppTheme.primaryDeep.opacity(0.7))
                    }
                }
                .frame(height: 168)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                HStack(spacing: 8) {
                    AppTag("\(recipe.calories) kcal", color: .white, icon: "flame.fill")
                    AppTag("\(recipe.prepTimeMin) min", color: .white, icon: "clock")
                }
                .padding(14)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    MacroTag(label: "\(Int(recipe.macros.proteinG))g protein", color: .blue)
                    if recipe.macros.carbsG < 20 {
                        MacroTag(label: "Keto", color: AppTheme.primary)
                    }
                    if recipe.macros.proteinG > 35 {
                        MacroTag(label: "High-protein", color: AppTheme.accent)
                    }
                }

                HStack(spacing: 12) {
                    Label("\(Int(recipe.macros.proteinG)) g protein", systemImage: "bolt.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    Label("\(Int(recipe.macros.carbsG)) g carbs", systemImage: "leaf.fill")
                        .foregroundStyle(AppTheme.primary)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(16)
        }
        .frame(width: 256)
        .background(AppTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }
}

struct MacroTag: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Recipe library

struct RecipeLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecipe: Recipe?
    @State private var query = ""
    @State private var filter: RecipeLibraryFilter = .all

    private let mealSlots = ["Breakfast", "Lunch", "Dinner"]

    private var filteredRecipes: [Recipe] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.recipeLibrary
            .filter { recipe in
                matchesSearch(recipe, needle: needle) && filter.includes(recipe, isSaved: appState.isRecipeSaved(recipe))
            }
            .sorted { lhs, rhs in
                let lhsSaved = appState.isRecipeSaved(lhs)
                let rhsSaved = appState.isRecipeSaved(rhs)
                if lhsSaved != rhsSaved { return lhsSaved && !rhsSaved }
                if lhs.macros.proteinG != rhs.macros.proteinG {
                    return lhs.macros.proteinG > rhs.macros.proteinG
                }
                return lhs.calories < rhs.calories
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        librarySummary
                        searchField
                        filterRow
                        recipeList
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedRecipe) { recipe in
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recipe library")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.text)

            Text("\(appState.recipeLibrary.count) meals sorted by calories, protein, prep time, and saved status.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var librarySummary: some View {
        AppCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    summaryMetrics
                }

                VStack(spacing: 12) {
                    summaryMetrics
                }
            }
        }
    }

    private var summaryMetrics: some View {
        Group {
            LibraryMetric(
                title: "Saved",
                value: "\(appState.savedRecipes.count)",
                icon: "bookmark.fill",
                tint: AppTheme.primary
            )
            LibraryMetric(
                title: "Avg protein",
                value: "\(averageProtein)g",
                icon: "bolt.fill",
                tint: .blue
            )
            LibraryMetric(
                title: "Under 500",
                value: "\(under500Count)",
                icon: "flame.fill",
                tint: AppTheme.accent
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            TextField("Search recipes or ingredients", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(AppTheme.text)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(RecipeLibraryFilter.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            filter = option
                        }
                    } label: {
                        Label(option.rawValue, systemImage: option.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == option ? .white : AppTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == option ? AppTheme.primary : AppTheme.primary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var recipeList: some View {
        VStack(alignment: .leading, spacing: 14) {
            LibrarySectionTitle(title: sectionTitle, action: "\(filteredRecipes.count)")

            if filteredRecipes.isEmpty {
                EmptyRecipeLibraryView {
                    query = ""
                    filter = .all
                }
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(filteredRecipes) { recipe in
                        RecipeLibraryRow(
                            recipe: recipe,
                            isSaved: appState.isRecipeSaved(recipe),
                            mealSlots: mealSlots,
                            onOpen: { selectedRecipe = recipe },
                            onToggleSave: { appState.toggleSavedRecipe(recipe) },
                            onUse: { slot in appState.useRecipe(recipe, for: slot) }
                        )
                    }
                }
            }
        }
    }

    private var sectionTitle: String {
        switch filter {
        case .all: return "All recipes"
        case .saved: return "Saved recipes"
        case .highProtein: return "High-protein"
        case .under500: return "Under 500 kcal"
        case .lowCarb: return "Low carb"
        }
    }

    private var averageProtein: Int {
        guard !appState.recipeLibrary.isEmpty else { return 0 }
        let total = appState.recipeLibrary.reduce(0) { $0 + Int($1.macros.proteinG) }
        return total / appState.recipeLibrary.count
    }

    private var under500Count: Int {
        appState.recipeLibrary.filter { $0.calories <= 500 }.count
    }

    private func matchesSearch(_ recipe: Recipe, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        if recipe.name.localizedCaseInsensitiveContains(needle) { return true }
        return recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(needle) }
    }
}

private enum RecipeLibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case saved = "Saved"
    case highProtein = "High protein"
    case under500 = "Under 500"
    case lowCarb = "Low carb"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .saved: return "bookmark.fill"
        case .highProtein: return "bolt.fill"
        case .under500: return "flame.fill"
        case .lowCarb: return "leaf.fill"
        }
    }

    func includes(_ recipe: Recipe, isSaved: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .saved:
            return isSaved
        case .highProtein:
            return recipe.macros.proteinG >= 35
        case .under500:
            return recipe.calories <= 500
        case .lowCarb:
            return recipe.macros.carbsG <= 25
        }
    }
}

private struct LibrarySectionTitle: View {
    let title: String
    let action: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.text)
            Spacer()
            Text(action)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.primary.opacity(0.10))
                .clipShape(Capsule())
        }
    }
}

private struct LibraryMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecipeLibraryRow: View {
    let recipe: Recipe
    let isSaved: Bool
    let mealSlots: [String]
    let onOpen: () -> Void
    let onToggleSave: () -> Void
    let onUse: (String) -> Void

    private var ingredientPreview: String {
        recipe.ingredients
            .prefix(3)
            .map { $0.name.capitalized }
            .joined(separator: ", ")
    }

    var body: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Button(action: onOpen) {
                        RemoteImageView(url: recipe.imageURL, cornerRadius: 18) {
                            ZStack {
                                AppTheme.mutedCard
                                Image(systemName: "fork.knife")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.primaryDeep.opacity(0.65))
                            }
                        }
                        .frame(width: 92, height: 92)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(recipe.name)")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Button(action: onOpen) {
                                Text(recipe.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button(action: onToggleSave) {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(isSaved ? AppTheme.primary : AppTheme.secondaryText)
                                    .frame(width: 34, height: 34)
                                    .background((isSaved ? AppTheme.primary : AppTheme.secondaryText).opacity(0.10))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSaved ? "Remove saved recipe" : "Save recipe")
                        }

                        Text(ingredientPreview)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            MacroTag(label: "\(recipe.calories) kcal", color: AppTheme.accent)
                            MacroTag(label: "\(Int(recipe.macros.proteinG))g protein", color: .blue)
                        }
                    }
                }

                RecipeMacroStrip(recipe: recipe)

                HStack(spacing: 10) {
                    Menu {
                        ForEach(mealSlots, id: \.self) { slot in
                            Button(slot) {
                                onUse(slot)
                            }
                        }
                    } label: {
                        Label("Use", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.primary)
                            .clipShape(Capsule())
                    }

                    Button(action: onOpen) {
                        Label("Details", systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.primary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Label("\(recipe.prepTimeMin) min", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }
}

private struct RecipeMacroStrip: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 8) {
            macro("Carbs", "\(Int(recipe.macros.carbsG))g", .green)
            macro("Fat", "\(Int(recipe.macros.fatG))g", .purple)
            macro("Time", "\(recipe.prepTimeMin)m", AppTheme.primary)
        }
    }

    private func macro(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EmptyRecipeLibraryView: View {
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 54, height: 54)
                .background(AppTheme.primary.opacity(0.10))
                .clipShape(Circle())

            Text("No matching recipes")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.text)

            Button {
                onClear()
            } label: {
                Text("Clear filters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(AppTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
