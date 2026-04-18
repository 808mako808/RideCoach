# Ride Coach Beta 0.0.1.14

Ride Coach is a macOS menu bar app that connects to Strava, checks for new rides on an hourly, daily, or weekly cadence, and sends the latest ride to a local Ollama model for coaching feedback.

Ride Coach Beta uses local AI analysis from Ollama. AI output may be incomplete, inaccurate, or overconfident, and it may miss important training, medical, weather, equipment, traffic, or safety context. Treat the analysis as a helpful reflection aid, not professional coaching, medical advice, or a substitute for your own judgment.

## Run

## Install From GitHub

Ride Coach Beta is currently ad-hoc signed, but it is not notarized by Apple. After downloading the DMG, macOS Gatekeeper may say it cannot verify that the app is free from malware.

To open it:

1. Drag `Ride Coach Beta.app` to Applications.
2. Control-click or right-click the app in Applications.
3. Choose Open.
4. Click Open again if macOS asks for confirmation.

If macOS still blocks it and you trust this GitHub build, remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Ride Coach Beta.app"
open "/Applications/Ride Coach Beta.app"
```

For broader public distribution, Ride Coach Beta should eventually be signed with an Apple Developer ID certificate and notarized.

## Development

Build and launch the app bundle for notification support:

```sh
swift Scripts/BuildAppBundle.swift
open ".build/Ride Coach Beta.app"
```

Build a GitHub release DMG:

```sh
swift Scripts/BuildDMG.swift
```

You can still run the raw executable while developing, but macOS notifications require the app bundle:

```sh
swift run RideCoach
```

Keep Ollama running locally before checking a ride. You can install the selected model from Ride Coach Settings, or use the terminal:

```sh
ollama serve
ollama pull llama3.2
```

## Strava Setup

1. Create an app at <https://www.strava.com/settings/api>.
2. Set the app callback domain to `localhost`.
3. Upload `Assets/RideCoach-Strava-Icon.png` as the app icon.
4. In Ride Coach settings, enter your Strava client ID and client secret.
5. Click Connect Strava.

Ride Coach listens on `http://localhost:8754/callback` while you connect. It requests `read` and `activity:read_all` so it can read your ride history.

## Ride Analysis

Each check fetches up to three months of Strava activities and uses the rides in that window as comparison context for Ollama. Ride Coach then analyzes every unprocessed ride since the last successful analysis, oldest to newest, and stores those ride IDs so the same rides are not analyzed again.

If several rides are found, the menu shows one combined analysis with a section for each new ride.

## Configuration

The menu bar Settings window lets you configure:

- Strava client ID and client secret
- Ollama base URL, defaulting to `http://localhost:11434/api`
- Ollama setup helpers: check Ollama, open the Ollama download page, and install the selected model
- Ollama model:
  - `llama3.2:1b` - fastest; good quick summaries
  - `qwen2.5:1.5b` - fast; good structured notes
  - `qwen2.5:3b` - balanced; better detail
  - `llama3.2:3b` - stronger; slower analysis
- Automatic check frequency: hourly, daily, or weekly
- Daily check time and weekly check day/time
- Notification toggle for newly analyzed rides

The app stores tokens and preferences in user defaults for this prototype.
