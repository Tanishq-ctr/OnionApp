# Available Claude Skills/Plugins — OnionApp Development

This document lists the Claude Code plugins found relevant to building the OnionApp Flutter mobile app, discovered via a catalog search on 2026-09-27. None are installed by default — install from the suggestion card when ready, or via the plugin manager.

---

## Directly relevant (Flutter/Dart/Mobile)

### 1. Dart and Flutter (Official)
- **What it is:** Official Claude plugin for Dart and Flutter
- **What it installs:** Flutter/Dart Skills + the Dart MCP server
- **Use case:** Building natively compiled apps for mobile, web, desktop, and embedded devices from a single codebase
- **Recommended priority:** ⭐ Start here — most practical general-purpose foundation for OnionApp given the timeline; official support usually means better reliability

### 2. Very Good AI Flutter Plugin
- **What it is:** Best-practice skills for Flutter and Dart development
- **Covers:** accessibility, animations, BLoC (state management), testing, theming, navigation, security, internationalization, layered architecture, license compliance, UI packages, project creation, SDK/lint upgrades
- **Extra feature:** an autonomous quality-gate loop that drives `analyze`, `format`, `test`, and coverage to green — plus automated `dart analyze`/`format` hooks
- **Use case:** Useful once the app has a working core and you want to clean up architecture/quality before submission

### 3. flutter-skills
- **What it is:** Comprehensive Flutter development skills for Claude Code
- **Covers:** Riverpod 3.0 (state management), Freezed (code generation for immutable models), go_router (navigation), Flame game engine, feature-first architecture
- **Use case:** Helpful if OnionApp's screens (camera → inference → results → report) grow complex enough to benefit from a structured state-management pattern

---

## Potentially relevant (situational)

### 4. Ansight
- **What it is:** Let your agent build, test, and prove your app works
- **Covers:** 27 Ansight CLI skills, a verifier subagent, a session-start readiness check for mobile apps
- **Use case:** Could help validate the app actually builds/runs correctly before a hackathon demo — worth a look if time allows for a pre-submission check

### 5. Scandit SDK
- **What it is:** AI agent skills for integrating the Scandit Data Capture SDK
- **Covers:** product selection, documentation, implementation guides for barcode scanning, ID capture, smart label capture
- **Use case:** Not needed for OnionApp's core camera/TFLite flow, but could be relevant *if* the app later wants to scan a barcode/label alongside onion images (e.g., linking a scan to a specific batch/procurement center ID)

### 6. Bugsee
- **What it is:** Bugsee plugin for Claude Code — crash/bug report debugging, build size/dependency vulnerability inspection, symbol uploads, via Bugsee MCP server
- **Use case:** Only relevant if you set up Bugsee crash reporting for the app; not needed for a hackathon build

### 7. Auth0
- **What it is:** Essential Auth0 skills — quickstarts, migration from other providers, MFA
- **Use case:** Only relevant if OnionApp needs user login/authentication (e.g., per-procurement-center accounts) — not currently part of the planned scope

---

## Not relevant to OnionApp (found in search, excluded)
- **Flint** — AI website builder (not a mobile app tool)
- **liste** — CLI roadmap/task tracker
- **lite-bb** — Bitbucket CLI operations

---

## Recommendation for current stage
Given the hackathon timeline and that `inference.dart` (loading both `.tflite` models) is the next task, install **"Dart and Flutter"** (Official) first. Revisit **Very Good AI Flutter Plugin** or **flutter-skills** later if there's time to polish architecture/state management before submission.
