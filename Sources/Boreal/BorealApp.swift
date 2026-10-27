import AppKit
import SwiftUI
import Charts

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: NativeTray?
    func applicationDidFinishLaunching(_ notification: Notification) {
        tray = NativeTray(model: AppModel.shared) { self.showMainWindow() }
    }
    func showQuickMenu() {
        if tray == nil { tray = NativeTray(model: AppModel.shared) { self.showMainWindow() } }
        tray?.showQuickMenu(in: NSApp.keyWindow?.contentView)
    }
    func showMainWindow() {
        NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.terminate(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct BorealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        Window("Boreal", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 680)
                .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
        }
        .defaultSize(width: 1120, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Apri menu rapido") { delegate.showQuickMenu() }.keyboardShortcut("m", modifiers: [.command,.shift])
                Button("Esporta telemetria CSV") { model.exportHistory() }.keyboardShortcut("e", modifiers: [.command,.shift]).disabled(model.history.isEmpty)
                Button("Ripristina gestione Apple") { model.restore() }.keyboardShortcut("0", modifiers: [.command,.shift])
            }
        }
    }
}

private let accent = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.30, green: 0.82, blue: 0.74, alpha: 1)
        : NSColor(srgbRed: 0.08, green: 0.46, blue: 0.42, alpha: 1)
})

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredSection: String?
    @State private var sensorSearch = ""
    @State private var profileName = ""
    @State private var historySpan = 300
    private let sections = [("Panoramica","square.grid.2x2"),("Ventole","fanblades"),("Sensori","thermometer.medium"),
                            ("Profili","slider.horizontal.3"),("Cronologia","chart.xyaxis.line"),("Impostazioni","gearshape")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "wind").font(.system(size: 27, weight: .medium)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) { Text("boreal").font(.system(size: 25, weight: .semibold)); Text("CONTROLLO TERMICO").font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(.secondary) }
                }.padding(.top, 26)
                VStack(spacing: 6) {
                    ForEach(sections, id: \.0) { name, symbol in
                        Button { model.page = name } label: {
                            Label(name, systemImage: symbol).font(.system(size: 13, weight: model.page == name ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .background(model.page == name ? accent.opacity(0.12) : hoveredSection == name ? Color.primary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(model.page == name ? accent : Color.primary.opacity(0.65))
                        }.buttonStyle(.plain)
                            .onHover { over in if over { hoveredSection = name } else if hoveredSection == name { hoveredSection = nil } }
                            .accessibilityValue(model.page == name ? "Selezionato" : "")
                    }
                }
                Spacer(minLength: 8)
                Button { model.restore() } label: {
                    Label("Ripristina Auto", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).contentShape(Rectangle())
                }.buttonStyle(.bordered).help("Ripristina la gestione Apple per tutte le ventole (⌘⇧0)")
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.demo ? "Simulazione" : "Mac Intel", systemImage: "laptopcomputer").font(.system(size: 12, weight: .medium))
                    Text(model.demo ? "Valori dimostrativi" : "Telemetria SMC locale").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Boreal 0.2.5").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal, 18).padding(.bottom, 20).frame(width: 206).background(.regularMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.page).font(.system(size: 29, weight: .semibold))
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.restore() } label: { Label("Gestione Apple", systemImage: "arrow.uturn.backward") }.controlSize(.large)
                    }.padding(.top, 25)
                    if model.demo { notice("Modalità dimostrativa: i dati sono simulati e nessuna ventola viene controllata.", color: .orange) }
                    if let message = model.message {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(message).font(.system(size: 12)).textSelection(.enabled)
                            Spacer(); Button("Chiudi") { model.message = nil }.buttonStyle(.plain).font(.caption)
                        }.padding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if model.competingController { notice("Macs Fan Control è attivo: chiudilo prima di usare il controllo di Boreal.", color: .orange) }
                    if !model.demo && !model.helperAvailable {
                        notice("Monitoraggio attivo senza servizio. Per regolare le ventole, apri Installa controllo ventole.command dal pacchetto scaricato.", color: .secondary)
                    }
                    Group {
                        switch model.page {
                        case "Panoramica": OverviewView(model: model)
                        case "Ventole": FansView(model: model)
                        case "Sensori": SensorsView(model: model, search: $sensorSearch)
                        case "Profili": ProfilesView(model: model, name: $profileName)
                        case "Cronologia": HistoryView(model: model, span: $historySpan)
                        default: PreferencesView(model: model)
                        }
                    }
                    HStack {
                        Circle().fill(model.telemetryFresh ? accent : Color.orange).frame(width: 6, height: 6)
                        Text(model.telemetryFresh ? "Aggiornamento ogni secondo" : "Telemetria non aggiornata").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(); Text(model.demo ? "DEMO · \(model.controlStatus)" : model.controlStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.bottom, 18)
                }.padding(.horizontal, 30)
            }.id(model.page).background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent)
    }
    var subtitle: String {
        switch model.page {
        case "Panoramica": return "Il tuo Mac, a colpo d’occhio."
        case "Ventole": return "Una regolazione precisa, per ogni ventola."
        case "Sensori": return "Le temperature realmente esposte dal tuo hardware."
        case "Profili": return "Le tue impostazioni, pronte quando servono."
        case "Cronologia": return "L’andamento della sessione, fino a un’ora."
        default: return "Boreal, secondo le tue preferenze."
        }
    }
    func notice(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(color)
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color(white: 0.17) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)) }
}

struct MetricView: View {
    let name: String
    let value: String
    let caption: String
    let symbol: String
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(name).font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(accent) }
                Text(value).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            MetricView(name: "CPU", value: model.cpu.map(model.temperature) ?? "—", caption: "Sensore CPU disponibile", symbol: "cpu")
            MetricView(name: "GPU", value: model.gpu.map(model.temperature) ?? "—", caption: "Sensori grafici rilevati", symbol: "square.stack.3d.up")
            MetricView(name: "Ventole", value: "\(model.fans.count)", caption: "Dispositivi rilevati", symbol: "fanblades")
        }
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Andamento termico").font(.system(size: 15, weight: .semibold)); Spacer(); Text("Ultimi 5 minuti · picchi per intervallo").font(.caption).foregroundStyle(.secondary) }
                ThermalChart(model: model, limit: 300).frame(height: 180)
            }
        }
        HStack { Text("Le tue ventole").font(.system(size: 17, weight: .semibold)); Spacer(); Button("Tutte le impostazioni →") { model.page = "Ventole" }.buttonStyle(.plain).foregroundStyle(accent) }
        if model.fans.isEmpty { EmptyState(symbol: "fanblades", text: "Nessuna ventola rilevata. Il monitoraggio non mostrerà valori inventati.") }
        else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 14) { ForEach(model.fans) { fan in FanCard(model: model, fan: fan) } } }
    }
}

struct ThermalChart: View {
    @ObservedObject var model: AppModel
    var limit: Int = 300
    var points: [ThermalPoint] {
        thermalPoints(model.history, since: Date().addingTimeInterval(-Double(limit)),
                      fahrenheit: model.preferences.fahrenheit)
    }
    var body: some View {
        let displayedPoints = points
        if displayedPoints.isEmpty { EmptyState(symbol: "chart.xyaxis.line", text: "I dati appariranno dopo le prime letture.") }
        else {
            Chart(displayedPoints) { point in
                LineMark(x: .value("Ora",point.date), y: .value(model.preferences.fahrenheit ? "°F" : "°C",point.value), series: .value("Tratto", point.segment))
                    .foregroundStyle(by: .value("Sensore",point.series)).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Ora", point.date), y: .value("Temperatura", point.value))
                    .foregroundStyle(by: .value("Sensore", point.series)).symbolSize(8)
            }.chartForegroundStyleScale(["CPU":accent,"GPU":Color.blue])
                .chartYAxisLabel(model.preferences.fahrenheit ? "°F" : "°C")
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}

struct FanCard: View {
    @ObservedObject var model: AppModel
    let fan: FanReading
    @State private var editing = false
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "fanblades").font(.system(size: 26)).foregroundStyle(accent).padding(11).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) { Text(fan.name).font(.system(size: 14, weight: .semibold)); Text(model.active ? model.rule(for: fan.id).mode.title : model.controlStatus).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) { Text(Int(fan.current).formatted()).font(.system(size: 33, weight: .medium, design: .rounded)).monospacedDigit(); Text("RPM").font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: fan.maximum > 0 ? min(1,max(0,fan.current/fan.maximum)) : 0).tint(accent)
                HStack { Text("Min \(Int(fan.minimum))"); Spacer(); Text("Max \(Int(fan.maximum))") }.font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Regola ventola") { editing = true }.frame(maxWidth: .infinity).controlSize(.large)
                    .disabled(!model.helperAvailable || model.competingController || !fan.controllable)
                    .accessibilityLabel("Regola \(fan.name)")
                    .help(!model.helperAvailable ? "Installa il servizio per regolare le ventole" : !fan.controllable ? "Controllo non supportato per questa ventola" : "Modifica la regolazione di \(fan.name)")
            }
        }.sheet(isPresented: $editing) { FanEditor(model: model, fan: fan) }
    }
}
struct FansView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack { Button("Automatico Apple") { model.restore() }.disabled(!model.canRestore); Button("Tutte al massimo") { model.fullSpeed() }.disabled(!model.canControl); Spacer() }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 16) { ForEach(model.fans) { fan in FanCard(model: model, fan: fan) } }
        if model.fans.isEmpty { EmptyState(symbol: "fanblades", text: "Nessuna ventola disponibile su questo hardware.") }
    }
}

struct FanEditor: View {
    @ObservedObject var model: AppModel
    let fan: FanReading
    @Environment(\.dismiss) var dismiss
    @State private var rule = FanRule()
    @State private var applyError: String?
    private var unit: String { model.preferences.fahrenheit ? "°F" : "°C" }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Label(fan.name, systemImage: "fanblades").font(.title2); Spacer(); Text("\(Int(fan.minimum))–\(Int(fan.maximum)) RPM").font(.caption).foregroundStyle(.secondary) }
            Picker("Modalità",selection: $rule.mode) { ForEach(FanMode.allCases) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.segmented)
            switch rule.mode {
            case .automatic: Label("macOS sceglie la velocità in base alle condizioni del Mac.",systemImage: "apple.logo").foregroundStyle(.secondary)
            case .fixed:
                HStack { Text("Velocità richiesta"); Spacer(); Text("\(Int(rule.rpm)) RPM").monospacedDigit().foregroundStyle(accent) }
                Slider(value: $rule.rpm,in: fan.minimum...fan.maximum,step: 1)
            case .sensor:
                Picker("Sensore",selection: $rule.sensor) { if !model.sensors.contains(where: { $0.id == rule.sensor }) { Text("Sensore non disponibile").tag(rule.sensor) }; ForEach(model.sensors) { sensor in Text("\(sensor.name) · \(sensor.id)").tag(sensor.id) } }
                Stepper("Inizio rampa: \(model.temperature(rule.start))",value: $rule.start,in: 20...85,step: 1)
                Stepper("Massimo a: \(model.temperature(rule.full))",value: $rule.full,in: 25...90,step: 1)
                Chart {
                    ForEach(Array(stride(from: 20,through: 100,by: 2)), id: \.self) { t in
                        LineMark(x:.value("Temperatura",model.preferences.fahrenheit ? Double(t)*1.8+32 : Double(t)),y:.value("RPM",curve(Double(t))))
                    }
                }.chartXScale(domain: model.preferences.fahrenheit ? 68.0...212.0 : 20.0...100.0).chartXAxisLabel("Temperatura \(unit)").chartYAxisLabel("RPM").frame(height: 180).foregroundStyle(accent)
            }
            Text("Se la telemetria si interrompe, il servizio avvia il ritorno ad Auto alla scadenza del lease di 4 secondi. CPU o GPU ≥95 °C o sensori di protezione assenti interrompono il controllo manuale.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if let error = applyError ?? validationMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Applica") { model.update(fan.id,rule); model.apply { ok in if ok { dismiss() } else { applyError = model.message ?? "Applicazione non riuscita." } } }.buttonStyle(.borderedProminent).disabled(!valid || model.commandPending) }
        }.padding(30).frame(width: 520).tint(accent)
            .onChange(of: rule) { _ in applyError = nil }
            .onAppear {
                rule = model.rule(for: fan.id)
                rule.rpm = min(fan.maximum,max(fan.minimum,rule.rpm))
                if !model.sensors.contains(where: { $0.id == rule.sensor }), let first = model.sensors.first { rule.sensor = first.id }
            }
    }
    var validationMessage: String? {
        if !model.telemetryFresh { return "Telemetria non aggiornata: attendi una lettura valida." }
        if !model.helperAvailable { return "Servizio non disponibile." }
        if model.competingController { return "Chiudi l’altro controller prima di applicare." }
        if !model.fans.contains(where: { $0.id == fan.id }) { return "La ventola non è più disponibile." }
        if rule.mode == .sensor && rule.full <= rule.start { return "La temperatura di massimo deve essere superiore all’inizio della rampa." }
        if rule.mode == .sensor && !model.sensors.contains(where: { $0.id == rule.sensor }) { return "Seleziona un sensore disponibile." }
        return nil
    }
    var valid: Bool { model.telemetryFresh && model.helperAvailable && !model.competingController && model.fans.contains { $0.id == fan.id } && (try? rule.target(minimum: fan.minimum, maximum: fan.maximum, temperatures: Dictionary(uniqueKeysWithValues: model.sensors.map { ($0.id, $0.value) }))) != nil }
    func curve(_ t: Double) -> Double {
        guard rule.full > rule.start else { return fan.minimum }
        return fan.minimum + min(1,max(0,(t-rule.start)/(rule.full-rule.start)))*(fan.maximum-fan.minimum)
    }
}

struct SensorsView: View {
    @ObservedObject var model: AppModel
    @Binding var search: String
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    var rows: [SensorReading] { model.sensors.filter { query.isEmpty || "\($0.name) \($0.id) \($0.group)".localizedCaseInsensitiveContains(query) } }
    var body: some View {
        HStack {
            TextField("Cerca sensore, componente o chiave SMC",text: $search).textFieldStyle(.roundedBorder)
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help("Cancella ricerca").accessibilityLabel("Cancella ricerca") }
        }
        Text("\(rows.count) sensori visibili su \(model.sensors.count). Min e max dall’avvio; la stella sceglie il sensore della barra dei menu.").font(.caption).foregroundStyle(.secondary)
        Surface {
            VStack(spacing: 0) {
                HStack { Text("Sensore"); Spacer(); ForEach(["Min", "Attuale", "Max"], id: \.self) { Text($0).frame(width: 70, alignment: .trailing) }; Color.clear.frame(width: 28, height: 1).accessibilityHidden(true) }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 14)
                ForEach(rows) { sensor in
                    let extrema = model.extrema[sensor.id]
                    HStack {
                        Image(systemName: sensor.group == "GPU" ? "square.stack.3d.up" : "thermometer.medium").foregroundStyle(accent).frame(width: 22)
                        VStack(alignment:.leading,spacing:3) { Text(sensor.name).font(.system(size:13,weight:.medium)); Text("\(sensor.group) · \(sensor.id)").font(.system(size:10)).foregroundStyle(.secondary) }
                        Spacer()
                        Text(model.temperature(extrema?.minimum ?? sensor.value)).foregroundStyle(.secondary).frame(width: 70,alignment:.trailing)
                        Text(model.temperature(sensor.value)).fontWeight(.semibold).frame(width:70,alignment:.trailing)
                        Text(model.temperature(extrema?.maximum ?? sensor.value)).foregroundStyle(.secondary).frame(width:70,alignment:.trailing)
                        Button { model.preferences.menuSensor = sensor.id; model.persist() } label: { Image(systemName: model.preferences.menuSensor == sensor.id ? "star.fill" : "star").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help("Mostra nella barra dei menu").accessibilityLabel("Mostra \(sensor.name) nella barra dei menu").accessibilityValue(model.preferences.menuSensor == sensor.id ? "Selezionato" : "")
                    }.font(.system(size:12)).monospacedDigit().padding(.vertical,12)
                    Divider()
                }
                if rows.isEmpty { EmptyState(symbol:"thermometer.medium",text: model.sensors.isEmpty ? "Nessun sensore disponibile. Attendi la telemetria o controlla il messaggio diagnostico." : "Nessun risultato per “\(query)”. Prova un nome o una chiave diversa.") }
            }
        }
    }
}

struct ProfilesView: View {
    @ObservedObject var model: AppModel
    @Binding var name: String
    @State private var pendingDelete: UUID?
    var body: some View {
        Surface {
            VStack(alignment:.leading,spacing:16) {
                Text("Salva la configurazione corrente").font(.headline)
                Text("Ogni profilo conserva modalità, RPM e sensore di ciascuna ventola. Boreal non applica profili manuali all’avvio.").font(.caption).foregroundStyle(.secondary)
                HStack { TextField("Es. Lavoro, Montaggio, Gaming",text:$name).textFieldStyle(.roundedBorder); Button("Salva profilo") { if model.saveProfile(name) { name = "" } }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.fans.isEmpty) }
            }
        }
        ForEach(model.preferences.profiles) { profile in
            Surface { HStack {
                Image(systemName:"slider.horizontal.3").foregroundStyle(accent).font(.title2)
                VStack(alignment:.leading,spacing:4) { Text(profile.name).font(.headline); Text("\(profile.rules.count) ventole configurate").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("Applica") { model.loadProfile(profile) }.disabled(!model.helperAvailable || model.competingController).accessibilityLabel("Applica profilo \(profile.name)")
                Button { pendingDelete = profile.id } label: { Image(systemName:"trash").frame(width: 28, height: 28).contentShape(Rectangle()) }.help("Elimina profilo salvato").accessibilityLabel("Elimina profilo \(profile.name)")
            } }
        }
        if model.preferences.profiles.isEmpty { EmptyState(symbol:"slider.horizontal.3",text:"I tuoi profili appariranno qui. Regola le ventole, poi salva le impostazioni.") }
        HStack { Button("Importa JSON") { model.importProfiles() }; Button("Esporta JSON") { model.exportProfiles() }.disabled(model.preferences.profiles.isEmpty); Spacer() }
            .alert("Eliminare il profilo?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Elimina", role: .destructive) { if let id = pendingDelete { model.deleteProfile(id) }; pendingDelete = nil }
                Button("Annulla", role: .cancel) { pendingDelete = nil }
            }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Binding var span: Int
    var body: some View {
        HStack { Picker("Intervallo",selection:$span) { Text("5 minuti").tag(300); Text("15 minuti").tag(900); Text("1 ora").tag(3600) }.pickerStyle(.segmented).frame(width:300); Spacer(); Button("Esporta CSV") { model.exportHistory() }.disabled(model.history.isEmpty) }
        Surface { ThermalChart(model:model,limit:span).frame(height:310) }
        Text("\(model.history.count) campioni conservati nella sessione. Il grafico mostra i picchi per intervallo. L’esportazione include tutti i sensori e le ventole, con temperature in °C e timestamp ISO 8601.").font(.caption).foregroundStyle(.secondary)
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Surface {
            VStack(alignment:.leading,spacing:23) {
                Text("Aspetto e unità").font(.headline)
                Picker("Aspetto",selection:$model.preferences.appearance) { Text("Sistema").tag("system"); Text("Chiaro").tag("light"); Text("Scuro").tag("dark") }.onChange(of:model.preferences.appearance) { _ in model.persist() }
                Toggle("Mostra temperature in Fahrenheit",isOn:$model.preferences.fahrenheit).onChange(of:model.preferences.fahrenheit) { _ in model.persist() }
                Toggle("Mostra RPM nella barra dei menu",isOn:$model.preferences.menuRPM).onChange(of:model.preferences.menuRPM) { _ in model.persist() }
                Picker("Sensore barra dei menu",selection:$model.preferences.menuSensor) { if !model.sensors.contains(where: { $0.id == model.preferences.menuSensor }) { Text("Non disponibile (fallback automatico)").tag(model.preferences.menuSensor) }; ForEach(model.sensors) { Text("\($0.name) · \($0.id)").tag($0.id) } }.onChange(of:model.preferences.menuSensor) { _ in model.persist() }
                Picker("Ventola barra dei menu",selection:$model.preferences.menuFan) { if !model.fans.contains(where: { $0.id == model.preferences.menuFan }) { Text("Non disponibile (fallback automatico)").tag(model.preferences.menuFan) }; ForEach(model.fans) { Text($0.name).tag($0.id) } }.onChange(of:model.preferences.menuFan) { _ in model.persist() }
                Divider()
                Toggle("Apri Boreal al login",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)})).disabled(model.demo)
                Text("La finestra può essere chiusa: il controllo continua dalla barra dei menu. Uscendo dall’app viene richiesto Auto.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Surface {
            VStack(alignment:.leading,spacing:13) {
                Text("Compatibilità e diagnostica").font(.headline)
                Text("Prima versione per macOS 13+ su Intel. Le chiavi e i permessi SMC variano per modello; il controllo resta disabilitato quando non sono riconosciuti. SMART di dischi e backend Apple Silicon non ancora implementati.").font(.caption).foregroundStyle(.secondary)
                Button("Esporta informazioni tecniche") { model.exportDiagnostics() }
            }
        }
    }
}
struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View { VStack(spacing:12) { Image(systemName:symbol).font(.system(size:28)); Text(text).font(.system(size:12)).multilineTextAlignment(.center) }.foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,35) }
}
