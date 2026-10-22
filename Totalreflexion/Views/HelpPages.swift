import SwiftUI

/// Content of one help topic.
struct HelpPage: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch topic {
            case .overview: OverviewHelp()
            case .connect: ConnectHelp()
            case .views: ViewsHelp()
            case .mainWindow: MainWindowHelp()
            case .presentation: PresentationHelp()
            case .floating: FloatingHelp()
            case .devices: DevicesHelp()
            case .appearance: AppearanceHelp()
            case .shortcuts: ShortcutsHelp()
            case .troubleshooting: TroubleshootingHelp()
            }
        }
    }
}

private struct OverviewHelp: View {
    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top),
                           GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        HelpHeader(topic: .overview, intro: "Totalreflexion macht deinen Mac zum AirPlay-Empfänger: iPads (und iPhones) "
                   + "zeigen ihren Bildschirm drahtlos auf dem Mac – auch mehrere gleichzeitig. Gedacht für Vorführungen, "
                   + "Unterricht und Präsentationen.")
        HelpSection(title: "Das kann Totalreflexion") {
            LazyVGrid(columns: columns, spacing: 12) {
                HelpCard(icon: "ipad.and.iphone", title: "Mehrere iPads",
                         text: "Beliebig viele Geräte gleichzeitig, jedes mit eigener Verbindung.")
                HelpCard(icon: "rotate.right", title: "Dreht sich mit",
                         text: "Hoch- und Querformat folgen dem iPad automatisch.")
                HelpCard(icon: "rectangle.3.group", title: "Drei Ansichten",
                         text: "Hauptfenster, Präsentation mit Hintergrund oder frei schwebende Fenster.")
                HelpCard(icon: "eye", title: "Geräte verwalten",
                         text: "Ein- und ausblenden, Vollbild, umbenennen, stummschalten, trennen.")
                HelpCard(icon: "ipad", title: "iPad-Rahmen",
                         text: "Randlos, mit Home-Button, in sechs Farben – oder ein eigenes Mockup-Bild.")
                HelpCard(icon: "photo", title: "Hintergrund",
                         text: "Farbe, Verlauf oder ein Bild, z. B. eine PowerPoint-Folie.")
                HelpCard(icon: "plus.magnifyingglass", title: "Zoom",
                         text: "Details heranholen: Pinch, ⌥ + Scrollrad oder ⌘+ / ⌘−.")
                HelpCard(icon: "speaker.wave.2", title: "Ton",
                         text: "Der Ton der iPads wird mitübertragen, pro Gerät stummschaltbar.")
            }
        }
        HelpSection(title: "So fängst du an") {
            HelpSteps(steps: [
                "**iPad verbinden:** Kontrollzentrum › Bildschirmsynchronisierung › „Totalreflexion“.",
                "**Ansicht wählen:** Hauptfenster zum Zuschauen, Präsentation für den Beamer, eigene Fenster für den "
                    + "Schreibtisch oder über PowerPoint.",
                "**Verwalten:** Im Geräte-Fenster (⇧⌘G) blendest du iPads ein und aus oder holst eines ins Vollbild."
            ])
            HelpTopicLink(topic: .connect)
            HelpTopicLink(topic: .views)
        }
        HelpTip("Diese Hilfe findest du jederzeit im Menü **Hilfe** (⌘?), über das **?** im Geräte-Fenster "
                + "und über das Totalreflexion-Symbol in der Menüleiste.")
    }
}

private struct ConnectHelp: View {
    var body: some View {
        HelpHeader(topic: .connect, intro: "Das iPad sendet sein Bild per AirPlay. Kabel oder eine App auf dem iPad "
                   + "brauchst du nicht.")
        HelpSection(title: "Verbinden") {
            HelpSteps(steps: [
                "Mac und iPad sind im **selben WLAN**.",
                "Auf dem iPad das **Kontrollzentrum** öffnen: von der oberen rechten Ecke nach unten wischen.",
                "**Bildschirmsynchronisierung** antippen (Symbol mit zwei Rechtecken).",
                "**Totalreflexion** auswählen. Nach ein bis zwei Sekunden erscheint das iPad auf dem Mac."
            ])
            HelpText("Weitere iPads verbindest du genauso – sie erscheinen alle gleichzeitig.")
        }
        HelpSection(title: "Trennen") {
            HelpText("Auf dem iPad: Kontrollzentrum › Bildschirmsynchronisierung › **Synchronisierung stoppen**. "
                     + "Oder auf dem Mac: Rechtsklick auf das iPad › **Verbindung trennen**.")
        }
        HelpTip("Der Name in der AirPlay-Liste lässt sich ändern: **Einstellungen** (⌘,) › Empfänger › "
                + "„Name im AirPlay-Menü“.")
        HelpTip("Steht dein Mac zweimal in der Liste (z. B. „Totalreflexion“ und „…s iMac“), ist der zweite Eintrag "
                + "der eingebaute AirPlay-Empfänger von macOS. Wähle **Totalreflexion**.")
    }
}

private struct ViewsHelp: View {
    var body: some View {
        HelpHeader(topic: .views, intro: "Totalreflexion zeigt die iPads auf drei Arten. **Hauptfenster** und "
                   + "**Eigene Fenster** sind die zwei Grundmodi – du schaltest zwischen ihnen um. Die **Präsentation** "
                   + "öffnest du bei Bedarf zusätzlich.")
        HelpCard(icon: "square.grid.2x2", title: "1 · Hauptfenster",
                 text: "Ein normales Mac-Fenster. Alle iPads stehen automatisch nebeneinander, so groß wie möglich. "
                     + "Gut zum Zuschauen und Arbeiten.", windowID: "main", buttonTitle: "Hauptfenster öffnen")
        HelpCard(icon: "play.rectangle.on.rectangle", title: "2 · Präsentation",
                 text: "Eine Bühne für Beamer oder zweiten Bildschirm: Ein Hintergrund (Farbe, Verlauf oder Bild) füllt "
                     + "den Bildschirm, die iPads verschiebst und vergrößerst du frei mit der Maus.",
                 windowID: "presentation", buttonTitle: "Präsentation öffnen (⇧⌘P)")
        HelpCard(icon: "macwindow.on.rectangle", title: "3 · Eigene Fenster",
                 text: "Wie bei AirServer: kein Hauptfenster. Jedes iPad schwebt als eigenes, randloses Fenster auf dem "
                     + "Schreibtisch – auf Wunsch über allen anderen Programmen, z. B. über PowerPoint.",
                 windowID: "manager", buttonTitle: "Im Geräte-Fenster einschalten")
        HelpSection(title: "Umschalten") {
            HelpTable(rows: [
                ("Hauptfenster ↔ Eigene Fenster", "Geräte-Fenster (⇧⌘G) › oben **Anzeige**. Oder Menüleisten-Symbol › "
                    + "**Eigene Fenster**."),
                ("Präsentation öffnen", "⇧⌘P, Knopf **Präsentation** im Haupt- oder Geräte-Fenster, oder Menüleiste."),
                ("Präsentation beenden", "Esc verlässt das Vollbild, ⌘W schließt das Fenster.")
            ])
        }
        HelpSection(title: "Welche Ansicht passt?") {
            HelpTable(rows: [
                ("Nur sehen, was auf den iPads passiert", "**Hauptfenster**"),
                ("iPads über den Beamer zeigen", "**Präsentation**, dort mit **Vollbild** und **Bildschirm** auf den Beamer"),
                ("PowerPoint-Folie hinter den iPads", "**Präsentation** › Hintergrund › **Bild wählen …** (die Folie "
                    + "vorher in PowerPoint als Bild exportieren) – oder **Eigene Fenster** mit „Immer im Vordergrund“ "
                    + "über der laufenden Bildschirmpräsentation"),
                ("iPads frei neben anderen Programmen", "**Eigene Fenster**")
            ])
        }
    }
}

private struct MainWindowHelp: View {
    var body: some View {
        HelpHeader(topic: .mainWindow, intro: "Das Hauptfenster ordnet alle sichtbaren iPads automatisch an. Kommt ein "
                   + "iPad dazu oder wird eines gedreht, ordnet sich das Raster neu.")
        HelpSection(title: "Bedienung") {
            HelpTable(rows: [
                ("Doppelklick", "Zeigt nur dieses iPad (Fokus). **Esc** oder **Alle zeigen** kehrt zurück."),
                ("Pinch / ⌥ + Scrollen", "Zoomen. Bei Zoom mit zwei Fingern verschieben."),
                ("⌘+ / ⌘− / ⌘0", "Vergrößern, verkleinern, Zoom zurücksetzen."),
                ("Maus über iPad", "Oben rechts erscheint **…** mit dem Gerätemenü (auch per Rechtsklick).")
            ])
        }
        HelpSection(title: "Symbolleiste") {
            HelpTable(rows: [
                ("Statuspunkt", "Grün = bereit, mit Anzahl der verbundenen Geräte."),
                ("Rahmen", "Standard-Rahmen und -Farbe für alle iPads, Namen ein/aus."),
                ("Zoom", "Die drei Zoom-Knöpfe mit aktueller Vergrößerung."),
                ("Geräte", "Öffnet das Geräte-Fenster."),
                ("Präsentation", "Öffnet die Präsentation.")
            ])
        }
        HelpTopicLink(topic: .devices)
    }
}

private struct PresentationHelp: View {
    var body: some View {
        HelpHeader(topic: .presentation, intro: "Die Präsentation ist eine Bühne: Der Hintergrund füllt den Bildschirm, "
                   + "die iPads liegen darüber und lassen sich frei anordnen. Ideal für Beamer und zweite Bildschirme.")
        HelpSection(title: "iPads anordnen") {
            HelpTable(rows: [
                ("Ziehen", "iPad verschieben."),
                ("Griff unten rechts", "Größe ändern (erscheint, wenn die Maus über dem iPad ist)."),
                ("Doppelklick", "**Spotlight:** Das iPad kommt groß in die Mitte, die anderen werden abgedunkelt. "
                    + "Esc beendet."),
                ("Esc", "Nacheinander: Spotlight beenden → Zoom zurücksetzen → Vollbild verlassen.")
            ])
            HelpText("Die Anordnung wird pro iPad gespeichert und gilt auch beim nächsten Verbinden.")
        }
        HelpSection(title: "Die Leiste oben") {
            HelpText("Sie blendet sich nach ein paar Sekunden aus. **Maus bewegen** holt sie zurück.")
            HelpTable(rows: [
                ("Anordnen", "Alle iPads automatisch verteilen."),
                ("Fixieren", "Sperrt die Anordnung gegen versehentliches Verschieben."),
                ("Hintergrund", "Farbe, Verlauf oder Bild; „Bild füllt Bildschirm“ schneidet zu statt Ränder zu lassen."),
                ("Farbfelder", "Hintergrundfarbe und zweite Verlaufsfarbe."),
                ("Rahmen", "Rahmen, Farbe und Namen für alle iPads."),
                ("Bildschirm", "Präsentation auf einen anderen Bildschirm (z. B. Beamer) schieben."),
                ("Vollbild", "Vollbild ein/aus (⌃⌘F).")
            ])
        }
        HelpTip("**PowerPoint-Folie als Hintergrund:** In PowerPoint die Folie als Bild (PNG oder JPEG) exportieren, "
                + "dann in der Leiste **Hintergrund › Bild wählen …**.")
        HelpTip("Wirkt ein iPad **abgedunkelt** oder lässt sich **nicht verschieben**? Dann ist ein Spotlight aktiv "
                + "(**Esc**) oder **Fixieren** eingeschaltet (Schloss in der Leiste).")
    }
}

private struct FloatingHelp: View {
    var body: some View {
        HelpHeader(topic: .floating, intro: "Statt eines Hauptfensters bekommt jedes iPad ein eigenes, randloses Fenster. "
                   + "Die iPads liegen dann frei auf dem Schreibtisch – wie bei AirServer.")
        HelpSection(title: "Einschalten") {
            HelpSteps(steps: [
                "Geräte-Fenster öffnen (⇧⌘G).",
                "Oben bei **Anzeige** auf **Eigene Fenster** klicken. Das Hauptfenster schließt sich.",
                "Bei Bedarf **Immer im Vordergrund** einschalten."
            ])
            HelpText("Totalreflexion merkt sich den Modus und startet beim nächsten Mal direkt so. Bedient wird dann über "
                     + "das Geräte-Fenster und das Symbol in der Menüleiste. Zurück geht es mit **Anzeige › Hauptfenster**.")
        }
        HelpSection(title: "Bedienung") {
            HelpTable(rows: [
                ("Ziehen", "iPad-Fenster verschieben."),
                ("Kante oder Griff", "Größe ändern – an einer Kante ziehen oder am Griff unten rechts."),
                ("Doppelklick", "Vollbild; nochmal Doppelklick oder **Esc** kehrt zurück."),
                ("Anordnen", "Im Geräte-Fenster: verteilt alle iPad-Fenster nebeneinander.")
            ])
            HelpText("Position und Größe werden pro iPad gespeichert.")
        }
        HelpTip("**Über PowerPoint zeigen:** „Immer im Vordergrund“ einschalten, dann in PowerPoint die "
                + "Bildschirmpräsentation starten. Werden die iPads trotzdem verdeckt, nimm die **Präsentation** mit "
                + "der Folie als Hintergrundbild.")
    }
}

private struct DevicesHelp: View {
    var body: some View {
        HelpHeader(topic: .devices, intro: "Im Geräte-Fenster steuerst du jedes verbundene iPad einzeln. Du öffnest es mit "
                   + "⇧⌘G, über den Knopf **Geräte** im Hauptfenster oder über das Menüleisten-Symbol.")
        HelpSection(title: "Pro iPad") {
            HelpTable(rows: [
                ("👁 Auge", "Ein- und ausblenden – in allen Ansichten. Der Ton läuft weiter. Nach neuem Verbinden ist "
                    + "das iPad wieder sichtbar."),
                ("Vollbild", "Das iPad füllt allein den Bildschirm, in jeder Ansicht. Mit mehreren Bildschirmen: Knopf "
                    + "**gedrückt halten** und Bildschirm wählen. Esc oder Doppelklick beendet."),
                ("…", "Rahmen, Farbe, nach links/rechts drehen (z. B. für iPads im Ständer), stumm, umbenennen, trennen.")
            ])
        }
        HelpSection(title: "Oben im Fenster") {
            HelpTable(rows: [
                ("Anzeige", "Umschalten zwischen **Hauptfenster** und **Eigene Fenster**."),
                ("Immer im Vordergrund", "Nur bei eigenen Fenstern: iPads bleiben über anderen Programmen."),
                ("Alle einblenden", "Holt ausgeblendete iPads zurück."),
                ("Anordnen", "Nur bei eigenen Fenstern: alle iPad-Fenster verteilen."),
                ("Präsentation", "Öffnet die Präsentation.")
            ])
        }
        HelpSection(title: "Menüleiste") {
            HelpText("Das Totalreflexion-Symbol in der Menüleiste zeigt den Status und alle iPads – ein Häkchen bedeutet "
                     + "sichtbar. Von dort öffnest du auch alle Fenster, wenn gerade keines offen ist.")
        }
    }
}

private struct AppearanceHelp: View {
    var body: some View {
        HelpHeader(topic: .appearance, intro: "Jedes iPad kann mit einem gezeichneten Gehäuse oder einem eigenen "
                   + "Mockup-Bild erscheinen.")
        HelpSection(title: "Rahmen") {
            HelpTable(rows: [
                ("Nur Bildschirm", "Ohne Gehäuse."),
                ("iPad (randlos)", "Aktuelles iPad mit schmalem Rand."),
                ("iPad mit Home-Button", "Älteres iPad mit breitem Rand und Home-Button."),
                ("Eigenes Rahmenbild", "Ein PNG-Mockup deiner Wahl.")
            ])
            HelpText("Farben: Space Grau, Silber, Schwarz, Weiß, Blau, Rosé.")
        }
        HelpSection(title: "Für alle oder pro iPad") {
            HelpText("**Für alle:** Einstellungen (⌘,) › Darstellung, oder das Menü **Rahmen** im Hauptfenster bzw. in "
                     + "der Präsentation.")
            HelpText("**Pro iPad:** **…** oder Rechtsklick › Rahmen / Farbe. „Standard“ folgt der Einstellung für alle.")
        }
        HelpSection(title: "Eigenes Rahmenbild") {
            HelpText("Ein PNG, dessen Bildschirmbereich durchsichtig ist (typische iPad-Mockups). Wählen unter "
                     + "Einstellungen › Darstellung › Eigenes Rahmenbild. Den Bildschirmbereich erkennt Totalreflexion "
                     + "selbst, und das Bild dreht sich mit dem iPad mit.")
        }
    }
}

private struct ShortcutsHelp: View {
    var body: some View {
        HelpHeader(topic: .shortcuts, intro: "Die wichtigsten Tastenkürzel und Mausgesten auf einen Blick.")
        HelpSection(title: "Tastatur") {
            HelpTable(rows: [
                ("⇧⌘G", "Geräte-Fenster"),
                ("⇧⌘P", "Präsentation"),
                ("⌘,", "Einstellungen"),
                ("⌘?", "Hilfe"),
                ("⌘+ / ⌘− / ⌘0", "Zoom im Hauptfenster"),
                ("⌃⌘F", "Vollbild in der Präsentation"),
                ("Esc", "Zurück: Fokus, Spotlight, Zoom oder Vollbild beenden")
            ])
        }
        HelpSection(title: "Maus & Trackpad") {
            HelpTable(rows: [
                ("Doppelklick", "Hauptfenster: Fokus · Präsentation: Spotlight · Eigene Fenster: Vollbild"),
                ("Ziehen", "Präsentation und eigene Fenster: iPad verschieben"),
                ("Griff unten rechts", "Präsentation und eigene Fenster: Größe ändern"),
                ("Pinch / ⌥ + Scrollrad", "Zoomen"),
                ("Zwei Finger", "Bei Zoom: Ausschnitt verschieben"),
                ("Rechtsklick", "Gerätemenü des iPads")
            ])
        }
    }
}

private struct TroubleshootingHelp: View {
    var body: some View {
        HelpHeader(topic: .troubleshooting, intro: "Die häufigsten Stolpersteine und was hilft.")
        HelpSection(title: "„Totalreflexion“ fehlt in der AirPlay-Liste") {
            HelpSteps(steps: [
                "Mac und iPad im selben WLAN?",
                "Statuspunkt im Haupt- oder Geräte-Fenster grün? Sonst Einstellungen › Empfänger › **Empfänger neu starten**.",
                "Systemeinstellungen › Datenschutz & Sicherheit › **Lokales Netzwerk**: Totalreflexion erlauben.",
                "Fragt die Firewall nach eingehenden Verbindungen: **Erlauben**."
            ])
        }
        HelpSection(title: "Weitere Probleme") {
            HelpTable(rows: [
                ("iPad abgedunkelt", "Spotlight aktiv – in der Präsentation **Esc** drücken."),
                ("iPad lässt sich nicht verschieben", "Spotlight aktiv oder **Fixieren** eingeschaltet."),
                ("iPad fehlt", "Ausgeblendet? Geräte-Fenster › **Alle einblenden**."),
                ("„Bildschirm gesperrt“", "Das iPad ist gesperrt – entsperren, dann läuft das Bild weiter."),
                ("Videos aus Apps starten nicht", "Unterstützt wird die Bildschirmsynchronisierung. Das „Streamen“ "
                    + "einzelner Videos (AirPlay-Symbol in YouTube & Co.) nicht."),
                ("Kein Ton", "Einstellungen › Empfänger › „Ton wiedergeben“; Gerät stumm (…)? Lautstärke am iPad?"),
                ("Bild ruckelt", "Einstellungen › Empfänger: kleinere Auflösung oder 30 fps, danach neu starten."),
                ("Mac doppelt in der Liste", "Der zweite Eintrag ist der AirPlay-Empfänger von macOS. Abschalten unter "
                    + "Systemeinstellungen › Allgemein › AirDrop & Handoff.")
            ])
        }
    }
}
