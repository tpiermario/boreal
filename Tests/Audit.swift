import Foundation
import AppKit
import CSMC

@main struct Audit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var passed = 0
        var failed = 0
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) {
            if (try? condition()) == true { passed += 1; print("PASS\t\(name)") }
            else { failed += 1; print("FAIL\t\(name)") }
        }
        func rejects<T>(_ body: () throws -> T) -> Bool { do { _ = try body(); return false } catch { return true } }
        func accepts<T>(_ body: () throws -> T) -> Bool { !rejects(body) }
        let origin = Date(timeIntervalSince1970: 1000)
        func sample(_ t: Double, _ sensors: [String: Double] = ["TC0P":50,"TG0P":40]) -> Sample {
            Sample(date: origin.addingTimeInterval(t), sensors:sensors, fans:[:])
        }
        func plotted(_ samples: [Sample], _ f: Bool = false) -> [ThermalPoint] {
            thermalPoints(samples, since:origin, fahrenheit:f)
        }
        check("grafico vuoto", plotted([]).isEmpty)
        let regular = plotted([sample(0),sample(1),sample(2)])
        check("grafico continuo due serie", Set(regular.map(\.segment)).count == 2)
        let gapPoints = plotted([sample(0),sample(1),sample(20),sample(21)])
        check("grafico interruzione temporale", Set(gapPoints.map(\.segment)).count == 4)
        check("grafico singolo punto visibile", plotted([sample(0)]).count == 2)
        let missing = plotted([sample(0),sample(1,["TC0P":51]),sample(2)])
        check("grafico assenza GPU interrompe solo GPU", Set(missing.filter{$0.series=="GPU"}.map(\.segment)).count == 2 && Set(missing.filter{$0.series=="CPU"}.map(\.segment)).count == 1)
        check("grafico sensori invalidi", plotted([sample(0,["TC0P":.nan,"TG0P":.infinity])]).isEmpty)
        check("grafico filtro data", plotted([sample(-1),sample(0)]).count == 2)
        check("grafico Fahrenheit", plotted([sample(0)],true).first?.value == 122)
        check("grafico orologio arretra", Set(plotted([sample(2),sample(1)]).map(\.segment)).count == 4)
        check("grafico timestamp duplicato", Set(plotted([sample(1),sample(1)]).map(\.segment)).count == 4)
        let many = (0..<180).map { sample(Double($0 < 90 ? $0 : $0+100)) }
        let reduced = plotted(many)
        check("grafico riduzione conserva interruzione", Set(reduced.map(\.segment)).count == 4)
        check("grafico riduzione numero punti", reduced.count == 120)
        check("grafico soglia tre secondi", Set(plotted([sample(0),sample(3)]).map(\.segment)).count == 2)
        check("grafico oltre soglia", Set(plotted([sample(0),sample(3.001)]).map(\.segment)).count == 4)
        let auto = FanRule()
        check("auto senza sensori", accepts { try auto.target(minimum: 1000, maximum: 5000, temperatures: [:]) })
        check("auto con limiti NaN", (try auto.target(minimum: .nan, maximum: .nan, temperatures: [:])) == -1)
        let fixed = FanRule(mode: .fixed, rpm: 2500)
        for (name, lo, hi) in [("minimo negativo",-1.0,5000.0),("limiti invertiti",5000,1000),("limiti uguali",1000,1000),("massimo eccessivo",1000,20001),("minimo NaN",Double.nan,5000),("massimo infinito",1000,Double.infinity)] {
            check("regola rifiuta \(name)", rejects { try fixed.target(minimum: lo, maximum: hi, temperatures: [:]) })
        }
        for (name,rpm,valid) in [("sotto minimo",999.0,false),("minimo",1000,true),("intermedio",2500,true),("massimo",5000,true),("sopra massimo",5001,false),("NaN",Double.nan,false),("infinito",Double.infinity,false),("meno infinito",-Double.infinity,false)] {
            check("RPM \(name)", accepts { try FanRule(mode:.fixed,rpm:rpm).target(minimum:1000,maximum:5000,temperatures:[:]) } == valid)
        }
        let curve = FanRule(mode: .sensor)
        for (name,t,valid) in [("zero",0.0,false),("negativo",-1,false),("NaN",Double.nan,false),("infinito",Double.infinity,false),("freddo",30,true),("inizio",50,true),("mezzo",65,true),("massimo",80,true),("125",125,true),("oltre125",126,false)] {
            check("sensore \(name)", accepts { try curve.target(minimum:1000,maximum:5000,temperatures:["TC0P":t]) } == valid)
        }
        check("sensore mancante", rejects { try curve.target(minimum:1000,maximum:5000,temperatures:[:]) })
        check("curva interpolata", (try curve.target(minimum:1000,maximum:5000,temperatures:["TC0P":65])) == 3000)
        check("curva satura in basso", (try curve.target(minimum:1000,maximum:5000,temperatures:["TC0P":30])) == 1000)
        check("curva satura in alto", (try curve.target(minimum:1000,maximum:5000,temperatures:["TC0P":90])) == 5000)
        for (name,start,full,valid) in [("invertite",80.0,50.0,false),("uguali",50,50,false),("inizio basso",19,80,false),("massimo alto",50,91,false),("NaN",Double.nan,80,false),("infinito",50,Double.infinity,false),("estremi",20,90,true)] {
            check("soglie \(name)", accepts { try FanRule(mode:.sensor,start:start,full:full).target(minimum:1000,maximum:5000,temperatures:["TC0P":60]) } == valid)
        }
        for (key,valid) in [("TC0P",true),("FS! ",true),("",false),("TC0",false),("TC0PP",false),("TC\nP",false),("TC\0P",false),("T€",false),("😀",false),("éabc",false)] { check("chiave \(key.debugDescription)", validSensorKey(key) == valid) }
        let profile = FanProfile(name: "Lavoro", rules:[0:auto])
        check("profilo valido", accepts { try profile.validated() })
        check("profilo vuoto", rejects { try FanProfile(name:"A",rules:[:]).validated() })
        for (name,valid) in [("",false),("   ",false),("A\nB",false),("A\tB",false),(String(repeating:"a",count:61),false),(String(repeating:"a",count:60),true),("Lavoro 😀",true)] { check("nome \(name.debugDescription)", accepts { try FanProfile(name:name,rules:[0:auto]).validated() } == valid) }
        check("trim nome", (try FanProfile(name:" Lavoro ",rules:[0:auto]).validated()).name == "Lavoro")
        for index in [-1,10] { check("indice ventola \(index)", rejects { try FanProfile(name:"A",rules:[index:auto]).validated() }) }
        check("10 ventole valide", accepts { try FanProfile(name:"A",rules:Dictionary(uniqueKeysWithValues:(0..<10).map{($0,auto)})).validated() })
        check("11 ventole rifiutate", rejects { try FanProfile(name:"A",rules:Dictionary(uniqueKeysWithValues:(0..<11).map{($0,auto)})).validated() })
        for rpm in [-1.0,20001,Double.infinity,Double.nan] { check("profilo RPM \(rpm)", rejects { try FanProfile(name:"A",rules:[0:FanRule(rpm:rpm)]).validated() }) }
        check("preferenze predefinite", accepts { try Preferences().validated() })
        for version in [0,2,-1] { var p=Preferences();p.version=version;check("versione \(version)", rejects{try p.validated()}) }
        for appearance in ["system","light","dark"] { var p=Preferences();p.appearance=appearance;check("tema \(appearance)", accepts{try p.validated()}) }
        var pref=Preferences();pref.appearance="other";check("tema invalido",rejects{try pref.validated()})
        for index in [-1,10] { var p=Preferences();p.menuFan=index;check("menu ventola \(index)", rejects{try p.validated()}) }
        pref=Preferences();pref.menuSensor="bad";check("sensore menu invalido",rejects{try pref.validated()})
        pref=Preferences();pref.profiles=[profile,profile];check("UUID duplicato",rejects{try pref.validated()})
        pref=Preferences();pref.profiles=(0..<101).map{FanProfile(name:"P\($0)",rules:[0:auto])};check("limite101",rejects{try pref.validated()})
        pref.profiles.removeLast();check("limite100",accepts{try pref.validated()})
        check("JSON roundtrip", (try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(pref))).profiles.count == 100)
        for bad in ["{}","[]","null","{","{\"version\":2}"] { check("JSON incompleto \(bad)",rejects{try JSONDecoder().decode(Preferences.self,from:Data(bad.utf8))}) }
        check("import duplicato esistente", rejects{try mergeProfiles(existing:[profile],imported:[profile])})
        check("import duplicato interno", rejects{try mergeProfiles(existing:[],imported:[profile,profile])})
        check("import case insensitive", rejects{try mergeProfiles(existing:[profile],imported:[FanProfile(name:"LAVORO",rules:[0:auto])])})
        check("import diacritici", rejects{try mergeProfiles(existing:[profile],imported:[FanProfile(name:"Làvoro",rules:[0:auto])])})
        let imported=try mergeProfiles(existing:[],imported:[profile]);check("import nuovo UUID",imported[0].id != profile.id)
        check("import vuoto",try mergeProfiles(existing:[profile],imported:[]).count == 1)
        check("import oltre100",rejects{try mergeProfiles(existing:pref.profiles,imported:[profile])})
        check("import atomico invalido",rejects{try mergeProfiles(existing:[],imported:[profile,FanProfile(name:"",rules:[0:auto])])})
        for (value,expected) in [("","\"\""),("test","\"test\""),("a,b","\"a,b\""),("a\"b","\"a\"\"b\""),("a\nb","\"a\nb\""),("😀","\"😀\"")] { check("CSV \(value.debugDescription)",csvField(value)==expected) }
        let epoch=RequestEpoch();check("epoch iniziale",epoch.matches(0));epoch.set(1);check("epoch scarta vecchia richiesta",!epoch.matches(0));check("epoch accetta corrente",epoch.matches(1))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("boreal-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let model=AppModel(demo:true,storageDirectory:root,startMonitoring:false)
        check("avvio non dichiara Auto",!model.autoConfirmed && !model.active)
        check("avvio telemetria non valida",!model.telemetryFresh)
        check("tray senza dati esplicito",model.trayText == "Dati non aggiornati")
        check("avvio controlli manuali disabilitati",!model.canControl)
        check("apply senza ventole rifiutato",!model.apply())
        model.restore();check("Auto demo confermato",model.autoConfirmed)
        model.fans=[FanReading(id:0,name:"Ventola",current:2000,minimum:1000,maximum:5000,controllable:true)]
        model.sensors=[SensorReading(id:"TC0P",name:"CPU",group:"CPU",value:50)]
        model.lastUpdated=Date();check("telemetria recente",model.telemetryFresh)
        model.lastUpdated=Date().addingTimeInterval(-4);check("telemetria scaduta",!model.telemetryFresh)
        model.lastUpdated=Date().addingTimeInterval(4);check("telemetria futura",!model.telemetryFresh)
        model.lastUpdated=Date();check("manuale disponibile demo",model.canControl)
        model.commandPending=true;check("comando pendente blocca manuale",!model.canControl);model.commandPending=false
        model.competingController=true;check("conflitto blocca manuale",!model.canControl);check("conflitto blocca Auto",!model.canRestore);model.competingController=false
        model.sensors[0].value=95;check("CPU95 blocca",!model.canControl);model.sensors[0].value=50
        model.sensors.append(SensorReading(id:"TG0P",name:"GPU",group:"GPU",value:95));check("GPU95 blocca",!model.canControl);model.sensors.removeLast()
        check("profilo salvato su disco",model.saveProfile(" Lavoro "))
        check("nome conservato",model.preferences.profiles.first?.name=="Lavoro")
        check("duplicato salvataggio rifiutato",!model.saveProfile("LAVORO"))
        check("nome lungo non troncato",!model.saveProfile(String(repeating:"x",count:61)))
        let reloaded=AppModel(demo:true,storageDirectory:root,startMonitoring:false);check("preferenze persistenti",reloaded.preferences.profiles.count==1)
        let file=root.appendingPathComponent("preferences.json")
        try Data("corrotto".utf8).write(to:file)
        let repaired=AppModel(demo:true,storageDirectory:root,startMonitoring:false)
        check("backup corruzione",try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix("preferences-invalid-")})
        check("originale non sovrascritto al caricamento",try String(contentsOf:file,encoding:.utf8)=="corrotto")
        check("persistenza dopo backup",repaired.persist())
        let blocked=root.appendingPathComponent("file-invece-di-cartella");try Data().write(to:blocked)
        let broken=AppModel(demo:true,storageDirectory:blocked,startMonitoring:false);broken.fans=model.fans
        check("errore disco segnalato",!broken.saveProfile("Non salvato"))
        check("rollback creazione profilo",broken.preferences.profiles.isEmpty)
        broken.preferences.profiles=[profile];broken.deleteProfile(profile.id);check("rollback eliminazione",broken.preferences.profiles.count==1)
        let big=root.appendingPathComponent("big.json");try Data(repeating:65,count:1_000_001).write(to:big)
        check("lettura oltre1MB rifiutata",rejects{try AppModel.readLimited(big)})
        try Data(repeating:65,count:1_000_000).write(to:big);check("lettura1MB",try AppModel.readLimited(big).count==1_000_000)
        let tray=NativeTray(model:model,openWindow:{},install:false)
        check("menu non vuoto prima apertura", !tray.menu.items.isEmpty)
        tray.menuWillOpen(tray.menu)
        check("menu tracking",tray.tracking)
        let originalItems=tray.menu.items
        let titles=originalItems.map(\.title)
        let label=tray.item.button?.title
        model.lastUpdated=Date();model.sensors[0].value=70;model.preferences.profiles=[]
        tray.refreshLabel()
        check("righe immutate durante lettura",tray.menu.items.map(\.title)==titles)
        check("identità righe immutata",zip(originalItems,tray.menu.items).allSatisfy{$0 === $1})
        check("larghezza barra immutata durante menu",tray.item.button?.title==label)
        check("nessuna custom view nelle righe",tray.menu.items.allSatisfy{$0.view==nil})
        check("titoli informativi disabilitati",!tray.menu.items[0].isEnabled && !tray.menu.items[1].isEnabled)
        check("azioni hanno target",tray.menu.items.filter{$0.action != nil && $0.submenu == nil}.allSatisfy{$0.target === tray})
        check("profili in sottomenu",tray.menu.items.contains{$0.title=="Profili" && $0.submenu != nil})
        tray.menuDidClose(tray.menu);check("tracking termina",!tray.tracking)
        check("etichetta aggiornata dopo chiusura",tray.item.button?.title != label)
        tray.menuWillOpen(tray.menu);check("profili rimossi alla riapertura",!tray.menu.items.contains{$0.title=="Profili"})
        tray.menuDidClose(tray.menu);tray.remove()
        print("RESULT\t\(passed) passed\t\(failed) failed")
        if failed>0 { exit(1) }
    }
}
