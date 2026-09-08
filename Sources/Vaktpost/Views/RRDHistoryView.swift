import SwiftUI

/// Historical traffic from pfSense's RRD files.
///
/// Loaded on demand so the refresh timer does not pay the cost. The chart
/// shows a day of five-minute averages, which is the finest resolution the
/// firewall keeps.

struct RRDHistoryView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    private var interfaces: [RRDSeries] {
        guard let history = store.rrdHistory, history.available else { return [] }
        return history.series
    }

    private var interfaceNames: [(label: String, file: String)] {
        var seen = Set<String>()
        var result: [(label: String, file: String)] = []
        for series in interfaces {
            if seen.insert(series.file).inserted {
                let label = store.interfaceLabel(for: series.file) ?? series.file
                result.append((label, series.file))
            }
        }
        return result
    }

    @State private var selectedFile: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if !interfaces.isEmpty {
                    picker
                    chart
                    legend
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.loadRRD() }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private var header: some View {
        Slab(rail: .idle) {
            if store.isLoadingRRD {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the firewall's records…")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                }
            } else if let err = store.errors[.rrd] {
                VStack(alignment: .leading, spacing: 6) {
                    Text(err)
                        .scaledFont(12)
                        .foregroundStyle(theme.warn)
                    Text("This pfSense cannot read its own RRD files from PHP — that needs rrdtool, a shell binary. The app shows nothing rather than an empty chart that looks like an interface with no traffic.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            } else if let history = store.rrdHistory, !history.available {
                Text("This pfSense cannot read its own RRD files from PHP — that needs rrdtool, a shell binary.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private var picker: some View {
        Picker("Interface", selection: $selectedFile) {
            ForEach(interfaceNames, id: \.file) { item in
                Text(item.label).tag(item.file as String?)
            }
        }
        .pickerStyle(.menu)
        .onAppear { if selectedFile == nil, let first = interfaceNames.first?.file { selectedFile = first } }
    }

    private var chart: some View {
        Slab(rail: .info, title: "Last 24 hours") {
            if let file = selectedFile {
                let series = interfaces.filter { $0.file == file }
                if !series.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        RRDChart(series: series)
                            .frame(height: 200)
                        Text("Five-minute averages from pfSense's own records.")
                            .scaledFont(10)
                            .foregroundStyle(theme.labelFaint)
                    }
                } else {
                    Text("No data for this interface.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Rectangle().fill(theme.ok.opacity(0.7)).frame(width: 20, height: 2)
                Text("Received")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelMuted)
            }
            HStack(spacing: 4) {
                Rectangle().fill(theme.info.opacity(0.7)).frame(width: 20, height: 2)
                Text("Sent")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelMuted)
            }
        }
    }
}
