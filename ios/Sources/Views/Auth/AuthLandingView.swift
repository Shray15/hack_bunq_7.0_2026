import SwiftUI

struct AuthLandingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login = "Sign in"
        case signup = "Create account"
        var id: String { rawValue }
    }

    @EnvironmentObject private var auth: AuthService
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Field: Hashable {
        case email, password
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    formCard
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { focused = nil }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 78, height: 78)
            .shadow(color: AppTheme.primary.opacity(0.28), radius: 18, y: 10)

            VStack(spacing: 6) {
                Text("Cooking Companion")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.text)
                Text("AI meal plans, real groceries, paid via bunq.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
    }

    private var formCard: some View {
        AppCard {
            VStack(spacing: 18) {
                modeToggle

                fieldRow(
                    icon: "envelope.fill",
                    title: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    field: .email,
                    keyboard: .emailAddress,
                    autocapitalize: false,
                    secure: false
                )

                fieldRow(
                    icon: "lock.fill",
                    title: "Password",
                    placeholder: "At least 8 characters",
                    text: $password,
                    field: .password,
                    keyboard: .default,
                    autocapitalize: false,
                    secure: true
                )

                if let error = auth.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        if auth.isWorking {
                            ProgressView().tint(.white)
                        }
                        Text(mode == .login ? "Sign in" : "Create account")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(!isFormValid || auth.isWorking)
                .opacity(isFormValid ? 1 : 0.7)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { option in
                Button {
                    if mode != option {
                        mode = option
                        auth.lastError = nil
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(option == mode ? .white : AppTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(option == mode ? AppTheme.primary : AppTheme.mutedCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fieldRow(
        icon: String,
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType,
        autocapitalize: Bool,
        secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 26, height: 26)
                    .background(AppTheme.primary.opacity(0.12))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
            }

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } else {
                    TextField(placeholder, text: text)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
            }
            .textFieldStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(AppTheme.text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled(true)
            .focused($focused, equals: field)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.mutedCard.opacity(0.7))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(mode == .login ? "New here? Tap Create account above." : "Already have an account? Tap Sign in above.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                Text("Password must be 8–128 characters.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.8))
            }

            BunqAttribution(.pill)
        }
    }

    // MARK: - Validation + actions

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        guard !trimmedEmail.isEmpty else { return false }
        return trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    private var isPasswordValid: Bool {
        password.count >= 8 && password.count <= 128
    }

    private var isFormValid: Bool {
        isEmailValid && isPasswordValid
    }

    private func submit() {
        focused = nil
        guard isFormValid else { return }
        Task {
            switch mode {
            case .login:
                await auth.login(email: trimmedEmail, password: password)
            case .signup:
                await auth.signup(email: trimmedEmail, password: password)
            }
        }
    }
}
