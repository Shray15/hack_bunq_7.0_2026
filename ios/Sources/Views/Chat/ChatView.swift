import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @StateObject private var speech = SpeechService()
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var selectedRecipe: Recipe?
    @State private var hasRequestedSpeechPermission = false
    @State private var shouldSubmitRecordedTranscript = false
    @State private var recordingErrorMessage: String?
    @State private var showClearConfirm = false
    @State private var lastSpokenMessageID: UUID?
    @FocusState private var isInputFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                messagesArea
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerArea
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.backgroundTop.opacity(0.96), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Plan a meal")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !vm.messages.isEmpty {
                        Button {
                            showClearConfirm = true
                        } label: {
                            Text("New")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.card.opacity(0.9))
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel("Start a new plan")
                    }
                }
            }
            .confirmationDialog(
                "Start a new plan?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear conversation", role: .destructive) {
                    vm.reset()
                    inputText = ""
                    recordingErrorMessage = nil
                    speech.stopSpeaking()
                    lastSpokenMessageID = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the current brief and recipe options.")
            }
            .navigationDestination(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
        .task {
            submitPendingPlanningBrief()
            await speech.requestAuthorization()
            hasRequestedSpeechPermission = true
        }
        .onChange(of: appState.planningPrefill) {
            submitPendingPlanningBrief()
        }
        .onChange(of: vm.suggestedRecipes) {
            appState.addRecipesToLibrary(vm.suggestedRecipes)
        }
        .onChange(of: speech.isRecording, initial: false) { wasRecording, isRecording in
            guard wasRecording, !isRecording, shouldSubmitRecordedTranscript else { return }
            shouldSubmitRecordedTranscript = false
            let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            send(transcript)
        }
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if vm.messages.isEmpty {
                        EmptyPromptView { prompt in
                            send(prompt)
                        }
                        .padding(.top, 8)
                    }

                    ForEach(vm.messages) { msg in
                        ChatBubbleView(message: msg) { recipe in
                            selectedRecipe = recipe
                        }
                        .id(msg.id)
                    }

                    if !vm.streamingText.isEmpty {
                        assistantBubble(text: vm.streamingText)
                            .id("streaming")
                    }

                    if vm.isLoading && vm.streamingText.isEmpty {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) {
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    if last.role == .assistant, last.id != lastSpokenMessageID, !last.text.isEmpty {
                        lastSpokenMessageID = last.id
                        speech.speak(last.text)
                    }
                }
            }
            .onChange(of: vm.streamingText) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private func assistantBubble(text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            BotAvatar()

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.text)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer(minLength: 42)
        }
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(spacing: 8) {
            if hasContextStrip {
                contextStrip
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            composerBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(height: 1)
        }
        .animation(.easeOut(duration: 0.18), value: contextStripKey)
    }

    private var composerBar: some View {
        ZStack {
            if speech.isRecording {
                recordingRow
                    .transition(.opacity)
            } else {
                inputRow
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 56)
        .background(AppTheme.card.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(composerBorderColor, lineWidth: composerBorderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
        .animation(.easeInOut(duration: 0.22), value: speech.isRecording)
        .animation(.easeOut(duration: 0.18), value: isInputFocused)
        .animation(.easeOut(duration: 0.18), value: vm.isLoading)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "Tell us what's happening today",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.black)
            .focused($isInputFocused)
            .submitLabel(.send)
            .lineLimit(1...4)
            .onSubmit {
                guard canSend else { return }
                send(inputText)
            }
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.vertical, 12)

            trailingButtonStack
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
    }

    private var recordingRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                AudioWaveBars(tint: .red)
                    .frame(width: 30)

                Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 18)
            .padding(.vertical, 12)

            VoiceButton(isRecording: true, size: 38) {
                handleVoiceTap()
            }
            .accessibilityLabel("Stop recording and send")
            .padding(.trailing, 6)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var trailingButtonStack: some View {
        HStack(spacing: 6) {
            if vm.isLoading {
                stopStreamingButton
                    .transition(.scale.combined(with: .opacity))
            } else if trimmedInput.isEmpty {
                primaryMicButton
                    .transition(.scale.combined(with: .opacity))
            } else {
                sendButton
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: trailingStateKey)
    }

    private var trailingStateKey: String {
        if vm.isLoading { return "loading" }
        if trimmedInput.isEmpty { return "empty" }
        return "typing"
    }

    private var primaryMicButton: some View {
        Button {
            handleVoiceTap()
        } label: {
            Image(systemName: "mic.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(speechPermissionDenied ? AppTheme.secondaryText.opacity(0.6) : AppTheme.primary)
                .clipShape(Circle())
                .shadow(color: AppTheme.primary.opacity(speechPermissionDenied ? 0 : 0.28), radius: 8, y: 4)
        }
        .disabled(speechPermissionDenied)
        .accessibilityLabel("Start voice brief")
    }

    private var sendButton: some View {
        Button {
            send(inputText)
        } label: {
            Image(systemName: "arrow.up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.primary)
                .clipShape(Circle())
                .shadow(color: AppTheme.primary.opacity(0.32), radius: 8, y: 4)
        }
        .accessibilityLabel("Send")
    }

    private var stopStreamingButton: some View {
        Button {
            vm.cancel()
        } label: {
            Image(systemName: "stop.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.secondaryText)
                .clipShape(Circle())
        }
        .accessibilityLabel("Stop response")
    }

    private var composerBorderColor: Color {
        if speech.isRecording { return Color.red.opacity(0.55) }
        if vm.isLoading        { return AppTheme.primary.opacity(0.45) }
        if isInputFocused      { return AppTheme.primary.opacity(0.55) }
        return AppTheme.stroke
    }

    private var composerBorderWidth: CGFloat {
        speech.isRecording || vm.isLoading || isInputFocused ? 1.5 : 1
    }

    // MARK: - Context strip

    private var contextStripKey: String {
        if let recordingErrorMessage { return "err:\(recordingErrorMessage)" }
        if speech.isRecording { return "rec" }
        if speechPermissionDenied { return "denied" }
        if vm.isLoading { return "loading" }
        return ""
    }

    private var hasContextStrip: Bool {
        !contextStripKey.isEmpty
    }

    @ViewBuilder
    private var contextStrip: some View {
        if let recordingErrorMessage {
            stripView(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                title: recordingErrorMessage,
                action: nil
            )
        } else if speech.isRecording {
            stripView(
                icon: "waveform",
                tint: .red,
                title: speech.transcript.isEmpty ? "Listening… speak naturally." : "Listening…",
                action: nil
            )
        } else if speechPermissionDenied {
            stripView(
                icon: "mic.slash.fill",
                tint: .red,
                title: "Voice is off. Typing still works.",
                action: ("Settings", openAppSettings)
            )
        } else if vm.isLoading {
            stripView(
                icon: "sparkles",
                tint: AppTheme.primary,
                title: vm.streamingText.isEmpty ? "Planner is thinking…" : "Streaming response…",
                action: nil
            )
        }
    }

    private func stripView(
        icon: String,
        tint: Color,
        title: String,
        action: (label: String, run: () -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let action {
                Button(action.label, action: action.run)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !vm.isLoading && !trimmedInput.isEmpty
    }

    private var speechPermissionDenied: Bool {
        hasRequestedSpeechPermission && !speech.isAuthorized
    }

    private func openAppSettings() {
        if let url = URL(string: "app-settings:") {
            openURL(url)
        }
    }

    private func handleVoiceTap() {
        recordingErrorMessage = nil

        if speech.isRecording {
            speech.stopRecording()
            return
        }

        guard speech.isAuthorized else {
            recordingErrorMessage = "Voice is unavailable right now. Type the same brief below."
            return
        }

        do {
            shouldSubmitRecordedTranscript = true
            try speech.startRecording()
        } catch {
            shouldSubmitRecordedTranscript = false
            recordingErrorMessage = "Could not start the microphone. Try typing the brief instead."
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speech.stopSpeaking()
        isInputFocused = false
        inputText = ""
        recordingErrorMessage = nil
        vm.send(trimmed, profile: appState.userProfile())
    }

    private func submitPendingPlanningBrief() {
        guard let brief = appState.consumePlanningPrefill() else { return }
        send(brief)
    }
}

// MARK: - Empty state

struct EmptyPromptView: View {
    let onPromptSelected: (String) -> Void

    private let suggestions: [PromptSuggestion] = [
        .init(
            title: "Post-workout",
            detail: "35g+ protein",
            prompt: "Post-workout meal with at least 35 grams of protein",
            icon: "bolt.fill",
            tint: AppTheme.primary
        ),
        .init(
            title: "Cut-friendly",
            detail: "Dinner under 550 kcal",
            prompt: "Cut-friendly dinner under 550 calories with vegetables",
            icon: "flame.fill",
            tint: AppTheme.accent
        ),
        .init(
            title: "Meal prep",
            detail: "3 training lunches",
            prompt: "Three high-protein lunch prep recipes for training days",
            icon: "calendar",
            tint: AppTheme.primaryDeep
        ),
        .init(
            title: "Vegetarian protein",
            detail: "High-fiber dinner",
            prompt: "Vegetarian high-protein dinner with beans or tofu",
            icon: "leaf.fill",
            tint: AppTheme.accent
        )
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tell us what's happening.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                Text("Speak or type people, timing, diet, calories, and training goal. We turn it into recipes you can checkout.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(suggestions) { suggestion in
                    PromptSuggestionCard(suggestion: suggestion) {
                        onPromptSelected(suggestion.prompt)
                    }
                }
            }
        }
    }
}

private struct PromptSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let prompt: String
    let icon: String
    let tint: Color
}

private struct PromptSuggestionCard: View {
    let suggestion: PromptSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: suggestion.icon)
                    .font(.headline)
                    .foregroundStyle(suggestion.tint)
                    .frame(width: 36, height: 36)
                    .background(suggestion.tint.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(14)
            .background(AppTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.title). \(suggestion.detail)")
    }
}

// MARK: - Bubble & helpers

struct ChatBubbleView: View {
    let message: ChatMessage
    let onRecipeSelect: (Recipe) -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var isAssistant: Bool {
        message.role == .assistant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                if isAssistant {
                    BotAvatar()
                } else {
                    Spacer(minLength: 42)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(isAssistant ? AppTheme.text : .white)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isAssistant ? AppTheme.card : AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if isAssistant {
                    Spacer(minLength: 42)
                } else {
                    Circle()
                        .fill(AppTheme.primaryDeep.opacity(0.14))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.primaryDeep)
                        }
                }
            }

            HStack {
                if isAssistant {
                    Text(Self.timeFormatter.string(from: message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                } else {
                    Spacer()
                    Text(Self.timeFormatter.string(from: message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.leading, isAssistant ? 42 : 0)
            .padding(.trailing, isAssistant ? 0 : 42)

            if let recipes = message.recipes, !recipes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recipes) { recipe in
                            RecipeCardView(recipe: recipe)
                                .onTapGesture { onRecipeSelect(recipe) }
                        }
                    }
                    .padding(.leading, isAssistant ? 42 : 0)
                    .padding(.trailing, 4)
                }
            }
        }
    }
}

struct BotAvatar: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            BotAvatar()

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppTheme.secondaryText.opacity(0.75))
                        .frame(width: 7, height: 7)
                        .offset(y: animating ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.38)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct AudioWaveBars: View {
    let tint: Color
    var bars: Int = 5
    var minHeight: CGFloat = 5
    var maxHeight: CGFloat = 22
    var speed: Double = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = t * speed + Double(i) * 0.65
                    let normalized = (sin(phase) + 1) / 2
                    let height = minHeight + (maxHeight - minHeight) * normalized
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }
}
