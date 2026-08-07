# Release-Checkliste – ParkTimer v1.0.0

## Qualitätssicherung

- [ ] `flutter analyze` fehlerfrei
- [ ] `flutter test` vollständig grün
- [ ] Android-Build prüfen (`flutter build apk` / `appbundle`)
- [ ] iOS-Build prüfen (`flutter build ios` / Xcode Archive)

## Branding & Optik

- [ ] App-Icon (finale Grafik, Android + iOS)
- [ ] Splashscreen (Hintergrund `#0D1B2A`, zentriertes Logo)
- [ ] Anzeigename „ParkTimer“ auf Android und iOS

## Kernfunktionen manuell testen

- [ ] Standortberechtigung (anfordern, ablehnen, erneut erlauben)
- [ ] Notification-Berechtigung (Android 13+ / iOS)
- [ ] Timer starten, Countdown, „Parken bis HH:mm“
- [ ] Benachrichtigungen: 10 Min / 5 Min / Ablauf
- [ ] Timer nach App-Neustart korrekt fortsetzen
- [ ] Timer stoppen löscht Sitzung und geplante Benachrichtigungen
- [ ] Standort merken und Infokarte
- [ ] Navigation zum Auto (Karten-App / Fallback)

## Rechtliches & Store

- [ ] Datenschutz (PRIVACY.md) final prüfen und Kontaktplatzhalter ersetzen
- [ ] Store-Screenshots (siehe STORE_LISTING.md)
- [ ] Store-Texte DE/EN (siehe STORE_LISTING.md)
- [ ] Play Store Internal Test
- [ ] App Store TestFlight

## Release

- [ ] Version `1.0.0+1` (oder aktueller Build-Counter) bestätigt
- [ ] Release v1.0.0 taggen / veröffentlichen
- [ ] Store-Rollout starten
