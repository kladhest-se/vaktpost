import SwiftUI

/// pfSense firmware and package updates, together.
///
/// This used to be two sections buried partway down System. Both answer the
/// same question -- "is anything out of date on this firewall?" -- and
/// Overview's own Updates figure is already the two combined, so splitting
/// them across a scroll made the destination less specific than the summary
/// that pointed at it. One screen, reachable from Overview's Updates tile and
/// from a single row in System, replaces both.
struct UpdatesView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var pendingOperation: AdministrativeWrite?
    @State private var showUpdateConfirmation = false
    @State private var isStartingUpdate = false
    @State private var updateResult: String?
    @State private var writeError: WriteError?
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if hasAvailableUpdates {
                    AdministrationModeNotice()
                }

                if let updateResult {
                    Notice(symbol: "checkmark.circle", title: "Update accepted",
                           detail: updateResult, health: .ok)
                }

                GroupHeading(text: "Firmware")
                firmwareSlab.sectionFreshness([.version])

                GroupHeading(text: "Packages")
                packageCheckSlab.sectionFreshness([.packageUpdates])
                packagesSlab.sectionFreshness([.packages])
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable {
            await store.refresh()
        }
        .navigationTitle("Updates")
        .confirmationSheet(
            isPresented: $showUpdateConfirmation,
            title: confirmationTitle,
            message: pendingOperation.map { store.writeCoordinator.preview(for: $0) },
            destructive: true,
            destructiveLabel: "Start update",
            confirmLabel: "Cancel",
            onConfirm: startPendingUpdate
        ) {
            pendingOperation = nil
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
    }

    private var hasAvailableUpdates: Bool {
        store.version?.updateAvailable == true || store.packages.contains(where: \.updateAvailable)
    }

    /// Firmware, checked on demand like packages.
    ///
    /// The version comparison comes back with every refresh, but a person
    /// looking at this screen wants to know it is current *now*, not as of the
    /// last cycle — so the button forces a fresh read and says what it found.
    @ViewBuilder
    private var firmwareSlab: some View {
        Slab(rail: store.version?.updateAvailable == true ? .warn : .ok, title: "pfSense") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.version?.current ?? "unknown version")
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer()
                    if store.isCheckingFirmware {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await store.checkFirmware() }
                        }
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.accentColor)
                    }
                }
                if store.version?.updateAvailable == true, let latest = store.version?.latest {
                    Text("\(latest) is available.")
                        .scaledFont(12)
                        .foregroundStyle(theme.warn)
                    if let operation = firmwareOperation {
                        updateButton("Update pfSense", systemImage: "arrow.up.circle.fill") {
                            request(operation)
                        }
                    }
                } else {
                    Text(store.firmwareCheckResult ?? "Up to date as of the last refresh.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    @ViewBuilder
    private var packageCheckSlab: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Check against the repository")
                        .scaledFont(13)
                        .foregroundStyle(theme.label)
                    Spacer()
                    if store.isCheckingPackages {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await store.checkPackageUpdates() }
                        }
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.accentColor)
                    }
                }
                // The age of the answer matters as much as the answer: "no
                // updates" from a week ago is a different claim from "no
                // updates" from this morning.
                Text(store.packageCheckResult
                     ?? store.packageCheckAge.map { "Last checked \($0)." }
                     ?? "Not checked yet. Versions here come from the configuration; checking asks the repository and takes a few seconds.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    @ViewBuilder
    private var packagesSlab: some View {
        if store.packages.isEmpty {
            Slab(rail: .idle) {
                Text(store.errors[.packages] ?? "No packages installed.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            let sorted = store.packages.sorted {
                if $0.updateAvailable != $1.updateAvailable { return $0.updateAvailable }
                return $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending
            }
            ForEach(sorted) { pkg in
                Slab(rail: pkg.health) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(pkg.shortName)
                                .scaledFont(14, weight: .semibold)
                                .foregroundStyle(theme.label)
                            Spacer()
                            Text(pkg.versionLine)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(pkg.updateAvailable ? theme.warn : theme.labelMuted)
                        }
                        if let d = pkg.descr, !d.isEmpty {
                            Text(d)
                                .scaledFont(11)
                                .foregroundStyle(theme.labelFaint)
                                .lineLimit(2)
                        }
                        if let operation = packageOperation(pkg) {
                            updateButton("Update package", systemImage: "arrow.up.circle") {
                                request(operation)
                            }
                                .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    private var firmwareOperation: AdministrativeWrite? {
        guard store.version?.updateAvailable == true,
              let current = store.version?.current, !current.isEmpty,
              let target = store.version?.latest, !target.isEmpty else { return nil }
        return .startFirmwareUpdate(current: current, target: target)
    }

    private func packageOperation(_ package: PackageInfo) -> AdministrativeWrite? {
        guard package.updateAvailable,
              let installed = package.installedVersion, !installed.isEmpty,
              let target = package.latestVersion, !target.isEmpty else { return nil }
        return .startPackageUpdate(
            identifier: package.updateIdentifier,
            displayName: package.shortName,
            installed: installed,
            target: target
        )
    }

    private var confirmationTitle: String {
        guard let pendingOperation else { return "Start update" }
        if case .startFirmwareUpdate = pendingOperation { return "Update pfSense" }
        return "Update package"
    }

    private func updateButton(_ title: String, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .scaledFont(12, weight: .semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .tint(theme.accentColor)
        .disabled(!store.canAdminister || isStartingUpdate || store.writeCoordinator.isExecuting)
        .accessibilityHint("Reviews and starts this update directly on the firewall")
    }

    private func request(_ operation: AdministrativeWrite) {
        pendingOperation = operation
        showUpdateConfirmation = true
    }

    private func startPendingUpdate() async {
        guard let operation = pendingOperation else { return }
        isStartingUpdate = true
        defer {
            isStartingUpdate = false
            pendingOperation = nil
        }
        do {
            let outcome = try await store.writeCoordinator.execute(operation)
            updateResult = outcome.detail
                + " Leave the firewall powered on and refresh this screen after the updater finishes."
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}
