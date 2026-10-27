# Boreal

Temperature e ventole del Mac, in una finestra semplice.

Boreal permette di tenere d’occhio i sensori del Mac, vedere come cambiano le temperature e regolare le ventole quando serve. L’interfaccia è in italiano, con modalità chiara e scura.

**[Scarica Boreal per Mac Intel](https://github.com/tpiermario/boreal/releases/latest)**

## Cosa puoi fare

- Consultare temperature e velocità delle ventole in tempo reale.
- Scegliere il sensore da mostrare nella barra dei menu.
- Usare la gestione automatica Apple, impostare RPM fissi o una curva legata a un sensore.
- Salvare profili e consultare la cronologia della sessione.
- Esportare la telemetria in CSV e i profili in JSON.

## Installazione

1. Scarica il file `Boreal-0.2.3-Intel.dmg` dalla pagina della release.
2. Apri il DMG e trascina **Boreal** in **Applicazioni**.
3. Apri Boreal: il monitoraggio funziona anche senza installare il servizio.

Per regolare le ventole, apri la cartella **Opzioni** nel DMG ed esegui **Installa controllo ventole.command**. Il Terminale chiederà la password amministratore per installare il servizio locale.

La build è firmata localmente e non è notarizzata da Apple: macOS può impedirne l’apertura con le impostazioni predefinite.

## Compatibilità e controllo delle ventole

Boreal 0.2.3 è destinato ai **Mac Intel con macOS 13 o successivo**. Apple Silicon non è supportato. I sensori disponibili e la possibilità di controllare le ventole dipendono dal modello; il collaudo svolto non copre tutti i Mac Intel.

Il pulsante **Ripristina Auto** restituisce il controllo ad Apple. Chiudere la finestra lascia Boreal attivo nella barra dei menu; uscire dall’app richiede il ritorno ad Auto. Il servizio dispone di un watchdog che richiede il ripristino automatico dopo quattro secondi senza rinnovo del controllo. Non usare Boreal insieme a un altro programma che regola le ventole.

Per rimuovere il servizio, esegui **Rimuovi controllo ventole.command** dalla cartella **Opzioni**. Poi esci dall’app e rimuovila da Applicazioni.

## Cosa contiene questo repository

Questa pagina raccoglie il download, le istruzioni e le segnalazioni di Boreal. **Il codice sorgente non è incluso**: il progetto viene pubblicato qui come applicazione compilata, non come repository di sviluppo open source. La licenza MIT inclusa nel pacchetto è riportata anche nel file [LICENSE](LICENSE).

## Segnalare un problema

Apri una [segnalazione](https://github.com/tpiermario/boreal/issues) indicando il modello del Mac, la versione di macOS, cosa stavi facendo e cosa è successo. Uno screenshot può aiutare, purché non contenga informazioni personali. Non inserire password o numeri di serie.
