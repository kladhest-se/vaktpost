import SwiftUI

/// A reusable confirmation dialog for write operations.
///
/// Presents a modal with a title, message, and optional destructive action
/// label. The user must explicitly confirm before the action is executed.
struct ConfirmationSheet: View {

    let title: String
    let message: String?
    let destructive: Bool
    let destructiveLabel: String
    let confirmLabel: String
    let cancelLabel: String
    let onConfirm: () async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming = false
    @State private var error: String?

    var body: some View {
        ZStack {
            themeManager.bg.ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(themeManager.label)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .scaledFont(14)
                        .foregroundStyle(themeManager.labelMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error {
                    Text(error)
                        .scaledFont(13)
                        .foregroundStyle(themeManager.bad)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isConfirming {
                    ProgressView()
                        .tint(themeManager.accentColor)
                        .scaleEffect(0.8)
                }

                HStack(spacing: 12) {
                    Button(cancelLabel) {
                        dismiss()
                        onCancel()
                    }
                    .scaledFont(15)
                    .foregroundStyle(themeManager.label)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(themeManager.cardRaised)

                    Button(destructiveLabel) {
                        isConfirming = true
                        Task {
                            await onConfirm()
                            dismiss()
                            isConfirming = false
                        }
                    }
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(themeManager.palette.crust)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(destructive ? themeManager.bad : themeManager.accentColor)
                    .disabled(isConfirming)
                }
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: 320)
            .background(themeManager.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .presentationBackground(themeManager.bg)
    }

    @Environment(\.themeManager) private var themeManager
}

/// Extension to present a confirmation sheet from any view.
extension View {

    /// Presents a confirmation sheet for a write operation.
    ///
    /// - Parameters:
    ///   - isPresented: Binding to control presentation.
    ///   - title: Dialog title.
    ///   - message: Optional message explaining the operation.
    ///   - destructive: Whether the action is destructive (red button).
    ///   - destructiveLabel: Label for the confirm button.
    ///   - confirmLabel: Label for the cancel button.
    ///   - onConfirm: Sync closure to execute on confirmation.
    ///   - onCancel: Sync closure to execute on cancellation.
    func confirmationSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        destructive: Bool = false,
        destructiveLabel: String = "Confirm",
        confirmLabel: String = "Cancel",
        onConfirm: @escaping () async -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(ConfirmationSheetModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            destructive: destructive,
            destructiveLabel: destructiveLabel,
            confirmLabel: confirmLabel,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }
}

private struct ConfirmationSheetModifier: ViewModifier {

    let isPresented: Binding<Bool>
    let title: String
    let message: String?
    let destructive: Bool
    let destructiveLabel: String
    let confirmLabel: String
    let onConfirm: () async -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented) {
                ConfirmationSheet(
                    title: title,
                    message: message,
                    destructive: destructive,
                    destructiveLabel: destructiveLabel,
                    confirmLabel: "Confirm",
                    cancelLabel: confirmLabel,
                    onConfirm: onConfirm,
                    onCancel: onCancel
                )
            }
    }
}
