import SwiftUI

struct OverviewView: View {
    @Environment(\.themeManager) var theme: ThemeManager
    @Environment(\.dashboardStore) var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    @State private var visibleSections: [OverviewSection] = []
    @State private var draggedSection: OverviewSection?
    @State private var collapsedSections: Set<String> = []
    /// The measured height of each section.
    ///
    /// A single estimate was why dragging felt wrong: the status banner is a
    /// third of the system card, so one number was too large for half the
    /// sections and too small for the rest, and a card would jump two places
    /// or refuse to move. Each row reports its own height and the drag walks
    /// the real geometry.
    @State private var sectionHeights: [OverviewSection: CGFloat] = [:]
    @State private var isEditing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.bg.ignoresSafeArea()
                
                ScrollView {
                    PageHeader(title: "Overview", subtitle: store.profile.displayName)
                    VStack(alignment: .leading, spacing: 14) {
                        if let msg = store.connectionError {
                            connectionBannerContent(for: msg)
                        }

                        let indexedSections = Array(visibleSections.enumerated())
                        ForEach(indexedSections, id: \.element.self) { index, section in
                            SectionView(
                                section: section,
                                title: section.displayName,
                                isEditing: $isEditing,
                                visibleSections: $visibleSections,
                                collapsedSections: $collapsedSections,
                                registry: registry,
                                content: { sectionContentView(section) },
                                draggedSection: $draggedSection,
                                sectionHeights: $sectionHeights,
                                currentIndex: index
                            )
                        }

                        if isEditing {
                            hiddenSectionsPicker
                        }
                        
                        if visibleSections.isEmpty && !isEditing {
                            Spacer(minLength: 200)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(longPressGesture)
            .refreshable { await store.refreshManually() }
            .onChange(of: registry.active?.id) { _, _ in loadVisibleSections() }
            .onChange(of: registry.active?.overviewVisibleSections) { _, _ in loadVisibleSections() }
            .onAppear { loadVisibleSections() }
            .onChange(of: store.isOverviewEditing) { _, isEditing in
                self.isEditing = isEditing
                if isEditing { loadVisibleSections() }
            }
            .onChange(of: registry.active?.overviewVisibleSections) { _, _ in
                if isEditing { loadVisibleSections() }
            }
        }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                store.isOverviewEditing.toggle()
            }
    }

    private func loadVisibleSections() {
        guard var active = registry.active else { return }
        // The stored array in its stored order.
        //
        // Filtering `allCases` returned declaration order and threw the saved
        // arrangement away, so a section dragged to the top came back in the
        // middle on the next appearance.
        // Migrate the stored names first, and write them back.
        //
        // Expanding an old name at read time and leaving it in storage was
        // half a migration. Hiding VPN servers removed `vpnServers`, which was
        // never stored; `vpn` stayed, and the next load expanded it again — so
        // both VPN sections reappeared as soon as anything else was added,
        // which looked exactly like the sections being linked together.
        var names = active.overviewVisibleSections
        if let migrated = OverviewSection.migrate(storedNames: names) {
            names = migrated
            registry.setOverviewSectionNames(active, migrated)
        }

        // A one-time upgrade, not a standing rule: alerts used to be an
        // always-on banner rather than a section somebody could hide, so a
        // profile saved before this existed gets it inserted once here. The
        // flag on the profile is what keeps this from running again — once
        // it is set, hiding alerts afterward stays hidden rather than being
        // silently re-added on the next load.
        if active.hasMigratedAlertsSection != true {
            active = registry.migrateAlertsSection(for: active)
            names = active.overviewVisibleSections
        }

        var seen = Set<OverviewSection>()
        visibleSections = names
            .compactMap(OverviewSection.init(rawValue:))
            .filter { seen.insert($0).inserted }
        collapsedSections = Set(active.collapsedSections.compactMap { OverviewSection.init(rawValue: $0) }.map(\.rawValue))
    }
    
    private func resetSections() {
        guard let active = registry.active else { return }
        registry.resetSectionOrder(toDefault: active)
        loadVisibleSections()
    }
    
    @ViewBuilder
    private var hiddenSectionsPicker: some View {
        let hidden = OverviewSection.allCases.filter { !visibleSections.contains($0) }
        VStack(alignment: .leading, spacing: 8) {
            if hidden.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hidden Sections")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                        .padding(.top, 8)
                    
                    ForEach(hidden) { section in
                        HStack {
                            Text(section.displayName)
                                .scaledFont(14)
                                .foregroundStyle(theme.label)
                            Spacer()
                            Button {
                                addSection(section)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(theme.ok)
                                    .scaledFont(20)
                            }
                            .accessibilityLabel("Add \(section.displayName) to the overview")
                        }
                    }
                }
            }
            
            Button {
                resetSections()
            } label: {
                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    .scaledFont(14)
                    .foregroundStyle(theme.label)
            }
        }
    }
    
    private func addSection(_ section: OverviewSection) {
        if !visibleSections.contains(section) {
            visibleSections.append(section)
        }
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: true)
    }

    /// No `@ViewBuilder`: this returns `AnyView` through explicit `return`
    /// statements, which turns the builder off anyway and warns about it.
    private func sectionContentView(_ section: OverviewSection) -> AnyView {
        switch section {
        case .alerts:
            return AnyView(alertsSlab)
        case .status:
            return AnyView(statusSlab.sectionFreshness([.system]))
        case .interfaces:
            return AnyView(interfacesSlab.sectionFreshness([.interfaces]))
        case .system:
            return AnyView(systemSlab.sectionFreshness([.system]))
        case .gateways:
            return AnyView(gatewaysSlab.sectionFreshness([.gateways]))
        case .services:
            return AnyView(servicesSlab.sectionFreshness([.services]))
        case .firewall:
            return AnyView(firewallSlab.sectionFreshness([.firewallLog]))
        case .vpnServers:
            return AnyView(vpnServersSlab)
        case .vpnClients:
            return AnyView(vpnClientsSlab)
        case .clients:
            return AnyView(topTalkersSlab)
        case .dnsbl:
            return AnyView(dnsblSlab)
        }
    }
}

struct GatewayRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let gateway: GatewayStatus
    let gatewayMetrics: GatewayMetricTracker

    private var delayPoints: [Double] {
        gatewayMetrics.readings(for: gateway.name).compactMap { $0.delayMS }
    }

    private var lossPoints: [Double] {
        gatewayMetrics.readings(for: gateway.name).compactMap { $0.lossPercent }
    }

    var body: some View {
        Slab(rail: gateway.health) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(gateway.name)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: gateway.status, health: gateway.health)
                }
                Text(gateway.readout)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.labelMuted)
                GatewayTrend(
                    delayPoints: delayPoints,
                    lossPoints: lossPoints,
                    latestDelay: gateway.delayMS,
                    latestLoss: gateway.lossPercent
                )
                if let ip = gateway.monitorIP, !ip.isEmpty {
                    Text("monitor \(ip)")
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }
}

private struct SectionView: View {
    let section: OverviewSection
    let title: String
    @Binding var isEditing: Bool
    @Binding var visibleSections: [OverviewSection]
    @Binding var collapsedSections: Set<String>
    let registry: ServerRegistry
    let content: () -> AnyView
    @Environment(\.themeManager) private var theme: ThemeManager
    
    @Binding var draggedSection: OverviewSection?
    @Binding var sectionHeights: [OverviewSection: CGFloat]
    let currentIndex: Int

    @State private var isDragging = false
    @State private var isCollapsed = false

    /// Where the drag started, in the list.
    ///
    /// The rows reorder while the finger is still down, so `currentIndex`
    /// changes underneath the gesture. The origin is fixed at the start and
    /// every target is computed from it, which is what keeps a drag from
    /// fighting its own reordering.
    @State private var dragOrigin: Int?
    @State private var translation: CGFloat = 0

    /// How far the dragged card is from its slot.
    ///
    /// The card follows the finger; its slot has already moved to wherever the
    /// reordering put it, so the visible offset is the finger's travel minus
    /// the distance the slot itself has travelled. Without that subtraction
    /// the card runs away from the cursor by a row each time the list shifts.
    private var liveOffset: CGFloat {
        guard isDragging, let origin = dragOrigin else { return 0 }
        // The distance this card's slot has already travelled, in real
        // heights: the rows it passed are not all the same size, so counting
        // them and multiplying by an average put the card visibly off the
        // finger by the third row.
        return translation - travelled(from: origin, to: currentIndex)
    }

    /// The height of the rows between two positions, signed.
    private func travelled(from: Int, to: Int) -> CGFloat {
        guard from != to else { return 0 }
        let range = from < to ? (from + 1)...to : (to + 1)...from
        let distance = range.reduce(CGFloat.zero) { total, index in
            guard visibleSections.indices.contains(index) else { return total }
            return total + height(of: visibleSections[index])
        }
        return from < to ? distance : -distance
    }

    /// A measured height, or a middling default until the row has been laid
    /// out once.
    private func height(of section: OverviewSection) -> CGFloat {
        sectionHeights[section] ?? 80
    }

    /// Where a drag of this distance should land, measured in real rows.
    private func targetIndex(from origin: Int, translation: CGFloat) -> Int {
        var index = origin
        var remaining = translation

        if remaining > 0 {
            while index < visibleSections.count - 1 {
                let next = height(of: visibleSections[index + 1])
                    // Two thirds, not half.
                //
                // Half means a card swaps the instant it overlaps its
                // neighbour, so a small wobble near a boundary flips it back
                // and forth. The extra sixth is hysteresis: enough that a
                // deliberate move still feels immediate and a shaky hand does
                // not.
                guard remaining > next * 0.66 else { break }
                remaining -= next
                index += 1
            }
        } else {
            while index > 0 {
                let previous = height(of: visibleSections[index - 1])
                guard -remaining > previous * 0.66 else { break }
                remaining += previous
                index -= 1
            }
        }
        return index
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = currentIndex
                    isDragging = true
                    draggedSection = section
                }
                translation = value.translation.height

                guard let origin = dragOrigin else { return }

                // Walk the real rows rather than dividing by an average.
                //
                // A card swaps once it is more than halfway over its
                // neighbour, and "halfway" depends on how tall that neighbour
                // is — which is what made this feel jumpy with sections
                // ranging from a banner to a full system card.
                let target = targetIndex(from: origin, translation: translation)

                if target != currentIndex,
                   let from = visibleSections.firstIndex(of: section) {
                    // Reorder as the finger moves. Everything else animates
                    // into place because the ForEach re-renders with the new
                    // order — the cards move in relation to each other, which
                    // is the whole point of dragging one.
                    withAnimation(Motion.animation(.spring(response: 0.35, dampingFraction: 0.86))) {
                        var reordered = visibleSections
                        let item = reordered.remove(at: from)
                        reordered.insert(item, at: target)
                        visibleSections = reordered
                    }
                }
            }
            .onEnded { _ in
                // Saved once, at the end. Persisting on every swap would write
                // the profile a dozen times during one gesture.
                persistOrder(visibleSections)
                HapticFeedback.sectionReorder()

                withAnimation(Motion.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                    isDragging = false
                    translation = 0
                    dragOrigin = nil
                    draggedSection = nil
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        hideSection()
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(10, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(theme.bad, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                    .accessibilityLabel("Hide this section")
                    .accessibilityHidden(true)
                    
                    Image(systemName: "line.3.horizontal")
                        .scaledFont(14)
                        .foregroundStyle(theme.labelFaint)
                        .symbolVariant(.fill)
                        .frame(width: 24)
                        .contentShape(Rectangle())
                }
                
                GroupHeading(text: title)
                Spacer()
                
                if !isEditing {
                    Button {
                        toggleCollapse()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .scaledFont(10)
                            .foregroundStyle(theme.labelFaint)
                            .symbolVariant(.fill.circle)
                            .frame(width: 20, height: 20)
                    }
                    .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
                }
            }
            .animation(Motion.animation(.easeInOut(duration: 0.2)), value: isEditing)
            
            if isEditing {
                sectionMockup
            } else if isCollapsed {
                Text("Section collapsed")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                content()
            }
        }
        // Lifted as a whole, not just its title.
        //
        // These were on the header row, so dragging moved the heading and left
        // the card behind it — the offsets that used to nudge the neighbours
        // are gone because the list reorders underneath instead.
        // Reports its own height so the drag can walk real geometry. Read
        // during layout and written back once it changes, which is cheap: a
        // section's height only moves when its contents do.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SectionHeightKey.self,
                                       value: [section: proxy.size.height])
            }
        )
        .onPreferenceChange(SectionHeightKey.self) { heights in
            for (key, value) in heights where sectionHeights[key] != value {
                sectionHeights[key] = value
            }
        }
        .offset(y: liveOffset)
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .opacity(isDragging ? 0.95 : 1.0)
        .shadow(color: isDragging ? theme.label.opacity(0.15) : .clear,
                radius: 12, y: isDragging ? 8 : 0)
        .zIndex(isDragging ? 1 : 0)
        .gesture(isEditing ? dragGesture : nil)
        .onAppear {
            if let active = registry.active, active.collapsedSections.contains(section.rawValue) {
                isCollapsed = true
            }
        }
    }
    
    private var sectionMockup: some View {
        Rectangle()
            .fill(theme.labelFaint.opacity(0.08))
            .frame(height: 1)
    }

    private func hideSection() {
        visibleSections.removeAll { $0 == section }
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: false)
    }
    
    private func toggleCollapse() {
        isCollapsed.toggle()
        guard let active = registry.active else { return }
        registry.setOverviewSectionCollapsed(active, section, collapsed: isCollapsed)
    }
    
    /// Writes the arrangement back to the profile.
    ///
    /// Every path that reorders has to call this: the order is stored per
    /// firewall, and a rearrangement that lives only in view state is undone
    /// the next time the screen appears.
    private func persistOrder(_ sections: [OverviewSection]) {
        guard let active = registry.active else { return }
        registry.setOverviewSectionOrder(active, sections)
    }
}

extension View {
    /// The nudge that says these cards can be dragged.
    ///
    /// Skipped entirely under Reduce Motion: a repeating wobble is the kind of
    /// movement that setting exists to stop, and the drag handles say the same
    /// thing without moving.
    @ViewBuilder
    func wobble(_ isEditing: Bool) -> some View {
        if isEditing && !Motion.isReduced {
            self
                // Motion.isReduced guards this above: the whole wobble is skipped.
                .animation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true), value: isEditing)
                .wobbleOffset()
        } else {
            self
        }
    }
}

private struct WobbleOffset: ViewModifier {
    @State private var offset = CGFloat.random(in: -1...1)
    
    func body(content: Content) -> some View {
        content.offset(x: offset, y: 0)
    }
}

private extension View {
    func wobbleOffset() -> some View {
        modifier(WobbleOffset())
    }
}

/// Collects each section's measured height.
///
/// A dictionary rather than a single value, because the rows report
/// independently and the drag needs all of them at once — it walks from one
/// row to another and has to know how tall each one it passes is.
struct SectionHeightKey: PreferenceKey {
    static var defaultValue: [OverviewSection: CGFloat] { [:] }

    static func reduce(value: inout [OverviewSection: CGFloat],
                       nextValue: () -> [OverviewSection: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
