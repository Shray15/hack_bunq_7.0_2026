import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @StateObject private var speech = SpeechService()
    @State private var inputText = ""
    @State private var selectedRecipe: Recipe?
    @State private var hasRequestedSpeechPermission = false
    @State private var shouldSubmitRecordedTranscript = false
    @State private var recordingErrorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                messagesArea
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerPanel
            }
            .navigationTitle("Plan a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !vm.messages.isEmpty {
                        Button {
                            vm.reset()
                            inputText = ""
                            recordingErrorMessage = nil
                        } label: {
                            Text("Clear")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.card.opacity(0.9))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
        .task {
            await speech.requestAuthorization()
            hasRequestedSpeechPermission = true
        }
        .onChange(of: speech.isRecording, initial: false) { wasRecording, isRecording in
            guard wasRecording, !isRecording, shouldSubmitRecordedTranscript else { return }
            shouldSubmitRecordedTranscript = false
            let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            Task { await send(transcript) }
        }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let latestCommittedTask, !vm.messages.isEmpty {
                        ChatContextPill(text: latestCommittedTask)
                    }

                    if vm.messages.isEmpty {
                        EmptyPromptView { prompt in
                            inputText = prompt
                            Task { await send(prompt) }
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
            .onChange(of: vm.messages.count) {
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
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

    private var composerPanel: some View {
        VStack(spacing: 12) {
            taskBar
            voicePanel
            textComposer
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(height: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: -6)
    }

    private var taskBar: some View {
        AppCard(padding: 16, background: AppTheme.card.opacity(0.94)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(taskBarTitle, systemImage: taskBarIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(taskBarTint)

                    Spacer()

                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear draft") {
                            inputText = ""
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    } else if let latestCommittedTask, !speech.isRecording {
                        Button("Reuse") {
                            inputText = latestCommittedTask
                            isInputFocused = true
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    }
                }

                Text(taskBarText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineSpacing(3)

                Text(taskBarSupportText)
                    .font(.caption)
                    .foregroundStyle(recordingErrorMessage == nil ? AppTheme.secondaryText : .red)
            }
        }
    }

    private var voicePanel: some View {
        AppCard(padding: 18, background: AppTheme.mutedCard.opacity(0.92)) {
            VStack(spacing: 14) {
                VoiceButton(isRecording: speech.isRecording, size: 74) {
                    handleVoiceTap()
                }
                .disabled(vm.isLoading || speechPermissionDenied)
                .opacity(vm.isLoading || speechPermissionDenied ? 0.55 : 1)

                VStack(spacing: 4) {
                    Text(voicePanelTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)

                    Text(voicePanelDetail)
                        .font(.caption)
                        .foregroundStyle(speechPermissionDenied ? .red : AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    AppTag("Voice", color: AppTheme.primary, icon: "waveform")
                    AppTag("Hands free", color: AppTheme.accent, icon: "sparkles")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var textComposer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Quick lunch, high-protein, under 600 calories", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isInputFocused)
                .submitLabel(.send)
                .lineLimit(1...3)
                .onSubmit {
                    guard canSend else { return }
                    Task { await send(inputText) }
                }

            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    inputText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await send(inputText) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(canSend ? AppTheme.primary : AppTheme.primary.opacity(0.35))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.card.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var latestCommittedTask: String? {
        vm.messages.last(where: { $0.role == .user })?.text
    }

    private var speechPermissionDenied: Bool {
        hasRequestedSpeechPermission && !speech.isAuthorized
    }

    private var canSend: Bool {
        !vm.isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskBarTitle: String {
        if speech.isRecording { return "Listening live" }
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Draft request" }
        if latestCommittedTask != nil { return "Current brief" }
        return "Task bar"
    }

    private var taskBarIcon: String {
        if speech.isRecording { return "waveform" }
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "square.and.pencil" }
        if latestCommittedTask != nil { return "sparkles.rectangle.stack" }
        return "list.bullet.rectangle.portrait"
    }

    private var taskBarTint: Color {
        if speech.isRecording { return .red }
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return AppTheme.accent }
        return AppTheme.primary
    }

    private var taskBarText: String {
        if speech.isRecording {
            return speech.transcript.isEmpty
                ? "Listening for who it is for, the timing, the mood, and the food goal."
                : speech.transcript
        }

        let draft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { return draft }
        if let latestCommittedTask { return latestCommittedTask }
        return "Describe the people, occasion, diet, and calorie target. We will turn that into recipe options."
    }

    private var taskBarSupportText: String {
        if let recordingErrorMessage { return recordingErrorMessage }
        if speech.isRecording { return "Stop the mic when the brief sounds right. The transcript sends automatically." }
        if speechPermissionDenied { return "Speech recognition is off on this device. Typing still works." }
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Press send or hit return when the brief is ready."
        }
        return "Best results mention who it is for, the time available, and any diet or calorie constraints."
    }

    private var voicePanelTitle: String {
        if speech.isRecording { return "Recording now" }
        if speechPermissionDenied { return "Voice needs permission" }
        if vm.isLoading { return "Planner is responding" }
        return "Speak your meal brief"
    }

    private var voicePanelDetail: String {
        if speech.isRecording {
            return "Say it naturally. We will capture the brief and send it when you stop."
        }
        if speechPermissionDenied {
            return "Enable Microphone and Speech Recognition in Settings to use the voice flow."
        }
        if vm.isLoading {
            return "Hold on while the planner streams ideas back."
        }
        return "Great for longer requests like dinner for four tomorrow, something keto, or a date-night plan."
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

    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isInputFocused = false
        inputText = ""
        recordingErrorMessage = nil
        await vm.send(trimmed)
    }
}

struct EmptyPromptView: View {
    let onPromptSelected: (String) -> Void

    private let suggestions: [PromptSuggestion] = [
        .init(
            title: "High-protein reset",
            detail: "Dinner under 600 calories",
            prompt: "High-protein dinner under 600 calories",
            icon: "bolt.fill",
            tint: AppTheme.primary
        ),
        .init(
            title: "Keto lunch",
            detail: "Fast and solo",
            prompt: "Quick keto lunch for one",
            icon: "leaf.fill",
            tint: AppTheme.accent
        ),
        .init(
            title: "Family dinner",
            detail: "Chicken for four",
            prompt: "Dinner for four with chicken",
            icon: "person.3.fill",
            tint: AppTheme.primaryDeep
        ),
        .init(
            title: "Date night",
            detail: "Something impressive",
            prompt: "Something impressive for Saturday night",
            icon: "sparkles",
            tint: AppTheme.accent
        )
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        AppTag("Voice first", color: AppTheme.primary, icon: "waveform")
                        Spacer()
                        AppTag("Checkout ready", color: AppTheme.accent, icon: "cart.fill")
                    }

                    Text("Tell us what is happening. We handle the food.")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.text)

                    Text("Describe the people, timing, dietary limits, and calorie goal. The planner answers with recipe choices that are ready for checkout.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    HStack(spacing: 12) {
                        MetricChip(title: "Recipe options", value: "4 ideas", icon: "square.grid.2x2.fill", tint: AppTheme.primary)
                        MetricChip(title: "Voice to order", value: "One flow", icon: "waveform.and.mic", tint: AppTheme.accent)
                    }
                }
            }

            AppSectionHeader("Start fast", detail: "Tap one or say the same thing out loud.")

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
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.headline)
                    .foregroundStyle(suggestion.tint)
                    .frame(width: 38, height: 38)
                    .background(suggestion.tint.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .padding(16)
            .background(AppTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatContextPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.primary)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryDeep)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.primary.opacity(0.14))
        .clipShape(Capsule())
    }
}

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
