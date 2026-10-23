import SwiftUI

/// Content of one help topic.
struct HelpPage: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch topic {
            case .overview: OverviewHelp()
            case .connect: ConnectHelp()
            case .control: ControlHelp()
            case .views: ViewsHelp()
            case .grid: GridHelp()
            case .stage: StageHelp()
            case .floating: FloatingHelp()
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
        HelpSection(title: "Das Prinzip") {
            HelpText("**Ein Steuerfenster für alles.** Dort wählst du die Ansicht, steuerst jedes iPad und stellst Rahmen, "
                     + "Hintergrund und Empfänger ein. Die Ansicht selbst zeigt nur die iPads – dort wirkt nur die Maus: "
                     + "ziehen, Doppelklick, Rechtsklick.")
            OpenControlButton()
        }
        HelpSection(title: "Das kann Totalreflexion") {
            LazyVGrid(columns: columns, spacing: 12) {
                HelpCard(icon: "ipad.and.iphone", title: "Mehrere iPads",
                         text: "Beliebig viele Geräte gleichzeitig, jedes mit eigener Verbindung.")
                HelpCard(icon: "rotate.right", title: "Dreht sich mit",
                         text: "Hoch- und Querformat folgen dem iPad automatisch.")
                HelpCard(icon: "rectangle.3.group", title: "Drei Ansichten",
                         text: "Raster, Bühne mit Hintergrund oder frei schwebende Fenster.")
                HelpCard(icon: "eye", title: "iPads einzeln steuern",
                         text: "Ein- und ausblenden, Vollbild, umbenennen, stummschalten, trennen.")
                HelpCard(icon: "ipad", title: "iPad-Rahmen",
                         text: "Randlos, mit Home-Button, in sechs Farben – oder ein eigenes Mockup-Bild.")
                HelpCard(icon: "photo", title: "Hintergrund",
                         text: "Farbe, Verlauf oder ein Bild, z. B. eine PowerPoint-Folie.")
                HelpCard(icon: "plus.magnifyingglass", title: "Zoom",
                         text: "Details heranholen: Pinch, ⌥ + Scrollrad oder ⌘+ / ⌘−.")
                HelpCard(icon: "speaker.wave.2", title: "Ton",
                         text: "Der Ton der iPads wird mitübertragen, lippensynchron und pro Gerät stummschaltbar.")
            }
        }
        HelpSection(title: "So fängst du an") {
            HelpSteps(steps: [
                "**iPad verbinden:** Kontrollzentrum › Bildschirmsynchronisierung › „Totalreflexion“.",
                "**Ansicht wählen:** Im Steuerfenster oben **Raster**, **Bühne** oder **Frei schwebend** anklicken.",
                "**iPads steuern:** In der Liste im Steuerfenster ein- und ausblenden oder ins Vollbild holen."
            ])
            HelpTopicLink(topic: .connect)
            HelpTopicLink(topic: .views)
        }
        HelpTip("Diese Hilfe findest du jederzeit im Menü **Hilfe** (⌘?) und über das **?** oben im Steuerfenster.")
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
            HelpText("Weitere iPads verbindest du genauso – sie erscheinen alle gleichzeitig und stehen in der Liste "
                     + "im Steuerfenster.")
        }
        HelpSection(title: "Trennen") {
            HelpText("Auf dem iPad: Kontrollzentrum › Bildschirmsynchronisierung › **Synchronisierung stoppen**. "
                     + "Oder im Steuerfenster: **…** neben dem iPad › **Verbindung trennen**.")
        }
        HelpSection(title: "Name in der Liste") {
            HelpText("Auf dem iPad steht dein Mac als „Totalreflexion“ in der Liste. Unter Steuerfenster › **Empfänger** › "
                     + "**Name auf dem iPad** gibst du ihm einen eigenen Namen, z. B. den Raum („Raum 204“). Danach "
                     + "**Neu starten** klicken.")
        }
        HelpSection(title: "Anmeldung: Code oder Passwort") {
            HelpText("Unter Steuerfenster › **Empfänger** › **Anmeldung** legst du fest, wer sich verbinden darf. "
                     + "Danach **Neu starten** klicken.")
            HelpTable(rows: [
                ("Ohne", "Jedes iPad im selben WLAN kann sich verbinden."),
                ("Code auf dem Bildschirm", "Beim ersten Verbinden zeigt der Mac einen 4-stelligen Code groß auf allen "
                    + "Bildschirmen, auch auf dem Beamer. Wer ihn sieht, tippt ihn am iPad ein. Danach erkennt der Mac "
                    + "das iPad wieder. **Alle vergessen** verlangt den Code von allen erneut."),
                ("Passwort", "Das iPad fragt beim Verbinden nach dem Passwort, das du im Steuerfenster festlegst.")
            ])
        }
        HelpTip("Steht dein Mac zweimal in der Liste (z. B. „Totalreflexion“ und „…s iMac“), ist der zweite Eintrag "
                + "der eingebaute AirPlay-Empfänger von macOS. Wähle **Totalreflexion**.")
    }
}

private struct ControlHelp: View {
    var body: some View {
        HelpHeader(topic: .control, intro: "Das Steuerfenster „Totalreflexion“ ist die eine Stelle, an der du alles "
                   + "einstellst. Es öffnet sich beim Start. Geschlossen? **⌘1**, ⌘, oder das Symbol in der Menüleiste "
                   + "holen es zurück.")
        HelpSection(title: "Von oben nach unten") {
            HelpTable(rows: [
                ("Status", "Grüner Punkt = bereit, mit Anzahl der verbundenen iPads. Das **?** öffnet diese Hilfe."),
                ("Ansicht", "**Raster**, **Bühne** oder **Frei schwebend** – immer genau eine ist aktiv. Darunter die "
                    + "Optionen der gewählten Ansicht, z. B. Fenster zeigen, Bildschirm, Vollbild, Anordnen."),
                ("iPads", "Jedes verbundene iPad mit Live-Vorschau (siehe unten)."),
                ("Rahmen", "Rahmen, Farbe, eigenes Rahmenbild und Namen – für alle iPads."),
                ("Hintergrund", "Nur bei der Bühne: Farbe, Verlauf oder Bild."),
                ("Empfänger", "Name auf dem iPad, Anmeldung (ohne, Code oder Passwort) und unter „Qualität & Ton“ "
                    + "Auflösung, Bildrate, Ton und „Bild und Ton synchron“.")
            ])
        }
        HelpSection(title: "Pro iPad in der Liste") {
            HelpTable(rows: [
                ("👁 Auge", "Ein- und ausblenden. Der Ton läuft weiter. Nach neuem Verbinden ist das iPad wieder sichtbar."),
                ("Vollbild", "Nur dieses iPad füllt den Bildschirm – egal welche Ansicht. Mit mehreren Bildschirmen: "
                    + "Knopf **gedrückt halten** und Bildschirm wählen. Esc oder Doppelklick beendet."),
                ("…", "Rahmen und Farbe nur für dieses iPad, drehen (z. B. im Ständer), stumm, umbenennen, trennen.")
            ])
            HelpText("Dasselbe Menü wie „…“ bekommst du auch mit **Rechtsklick** direkt auf ein iPad in der Ansicht.")
        }
    }
}

private struct ViewsHelp: View {
    var body: some View {
        HelpHeader(topic: .views, intro: "Die Ansicht bestimmt, wo die iPads erscheinen. Du wählst sie im Steuerfenster "
                   + "ganz oben. Es ist **immer genau eine Ansicht aktiv** – beim Umschalten schließt sich die vorige.")
        HelpCard(icon: "square.grid.2x2", title: "Raster",
                 text: "Ein normales Fenster. Alle iPads stehen automatisch nebeneinander, so groß wie möglich. "
                     + "Gut zum Zuschauen und Arbeiten.")
        HelpCard(icon: "play.rectangle.on.rectangle", title: "Bühne",
                 text: "Für Beamer oder zweiten Bildschirm: Ein Hintergrund (Farbe, Verlauf oder Bild) füllt den "
                     + "Bildschirm, die iPads verschiebst und vergrößerst du frei mit der Maus.")
        HelpCard(icon: "macwindow.on.rectangle", title: "Frei schwebend",
                 text: "Wie bei AirServer: kein großes Fenster. Jedes iPad schwebt als eigenes, randloses Fenster auf "
                     + "dem Schreibtisch – auf Wunsch über allen anderen Programmen, z. B. über PowerPoint.")
        OpenControlButton()
        HelpSection(title: "Welche Ansicht passt?") {
            HelpTable(rows: [
                ("Nur sehen, was auf den iPads passiert", "**Raster**"),
                ("iPads über den Beamer zeigen", "**Bühne**, dann im Steuerfenster **Bildschirm** › Beamer"),
                ("PowerPoint-Folie hinter den iPads", "**Bühne** mit Hintergrund **Bild** (die Folie vorher in "
                    + "PowerPoint als Bild exportieren) – oder **Frei schwebend** mit „Immer im Vordergrund“ über der "
                    + "laufenden Bildschirmpräsentation"),
                ("iPads frei neben anderen Programmen", "**Frei schwebend**")
            ])
        }
        HelpTopicLink(topic: .grid)
        HelpTopicLink(topic: .stage)
        HelpTopicLink(topic: .floating)
    }
}

private struct GridHelp: View {
    var body: some View {
        HelpHeader(topic: .grid, intro: "Das Raster ordnet alle sichtbaren iPads automatisch in einem Fenster an. Kommt "
                   + "ein iPad dazu oder wird eines gedreht, ordnet sich das Raster neu.")
        HelpSection(title: "Im Steuerfenster") {
            HelpTable(rows: [
                ("Zeigen", "Holt das Raster-Fenster nach vorne oder öffnet es wieder, falls du es geschlossen hast."),
                ("Bildschirm", "Legt das Fenster im Vollbild auf einen anderen Bildschirm (nur bei mehreren Bildschirmen)."),
                ("Vollbild", "Vollbild ein/aus.")
            ])
        }
        HelpSection(title: "Direkt im Raster") {
            HelpTable(rows: [
                ("Doppelklick", "Zeigt nur dieses iPad groß. Nochmal Doppelklick oder **Esc** zeigt wieder alle."),
                ("Pinch / ⌥ + Scrollen", "Zoomen. Bei Zoom mit zwei Fingern verschieben."),
                ("⌘+ / ⌘− / ⌘0", "Vergrößern, verkleinern, Zoom zurücksetzen."),
                ("Rechtsklick", "Menü für dieses iPad.")
            ])
        }
    }
}

private struct StageHelp: View {
    var body: some View {
        HelpHeader(topic: .stage, intro: "Die Bühne ist für Vorführungen: Der Hintergrund füllt den Bildschirm, die iPads "
                   + "liegen darüber und lassen sich frei anordnen. Ideal für Beamer und zweite Bildschirme.")
        HelpSection(title: "Im Steuerfenster") {
            HelpTable(rows: [
                ("Bildschirm", "Legt die Bühne im Vollbild auf einen Bildschirm, z. B. den Beamer."),
                ("Vollbild", "Vollbild ein/aus."),
                ("Anordnung fixieren", "Sperrt die iPads gegen versehentliches Verschieben."),
                ("Automatisch anordnen", "Verteilt alle iPads neu."),
                ("Hintergrund", "Farbe, Verlauf oder Bild, mit Vorschau.")
            ])
        }
        HelpSection(title: "Direkt auf der Bühne") {
            HelpTable(rows: [
                ("Ziehen", "iPad verschieben."),
                ("Griff unten rechts", "Größe ändern (erscheint, wenn die Maus über dem iPad ist)."),
                ("Doppelklick", "**Spotlight:** Das iPad kommt groß in die Mitte, die anderen werden abgedunkelt."),
                ("Esc", "Nacheinander: Spotlight beenden → Zoom zurücksetzen → Vollbild verlassen."),
                ("Rechtsklick", "Menü für dieses iPad.")
            ])
            HelpText("Die Anordnung wird pro iPad gespeichert und gilt auch beim nächsten Verbinden. Der Mauszeiger "
                     + "verschwindet nach ein paar Sekunden ohne Bewegung.")
        }
        HelpTip("**PowerPoint-Folie als Hintergrund:** In PowerPoint die Folie als Bild (PNG oder JPEG) exportieren, "
                + "dann im Steuerfenster unter **Hintergrund der Bühne** › Bild › **Wählen …**.")
        HelpTip("Wirkt ein iPad **abgedunkelt** oder lässt sich **nicht verschieben**? Dann ist ein Spotlight aktiv "
                + "(**Esc**) oder **Anordnung fixieren** eingeschaltet.")
    }
}

private struct FloatingHelp: View {
    var body: some View {
        HelpHeader(topic: .floating, intro: "Jedes iPad bekommt ein eigenes, randloses Fenster und liegt frei auf dem "
                   + "Schreibtisch – wie bei AirServer. Ein großes Fenster gibt es dann nicht.")
        HelpSection(title: "Im Steuerfenster") {
            HelpTable(rows: [
                ("Immer im Vordergrund", "Die iPads bleiben über anderen Programmen sichtbar."),
                ("Automatisch anordnen", "Verteilt alle iPad-Fenster nebeneinander auf dem Bildschirm.")
            ])
            HelpText("Das Steuerfenster kannst du schließen, damit nur noch die iPads zu sehen sind. Totalreflexion "
                     + "merkt sich die Ansicht und startet beim nächsten Mal wieder so.")
        }
        HelpSection(title: "Direkt am iPad") {
            HelpTable(rows: [
                ("Ziehen", "iPad-Fenster verschieben."),
                ("Kante oder Griff", "Größe ändern – an einer Kante ziehen oder am Griff unten rechts."),
                ("Doppelklick", "Vollbild; nochmal Doppelklick oder **Esc** kehrt zurück."),
                ("Rechtsklick", "Menü für dieses iPad.")
            ])
            HelpText("Position und Größe werden pro iPad gespeichert.")
        }
        HelpTip("**Über PowerPoint zeigen:** „Immer im Vordergrund“ einschalten, dann in PowerPoint die "
                + "Bildschirmpräsentation starten. Werden die iPads trotzdem verdeckt, nimm die **Bühne** mit der Folie "
                + "als Hintergrundbild.")
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
            HelpText("**Für alle:** Steuerfenster › Abschnitt **Rahmen**.")
            HelpText("**Pro iPad:** **…** neben dem iPad oder Rechtsklick auf das iPad › Rahmen / Farbe. „Standard“ "
                     + "folgt der Einstellung für alle.")
        }
        HelpSection(title: "Eigenes Rahmenbild") {
            HelpText("Ein PNG, dessen Bildschirmbereich durchsichtig ist (typische iPad-Mockups). Wählen unter "
                     + "Steuerfenster › Rahmen › Eigenes Rahmenbild. Den Bildschirmbereich erkennt Totalreflexion "
                     + "selbst, und das Bild dreht sich mit dem iPad mit.")
        }
    }
}

private struct ShortcutsHelp: View {
    var body: some View {
        HelpHeader(topic: .shortcuts, intro: "Die wichtigsten Tastenkürzel und Mausgesten auf einen Blick.")
        HelpSection(title: "Tastatur") {
            HelpTable(rows: [
                ("⌘1", "Steuerfenster (auch ⌘,)"),
                ("⌘?", "Hilfe"),
                ("⌘+ / ⌘− / ⌘0", "Zoom in Raster und Bühne"),
                ("Esc", "Zurück: Spotlight, Zoom, Vollbild oder Einzelansicht beenden")
            ])
        }
        HelpSection(title: "Maus & Trackpad") {
            HelpTable(rows: [
                ("Doppelklick", "Raster: ein iPad allein · Bühne: Spotlight · Frei schwebend: Vollbild"),
                ("Ziehen", "Bühne und frei schwebend: iPad verschieben"),
                ("Griff unten rechts", "Bühne und frei schwebend: Größe ändern"),
                ("Pinch / ⌥ + Scrollrad", "Zoomen"),
                ("Zwei Finger", "Bei Zoom: Ausschnitt verschieben"),
                ("Rechtsklick", "Menü für dieses iPad")
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
                "Statuspunkt oben im Steuerfenster grün? Sonst Totalreflexion beenden (⌘Q) und neu öffnen.",
                "Systemeinstellungen › Datenschutz & Sicherheit › **Lokales Netzwerk**: Totalreflexion erlauben.",
                "Fragt die Firewall nach eingehenden Verbindungen: **Erlauben**."
            ])
        }
        HelpSection(title: "Weitere Probleme") {
            HelpTable(rows: [
                ("Kein Fenster mehr zu sehen", "**⌘1** oder Menüleisten-Symbol › **Steuerung öffnen**."),
                ("Ansicht ist weg", "Im Steuerfenster bei der Ansicht auf **Zeigen** klicken."),
                ("iPad abgedunkelt", "Spotlight aktiv – auf der Bühne **Esc** drücken."),
                ("iPad lässt sich nicht verschieben", "Spotlight aktiv oder **Anordnung fixieren** eingeschaltet."),
                ("iPad fehlt", "Ausgeblendet? Im Steuerfenster bei iPads **Alle einblenden**."),
                ("„Bildschirm gesperrt“", "Das iPad ist gesperrt – entsperren, dann läuft das Bild weiter."),
                ("Videos aus Apps starten nicht", "Unterstützt wird die Bildschirmsynchronisierung. Das „Streamen“ "
                    + "einzelner Videos (AirPlay-Symbol in YouTube & Co.) nicht."),
                ("Code erscheint nicht", "Anmeldung auf „Code auf dem Bildschirm“ und **Neu starten** geklickt? Ein "
                    + "schon gekoppeltes iPad braucht keinen Code – **Alle vergessen** erzwingt ihn wieder."),
                ("Code oder Passwort wird abgelehnt", "Am iPad noch einmal verbinden; beim Code den aktuell angezeigten "
                    + "nehmen, er ändert sich bei jedem Versuch."),
                ("Kein Ton", "Empfänger › Qualität & Ton › „Ton wiedergeben“; iPad stumm (…)? Lautstärke am iPad?"),
                ("Bild ruckelt", "Empfänger › Qualität & Ton: „Bild und Ton synchron“ einschalten – das gleicht "
                    + "Schwankungen im WLAN aus. Hilft das nicht: kleinere Auflösung oder 30 fps, danach neu starten."),
                ("Ton und Bild versetzt", "Empfänger › Qualität & Ton › „Bild und Ton synchron“ einschalten. Bild und "
                    + "Ton kommen dann etwa 0,2 Sekunden verzögert, aber gemeinsam."),
                ("Bild reagiert zu träge", "Zum Schreiben und Zeichnen „Bild und Ton synchron“ ausschalten: Das Bild "
                    + "erscheint dann sofort, der Ton läuft etwas hinterher."),
                ("Mac doppelt in der Liste", "Der zweite Eintrag ist der AirPlay-Empfänger von macOS. Abschalten unter "
                    + "Systemeinstellungen › Allgemein › AirDrop & Handoff.")
            ])
        }
    }
}
