# Ember – Benutzerhandbuch

**Ember** ist ein Ein-Knopf-Mastering-Effekt mit warmem Charakter (Audio Unit v3) für macOS und iOS/iPadOS.
Ein einziger Regler – **Amount** – steuert eine komplette Mastering-Kette: Klangfarbe, Kompression,
Sättigung, Stereobreite und Limiter. Der Rest der Oberfläche dient der Feinkontrolle.

---

## Inhalt

1. [Installation](#1-installation)
2. [Die Oberfläche](#2-die-oberfläche)
3. [Was Amount macht](#3-was-amount-macht)
4. [Match – Lautheitsabgleich](#4-match--lautheitsabgleich)
5. [Ceiling und True Peak](#5-ceiling-und-true-peak)
6. [Meter](#6-meter)
7. [Presets](#7-presets)
8. [Workflow: ein Master in fünf Schritten](#8-workflow-ein-master-in-fünf-schritten)
9. [Technische Daten](#9-technische-daten)
10. [Fehlerbehebung](#10-fehlerbehebung)

---

## 1. Installation

**macOS:** `Ember-<Version>.pkg` doppelklicken und dem Installer folgen. Ember.app wird nach
*Programme* kopiert und das Plug-in automatisch registriert. Danach den Host (Logic Pro, GarageBand,
Ableton Live, Reaper …) neu starten. Ember erscheint unter **Audio Units → Gerov → Ember**.

> Taucht Ember nicht auf, einmal **Ember** aus dem Programme-Ordner öffnen – das zwingt macOS,
> das Plug-in zu registrieren.

**iOS/iPadOS:** App installieren und einmal öffnen. In AUM, Logic Pro für iPad, GarageBand usw.
findest du Ember unter den Audio-Unit-Effekten.

**Deinstallation (macOS):** Ember.app aus *Programme* in den Papierkorb ziehen.

---

## 2. Die Oberfläche

```
 EMBER                                   [TRUE PEAK] [MATCH]

   (INPUT)            ( AMOUNT )             (OUTPUT)

 ┌──────────────────────────────────────────────────────────┐
 │ GLUE  ▬▬▬▬▬▬▬▬▬▬▬▬▬  -1.2      (CEILING)       ▌▌ OUT     │
 │ LIMIT ▬▬▬▬▬▬▬▬▬▬▬▬▬  -2.4                                  │
 └──────────────────────────────────────────────────────────┘
```

| Element | Bereich | Standard | Funktion |
|---|---|---|---|
| **Amount** | 0–100 % | 45 % | Der Haupt-Regler. Steuert alle Stufen gleichzeitig (siehe [Abschnitt 3](#3-was-amount-macht)). |
| **Input** | −12 … +12 dB | 0 dB | Pegel *in* die Kette. Mehr Input = mehr Kompression, Sättigung und Limiting. |
| **Output** | −12 … +12 dB | 0 dB | Pegel ganz am Ende, nach dem Limiter. |
| **Ceiling** | −6 … 0 dB | −0,3 dB | Maximaler Ausgangspegel des Limiters (in dBTP, wenn True Peak an ist). |
| **True Peak** | an/aus | an | Begrenzt auch Spitzen *zwischen* den Samples (siehe [Abschnitt 5](#5-ceiling-und-true-peak)). |
| **Match** | an/aus | aus | Lautheitsabgleich zum fairen Vergleichen (siehe [Abschnitt 4](#4-match--lautheitsabgleich)). |

**Bedienung der Regler**

- **Ziehen** nach oben oder rechts erhöht den Wert, nach unten oder links verringert ihn.
- **Doppelklick** (bzw. Doppeltipp) setzt den Regler auf den Standardwert zurück.
- Alle Parameter sind im Host automatisierbar; Ziehen schreibt „Touch“-Automation.
- Mit VoiceOver lassen sich alle Regler per Wischgeste in 2-%-Schritten einstellen.

**Bypass** übernimmt der Host. Ember blendet dabei weich über (15 ms) und gibt das trockene Signal
zeitlich exakt ausgerichtet aus – es gibt keinen Versatz beim Umschalten.

---

## 3. Was Amount macht

Amount ist kein einfacher Wet/Dry-Regler. Jede Stufe der Kette folgt einer eigenen Kurve. Bei
**0 %** ist Ember klanglich neutral – nur der Limiter fängt Spitzen über dem Ceiling ab. Bei
**100 %** arbeiten alle Stufen mit voller Intensität.

Signalfluss:

```
Input → Klang-EQ → Glue-Kompressor → Sättigung (4× Oversampling) → Stereobreite → Limiter → Match → Output
```

| Stufe | Bei 0 % | Bei 100 % | Wirkung |
|---|---|---|---|
| **Tiefen** (Shelf 105 Hz) | 0 dB | +3 dB | Gewicht und Fundament |
| **Mitten-Entschlackung** (320 Hz) | 0 dB | −1,5 dB | Weniger Matsch in den unteren Mitten |
| **Air** (Shelf 10 kHz) | 0 dB | +1,5 dB | Dezenter Glanz |
| **Glue-Kompressor** | 1:1 (aus) | 2,5:1 ab −20 dB | Verdichtet den Mix sanft (Soft Knee 8 dB, Attack 12 ms, Release 180 ms) |
| **Sättigung** | aus | +9 dB Drive, voll wet | Warme, leicht asymmetrische Röhren-Charakteristik – geradzahlige Obertöne |
| **Stereobreite** | neutral | Bass < 150 Hz −40 % Seite, Höhen +25 % Seite | Tiefer, mono-stabiler Bass; breitere Höhen |
| **Push in den Limiter** | 0 dB | +8 dB | Lautheit |

Die Sättigung erreicht ihren vollen Wet-Anteil schon bei 50 %. Darüber steigt nur noch der Drive.

**Faustregeln**

- **20–35 %** – leichte Politur, kaum hörbare Kompression
- **40–60 %** – deutlich wärmer und dichter, typischer Master
- **70–100 %** – laut, gesättigt, aggressiv; Gain-Reduction-Meter im Blick behalten

---

## 4. Match – Lautheitsabgleich

### Das Problem

Lauter klingt fast immer „besser“. Dreht man Amount auf, wird das Signal deutlich lauter (bis zu
+8 dB Push plus Kompression und Sättigung). Ein direkter Vergleich mit dem Original ist dann
unfair: Man hört vor allem den Pegelunterschied und nicht, ob Ember den Klang tatsächlich verbessert.

### Was Match macht

Ist **Match** eingeschaltet, senkt Ember den Ausgang automatisch so weit ab, dass das bearbeitete
Signal **ungefähr so laut ist wie das Eingangssignal**. Du hörst dann nur noch die
*klangliche* Veränderung – Wärme, Dichte, Breite – und nicht die Lautheit.

### Wie es genau funktioniert

1. Ember misst laufend die **mittlere Energie (RMS)** des Signals an zwei Stellen:
   - am **Eingang**, *vor* dem Input-Regler
   - am **Ausgang des Limiters**, *vor* dem Output-Regler
2. Beide Messungen sind über etwa **1,2 Sekunden** geglättet, sodass einzelne Transienten den
   Abgleich nicht beeinflussen.
3. Aus dem Verhältnis ergibt sich eine Korrektur, die über rund **300 ms** weich nachgeführt wird.
   Es gibt keine Sprünge und kein Pumpen.
4. Die Korrektur wird **nach dem Limiter** angewendet. Der Output-Regler wirkt danach wie gewohnt.

### Wichtige Details

- **Match senkt nur ab, es hebt nie an** (Bereich 0 bis −24 dB). Damit bleibt das Ceiling eine
  harte Grenze. Ist das bearbeitete Signal leiser als das Original (z. B. bei Input −12 dB), tut
  Match nichts.
- **Match neutralisiert auch den Input-Regler.** Weil am Eingang *vor* dem Input-Regler gemessen
  wird, bleibt die Lautheit bei aktivem Match gleich, egal wie viel Input du gibst. Du hörst nur,
  wie sich der härtere Antrieb auf Kompression und Sättigung *anhört*.
- **Gemessen wird RMS, nicht LUFS.** Für den Hörvergleich reicht das völlig. Für eine verbindliche
  Lautheitsmessung (z. B. −14 LUFS für Streaming) brauchst du ein LUFS-Meter im Host.
- Nach dem Einschalten braucht Match **1–2 Sekunden Musik**, bis der Abgleich eingeschwungen ist.
- In Pausen und bei Stille wird die zuletzt gemessene Korrektur gehalten.

### So benutzt du Match

1. **Match einschalten.**
2. Amount (und ggf. Input) einstellen und dabei mit dem **Bypass des Hosts** vergleichen. Beide
   Varianten sind jetzt etwa gleich laut. Entscheide nach Klang: Ist es wirklich besser?
3. **Match vor dem Export ausschalten!** Sonst wird der Master nicht lauter als das Original, und
   der Lautheitsgewinn von Ember geht verloren.

> **Merksatz:** Match ist ein Werkzeug zum *Zuhören*, nicht zum *Exportieren*.

---

## 5. Ceiling und True Peak

**Ceiling** legt fest, wie laut der Ausgang maximal werden darf. Der Limiter arbeitet mit 1,5 ms
Lookahead: Er erkennt Spitzen, bevor sie ankommen, und regelt ohne hörbares Klicken.

### True Peak (Standard: an)

Digitale Samples sind nur Messpunkte. Die tatsächliche Wellenform, die ein D/A-Wandler oder ein
MP3/AAC-Decoder rekonstruiert, kann **zwischen** zwei Samples höher liegen – im Extremfall um
mehr als 3 dB. Solche *Inter-Sample-Peaks* verursachen Verzerrungen bei der Wiedergabe und beim
Encoding für Streaming-Dienste.

- **True Peak an:** Ember rekonstruiert die Wellenform intern mit 8-fachem Oversampling und
  begrenzt auch die Spitzen zwischen den Samples. Die Ceiling-Anzeige wechselt auf **dBTP**.
  Ember zielt dabei mit einer festen **Sicherheitsreserve von 0,15 dB** unter das Ceiling. Der
  tatsächliche True Peak liegt deshalb typischerweise 0,06–0,15 dB unter dem eingestellten Wert.
  Dafür wird das Ceiling auch bei extrem hellem Material nicht überschritten.
- **True Peak aus:** Der Limiter begrenzt nur die Sample-Werte, exakt auf das Ceiling und ohne
  Reserve. Das ist minimal lauter, aber Inter-Sample-Peaks können durchkommen.

**Empfehlungen**

| Ziel | Ceiling | True Peak |
|---|---|---|
| Streaming (Spotify, Apple Music, YouTube …) | −1,0 dB | an |
| CD / WAV-Master | −0,3 dB | an |
| Weiterverarbeitung (Stems, Mastering-Engineer) | −1,0 dB oder tiefer | an |

Die Latenz ist in beiden Modi gleich. Umschalten verschiebt im Host nichts.

---

## 6. Meter

| Meter | Zeigt | Skala |
|---|---|---|
| **GLUE** | Gain Reduction des Glue-Kompressors | 0–12 dB |
| **LIMIT** | Gain Reduction des Limiters | 0–12 dB |
| **OUT** | Ausgangspegel links/rechts (Sample-Peak) | −48 … 0 dBFS |

Der Funkenflug hinter dem Amount-Regler ist eine Visualisierung: Die Menge der Funken folgt Amount,
die Helligkeit dem Ausgangspegel.

**Richtwerte:**

- **GLUE** um 1–3 dB: gesunde Verdichtung. Dauerhaft deutlich mehr klingt schnell flach.
- **LIMIT** kurzzeitig 2–4 dB auf Spitzen: unauffällig. Liegt LIMIT dauerhaft über 6 dB, wird es
  hörbar. Dann Input oder Amount zurücknehmen.
- Das OUT-Meter zeigt Sample-Peaks. Für die True-Peak- und LUFS-Kontrolle das Meter des Hosts
  verwenden.

---

## 7. Presets

| Preset | Amount | Charakter |
|---|---|---|
| **Glow** | 20 % | Dezente Politur |
| **Warm** | 45 % | Standard – warm und dicht |
| **Hot** | 70 % | Laut und kräftig gesättigt |
| **Blaze** | 95 % | Maximal – für aggressive Genres |

Factory-Presets setzen alle anderen Parameter auf ihre Standardwerte zurück (Input/Output 0 dB,
Ceiling −0,3 dB, True Peak an, Match aus). Eigene Presets speicherst du über den Preset-Dialog
deines Hosts.

---

## 8. Workflow: ein Master in fünf Schritten

1. **Ember als letztes Plug-in** auf den Master-Bus setzen. Der Mix sollte Headroom haben
   (Spitzen bei etwa −6 dBFS).
2. **Match einschalten.** Amount langsam aufdrehen und per Bypass vergleichen, bis der Klang am
   besten passt.
3. **Input** justieren: Mehr Input gibt mehr Dichte und Biss. GLUE und LIMIT dabei im Blick
   behalten.
4. **Ceiling** passend zum Ziel setzen (siehe [Abschnitt 5](#5-ceiling-und-true-peak)), True Peak
   anlassen.
5. **Match ausschalten**, mit einem LUFS-Meter die Ziellautheit prüfen und exportieren.

---

## 9. Technische Daten

| | |
|---|---|
| Format | Audio Unit v3 (Effekt), macOS 14+ (Apple Silicon und Intel), iOS/iPadOS 17+ |
| Kanäle | Mono → Mono, Stereo → Stereo |
| Abtastraten | alle gängigen (getestet von 11,025 bis 192 kHz) |
| Latenz | 127 Samples bei 48 kHz (≈ 2,6 ms), wird dem Host gemeldet und automatisch ausgeglichen |
| Oversampling | 4× für die Sättigung, 8× für die True-Peak-Erkennung |
| CPU | ca. 3 % eines Apple-Silicon-Kerns bei 48 kHz Stereo |
| AU-Kennung | `aufx` / `Embr` / `Grov` – „Gerov: Ember“ |

---

## 10. Fehlerbehebung

**Ember erscheint nicht im Host.**
Ember.app einmal öffnen und den Host neu starten. In Logic Pro zusätzlich im Plug-in-Manager
„Zurücksetzen & erneut scannen“ wählen.

**Mit Match ist es nicht lauter geworden.**
Das ist die Aufgabe von Match (siehe [Abschnitt 4](#4-match--lautheitsabgleich)). Für den Export
Match ausschalten.

**Der Master verzerrt hörbar.**
Amount oder Input zurücknehmen. Bleibt LIMIT dauerhaft über 6 dB, bekommt der Limiter zu viel
Pegel.

**Der Bass wirkt schmaler.**
Das ist beabsichtigt: Ember macht Frequenzen unter 150 Hz mit steigendem Amount mono-stabiler.
Das sorgt für einen festeren Bass auf Club-Anlagen und Mono-Lautsprechern.

**Das Messgerät im Host zeigt einen True Peak knapp unter dem Ceiling.**
Das ist die eingebaute Sicherheitsreserve von 0,15 dB (siehe [Abschnitt 5](#5-ceiling-und-true-peak)).
