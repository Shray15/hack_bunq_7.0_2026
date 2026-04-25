import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var health: HealthKitService
    @EnvironmentObject private var auth: AuthService
    @State private var weightText: String = ""
    @State private var heightText: String = ""
    @State private var showSignOutConfirm = false
    @FocusState private var focusedField: ProfileField?

    enum ProfileField: Hashable {
        case name, weight, height
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        identityCard
                        targetsCard
                        bodyStatsCard
                        goalsCard
                        dietCard
                        healthCard
                        orderHistoryCard
                        signOutCard
                    }
                    .appScrollContentPadding()
                }
            }
            .navigationTitle("Profile")
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                weightText = formatKg(appState.bodyweightKg)
                heightText = formatCm(appState.heightCm)
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue == nil {
                    commitWeightTextIfNeeded()
                    commitHeightTextIfNeeded()
                }
            }
            .toolbar {
                if focusedField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                "Sign out of Cooking Companion?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    // Cancel the in-flight profile PATCH synchronously so the next
                    // 401 doesn't trigger handleUnauthorized after we've already
                    // logged out.
                    appState.prepareForSignOut()
                    // Wait for the confirmation dialog to fully dismiss before
                    // we wipe the auth token. Flipping auth state mid-dismissal
                    // crashes (iOS 17.0–17.3) or freezes (17.4+) the view tree.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        auth.logout()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved recipes and local goals stay on this device. You can sign back in anytime.")
            }
        }
    }

    // MARK: - Order history

    private var orderHistoryCard: some View {
        NavigationLink {
            OrderHistoryView()
        } label: {
            AppCard(padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.primary.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Order history")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text("All paid orders, meal-card and bunq.me.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sign out

    private var signOutCard: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                Text("Sign out")
                    .font(.headline)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.red.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign out of Cooking Companion")
    }

    // MARK: - Identity

    private var identityCard: some View {
        AppCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primary, AppTheme.primaryDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .shadow(color: AppTheme.primary.opacity(0.22), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Your name", text: $appState.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = nil }

                    Text(profileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Targets summary

    private var targetsCard: some View {
        AppCard(background: AppTheme.primary.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily target")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .textCase(.uppercase)
                        Text("\(formatKcal(appState.dailyCalorieTarget)) kcal")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.text)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: appState.goal.icon)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.primary)
                        .clipShape(Circle())
                }

                let macros = appState.macroTargets
                HStack(spacing: 10) {
                    MacroChip(label: "Protein", value: "\(macros.protein)g", color: .blue)
                    MacroChip(label: "Carbs",   value: "\(macros.carbs)g",   color: AppTheme.primary)
                    MacroChip(label: "Fat",     value: "\(macros.fat)g",     color: .purple)
                }

                Text("BMR \(formatKcal(appState.bmr)) · TDEE \(formatKcal(appState.tdee)) · \(appState.goal.label) phase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    // MARK: - Body stats

    private var bodyStatsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Body stats")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                HStack(spacing: 10) {
                    statField(
                        icon: "scalemass.fill",
                        tint: AppTheme.accent,
                        title: "Weight",
                        unit: "kg",
                        text: $weightText,
                        field: .weight
                    )
                    statField(
                        icon: "ruler.fill",
                        tint: .blue,
                        title: "Height",
                        unit: "cm",
                        text: $heightText,
                        field: .height
                    )
                }

                HStack(spacing: 12) {
                    AppIconValueRow(
                        icon: "calendar",
                        tint: AppTheme.primary,
                        title: "Age",
                        value: "\(appState.age)"
                    )
                    InlineStepper(
                        value: $appState.age,
                        range: 14...90,
                        step: 1
                    )
                }

                segmentedRow(
                    title: "Biological sex",
                    selection: Binding(
                        get: { appState.biologicalSex },
                        set: { appState.biologicalSex = $0 }
                    ),
                    options: BiologicalSex.allCases,
                    label: { $0.label }
                )
            }
        }
    }

    private func statField(
        icon: String,
        tint: Color,
        title: String,
        unit: String,
        text: Binding<String>,
        field: ProfileField
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(12)
        .background(AppTheme.mutedCard.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Goals

    private var goalsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Training goal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                VStack(spacing: 10) {
                    ForEach(NutritionGoal.allCases) { goal in
                        GoalRow(
                            goal: goal,
                            isSelected: goal == appState.goal
                        ) {
                            appState.goal = goal
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accent.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity level")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(appState.activityLevel.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                    }

                    Spacer()

                    Menu {
                        ForEach(ActivityLevel.allCases) { level in
                            Button {
                                appState.activityLevel = level
                            } label: {
                                if level == appState.activityLevel {
                                    Label(level.label, systemImage: "checkmark")
                                } else {
                                    Text(level.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Change")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Change activity level")
                }
            }
        }
    }

    // MARK: - Diet & household

    private var dietCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Preferences")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                dietRow
                Divider()
                HStack(spacing: 12) {
                    AppIconValueRow(
                        icon: "person.2.fill",
                        tint: AppTheme.primary,
                        title: "Default household",
                        value: "\(appState.householdSize) \(appState.householdSize == 1 ? "person" : "people")"
                    )
                    InlineStepper(
                        value: $appState.householdSize,
                        range: 1...10,
                        step: 1
                    )
                }
            }
        }
    }

    private var dietRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(AppTheme.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Diet style")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(appState.dietType.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
            }

            Spacer()

            Menu {
                ForEach(DietType.allCases, id: \.rawValue) { diet in
                    Button {
                        appState.dietType = diet
                    } label: {
                        if diet == appState.dietType {
                            Label(diet.rawValue, systemImage: "checkmark")
                        } else {
                            Text(diet.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Change")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Change diet style")
        }
    }

    // MARK: - Apple Health

    @ViewBuilder
    private var healthCard: some View {
        if health.isAvailable {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Apple Health")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.text)
                        Spacer()
                        if health.isAuthorized {
                            AppTag("Connected", color: AppTheme.success, icon: "checkmark.seal.fill")
                        }
                    }

                    if health.isAuthorized {
                        VStack(alignment: .leading, spacing: 8) {
                            HKStat(
                                icon: "scalemass.fill",
                                tint: AppTheme.accent,
                                title: "Latest weight",
                                value: health.latestWeightKg.map { "\(formatKg($0)) kg" } ?? "—"
                            )
                            HKStat(
                                icon: "flame.fill",
                                tint: AppTheme.primary,
                                title: "Active energy today",
                                value: "\(health.todayActiveEnergyKcal) kcal"
                            )
                            HKStat(
                                icon: "figure.strengthtraining.traditional",
                                tint: .blue,
                                title: "Last workout",
                                value: health.lastWorkoutEndedAt.map { lastWorkoutLabel(for: $0) } ?? "—"
                            )
                        }

                        Button {
                            Task { await health.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.primary.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Connect Apple Health to auto-fill weight, sync workouts, and write meal calories back.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)

                        Button {
                            Task { await health.requestAuthorization() }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.fill")
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: .pink))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = appState.displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return parts.isEmpty ? "?" : parts.joined()
    }

    private var profileSubtitle: String {
        let weight = formatKg(appState.bodyweightKg)
        let people = appState.householdSize == 1 ? "solo" : "\(appState.householdSize) people"
        return "\(weight) kg · \(appState.goal.label) · \(people)"
    }

    private func formatKg(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func formatCm(_ value: Double) -> String {
        String(Int(value))
    }

    private func formatKcal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func lastWorkoutLabel(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if interval < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func commitWeightTextIfNeeded() {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), value > 30, value < 300 {
            appState.bodyweightKg = value
            weightText = formatKg(value)
        } else {
            weightText = formatKg(appState.bodyweightKg)
        }
    }

    private func commitHeightTextIfNeeded() {
        let normalized = heightText.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), value > 100, value < 240 {
            appState.heightCm = value
            heightText = formatCm(value)
        } else {
            heightText = formatCm(appState.heightCm)
        }
    }

    private func segmentedRow<Option: Hashable>(
        title: String,
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(option == selection.wrappedValue ? .white : AppTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(option == selection.wrappedValue ? AppTheme.primary : AppTheme.mutedCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Goal row

private struct GoalRow: View {
    let goal: NutritionGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : AppTheme.primary)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? AppTheme.primary : AppTheme.primary.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                    Text(goal.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .padding(12)
            .background(isSelected ? AppTheme.primary.opacity(0.08) : AppTheme.mutedCard.opacity(0.6))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.primary.opacity(0.6) : AppTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro chip

private struct MacroChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - HealthKit stat

private struct HKStat: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
        }
    }
}

// MARK: - Inline stepper

private struct InlineStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", enabled: value > range.lowerBound) {
                let next = value - step
                value = max(next, range.lowerBound)
            }
            .accessibilityLabel("Decrease")

            stepperButton(systemImage: "plus", enabled: value < range.upperBound) {
                let next = value + step
                value = min(next, range.upperBound)
            }
            .accessibilityLabel("Increase")
        }
        .background(AppTheme.mutedCard)
        .overlay {
            Capsule()
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? AppTheme.primary : AppTheme.secondaryText.opacity(0.4))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

