import SwiftUI

/// Presents an alert with an error message and optional recovery suggestion.
struct ErrorAlertModifier: ViewModifier {

    @Binding var isErrorPresented: Bool
    let error: WriteError

    func body(content: Content) -> some View {
        content.alert(
            error.title,
            isPresented: $isErrorPresented,
            actions: {
                Button("OK") {}
            },
            message: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.message)
                    if let suggestion = error.suggestion {
                        Text(suggestion)
                            .scaledFont(12)
                            .foregroundStyle(Color(uiColor: .systemGray))
                    }
                }
            }
        )
    }
}

/// Represents a formatted write error with optional suggestion.
struct WriteError {
    let title: String
    let message: String
    let suggestion: String?

    static func from(_ error: Error, operation: WriteOperation) -> WriteError {
        let title = "Operation failed"
        let message = WriteErrorFormatter.message(for: error, operation: operation)
        let suggestion = WriteErrorFormatter.suggestion(for: error)
        return WriteError(title: title, message: message, suggestion: suggestion)
    }
}

extension View {
    /// Presents an error alert with a formatted message and optional suggestion.
    ///
    /// - Parameters:
    ///   - isErrorPresented: Binding to control alert visibility.
    ///   - error: Binding to the error to display.
    func writeErrorAlert(isErrorPresented: Binding<Bool>, error: Binding<WriteError?>) -> some View {
        self.modifier(ErrorAlertModifier(
            isErrorPresented: isErrorPresented,
            error: error.wrappedValue ?? WriteError(title: "", message: "", suggestion: nil)
        ))
    }
}
