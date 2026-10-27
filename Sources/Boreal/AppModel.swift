import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import CSMC
import Darwin

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var fans: [FanReading] = []
    @Published var sensors: [SensorReading] = []
    @Published var history: [Sample] = []
    @Published var extrema: [String: (minimum: Double, maximum: Double)] = [:]
    @Published var competingController = false
    @Published var desired: [Int: FanRule] = [:]
    @Published var preferences = Preferences()
    @Published var page = "Panoramica"
    @Published var message: String? = nil
    @Published var helperAvailable = false
    @Published var activeName = "Monitoraggio"
    @Published var commandPending = false
    @Published var autoConfirmed = false
    @Published var active = false
    @Published var lastUpdated: Date? = nil
    @Published var busy = false
    @Published var loginEnabled = false
    let demo: Bool
    private let storageDirectory: URL?
    nonisolated private let reader = SMCReader()
    private let queue = DispatchQueue(label: "it.boreal.smc", qos: .utility)
    private var timer: Timer?
    private var tick = 0
    private let epoch = RequestEpoch()
    private var requestGeneration = 0 { didSet { epoch.set(requestGeneration) } }
    private var lastPoll: TimeInterval = 0
    private var lastValidPoll: TimeInterval = 0
    private var terminating = false
    private var observers: [NSObjectProtocol] = []
    private var storeURL: URL {
        (storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(demo ? "Boreal-Demo" : "Boreal", isDirectory: true)).appendingPathComponent("preferences.json")
    }
    private var socket: String { "/var/run/it.boreal.fans.\(getuid()).sock" }
    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo"), storageDirectory: URL? = nil, startMonitoring: Bool = true) {
        self.demo = demo
        self.storageDirectory = storageDirectory
        if FileManager.default.fileExists(atPath: storeURL.path) {
            do { preferences = try JSONDecoder().decode(Preferences.self, from: Self.readLimited(storeURL)).validated() }
            catch {
                let backup = storeURL.deletingLastPathComponent().appendingPathComponent("preferences-invalid-\(UUID().uuidString).json")
                do { try FileManager.default.copyItem(at: storeURL, to: backup)
                    message = "Impostazioni non valide. Copia originale conservata in \(backup.lastPathComponent)."
                } catch { persistenceBlocked = true; message = "Impostazioni non valide: impossibile conservarne una copia. Salvataggio sospeso." }
            }
        }
        guard startMonitoring else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.restore() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.restore(); AppModel.shared.poll() }
        })
        timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        poll()
    }
    private var persistenceBlocked = false
    @discardableResult func persist() -> Bool {
        guard !persistenceBlocked else { message = "Salvataggio sospeso per conservare le impostazioni originali."; return false }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences.validated()).write(to: storeURL, options: .atomic)
            return true
        } catch { message = "Salvataggio impostazioni: \(error.localizedDescription)"; return false }
    }
    var telemetryFresh: Bool {
        lastUpdated.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 3 } ?? false
    }
    var canRestore: Bool { (helperAvailable || demo) && !competingController && !commandPending }
    var canControl: Bool { canRestore && telemetryFresh && !fans.isEmpty && fans.allSatisfy(\.controllable) && (cpu ?? 100) < 95 && (gpu ?? 0) < 95 }
    var controlStatus: String {
        if commandPending { return "In attesa del servizio…" }
        if active { return activeName }
        return autoConfirmed ? "Automatico Apple confermato" : "Monitoraggio · Auto non verificato"
    }
    func temperature(_ c: Double) -> String {
        String(format: "%.0f°%@", preferences.fahrenheit ? c * 1.8 + 32 : c, preferences.fahrenheit ? "F" : "C")
    }
    var cpu: Double? { sensors.filter { $0.group == "CPU" }.map(\.value).max() }
    var gpu: Double? { sensors.filter { $0.group == "GPU" }.map(\.value).max() }
    var trayText: String {
        guard telemetryFresh else { return "Dati non aggiornati" }
        let t = (sensors.first(where: { $0.id == preferences.menuSensor }) ?? sensors.first).map { temperature($0.value) } ?? "—"
        let rpm = (fans.first(where: { $0.id == preferences.menuFan }) ?? fans.first).map { String(Int($0.current)) + " rpm" } ?? "—"
        return preferences.menuRPM ? "\(t) · \(rpm)" : t
    }
    func rule(for id: Int) -> FanRule { desired[id] ?? FanRule() }
    func update(_ id: Int, _ rule: FanRule) { desired[id] = rule }
    func poll() {
        guard !busy, !terminating else { return }; busy = true
        competingController = !demo && NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.lastPathComponent == "Macs Fan Control.app" }
        let generation = requestGeneration
        let isDemo = demo, demoTick = tick
        tick += 1
        queue.async { [self] in
            let snapshot: Snapshot
            if isDemo {
                let c = 62 + sin(Double(demoTick)/9) * 6
                snapshot = Snapshot(fans: [
                    FanReading(id: 0, name: "Ventola 1", current: 2300 + sin(Double(demoTick)/5)*150, minimum: 1200, maximum: 5500, controllable: true),
                    FanReading(id: 1, name: "Ventola 2", current: 2500 + sin(Double(demoTick)/6)*180, minimum: 1200, maximum: 5500, controllable: true)
                ], sensors: [SensorReading(id: "TC0P", name: "CPU · prossimità", group: "CPU", value: c),
                             SensorReading(id: "TG0P", name: "GPU · prossimità", group: "GPU", value: c-8),
                             SensorReading(id: "TB0T", name: "Batteria", group: "Batteria", value: 33)])
            } else { snapshot = reader.snapshot() }
            var response = [CChar](repeating: 0, count: 256)
            let path = "/var/run/it.boreal.fans.\(getuid()).sock"
            let reachable = isDemo || path.withCString { p in "PING\n".withCString { c in bf_request(p, c, &response, 256) } } == 0 && String(cString: response) == "OK 1\n"
            Task { @MainActor in
                self.busy = false
                guard !self.terminating, generation == self.requestGeneration else { return }
                let gap = self.lastPoll > 0 && ProcessInfo.processInfo.systemUptime - self.lastPoll > 3
                self.lastPoll = ProcessInfo.processInfo.systemUptime
                if gap && self.active { self.restore(); self.message = "Campionamento interrotto: ritorno Auto richiesto." }
                self.fans = snapshot.fans; self.sensors = snapshot.sensors
                self.helperAvailable = reachable
                if !reachable || self.competingController { self.autoConfirmed = false }
                if self.active && (!reachable || self.competingController) { self.restore(); self.message = "Controllo interrotto: servizio assente o altro controller attivo." }
                self.lastUpdated = snapshot.error == nil ? Date() : nil
                self.lastValidPoll = snapshot.error == nil ? ProcessInfo.processInfo.systemUptime : 0
                if let error = snapshot.error { self.message = error; if self.active { self.restore() } }
                if snapshot.error == nil {
                    for sensor in snapshot.sensors {
                        let previous = self.extrema[sensor.id] ?? (sensor.value, sensor.value)
                        self.extrema[sensor.id] = (min(previous.0, sensor.value), max(previous.1, sensor.value))
                    }
                    self.history.append(Sample(date: Date(), sensors: Dictionary(uniqueKeysWithValues: snapshot.sensors.map { ($0.id,$0.value) }),
                                               fans: Dictionary(uniqueKeysWithValues: snapshot.fans.map { ($0.id,$0.current) })))
                    if self.history.count > 3600 { self.history.removeFirst(self.history.count-3600) }
                }
                if self.active && !self.commandPending { self.sendCurrentRules() }
            }
        }
    }
    private func targets() throws -> [Double] {
        guard !fans.isEmpty, fans.map(\.id) == Array(0..<fans.count),
              lastValidPoll > 0, ProcessInfo.processInfo.systemUptime - lastValidPoll < 3,
              let cpu, cpu > 0, cpu < 95, (gpu ?? 0) < 95 else { throw BorealError.message("Telemetria assente, incompleta o CPU ≥95 °C: modalità Auto.") }
        let temperatures = Dictionary(uniqueKeysWithValues: sensors.map { ($0.id, $0.value) })
        return try fans.map { fan in
            let rule = rule(for: fan.id)
            guard rule.mode == .automatic || fan.controllable else { throw BorealError.message("Controllo SMC non supportato per \(fan.name).") }
            return try rule.target(minimum: fan.minimum, maximum: fan.maximum, temperatures: temperatures)
        }
    }
    @discardableResult func apply(name: String = "Personalizzato", completion: ((Bool) -> Void)? = nil) -> Bool {
        guard !commandPending else { completion?(false); return false }
        guard !competingController else { message = "Chiudi l’altro controller prima di attivare Boreal."; completion?(false); return false }
        guard helperAvailable || demo else { message = "Servizio non raggiungibile. Usa Installa controllo ventole.command incluso nel DMG."; completion?(false); return false }
        guard !fans.isEmpty else { message = "Nessuna ventola disponibile."; completion?(false); return false }
        if fans.allSatisfy({ rule(for: $0.id).mode == .automatic }) { restore(completion: completion); return true }
        do {
            let values = try targets()
            requestGeneration += 1; active = false; autoConfirmed = false; commandPending = true
            let generation = requestGeneration
            send(command(for: values), generation: generation) { ok in
                guard generation == self.requestGeneration else { completion?(false); return }
                self.commandPending = false
                if ok { self.active = true; self.activeName = name; self.message = nil }
                completion?(ok)
            }
            return true
        } catch { message = error.localizedDescription; completion?(false); return false }
    }
    private func command(for values: [Double]) -> String {
        "APPLY " + values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: " ") + "\n"
    }
    private func sendCurrentRules() {
        do {
            let values = try targets()
            if demo { return }
            let command = "APPLY " + values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: " ") + "\n"
            send(command, generation: requestGeneration)
        } catch { restore(); message = error.localizedDescription }
    }
    private func send(_ command: String, generation: Int, completion: ((Bool) -> Void)? = nil) {
        if demo { completion?(true); return }
        let path = socket
        let epoch = self.epoch
        queue.async {
            guard epoch.matches(generation) else { Task { @MainActor in completion?(false) }; return }
            var buffer = [CChar](repeating: 0, count: 256)
            let rc = path.withCString { p in command.withCString { c in bf_request(p, c, &buffer, 256) } }
            let result = String(cString: buffer)
            let ok = rc == 0 && result == "OK\n"
            // Best-effort immediate restoration after rejected APPLY. The helper watchdog remains independent.
            if !ok && command.hasPrefix("APPLY ") {
                _ = path.withCString { p in "AUTO\n".withCString { c in bf_request(p,c,&buffer,256) } }
            }
            Task { @MainActor in
                guard !self.terminating, generation == self.requestGeneration else { completion?(false); return }
                if !ok {
                    self.active = false; self.autoConfirmed = false; self.activeName = "Auto non verificato"
                    self.helperAvailable = false
                    self.message = "Servizio ventole: \(result.isEmpty ? "non raggiungibile" : result.trimmingCharacters(in: .whitespacesAndNewlines)). Ritorno Auto richiesto; verifica non disponibile."
                }
                completion?(ok)
            }
        }
    }
    func restore(completion: ((Bool) -> Void)? = nil) {
        requestGeneration += 1; active = false; autoConfirmed = false; commandPending = false
        desired = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, FanRule()) })
        guard !competingController, demo || helperAvailable else {
            message = "Auto non verificato: servizio assente o altro controller attivo."; completion?(false); return
        }
        commandPending = true
        let generation = requestGeneration
        send("AUTO\n", generation: generation) { ok in
            guard generation == self.requestGeneration else { completion?(false); return }
            self.commandPending = false; self.autoConfirmed = ok
            if ok { self.message = nil }
            completion?(ok)
        }
    }
    func terminate() {
        terminating = true; requestGeneration += 1; timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        let shouldRestore = !demo && helperAvailable && !competingController
        let path = socket
        queue.sync {
            if shouldRestore {
                var response = [CChar](repeating: 0, count: 256)
                _ = path.withCString { p in "AUTO\n".withCString { c in bf_request(p,c,&response,256) } }
            }
            bf_close()
        }
    }
    func fullSpeed() {
        guard helperAvailable, !fans.isEmpty, !competingController else { message = "Controllo non disponibile."; return }
        desired = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, FanRule(mode: .fixed, rpm: $0.maximum)) })
        apply(name: "Massima ventilazione")
    }
    @discardableResult func saveProfile(_ name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !fans.isEmpty else { message = "Inserisci un nome e attendi la lettura delle ventole."; return false }
        guard preferences.profiles.count < 100 else { message = "Limite di 100 profili raggiunto."; return false }
        guard !preferences.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame }) else { message = "Esiste già un profilo con questo nome."; return false }
        let profile = FanProfile(name: cleaned, rules: Dictionary(uniqueKeysWithValues: fans.map { ($0.id, rule(for: $0.id)) }))
        do { preferences.profiles = try mergeProfiles(existing: preferences.profiles, imported: [profile]) } catch { message = error.localizedDescription; return false }
        if persist() { return true }
        preferences.profiles.removeLast(); return false
    }
    func loadProfile(_ profile: FanProfile) {
        guard Set(profile.rules.keys) == Set(fans.map(\.id)) else { message = "Il profilo contiene ventole diverse da quelle rilevate."; return }
        guard helperAvailable, !competingController else { message = "Controllo non disponibile."; return }
        do { desired = try profile.validated().rules; apply(name: profile.name) } catch { message = error.localizedDescription }
    }
    func deleteProfile(_ id: UUID) {
        let original = preferences.profiles
        preferences.profiles.removeAll { $0.id == id }
        if !persist() { preferences.profiles = original }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "Autorizza Boreal negli Elementi login di macOS." }
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = error.localizedDescription }
    }
    func exportProfiles() { exportData(try? JSONEncoder().encode(preferences.profiles), name: "Boreal-profili.json", type: .json) }
    func importProfiles() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Self.readLimited(url)
            guard data.count < 1_000_000 else { throw BorealError.message("File troppo grande.") }
            let imported = try JSONDecoder().decode([FanProfile].self, from: data)
            guard imported.count <= 100 else { throw BorealError.message("Massimo 100 profili per importazione.") }
            guard preferences.profiles.count + imported.count <= 100 else { throw BorealError.message("Limite complessivo di 100 profili superato.") }
            let merged = try mergeProfiles(existing: preferences.profiles, imported: imported)
            let original = preferences.profiles
            preferences.profiles = merged
            if !persist() { preferences.profiles = original }
        } catch { message = "Importazione: \(error.localizedDescription)" }
    }
    func exportHistory() {
        guard !history.isEmpty else { message = "Nessun campione da esportare."; return }
        let sensorKeys = Array(Set(history.flatMap { $0.sensors.keys })).sorted()
        let fanKeys = Array(Set(history.flatMap { $0.fans.keys })).sorted()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = [( ["timestamp"] + sensorKeys.map { "\($0)_celsius" } + fanKeys.map { "fan\($0)_rpm" } ).map(csvField).joined(separator: ",")]
        for sample in history {
            let values = [formatter.string(from: sample.date)] + sensorKeys.map { sample.sensors[$0].map { String($0) } ?? "" }
                + fanKeys.map { sample.fans[$0].map { String($0) } ?? "" }
            lines.append(values.map(csvField).joined(separator: ","))
        }
        exportData((lines.joined(separator: "\r\n") + "\r\n").data(using: .utf8), name: "Boreal-telemetria.csv", type: .commaSeparatedText)
    }
    func exportDiagnostics() {
        let object: [String:Any] = ["app":"Boreal 0.2.5", "os":ProcessInfo.processInfo.operatingSystemVersionString,
            "demo":demo, "helper":helperAvailable, "otherController":competingController, "active":active, "lastError":message ?? "", "architecture":"x86_64", "sensorKeys":sensors.map(\.id),
            "fans":fans.map { ["id":$0.id,"minimum":$0.minimum,"maximum":$0.maximum,"controllable":$0.controllable] as [String:Any] }]
        exportData(try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), name: "Boreal-diagnostica.json", type: .json)
    }
    static func readLimited(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_000_001) ?? Data()
        guard data.count <= 1_000_000 else { throw BorealError.message("File troppo grande (massimo 1 MB).") }
        return data
    }
    private func exportData(_ data: Data?, name: String, type: UTType) {
        guard let data else { message = "Impossibile preparare l’esportazione."; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic) } catch { message = error.localizedDescription }
        }
    }
}
/* Privileged, per-user Intel SMC helper. Small text protocol, no shell execution. */
