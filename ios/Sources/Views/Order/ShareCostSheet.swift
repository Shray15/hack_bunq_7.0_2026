import SwiftUI
import UIKit

/// Post-checkout "Split the cost" sheet. User picks how many friends are
/// joining; we mint a fixed-amount bunq.me link via the backend and let the
/// user share it with the system share sheet.
struct ShareCostSheet: View {
    let orderId: String
    let totalEur: Double
    let recipeName: String

    @Environment(\.dismiss) private var dismiss

    @State private var friendCount: Int = 1
    @State private var isLoading: Bool = false
    @State private var share: MealShare?
    @State private var copyToast: Bool = false
    @State private var errorMsg: String?

    private var divisor: Int { friendCount + 1 }
    private var perPersonPreview: Double {
        guard divisor > 1 else { return totalEur }
        return (totalEur / Double(divisor) * 100).rounded() / 100
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let share {
                            resultView(share: share)
                        } else {
                            inputView
                        }
                        if let errorMsg {
                            Text(errorMsg)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .appScrollContentPadding()
                }

                VStack {
                    Spacer()
                    if let share {
                        actionButtons(for: share)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    } else {
                        generateButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }

                if copyToast {
                    VStack {
                        Spacer()
                        Text("Link copied")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(AppTheme.primaryDeep)
                            .clipShape(Capsule())
                            .padding(.bottom, 100)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .animation(.easeOut(duration: 0.2), value: copyToast)
                }
            }
            .navigationTitle(share == nil ? "Split the cost" : "Share the link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Input state (before generation)

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How many friends are joining?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text("We'll generate a bunq.me link with their share — friends pay you back via iDEAL, card, or bank transfer.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            stepperCard
            previewCard
        }
    }

    private var stepperCard: some View {
        AppCard(padding: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friends")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Plus you = \(divisor) people")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Stepper(value: $friendCount, in: 1...9) {
                    Text("\(friendCount)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .monospacedDigit()
                }
                .labelsHidden()
            }
        }
    }

    private var previewCard: some View {
        AppCard(padding: 18, background: AppTheme.mutedCard) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Per person")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("€\(format(perPersonPreview))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryDeep)
                        .monospacedDigit()
                }
                Divider()
                HStack {
                    Text("Total cart")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("€\(format(totalEur))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                HStack {
                    Text("Split across")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("\(divisor) people")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(isLoading ? "Generating link…" : "Generate share link")
            }
        }
        .buttonStyle(AppPrimaryButtonStyle())
        .disabled(isLoading)
    }

    // MARK: - Result state (after generation)

    private func resultView(share: MealShare) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("€\(format(share.perPersonEur)) each")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text("Send the link below to your \(share.participantCount) \(share.participantCount == 1 ? "friend" : "friends"). Each opens it in any browser and pays via iDEAL, card, or bank.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            urlCard(share: share)

            statusFooter(share: share)
        }
    }

    private func urlCard(share: MealShare) -> some View {
        AppCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BUNQ.ME LINK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(share.shareURL)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusFooter(share: MealShare) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(share.status == "open" ? AppTheme.success : AppTheme.secondaryText)
                .frame(width: 8, height: 8)
            Text(share.status == "open" ? "Link is live" : "Link is closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func actionButtons(for share: MealShare) -> some View {
        VStack(spacing: 10) {
            if let url = URL(string: share.shareURL) {
                ShareLink(
                    item: url,
                    message: Text(prefilledMessage(share: share))
                ) {
                    Label("Share with friends", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }

            Button {
                UIPasteboard.general.string = share.shareURL
                withAnimation { copyToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    withAnimation { copyToast = false }
                }
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primary)
        }
    }

    // MARK: - Actions

    private func generate() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            share = try await APIService.shared.createShareCost(
                orderId: orderId,
                participantCount: friendCount,
                includeSelf: true
            )
        } catch {
            errorMsg = "Could not generate share link: \(error.localizedDescription)"
        }
    }

    private func prefilledMessage(share: MealShare) -> String {
        "Hey! Here's your €\(format(share.perPersonEur)) share for tonight's \(recipeName). Tap to pay via bunq:"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
