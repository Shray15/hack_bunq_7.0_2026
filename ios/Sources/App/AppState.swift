import Foundation
import Combine

struct DayKcal: Identifiable, Hashable, Codable {
    var id = UUID()
    let date: Date
    let kcal: Int?
}

@MainActor
final class AppState: ObservableObject {
    @Published var displayName: String = "Sai" { didSet { persistDisplayName() } }
    @Published var dietType: DietType = .balanced { didSet { schedulePatchIfChanged(dietType, oldValue) } }
    @Published var householdSize: Int = 1 { didSet { persistHouseholdSize() } }

    // MARK: - Body stats & goal (persisted)

    @Published var bodyweightKg: Double = 70 { didSet { persistBodyStats(); schedulePatchIfChanged(bodyweightKg, oldValue) } }
    @Published var heightCm: Double = 175 { didSet { persistBodyStats(); schedulePatchIfChanged(heightCm, oldValue) } }
    @Published var age: Int = 30 { didSet { persistBodyStats(); schedulePatchIfChanged(age, oldValue) } }
    @Published var biologicalSex: BiologicalSex = .male { didSet { persistBodyStats(); schedulePatchIfChanged(biologicalSex, oldValue) } }
    @Published var goal: NutritionGoal = .maintain { didSet { persistBodyStats(); schedulePatchIfChanged(goal, oldValue) } }
    @Published var activityLevel: ActivityLevel = .moderate { didSet { persistBodyStats(); schedulePatchIfChanged(activityLevel, oldValue) } }

    // MARK: - Library & meal state

    @Published var recipeLibrary: [Recipe] = [] { didSet { persistRecipeLibrary() } }
    @Published var savedRecipeIDs: Set<String> = [] { didSet { persistSavedRecipeIDs() } }
    @Published var plannedMeals: [PlannedMeal] = [] { didSet { persistPlannedMeals() } }
    @Published var weeklyHistory: [DayKcal] = [] { didSet { persistWeeklyHistory() } }
    @Published var upcomingDelivery: Date?
    @Published var planningPrefill: String?
    @Published var pendingMealSlot: String?

    // MARK: - Bodyweight log & water

    @Published var weightLog: [WeightEntry] = [] { didSet { persistWeightLog() } }
    @Published private(set) var waterByDate: [String: Int] = [:] {
        didSet { persistWaterLog() }
    }

    /// While true, didSet observers skip persisting. Used during hydration to
    /// stop the just-loaded values from being written straight back out.
    private var isHydrating = false

    // MARK: - Backend profile sync state

    /// True once we've at least attempted a fetch this session. Stops the
    /// debounced PATCH from racing the initial GET on launch.
    @Published private(set) var hasFetchedBackendProfile: Bool = false
    private var profileSyncTask: Task<Void, Never>?

    // MARK: - Meal card (bunq sandbox monthly grocery card)

    /// Current month's meal card. nil if the user hasn't set one up yet,
    /// or while the first GET is in flight. Refreshed via `refreshMealCard()`.
    @Published var currentMealCard: MealCard?
    @Published private(set) var mealCardLoading: Bool = false

    // MARK: - HealthKit-sourced state

    @Published var lastWorkoutEndedAt: Date?
    @Published var todayActiveEnergyKcal: Int = 0
    @Published var healthKitAuthorized: Bool = false

    init() {
        hydrateFromStore()
        loadMock()
    }

    /// Re-hydrate every persisted slice from `UserStore` for the user that's
    /// currently authenticated. Call this after login / on auth flips so the
    /// previous user's residual state isn't shown.
    func reloadForCurrentUser() {
        hydrateFromStore()
        loadMock()
    }

    /// Cancel any in-flight backend sync before the keychain token is wiped.
    /// Call this immediately before `AuthService.logout()`.
    /// Intentionally does NOT touch `hasFetchedBackendProfile` — that fires
    /// `objectWillChange` on every observer, which creates extra churn while
    /// SwiftUI is mid-dismissing the sign-out confirmation dialog.
    func prepareForSignOut() {
        profileSyncTask?.cancel()
        profileSyncTask = nil
    }

    // MARK: - Persistence

    private func persistBodyStats() {
        guard !isHydrating else { return }
        let snapshot = BodyStatsSnapshot(
            bodyweightKg: bodyweightKg,
            heightCm: heightCm,
            age: age,
            biologicalSex: biologicalSex,
            goal: goal,
            activityLevel: activityLevel
        )
        UserStore.save(snapshot, for: .bodyStats)
    }

    private func persistWeightLog() {
        guard !isHydrating else { return }
        UserStore.save(weightLog, for: .weightLog)
    }

    private func persistWaterLog() {
        guard !isHydrating else { return }
        UserStore.save(waterByDate, for: .waterByDate)
    }

    private func persistRecipeLibrary() {
        guard !isHydrating else { return }
        UserStore.save(recipeLibrary, for: .recipeLibrary)
    }

    private func persistSavedRecipeIDs() {
        guard !isHydrating else { return }
        UserStore.save(Array(savedRecipeIDs), for: .savedRecipeIDs)
    }

    private func persistPlannedMeals() {
        guard !isHydrating else { return }
        UserStore.save(plannedMeals, for: .plannedMeals)
    }

    private func persistWeeklyHistory() {
        guard !isHydrating else { return }
        UserStore.save(weeklyHistory, for: .weeklyHistory)
    }

    private func persistDisplayName() {
        guard !isHydrating else { return }
        UserStore.save(displayName, for: .displayName)
    }

    private func persistHouseholdSize() {
        guard !isHydrating else { return }
        UserStore.save(householdSize, for: .householdSize)
    }

    private func hydrateFromStore() {
        isHydrating = true
        defer { isHydrating = false }

        if let snapshot = UserStore.load(BodyStatsSnapshot.self, for: .bodyStats) {
            bodyweightKg = snapshot.bodyweightKg
            heightCm = snapshot.heightCm
            age = snapshot.age
            biologicalSex = snapshot.biologicalSex
            goal = snapshot.goal
            activityLevel = snapshot.activityLevel
        }
        weightLog    = UserStore.load([WeightEntry].self, for: .weightLog)        ?? []
        waterByDate  = UserStore.load([String: Int].self, for: .waterByDate)      ?? [:]
        recipeLibrary = UserStore.load([Recipe].self, for: .recipeLibrary)        ?? []
        plannedMeals  = UserStore.load([PlannedMeal].self, for: .plannedMeals)    ?? []
        weeklyHistory = UserStore.load([DayKcal].self, for: .weeklyHistory)       ?? []
        savedRecipeIDs = Set(UserStore.load([String].self, for: .savedRecipeIDs)  ?? [])
        if let name = UserStore.load(String.self, for: .displayName) {
            displayName = name
        }
        if let hh = UserStore.load(Int.self, for: .householdSize) {
            householdSize = hh
        }
    }

    // MARK: - Profile out

    // MARK: - Backend profile sync

    /// Fetch `/user/profile` and apply any server-side fields we honour.
    /// Called once per authenticated session from the root view.
    func refreshProfileFromBackend() async {
        do {
            let profile = try await APIService.shared.getProfile()
            ingest(profile)
        } catch {
            // Surfacing this is low priority — the user can keep editing locally
            // and the next PATCH will resync.
        }
        hasFetchedBackendProfile = true
    }

    // MARK: - Meal card

    /// Pull the current month's meal card from backend. nil = no card yet
    /// (Home tile shows the setup CTA in that case).
    func refreshMealCard() async {
        mealCardLoading = true
        defer { mealCardLoading = false }
        do {
            currentMealCard = try await APIService.shared.getCurrentMealCard()
        } catch {
            // Don't drop the cached card on transient errors — the tile keeps
            // showing the previous balance until the next refresh succeeds.
        }
    }

    /// Replace the in-memory card after a mutation (creation, top-up, charge).
    /// Lets views update without waiting for a follow-up GET round-trip.
    func setMealCard(_ card: MealCard?) {
        currentMealCard = card
    }

    /// Apply the server's view of the profile to local state, mapping wire
    /// strings back to typed enums. Body stats / goal / activity remain local
    /// because the backend does not store them.
    private func ingest(_ profile: BackendUserProfile) {
        if let raw = profile.diet, let mapped = DietType.fromBackend(raw), mapped != dietType {
            // Set without re-triggering a PATCH — the backend just told us this value.
            withoutPatchScheduling { dietType = mapped }
        }
    }

    /// Build the wire shape from current local state. Sent on every PATCH.
    func currentBackendProfile() -> BackendUserProfile {
        let macros = macroTargets
        return BackendUserProfile(
            diet: dietType.backendString,
            allergies: nil,
            dailyCalorieTarget: dailyCalorieTarget,
            proteinGTarget: macros.protein,
            carbsGTarget: macros.carbs,
            fatGTarget: macros.fat,
            storePriority: ["ah", "picnic"]
        )
    }

    /// Trigger a debounced PATCH. Skips the call when we haven't fetched yet
    /// (avoids racing the initial GET).
    private func schedulePatchIfChanged<Value: Equatable>(_ newValue: Value, _ oldValue: Value) {
        guard newValue != oldValue else { return }
        guard !suppressPatchScheduling else { return }
        guard hasFetchedBackendProfile else { return }
        profileSyncTask?.cancel()
        profileSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.currentBackendProfile()
            _ = try? await APIService.shared.patchProfile(snapshot)
        }
    }

    private var suppressPatchScheduling: Bool = false

    private func withoutPatchScheduling(_ work: () -> Void) {
        suppressPatchScheduling = true
        work()
        suppressPatchScheduling = false
    }

    func userProfile() -> UserProfile {
        let macros = macroTargets
        return UserProfile(
            dietType: dietType,
            dailyCalorieTarget: dailyCalorieTarget,
            proteinTargetG: Double(macros.protein),
            carbTargetG: Double(macros.carbs),
            fatTargetG: Double(macros.fat),
            householdSize: householdSize,
            bodyweightKg: bodyweightKg,
            heightCm: heightCm,
            age: age,
            biologicalSex: biologicalSex,
            goal: goal,
            activityLevel: activityLevel
        )
    }

    // MARK: - Derived targets

    var bmr: Int {
        Int(NutritionMath.bmr(
            weightKg: bodyweightKg,
            heightCm: heightCm,
            age: age,
            sex: biologicalSex
        ).rounded())
    }

    var tdee: Int {
        Int(NutritionMath.tdee(bmr: Double(bmr), activity: activityLevel).rounded())
    }

    var dailyCalorieTarget: Int {
        NutritionMath.calorieTarget(tdee: Double(tdee), goal: goal)
    }

    var macroTargets: (protein: Int, carbs: Int, fat: Int) {
        NutritionMath.macroGrams(
            calories: dailyCalorieTarget,
            bodyweightKg: bodyweightKg,
            goal: goal
        )
    }

    var waterTargetMl: Int {
        NutritionMath.waterTargetMl(weightKg: bodyweightKg)
    }

    // MARK: - Logged meals & consumed totals

    private var loggedMeals: [PlannedMeal] {
        plannedMeals.filter(\.isPlanned)
    }

    var mealLog: [PlannedMeal] {
        loggedMeals.sorted {
            ($0.loggedAt ?? .distantPast) > ($1.loggedAt ?? .distantPast)
        }
    }

    var consumedCalories: Int { loggedMeals.reduce(0) { $0 + $1.calories } }
    var consumedProtein: Int { loggedMeals.reduce(0) { $0 + $1.protein } }
    var consumedCarbs: Int { loggedMeals.reduce(0) { $0 + $1.carbs } }
    var consumedFat: Int { loggedMeals.reduce(0) { $0 + $1.fat } }
    var remainingCalories: Int { max(dailyCalorieTarget - consumedCalories, 0) }

    // MARK: - Recipes

    var savedRecipes: [Recipe] {
        recipeLibrary.filter { savedRecipeIDs.contains($0.id) }
    }

    func addRecipesToLibrary(_ recipes: [Recipe]) {
        for recipe in recipes {
            if let index = recipeLibrary.firstIndex(where: { $0.id == recipe.id }) {
                recipeLibrary[index] = recipe
            } else {
                recipeLibrary.append(recipe)
            }
        }
    }

    func isRecipeSaved(_ recipe: Recipe) -> Bool {
        savedRecipeIDs.contains(recipe.id)
    }

    func toggleSavedRecipe(_ recipe: Recipe) {
        addRecipesToLibrary([recipe])
        if savedRecipeIDs.contains(recipe.id) {
            savedRecipeIDs.remove(recipe.id)
        } else {
            savedRecipeIDs.insert(recipe.id)
        }
    }

    func useRecipe(_ recipe: Recipe, for slot: String) {
        addRecipesToLibrary([recipe])
        upsertPlannedMeal(
            slot: slot,
            recipe: recipe,
            title: nil,
            calories: recipe.calories,
            protein: Int(recipe.macros.proteinG),
            carbs: Int(recipe.macros.carbsG),
            fat: Int(recipe.macros.fatG),
            imageURL: recipe.imageURL,
            loggedAt: Date()
        )
        pendingMealSlot = nil
    }

    func requestPlanning(for slot: String) {
        pendingMealSlot = slot
        planningPrefill = planningBrief(for: slot)
    }

    func consumePlanningPrefill() -> String? {
        let prefill = planningPrefill
        planningPrefill = nil
        return prefill
    }

    func addMeal(
        name: String,
        kcal: Int,
        protein: Int,
        carbs: Int = 0,
        fat: Int = 0,
        time: Date = Date(),
        imageURL: URL? = nil
    ) {
        logMeal(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, time: time, imageURL: imageURL)
    }

    func removeMeal(id: String) {
        clearSlot(id)
    }

    func logMeal(
        name: String,
        kcal: Int,
        protein: Int,
        carbs: Int = 0,
        fat: Int = 0,
        time: Date = Date(),
        imageURL: URL? = nil
    ) {
        let slot = slot(for: time)
        upsertPlannedMeal(
            slot: slot,
            recipe: nil,
            title: name,
            calories: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            imageURL: imageURL,
            loggedAt: time
        )
    }

    func clearSlot(_ slot: String) {
        upsertPlannedMeal(
            slot: slot,
            recipe: nil,
            title: nil,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            imageURL: nil,
            loggedAt: nil
        )
    }

    func completeOrder(recipe: Recipe, servings: Int) {
        let slot = pendingMealSlot ?? firstOpenMealSlot ?? "Dinner"
        upsertPlannedMeal(
            slot: slot,
            recipe: recipe,
            title: nil,
            calories: recipe.calories,
            protein: Int(recipe.macros.proteinG),
            carbs: Int(recipe.macros.carbsG),
            fat: Int(recipe.macros.fatG),
            imageURL: recipe.imageURL,
            loggedAt: Date()
        )
        upcomingDelivery = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
        pendingMealSlot = nil
    }

    // MARK: - Bodyweight log

    /// Latest entry (most recent date).
    var latestWeightEntry: WeightEntry? {
        weightLog.max(by: { $0.date < $1.date })
    }

    /// Last 14 days of logged weights, sorted oldest → newest.
    var recentWeightLog: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
        return weightLog
            .filter { $0.date >= Calendar.current.startOfDay(for: cutoff) }
            .sorted { $0.date < $1.date }
    }

    /// Difference (kg) between newest and 7-day prior weight, when available.
    var weightDelta7d: Double? {
        let sorted = weightLog.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: latest.date) ?? latest.date
        let priorEntries = sorted.filter { $0.date <= cutoff }
        guard let prior = priorEntries.last else { return nil }
        return latest.weightKg - prior.weightKg
    }

    func logWeight(_ kg: Double, on date: Date = Date()) {
        let entry = WeightEntry(date: Calendar.current.startOfDay(for: date), weightKg: kg)
        weightLog.removeAll { $0.dateKey == entry.dateKey }
        weightLog.append(entry)
        weightLog.sort { $0.date < $1.date }
        bodyweightKg = kg
    }

    func ingestHealthKitWeight(_ kg: Double, sampleDate: Date) {
        // Only update bodyweight from HealthKit if it's the most recent reading we have.
        if let latest = latestWeightEntry, latest.date >= sampleDate { return }
        logWeight(kg, on: sampleDate)
    }

    // MARK: - Water

    private func waterDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var waterTodayMl: Int {
        waterByDate[waterDateKey(Date())] ?? 0
    }

    func addWater(ml: Int, on date: Date = Date()) {
        let key = waterDateKey(date)
        waterByDate[key] = max((waterByDate[key] ?? 0) + ml, 0)
    }

    func resetWaterToday() {
        waterByDate[waterDateKey(Date())] = 0
    }

    // MARK: - HealthKit hooks (set by HealthKitService)

    func updateLastWorkout(_ date: Date?) {
        lastWorkoutEndedAt = date
    }

    func updateActiveEnergy(_ kcal: Int) {
        todayActiveEnergyKcal = kcal
    }

    /// True if a workout finished within the last 90 minutes.
    var isPostWorkoutWindow: Bool {
        guard let end = lastWorkoutEndedAt else { return false }
        return Date().timeIntervalSince(end) < 90 * 60
    }

    // MARK: - Mock seed

    /// Seeds defaults *only when the persisted state is empty* — so reopening
    /// the app preserves whatever the user has accumulated (chat-generated
    /// recipes, planned meals, weekly history). Mock mode adds demo fixtures
    /// on top, again only when there's no real saved state.
    private func loadMock() {
        let calendar = Calendar.current
        let now = Date()

        // Empty slots so MealRow renders the "Plan this meal" CTA on a clean
        // account. Existing slots from `hydrateFromStore` are kept.
        if plannedMeals.isEmpty {
            plannedMeals = [
                PlannedMeal(slot: "Breakfast", recipe: nil, title: nil, calories: 0, imageURL: nil, loggedAt: nil),
                PlannedMeal(slot: "Lunch",     recipe: nil, title: nil, calories: 0, imageURL: nil, loggedAt: nil),
                PlannedMeal(slot: "Dinner",    recipe: nil, title: nil, calories: 0, imageURL: nil, loggedAt: nil),
            ]
        }
        upcomingDelivery = nil

        guard APIService.shared.useMockData else {
            // Live backend: nothing to seed. recipeLibrary / weeklyHistory
            // populate organically as the user uses the app.
            return
        }

        // Demo mode below: only seed when persisted slot is genuinely empty.
        let breakfast = calendar.date(bySettingHour: 8, minute: 10, second: 0, of: now) ?? now
        let lunch = calendar.date(bySettingHour: 12, minute: 35, second: 0, of: now) ?? now

        if recipeLibrary.isEmpty {
            recipeLibrary = MockData.recipes
        }
        if savedRecipeIDs.isEmpty, let starterRecipe = MockData.recipes.first {
            savedRecipeIDs = [starterRecipe.id]
        }

        if weightLog.isEmpty {
            weightLog = (0..<7).map { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
                let drift = Double.random(in: -0.4...0.4)
                return WeightEntry(
                    date: calendar.startOfDay(for: date),
                    weightKg: bodyweightKg + drift
                )
            }
            .sorted { $0.date < $1.date }
        }

        let allSlotsEmpty = plannedMeals.allSatisfy { !$0.isPlanned }
        if allSlotsEmpty {
            plannedMeals = [
                PlannedMeal(
                    slot: "Breakfast",
                    recipe: nil,
                    title: "Overnight Oats",
                    calories: 380,
                    protein: 23,
                    carbs: 52,
                    fat: 10,
                    imageURL: URL(string: "https://images.unsplash.com/photo-1614961233913-a5113a4a34ed?w=300"),
                    loggedAt: breakfast
                ),
                PlannedMeal(
                    slot: "Lunch",
                    recipe: MockData.recipes.first,
                    title: nil,
                    calories: MockData.recipes.first?.calories ?? 540,
                    protein: Int(MockData.recipes.first?.macros.proteinG ?? 45),
                    carbs: Int(MockData.recipes.first?.macros.carbsG ?? 40),
                    fat: Int(MockData.recipes.first?.macros.fatG ?? 18),
                    imageURL: MockData.recipes.first?.imageURL,
                    loggedAt: lunch
                ),
                PlannedMeal(
                    slot: "Dinner",
                    recipe: nil,
                    title: nil,
                    calories: 0,
                    imageURL: nil,
                    loggedAt: nil
                ),
            ]
        }
        if weeklyHistory.isEmpty {
            weeklyHistory = generateMockHistory(today: now, calendar: calendar)
        }
    }

    private func generateMockHistory(today: Date, calendar: Calendar) -> [DayKcal] {
        var entries: [DayKcal] = []
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return entries
        }
        let mockKcal = [1660, 1825, 2110, 1740, 0, 0, 0]
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                continue
            }
            if calendar.isDate(date, inSameDayAs: today) {
                entries.append(DayKcal(date: date, kcal: nil))
            } else if date < today {
                entries.append(DayKcal(date: date, kcal: mockKcal[offset]))
            } else {
                entries.append(DayKcal(date: date, kcal: nil))
            }
        }
        return entries
    }

    private var firstOpenMealSlot: String? {
        plannedMeals.first { !$0.isPlanned }?.slot
    }

    private func planningBrief(for slot: String) -> String {
        let people = householdSize == 1 ? "one person" : "\(householdSize) people"
        let macros = macroTargets
        let remaining = max(remainingCalories, 450)
        let postWorkout = isPostWorkoutWindow
            ? " I just finished a workout, so prioritise fast carbs and around 40g protein."
            : ""
        return "Plan \(slot.lowercased()) for \(people), \(goal.label.lowercased()) phase, \(dietType.rawValue.lowercased()), around \(remaining) calories with at least \(min(macros.protein / 3, 45))g protein.\(postWorkout)"
    }

    private func slot(for time: Date) -> String {
        switch Calendar.current.component(.hour, from: time) {
        case 5..<11:  return "Breakfast"
        case 11..<16: return "Lunch"
        default:      return "Dinner"
        }
    }

    private func upsertPlannedMeal(
        slot: String,
        recipe: Recipe?,
        title: String?,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        imageURL: URL?,
        loggedAt: Date?
    ) {
        let updated = PlannedMeal(
            slot: slot,
            recipe: recipe,
            title: title,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            imageURL: imageURL,
            loggedAt: loggedAt
        )
        if let index = plannedMeals.firstIndex(where: { $0.slot == slot }) {
            plannedMeals[index] = updated
        } else {
            plannedMeals.append(updated)
        }
    }
}

private struct BodyStatsSnapshot: Codable {
    var bodyweightKg: Double
    var heightCm: Double
    var age: Int
    var biologicalSex: BiologicalSex
    var goal: NutritionGoal
    var activityLevel: ActivityLevel
}
