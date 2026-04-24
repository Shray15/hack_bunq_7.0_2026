import SwiftUI

struct VoiceButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse: CGFloat = 1

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.16))
                        .frame(width: 62, height: 62)
                        .scaleEffect(pulse)
                }

                Circle()
                    .fill(isRecording ? Color.red : AppTheme.primary)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) {
            if isRecording {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    pulse = 1.35
                }
            } else {
                withAnimation(.default) { pulse = 1 }
            }
        }
    }
}
