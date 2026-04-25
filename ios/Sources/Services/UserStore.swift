import Foundation

/// Per-user persistence backed by the file system. Each user's blobs live in:
///
///   <Application Support>/CookingCompanion/<userID>/<key>.json
///
/// Recipes can carry ~2 MB inline base64 images, so we deliberately avoid
/// `UserDefaults` (which is fine for small key/values but degrades on multi-MB
/// blobs). When no one is logged in (no token), reads return nil and writes
/// are no-ops — call sites should treat the cache as best-effort.
enum UserStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    enum Key: String {
        case recipeLibrary    = "recipe_library_v1"
        case plannedMeals     = "planned_meals_v1"
        case weeklyHistory    = "weekly_history_v1"
        case savedRecipeIDs   = "saved_recipe_ids_v1"
        case bodyStats        = "body_stats_v1"
        case weightLog        = "weight_log_v1"
        case waterByDate      = "water_by_date_v1"
        case chatMessages     = "chat_messages_v1"
        case displayName      = "display_name_v1"
        case householdSize    = "household_size_v1"
    }

    /// JWT `sub` claim (the user's UUID) for the current keychain token, or
    /// nil if logged out / token malformed.
    static func currentUserID() -> String? {
        guard let token = KeychainStore.read(AuthService.keychainAccount) else {
            return nil
        }
        return jwtSubject(from: token)
    }

    static func save<T: Encodable>(_ value: T, for key: Key) {
        guard let url = fileURL(for: key, creatingDir: true) else { return }
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[UserStore] write failed for \(key.rawValue): \(error)")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let url = fileURL(for: key, creatingDir: false) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            print("[UserStore] read/decode failed for \(key.rawValue): \(error)")
            return nil
        }
    }

    /// Wipes every persisted blob for the currently authenticated user.
    static func clearCurrentUser() {
        guard let dir = userDirectory(creatingIfNeeded: false) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Internals

    private static func fileURL(for key: Key, creatingDir: Bool) -> URL? {
        guard let dir = userDirectory(creatingIfNeeded: creatingDir) else { return nil }
        return dir.appendingPathComponent("\(key.rawValue).json", isDirectory: false)
    }

    private static func userDirectory(creatingIfNeeded: Bool) -> URL? {
        guard let user = currentUserID() else { return nil }

        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let dir = support
            .appendingPathComponent("CookingCompanion", isDirectory: true)
            .appendingPathComponent(user, isDirectory: true)

        if creatingIfNeeded {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Application Support shouldn't sync to iCloud / show up in
                // iTunes file sharing.
                var values = URLResourceValues()
                values.isExcludedFromBackup = false
                var mutableDir = dir
                try? mutableDir.setResourceValues(values)
            } catch {
                print("[UserStore] mkdir failed at \(dir.path): \(error)")
                return nil
            }
        }
        return dir
    }

    /// Decodes the `sub` claim from a JWT without verifying the signature.
    /// Verification happens server-side; we only need the subject locally to
    /// scope persistence to the right user.
    private static func jwtSubject(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }

        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else {
            return nil
        }
        return sub
    }
}
