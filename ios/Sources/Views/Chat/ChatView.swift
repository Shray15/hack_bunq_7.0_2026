import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @StateObject private var speech = SpeechService()
    @State private var inputText = ""
    @State private var selectedRecipe: Recipe?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    messagesArea
                    inputBar
                }
            }
            .navigationTitle("AI planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.card)
                            .clipShape(Circle())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !vm.messages.isEmpty {
                        Button("Clear") {
                            vm.reset()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    }
                }
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
        .task { await speech.requestAuthorization() }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if vm.messages.isEmpty {
                        EmptyPromptView { prompt in
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
                .appScrollContentPadding()
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer(minLength: 42)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            if speech.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                    Text(speech.transcript.isEmpty ? "Listening..." : speech.transcript)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 12) {
                TextField("Quick lunch, high-protein, under 600 calories", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VoiceButton(isRecording: speech.isRecording) {
                    if speech.isRecording {
                        speech.stopRecording()
                        let transcript = speech.transcript
                        if !transcript.isEmpty {
                            Task { await send(transcript) }
                        }
                    } else {
                        try? speech.startRecording()
                    }
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
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        await vm.send(trimmed)
    }
}

struct EmptyPromptView: View {
    let onPromptSelected: (String) -> Void

    private let chips = [
        "High-protein dinner under 600 calories",
        "Quick keto lunch for one",
        "Dinner for four with chicken",
        "Something impressive for Saturday night",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        AppTag("Voice first", color: AppTheme.primary, icon: "waveform")
                        Spacer()
                    }

                    Text("Tell us what is happening. We handle the food.")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.text)

                    Text("Say who you're cooking for, the mood, dietary limits, and calorie target. The app responds with ready-to-order options.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    HStack(spacing: 12) {
                        MetricChip(title: "Recipe options", value: "4 ideas", icon: "square.grid.2x2.fill", tint: AppTheme.primary)
                        MetricChip(title: "Checkout ready", value: "AH + bunq", icon: "cart.fill", tint: AppTheme.accent)
                    }
                }
            }

            AppSectionHeader("Try one", detail: "Good prompts make the result feel premium.")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        onPromptSelected(chip)
                    } label: {
                        HStack {
                            Text(chip)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.text)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onRecipeSelect: (Recipe) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                if message.role == .assistant {
                    BotAvatar()
                } else {
                    Spacer(minLength: 42)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? .white : AppTheme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.role == .user ? AppTheme.primary : AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if message.role == .user {
                    Circle()
                        .fill(AppTheme.primaryDeep.opacity(0.14))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.primaryDeep)
                        }
                } else {
                    Spacer(minLength: 42)
                }
            }

            if let recipes = message.recipes, !recipes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recipes) { recipe in
                            RecipeCardView(recipe: recipe)
                                .onTapGesture { onRecipeSelect(recipe) }
                        }
                    }
                    .padding(.leading, 42)
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
