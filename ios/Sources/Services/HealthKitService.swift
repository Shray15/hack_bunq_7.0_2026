import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    @Published private(set) var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var latestWeightDate: Date?
    @Published private(set) var lastWorkoutEndedAt: Date?
    @Published private(set) var todayActiveEnergyKcal: Int = 0
    @Published private(set) var lastError: String?

    private weak var appState: AppState?

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKObjectType.workoutType()
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein)
        ]
    }

    private init() {}

    func bind(_ appState: AppState) {
        self.appState = appState
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            await refresh()
        } catch {
            isAuthorized = false
            lastError = error.localizedDescription
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard isAvailable else { return }
        async let weight = fetchLatestBodyMass()
        async let workout = fetchLastWorkoutEnd()
        async let energy = fetchTodayActiveEnergy()

        let (weightResult, workoutResult, energyResult) = await (weight, workout, energy)

        if let (kg, date) = weightResult {
            latestWeightKg = kg
            latestWeightDate = date
            appState?.ingestHealthKitWeight(kg, sampleDate: date)
        }
        lastWorkoutEndedAt = workoutResult
        appState?.updateLastWorkout(workoutResult)
        todayActiveEnergyKcal = energyResult
        appState?.updateActiveEnergy(energyResult)
    }

    // MARK: - Reads

    private func fetchLatestBodyMass() async -> (Double, Date)? {
        await mostRecentSample(for: HKQuantityType(.bodyMass)) { sample in
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            return (kg, sample.endDate)
        }
    }

    private func fetchLastWorkoutEnd() async -> Date? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let end = (samples?.first as? HKWorkout)?.endDate
                continuation.resume(returning: end)
            }
            store.execute(query)
        }
    }

    private func fetchTodayActiveEnergy() async -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let type = HKQuantityType(.activeEnergyBurned)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: Int(kcal.rounded()))
            }
            self.store.execute(query)
        }
    }

    private func mostRecentSample<T>(
        for type: HKQuantityType,
        transform: @escaping (HKQuantitySample) -> T
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: transform(sample))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Writes

    func writeMealNutrition(kcal: Int, proteinG: Int, mealName: String, at date: Date = Date()) async {
        guard isAvailable, isAuthorized else { return }
        let metadata = [HKMetadataKeyFoodType: mealName]
        var samples: [HKSample] = []

        if kcal > 0 {
            samples.append(
                HKQuantitySample(
                    type: HKQuantityType(.dietaryEnergyConsumed),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                    start: date,
                    end: date,
                    metadata: metadata
                )
            )
        }
        if proteinG > 0 {
            samples.append(
                HKQuantitySample(
                    type: HKQuantityType(.dietaryProtein),
                    quantity: HKQuantity(unit: .gram(), doubleValue: Double(proteinG)),
                    start: date,
                    end: date,
                    metadata: metadata
                )
            )
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }
}
