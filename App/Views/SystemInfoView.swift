import SwiftUI
import UnraidGatewayKit

/// "System information" (build 42): everything the Unraid API tells about the machine — OS, CPU,
/// memory modules, mainboard, versions, GPUs and the network interfaces that matter.
struct SystemInfoView: View {
    @EnvironmentObject private var model: ServersModel
    let server: ServerConfig
    @State private var info: SystemInfo?
    @State private var error: String?

    var body: some View {
        List {
            if let i = info {
                if let os = i.info?.os {
                    Section(header: SectionTitle("Operating system")) {
                        row("Hostname", os.fqdn ?? os.hostname)
                        row("Unraid", [os.distro, os.release].compactMap { $0 }.joined(separator: " "))
                        row("Kernel", os.kernel)
                        row("Architecture", os.arch)
                        if let u = os.uefi { row("Firmware", u ? "UEFI" : "BIOS") }
                        if let boot = i.bootDate {
                            LabeledContent("Up since") { Text(boot, format: .dateTime.day().month().hour().minute()) + Text(verbatim: " · ") + Text(boot, format: .relative(presentation: .named)) }
                        }
                    }
                }
                if let cpu = i.info?.cpu {
                    Section(header: SectionTitle("Processor")) {
                        row("Model", [cpu.manufacturer, cpu.brand].compactMap { $0 }.joined(separator: " "))
                        if let c = cpu.cores, let t = cpu.threads { row("Cores / threads", "\(c) / \(t)") }
                        if let s = cpu.speed { row("Clock", cpu.speedmax.map { String(format: "%.2f – %.2f GHz", s, $0) } ?? String(format: "%.2f GHz", s)) }
                        row("Socket", cpu.socket)
                        if let p = cpu.processors, p > 1 { row("Processors", String(p)) }
                    }
                }
                Section(header: SectionTitle("Memory")) {
                    if let total = i.installedMemory { row("Installed", bytes(total)) }
                    if let m = i.metrics?.memory, let used = m.used, let total = m.total { row("In use", bytes(used) + " / " + bytes(total)) }
                    if let modules = i.info?.memory?.layout, !modules.isEmpty {
                        ForEach(Array(modules.enumerated()), id: \.offset) { n, m in
                            LabeledContent("Module \(n + 1)") {
                                Text([m.bytes.map(bytes), m.type, m.clockSpeed.map { "\($0) MHz" }].compactMap { $0 }.joined(separator: " · ")).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                if let b = i.info?.baseboard {
                    Section(header: SectionTitle("Mainboard")) {
                        row("Manufacturer", b.manufacturer)
                        row("Model", b.model)
                        row("Version", b.version)
                        if let slots = b.memSlots, slots > 0 { row("Memory slots", String(Int(slots))) }
                        if let v = i.info?.system?.virtual, v { row("Virtual machine", String(localized: "yes")) }
                    }
                }
                if let v = i.info?.versions?.core {
                    Section(header: SectionTitle("Versions")) {
                        row("Unraid", v.unraid)
                        row("Kernel", v.kernel)
                        row("Unraid API", v.api)
                    }
                }
                if let gpus = i.info?.devices?.gpu, !gpus.isEmpty {
                    Section(header: SectionTitle("Graphics")) {
                        ForEach(gpus) { g in
                            LabeledContent(g.vendorname ?? g.type ?? "GPU", value: [g.productid, g.class].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                }
                let nics = (i.info?.networkInterfaces ?? []).filter(\.isRelevant)
                if !nics.isEmpty {
                    Section(header: SectionTitle("Network")) {
                        ForEach(nics) { n in
                            LabeledContent(n.name) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(n.ipAddress ?? "")
                                    Text([n.macAddress, n.speed.map { "\($0) Mb/s" }, n.operstate].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            } else {
                Section { HStack { ProgressView(); Text("Loading…") } }
            }
        }
        .navigationTitle("System information")
        .inlineNavigationTitle()
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(title) { Text(value).multilineTextAlignment(.trailing) } }
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .binary) }

    private func load() async {
        guard let client = model.client(for: server) else { error = String(localized: "Credentials missing from the Keychain"); return }
        if server.isDemo { error = String(localized: "The demo server has no hardware to describe."); return }
        do { info = try await client.graphQL(SystemInfo.query, as: SystemInfo.self); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
