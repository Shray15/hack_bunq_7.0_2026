import SwiftUI

enum AppTheme {
    static let primary = Color(red: 0.20, green: 0.67, blue: 0.45)
    static let primaryDeep = Color(red: 0.11, green: 0.32, blue: 0.23)
    static let accent = Color(red: 0.94, green: 0.53, blue: 0.24)
    static let backgroundTop = Color(red: 0.95, green: 0.98, blue: 0.96)
    static let backgroundBottom = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let card = Color.white.opacity(0.96)
    static let mutedCard = Color(red: 0.91, green: 0.96, blue: 0.93)
    static let stroke = Color.black.opacity(0.06)
    static let secondaryText = Color(red: 0.36, green: 0.43, blue: 0.40)
    static let text = Color(red: 0.10, green: 0.14, blue: 0.13)
    static let success = Color(red: 0.19, green: 0.63, blue: 0.43)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppTheme.primary.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: 90, y: -80)
        }
        .ignoresSafeArea()
    }
}

struct AppCard<Content: View>: View {
    let padding: CGFloat
    let background: Color
    @ViewBuilder let content: Content

    init(
        padding: CGFloat = 18,
        background: Color = AppTheme.card,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.background = background
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
    }
}

struct AppSectionHeader: View {
    let eyebrow: String?
    let title: String
    let detail: String?

    init(_ title: String, eyebrow: String? = nil, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.primary)
            }

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.text)

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct AppTag: View {
    let title: String
    let color: Color
    let icon: String?

    init(_ title: String, color: Color, icon: String? = nil) {
        self.title = title
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.text)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct RemoteImageView<Placeholder: View>: View {
    let url: URL?
    let cornerRadius: CGFloat
    @ViewBuilder let placeholder: Placeholder

    init(
        url: URL?,
        cornerRadius: CGFloat = 22,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder()
    }

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = AppTheme.primary) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: color.opacity(0.22), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AppIconValueRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.text)
            }
            Spacer()
        }
    }
}

extension View {
    func appScrollContentPadding() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
    }
}
