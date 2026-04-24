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
