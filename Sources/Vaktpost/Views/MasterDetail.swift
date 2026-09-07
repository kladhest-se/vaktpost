import SwiftUI

/// A list and its detail: side by side where there is room, pushed where there
/// is not.
///
/// On iPad the app was an enlarged phone: a column of cards down the middle of
/// a 13-inch screen, and tapping one replaced the whole thing. The Clients and
/// Firewall screens are the ones that suffer most, because comparing two
/// entries is most of what you do there and the phone layout makes it
/// impossible.
///
/// Selection is an identifier rather than the item itself. A stored copy of a
/// row goes stale on the next refresh — thirty seconds later the detail pane
/// would be showing an interface's counters from before the last sample. An id
/// is looked up again each time, so the detail follows the data.
struct MasterDetail<ListContent: View, DetailContent: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var theme: ThemeManager

    @Binding var selection: String?
    let emptyMessage: String
    @ViewBuilder let list: () -> ListContent
    @ViewBuilder let detail: (String) -> DetailContent

    var body: some View {
        if sizeClass == .regular {
            // Two columns in an HStack rather than a NavigationSplitView.
            //
            // A split view can only be a root, and these screens are not all
            // roots: Firewall is pushed from More. Nesting one inside a
            // navigation stack puts the detail in the wrong column or drops it
            // entirely. An HStack composes anywhere and gives the same thing —
            // the list stays visible while you read a detail, which is the
            // whole point on a screen this size.
            HStack(spacing: 0) {
                list()
                    .frame(maxWidth: 380)

                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .bottom)

                Group {
                    if let selection {
                        detail(selection)
                    } else {
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            // No NavigationStack of its own.
            //
            // Firewall is pushed from More, so creating one here nested a
            // stack inside a stack: going back from a rule popped the *outer*
            // one and landed on More rather than the rule list. A screen that
            // may be pushed cannot own the stack it is pushed into.
            //
            // `navigationDestination(isPresented:)` drives the ambient stack
            // instead, which works whether this is a tab root or a pushed
            // screen, and keeps the selection as the single source of truth.
            list()
                .navigationDestination(
                    isPresented: Binding(
                        get: { selection != nil },
                        set: { shown in if !shown { selection = nil } }
                    )
                ) {
                    if let selection { detail(selection) }
                }
        }
    }

    /// The right-hand column before anything is chosen. Named rather than
    /// blank: an empty half-screen looks like something failed to load.
    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .scaledFont(30)
                .foregroundStyle(theme.labelFaint)
            Text(emptyMessage)
                .scaledFont(14)
                .foregroundStyle(theme.labelMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
    }
}

/// Keeps a column of cards from stretching across a 13-inch screen.
///
/// Cards are designed to be read at a phone's width. Left to fill an iPad they
/// become lines of text a foot wide with a status pill marooned at the far
/// end, which is harder to read than the phone layout it replaced.
///
/// Applied to the scrolling content rather than the window, so the background
/// still runs edge to edge.
struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func readableWidth() -> some View { modifier(ReadableWidth()) }
}
