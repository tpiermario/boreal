# Boreal 0.2.5

Temperature e ventole del Mac, in una finestra semplice.
App nativa per Mac Intel con macOS 13 o successivo. Interfaccia in italiano,
tema chiaro e scuro, sensori, profili, cronologia ed esportazione CSV.
Il monitoraggio funziona senza installare un servizio.

[Scarica Boreal per Mac Intel](https://github.com/tpiermario/boreal/releases/latest)

Il codice di questa versione è pubblico con licenza MIT.

Questa cartella conserva i sorgenti ricostruiti dai frammenti di codice e dalle
modifiche presenti nella cronologia del progetto. Non è una decompilazione né
una copia byte per byte del vecchio archivio cancellato. Include l’app, il
backend C/IOKit, il servizio, la CLI, i test e gli script di distribuzione.

## Compilare e verificare

Su un Mac Intel con Xcode Command Line Tools installati:

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh
```

Il pacchetto finale viene creato in `dist/Boreal-0.2.5-Intel.dmg`. Per indicare
un’altra destinazione, passala come primo argomento a `package.sh`.
La build esegue i test prima di compilare la release. Non installa il servizio.
Non scarica dipendenze di rete. Il runner di verifica Swift usa Foundation e
AppKit: funziona anche con i soli Command Line Tools e non richiede XCTest.
I precedenti test XCTest dei modelli sono conservati in `Tests/BorealTests`;
`swift test` richiede un ambiente che fornisca il modulo XCTest.

La build usa una firma ad hoc locale. Non è notarizzata da Apple. `Resources`
contiene l’icona; `Packaging/layout.dmg` contiene soltanto lo sfondo, il layout
Finder e il collegamento Applicazioni, senza applicazione compilata.

## Cosa cambia nella 0.2.5

Il grafico lascia uno spazio quando mancano letture per più di tre secondi o
quando un sensore scompare. CPU e GPU sono segmentate separatamente, prima di
ridurre i campioni; anche un tratto composto da un solo punto resta visibile.

Il client attende fino a 5,5 secondi per APPLY e 3,5 per AUTO, includendo le
attese di verifica e ripristino dell’helper con dieci ventole. PING mantiene
0,8 secondi. Questi timeout non rinnovano né allungano il lease del watchdog.
Le chiamate al driver e il carico del sistema non hanno una durata garantita:
il timeout resta finito e un errore continua a richiedere il ritorno ad Auto.

## Correzioni della 0.2.4

Il menu della barra è un `NSMenu` nativo. Le sue voci sono una fotografia dello
stato all’apertura: non cambiano posizione durante gli aggiornamenti dei
sensori. La telemetria continua a essere letta; il testo del menu si aggiorna
alla successiva apertura. Scorciatoia dalla finestra: ⌘⇧M.

La UI distingue comandi in attesa, confermati e non verificati. L’editor resta
aperto se il servizio rifiuta la richiesta. I profili vengono salvati in modo
atomico: un errore di scrittura non viene presentato come un salvataggio
riuscito. Le impostazioni illeggibili vengono copiate prima di un nuovo
salvataggio. L’importazione rifiuta nomi duplicati e file oltre 1 MB.

## Installazione e uso

Trascina Boreal dal DMG in Applicazioni. Per il controllo manuale usa lo script
nella cartella Opzioni del DMG; per l’helper compilato localmente:

```sh
bash scripts/install-helper.sh
bash scripts/uninstall-helper.sh
```

Gli script chiedono la password amministratore nel Terminale. Il servizio è
riservato all’UID che lo installa; non applica un profilo manuale all’avvio.
Per la simulazione, senza comandi alle ventole:

```sh
dist/Boreal.app/Contents/MacOS/Boreal --demo
```

Impostazioni: `~/Library/Application Support/Boreal/preferences.json`.
La simulazione usa una cartella separata, `Boreal-Demo`.
Il servizio accetta PING, AUTO e APPLY. PING non rinnova il lease di quattro
secondi. Il watchdog e la protezione termica restano nel servizio.

## Limiti verificati

Il rapporto `AUDIT.txt` distingue difetti, verifiche e limiti del collaudo.
Non sono certificati Apple Silicon, altri modelli Intel, sospensione hardware,
crash del kernel o guasti SMC. I test del servizio usano un backend simulato.
Non avviare contemporaneamente altri controller ventole.

Licenza MIT, vedi `LICENSE`. Conserva questa cartella e l’archivio sorgenti:
sono necessari per riprodurre e mantenere la build.
