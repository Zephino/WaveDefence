Wave Defence — iOS

Contents after export (on a Mac):
  WaveDefence.ipa

Requirements:
1. macOS with Xcode installed
2. Godot iOS export templates (Editor → Manage Export Templates)
3. Apple Developer team / signing set in Godot:
   Editor → Editor Settings → Export → iOS
   and Project → Export → iOS (bundle id: com.wavedefence.game)

Export:
  Project → Export → iOS
  or on macOS: .\export_builds.ps1 -PhoneOnly

Then install via Xcode / Apple Configurator / TestFlight depending on your signing setup.

Note: iOS apps cannot be fully built on Windows; this folder is the export destination.

Free play on iPhone without an IPA: use the web build in Safari
  https://zephino.github.io/WaveDefence/
(after GitHub Pages is enabled on the repo). Shared leaderboards sync when online.
