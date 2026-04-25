import SwiftUI

// MARK: - Palette
//
// Editorial Warm — premium food-magazine vibe.
// Burnt terracotta primary + honey-gold accent + champagne/ivory backgrounds
// designed to flatter food photography and read as "Apple-app-of-the-year".

enum AppTheme {
    // Brand
    static let primary       = Color(red: 0.78, green: 0.27, blue: 0.10)   // burnt terracotta
    static let primaryDeep   = Color(red: 0.36, green: 0.13, blue: 0.05)   // deep mahogany
    static let primarySoft   = Color(red: 0.96, green: 0.83, blue: 0.74)   // tinted highlight
    static let accent        = Color(red: 0.86, green: 0.55, blue: 0.13)   // honey gold
    static let accentDeep    = Color(red: 0.55, green: 0.30, blue: 0.04)   // dark amber

    // Surfaces
    static let backgroundTop    = Color(red: 0.99, green: 0.96, blue: 0.91) // champagne cream
    static let backgroundBottom = Color(red: 1.00, green: 0.98, blue: 0.94) // warm ivory
    static let card             = Color.white.opacity(0.98)
    static let mutedCard        = Color(red: 0.97, green: 0.92, blue: 0.85) // peach cream
    static let softPanel        = Color(red: 0.99, green: 0.94, blue: 0.86) // lighter peach for info cards

    // Lines + ink
    static let stroke         = Color.black.opacity(0.06)
    static let strokeStrong   = Color.black.opacity(0.10)
    static let secondaryText  = Color(red: 0.44, green: 0.36, blue: 0.32)   // warm graphite
    static let text           = Color(red: 0.18, green: 0.10, blue: 0.06)   // deep cocoa ink

    // Semantic
    static let success        = Color(red: 0.34, green: 0.55, blue: 0.30)   // olive emerald
    static let danger         = Color(red: 0.78, green: 0.20, blue: 0.20)   // warm red

    // Brand partnership
    static let bunqGreen      = Color(red: 0.00, green: 0.83, blue: 0.30)   // bunq brand lime
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Warm terracotta bloom in the top-right.
            Circle()
                .fill(AppTheme.primary.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 140, y: -140)

            // Honey-gold bloom in the bottom-left.
            Circle()
                .fill(AppTheme.accent.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: 220)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

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
            // Layered shadow: a tight contact shadow plus a wider warm bloom
            // for a more dimensional, magazine-like depth.
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .shadow(color: AppTheme.primary.opacity(0.06), radius: 22, y: 12)
    }
}

// MARK: - Section header

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
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(1.2)
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

// MARK: - Tag

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
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}

// MARK: - Metric chip

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
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14))
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
        .background(AppTheme.mutedCard.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Remote image

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
                if let url, url.scheme == "data",
                   let uiImage = decodeDataURL(url) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
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
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func decodeDataURL(_ url: URL) -> UIImage? {
        let raw = url.absoluteString
        guard let commaIndex = raw.firstIndex(of: ",") else { return nil }
        let payload = String(raw[raw.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Primary button

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
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: color.opacity(0.32), radius: 18, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Icon row

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
                .background(tint.opacity(0.14))
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

// MARK: - Powered by bunq

/// Brand attribution — required for the bunq hackathon. Two flavours:
/// `.pill` for prominent moments (auth landing), `.inline` for subtle
/// footers (post-checkout, settings).
struct BunqAttribution: View {
    enum Variant { case pill, inline }

    let variant: Variant

    init(_ variant: Variant = .pill) {
        self.variant = variant
    }

    var body: some View {
        switch variant {
        case .pill:
            HStack(spacing: 6) {
                Text("Powered by")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("bunq")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.bunqGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.card)
            .overlay {
                Capsule()
                    .stroke(AppTheme.stroke, lineWidth: 1)
            }
            .clipShape(Capsule())
            .shadow(color: AppTheme.bunqGreen.opacity(0.18), radius: 14, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Powered by bunq")

        case .inline:
            HStack(spacing: 4) {
                Text("Powered by")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.85))
                Text("bunq")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(AppTheme.bunqGreen)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Powered by bunq")
        }
    }
}

// MARK: - Layout

extension View {
    func appScrollContentPadding() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
    }
}
