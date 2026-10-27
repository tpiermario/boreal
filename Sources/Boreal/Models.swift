import Foundation

final class RequestEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func set(_ newValue: Int) { lock.lock(); defer { lock.unlock() }; value = newValue }
    func matches(_ candidate: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == candidate }
}

import CSMC

enum FanMode: String, Codable, CaseIterable, Identifiable {
    case automatic, fixed, sensor
    var id: Self { self }
    var title: String { switch self { case .automatic: return "Automatico"; case .fixed: return "RPM fissi"; case .sensor: return "Sensore" } }
}
struct FanRule: Codable, Equatable {
    var mode: FanMode = .automatic
    var rpm: Double = 2500
    var sensor: String = "TC0P"
    var start: Double = 50
    var full: Double = 80
    func target(minimum: Double, maximum: Double, temperatures: [String: Double]) throws -> Double {
        if mode == .automatic { return -1 }
        guard bf_valid_target(minimum, minimum, maximum) != 0 else { throw BorealError.message("Limiti ventola non validi.") }
        switch mode {
        case .automatic: return -1
        case .fixed:
            guard bf_valid_target(rpm, minimum, maximum) != 0 else { throw BorealError.message("RPM fuori dai limiti della ventola.") }
            return rpm
        case .sensor:
            guard start.isFinite, full.isFinite, start >= 20, full <= 90, full > start,
                  let t = temperatures[sensor], t.isFinite, t > 0, t <= 125 else {
                throw BorealError.message("Sensore non disponibile o soglie non valide: ritorno ad Auto.")
            }
            return bf_curve(t, start, full, minimum, maximum)
        }
    }
}
struct FanReading: Identifiable, Codable {
    var id: Int
    var name: String
    var current: Double
    var minimum: Double
    var maximum: Double
    var controllable: Bool
}
struct SensorReading: Identifiable, Codable {
    var id: String
    var name: String
    var group: String
    var value: Double
}
struct Sample: Identifiable {
    let id = UUID()
    let date: Date
    let sensors: [String: Double]
    let fans: [Int: Double]
}
struct FanProfile: Identifiable, Codable {
    func validated() throws -> FanProfile {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60,
              !cleaned.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !rules.isEmpty, rules.count <= 10 else { throw BorealError.message("Nome o numero di ventole del profilo non valido.") }
        for (index, rule) in rules {
            guard (0..<10).contains(index), rule.rpm.isFinite, (0...20000).contains(rule.rpm),
                  rule.start.isFinite, rule.full.isFinite, rule.start >= 20, rule.full <= 90,
                  rule.full > rule.start, validSensorKey(rule.sensor) else {
                throw BorealError.message("Parametri del profilo non validi.")
            }
        }
        var result = self; result.name = cleaned; return result
    }
    var id: UUID = UUID()
    var name: String
    var rules: [Int: FanRule]
}
enum BorealError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
func validSensorKey(_ key: String) -> Bool {
    key.utf8.count == 4 && key.utf8.allSatisfy { (32...126).contains($0) }
}
func csvField(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
struct Preferences: Codable {
    func validated() throws -> Preferences {
        guard version == 1, profiles.count <= 100, Set(profiles.map(\.id)).count == profiles.count,
              validSensorKey(menuSensor), (0..<10).contains(menuFan),
              ["system", "light", "dark"].contains(appearance) else { throw BorealError.message("Impostazioni non valide o versione non supportata.") }
        var result = self; result.profiles = try profiles.map { try $0.validated() }; return result
    }
    var version = 1
    var profiles: [FanProfile] = []
    var fahrenheit = false
    var menuSensor = "TC0P"
    var menuFan = 0
    var menuRPM = true
    var appearance = "system"
}
struct Snapshot {
    var fans: [FanReading] = []
    var sensors: [SensorReading] = []
    var error: String? = nil
}

// Access is serialized by AppModel.queue, including shutdown.
final class SMCReader: @unchecked Sendable {
    private var keys: [String] = []
    private var opened = false
    private func read(_ key: String) -> Double? {
        var value: Double = 0
        return key.withCString { bf_number($0, &value) } == 0 ? value : nil
    }
    private func discover() {
        let count = Int(min(4096, max(0, read("#KEY") ?? 0)))
        var found = Set(["TC0P", "TC0D", "TCXC", "TCGC", "TG0P", "TG0D", "TB0T", "Tm0P", "TA0P"])
        for index in 0..<count {
            var bytes = [CChar](repeating: 0, count: 5)
            guard bf_key_at(UInt32(index), &bytes) == 0 else { continue }
            let key = String(cString: bytes)
            if validSensorKey(key) && key.hasPrefix("T") { found.insert(key) }
        }
        keys = found.sorted()
    }
    func snapshot() -> Snapshot {
        #if arch(arm64)
        return Snapshot(error: "Questo backend SMC è destinato ai Mac Intel. Apple Silicon non ancora validato.")
        #else
        guard bf_intel_hardware() != 0 else {
            return Snapshot(error: "Apple Silicon rilevato: backend Intel non disponibile, anche tramite Rosetta.")
        }
        if !opened {
            guard bf_open() == 0 else { return Snapshot(error: "AppleSMC non accessibile su questo Mac.") }
            opened = true
            discover()
        }
        let count = Int(bf_fan_count())
        guard count >= 0 else { opened = false; bf_close(); return Snapshot(error: "Impossibile leggere il numero di ventole. Nuovo tentativo automatico.") }
        var fans: [FanReading] = []
        for index in 0..<count {
            var minimum: Double = 0, maximum: Double = 0
            guard bf_fan_bounds(Int32(index), &minimum, &maximum) == 0,
                  let rpm = read("F\(index)Ac"), rpm >= 0, rpm <= 20000 else { continue }
            fans.append(FanReading(id: index, name: "Ventola \(index + 1)", current: rpm,
                                   minimum: minimum, maximum: maximum, controllable: bf_can_control(Int32(index)) != 0))
        }
        let names = ["TC0P": "CPU · prossimità", "TC0D": "CPU · diodo", "TCXC": "CPU · package",
                     "TCGC": "CPU · grafica integrata", "TG0P": "GPU · prossimità", "TG0D": "GPU · diodo",
                     "TB0T": "Batteria", "Tm0P": "Memoria", "TA0P": "Ambiente"]
        var sensors: [SensorReading] = []
        for key in keys {
            guard let value = read(key), value > 0, value <= 125 else { continue }
            let group: String
            switch key.dropFirst().first {
            case "C": group = "CPU"
            case "G": group = "GPU"
            case "B": group = "Batteria"
            case "m", "M": group = "Memoria"
            default: group = "Altri sensori"
            }
            sensors.append(SensorReading(id: key, name: names[key] ?? key, group: group, value: value))
        }
        return Snapshot(fans: fans, sensors: sensors, error: sensors.isEmpty ? "Nessun sensore termico leggibile." : fans.count != count ? "Letture ventole incomplete: controllo disabilitato." : nil)
        #endif
    }
}

func mergeProfiles(existing: [FanProfile], imported: [FanProfile]) throws -> [FanProfile] {
    guard existing.count + imported.count <= 100 else { throw BorealError.message("Limite di 100 profili superato.") }
    var result = existing
    var names = Set(existing.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) })
    for profile in imported {
        let valid = try profile.validated()
        let key = valid.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard names.insert(key).inserted else { throw BorealError.message("Nome profilo duplicato: \(valid.name). Nessun profilo importato.") }
        result.append(FanProfile(name: valid.name, rules: valid.rules))
    }
    return result
}

// Segment before reducing samples: averaging must never bridge missing data.
struct ThermalPoint: Identifiable {
    let id: String
    let date: Date
    let series: String
    let segment: String
    let value: Double
}
func thermalPoints(_ samples: [Sample], since: Date, fahrenheit: Bool) -> [ThermalPoint] {
    let visible = samples.filter { $0.date >= since }
    let bucketSize = max(1, Int(ceil(Double(visible.count) / 60)))
    var result: [ThermalPoint] = []
    for (name, prefix) in [("CPU", "TC"), ("GPU", "TG")] {
        var runs: [[(Sample, Double)]] = []
        var run: [(Sample, Double)] = []
        for sample in visible {
            let value = sample.sensors.filter { $0.key.hasPrefix(prefix) }
                .map(\.value).filter { $0.isFinite && $0 > 0 && $0 <= 125 }.max()
            let gap = run.last.map { sample.date.timeIntervalSince($0.0.date) } ?? 1
            if value == nil || gap > 3 || gap <= 0 {
                if !run.isEmpty { runs.append(run); run = [] }
            }
            if let value { run.append((sample, value)) }
        }
        if !run.isEmpty { runs.append(run) }
        for (index, samples) in runs.enumerated() {
            for start in stride(from: 0, to: samples.count, by: bucketSize) {
                let bucket = samples[start..<min(start + bucketSize, samples.count)]
                let sample = bucket.last!.0
                let maximum = bucket.map { $0.1 }.max()!
                result.append(ThermalPoint(id: "\(sample.id)-\(name)", date: sample.date,
                    series: name, segment: "\(name)-\(index)",
                    value: fahrenheit ? maximum * 1.8 + 32 : maximum))
            }
        }
    }
    return result
}
