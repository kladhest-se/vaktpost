import SwiftUI

/// Show per-host traffic for all interfaces, sorted by inbound or outbound bandwidth.
///
/// Useful for spotting which devices are consuming the most bandwidth, identifying
/// unexpected traffic, or monitoring specific clients.

struct TrafficView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    
    @State private var hostTrafficData: [HostTraffic] = []
    @State private var sortKey: SortKey = .bandwidthIn
    @State private var selectedInterface: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshInterval: TimeInterval = 5
    
    enum SortKey: String, CaseIterable, Identifiable {
        case bandwidthIn = "Bandwidth In"
        case bandwidthOut = "Bandwidth Out"
        case bandwidthTotal = "Total"
        case name = "Name"
        
        var id: String { rawValue }
        
        var title: String { rawValue }
    }
    
    private var interfaces: [String] {
        Array(Set(hostTrafficData.map { $0.interface })).sorted()
    }
    
    private var filteredHosts: [HostTraffic] {
        let iface = selectedInterface
        var list: [HostTraffic]
        if let iface {
            list = hostTrafficData.filter { $0.interface == iface }
        } else {
            list = hostTrafficData
        }
        list = list.sorted { lhs, rhs in
            switch sortKey {
            case .bandwidthIn:
                return lhs.bandwidthIn > rhs.bandwidthIn
            case .bandwidthOut:
                return lhs.bandwidthOut > rhs.bandwidthOut
            case .bandwidthTotal:
                let lhsTotal = lhs.bandwidthIn + lhs.bandwidthOut
                let rhsTotal = rhs.bandwidthIn + rhs.bandwidthOut
                return lhsTotal > rhsTotal
            case .name:
                let lhsName = lhs.hostname ?? lhs.ip
                let rhsName = rhs.hostname ?? rhs.ip
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
        }
        return list
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                
                VStack(spacing: 8) {
                    ForEach(filteredHosts) { host in
                        hostRow(for: host)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Traffic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadHostTraffic()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }
    
    private var controls: some View {
        VStack(spacing: 10) {
            if !interfaces.isEmpty {
                Picker("Interface", selection: $selectedInterface) {
                    Text("All").tag(nil as String?)
                    ForEach(interfaces, id: \.self) { iface in
                        Text(iface).tag(iface as String?)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Picker("Sort by", selection: $sortKey) {
                ForEach(SortKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private func loadHostTraffic() {
        Task {
            while !Task.isCancelled {
                do {
                    let data = try await store.client.hostTraffic()
                    if !Task.isCancelled {
                        hostTrafficData = data
                    }
                } catch {
                    // Silently ignore errors
                }
                do {
                    try await Task.sleep(for: .seconds(refreshInterval))
                } catch {
                    break
                }
            }
        }
    }
    
    private func hostRow(for host: HostTraffic) -> some View {
        let name = host.hostname ?? host.ip
        let total = host.bandwidthIn + host.bandwidthOut
        
        return Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .scaledFont(13, weight: .semibold)
                        if host.hostname != nil {
                            Text(host.ip)
                                .scaledFont(10, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                        } else {
                            Text(host.interface)
                                .scaledFont(10, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Rate.bits(host.bandwidthIn))
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.ok)
                        Text("IN")
                            .scaledFont(8, weight: .medium)
                            .foregroundStyle(theme.labelFaint)
                    }
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Rate.bits(host.bandwidthOut))
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.info)
                        Text("OUT")
                            .scaledFont(8, weight: .medium)
                            .foregroundStyle(theme.labelFaint)
                    }
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Rate.bits(total))
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.label)
                        Text("TOTAL")
                            .scaledFont(8, weight: .medium)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                
                // Progress bar showing proportion of total
                if total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.hairline.opacity(0.1))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(theme.ok.opacity(0.6))
                                .frame(width: geo.size.width * (host.bandwidthIn / total), height: 4)
                            
                            Rectangle()
                                .fill(theme.info.opacity(0.6))
                                .frame(
                                    width: geo.size.width * (host.bandwidthOut / total),
                                    height: 4
                                )
                                .offset(x: geo.size.width * (host.bandwidthIn / total))
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
        }
    }
}
