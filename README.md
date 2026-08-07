# ParkTimer

ParkTimer hilft dir, deine Parkzeit im Blick zu behalten und den Parkplatz wiederzufinden – einfach, lokal und ohne Benutzerkonto.

## Kurzbeschreibung

Starte eine Parkzeit mit einem Tippen, erhalte rechtzeitige Erinnerungen und speichere optional deinen Standort, um später zum Auto zurückzufinden. Alle relevanten Daten bleiben auf dem Gerät.

## Kernfunktionen

- Parkzeit starten (30 Minuten, 1 Stunde, 2 Stunden oder eigene Dauer)
- Countdown mit „Parken bis HH:mm“ und Restzeit
- Lokale Benachrichtigungen 10 Minuten vorher, 5 Minuten vorher und bei Ablauf
- Persistente Parksitzung: laufender Timer läuft nach App-Neustart korrekt weiter
- Standort merken (lokal gespeichert)
- Navigation zum Auto über die installierte Karten-App
- Modernes Material-3-UI

## Unterstützte Plattformen

- Android
- iOS

## Lokale Speicherung

ParkTimer benötigt **kein Benutzerkonto** und keine Cloud-Anmeldung.

Lokal auf dem Gerät gespeichert werden können:

- aktive Parksitzung (u. a. Endzeit)
- gemerkter Parkstandort (Koordinaten und Speicherzeitpunkt)

Weitere Details: siehe [PRIVACY.md](PRIVACY.md).

## Berechtigungen

Für den vollen Funktionsumfang werden benötigt:

- **Standort** – nur nach ausdrücklicher Freigabe, für „Standort merken“
- **Benachrichtigungen** – für lokale Erinnerungen zur Parkzeit
- ggf. **genaue Alarme** (Android) – für pünktliche Timer-Benachrichtigungen

## Entwicklungsstatus

**Version 1.0** – funktionsfähige Erstveröffentlichung.

Aktuelle Versionsnummer in `pubspec.yaml`: `1.0.0+1`

Release-Checkliste: [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)  
Store-Texte: [STORE_LISTING.md](STORE_LISTING.md)

## Entwicklung

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Branding-Assets liegen unter `assets/branding/`. Nach dem Austauschen der finalen Icon-/Splash-Grafiken:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
