# Hotspot Host Onboarding

This Flutter application delivers a two-step onboarding flow for Hotspot Hosts:

1. **Experience Selection** – Hosts choose one or more experience types while adding contextual notes.
2. **Onboarding Question** – Hosts respond to a long-form prompt with text plus optional audio *or* video, complete with in-app recording and playback.

The UI targets the provided design mocks closely, using Riverpod for state orchestration and Dio for networking.

---

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Screens](#screens)
- [State Management & Networking](#state-management--networking)
- [Media Capture & Playback](#media-capture--playback)
- [Running the App](#running-the-app)
- [Brownie Points (Optional Enhancements)](#brownie-points-optional-enhancements)
- [Known Limitations](#known-limitations)

---

## Architecture Overview

- **Flutter** – single codebase targeting mobile and web.
- **Riverpod** – composable, testable state containers (`StateNotifierProvider` & `FutureProvider`).
- **Dio** – HTTP client for the experience catalog.
- **Audio / Video** – `record`, `image_picker`, `audioplayers`, and `video_player` packages.
- **File Storage** – recordings stored in platform temp directories with cleanup handled by the notifiers.

Directory highlights:

```
lib/
 ├─ models/experience.dart                 # Experience DTO
 ├─ services/experience_service.dart       # Dio API wrapper
 ├─ providers/experience_providers.dart    # Riverpod providers & state notifiers
 ├─ screens/experience_selection_screen.dart
 ├─ screens/onboarding_question_screen.dart
 └─ widgets/
      ├─ experience_card.dart
      └─ audio_waveform.dart
```

---

## Screens

### Experience Selection
- Horizontally scrollable experience cards backed by API data.
- Card tap toggles selection with animated overlays and grayscale handling.
- Notes text field with 250 character cap, responsive to keyboard/viewport insets.
- Gradient “Next” button logs the selection state and routes to the next step.
- Custom wavy progress indicator in the header.

### Onboarding Question
- Dark-themed layout with bottom-aligned content and stylized radial gradients.
- Multi-line answer field with 600 character limit.
- Exclusive audio or video response capture:
  - Audio waveform rendered via `CustomPaint`.
  - Video thumbnail with play/pause overlay.
- Playback controls and record/delete flows mirror the provided mocks.
- Animated confirmation dialog appears on successful submission.

---

## State Management & Networking

- `experiencesProvider` (`FutureProvider`) fetches the experience catalog using Dio.
- `ExperienceSelectionNotifier` stores selected IDs and notes.
- `OnboardingAnswerNotifier` manages text answers, recording lifecycle, media paths, waveform samples, playback controllers, and UI flags.
- All navigation/state communication occurs through Riverpod overrides & `ConsumerWidget` rebuilds.

---

## Media Capture & Playback

- Audio recording with `record`, waveform sampling pushed into the notifier.
- Video capture via `image_picker`, with `video_player` for inline review.
- `audioplayers` handles in-app playback and exposes timers/durations back to state.
- Media tiles automatically collapse when assets are deleted, re-enabling the record buttons.

---

## Running the App

```bash
flutter pub get

# Mobile or desktop
flutter run

> The API works as-is on mobile and desktop builds; no extra setup is required in those environments.

# Chrome (development only – see CORS note below)
flutter run -d chrome \
  --web-browser-flag="--disable-web-security" \
  --web-browser-flag="--user-data-dir=${PWD}/tmp/chrome-profile"
```

> The Chrome command disables web security so the browser will accept responses from the staging API that lacks CORS headers. Use it only for local testing.

---

## Brownie Points (Optional Enhancements)

### UI/UX
- Pursued pixel-perfect layout based on the supplied mocks (spacing, typography, colors).
- Responsive handling when the keyboard opens (content reflows without overflow on both screens).

### State Management
- Riverpod (`StateNotifierProvider`, `FutureProvider`) powering both screens.
- Dio wired into the provider tree for API calls.

### Animations
- Experience cards animate according to the mocks, tinting and scaling on selection.
- Question screen “Next” button uses animated layout/width changes as media tiles appear/disappear.

---

## Known Limitations

- **CORS in Chrome** – The staging API does not emit CORS headers, so the web build must rely on the temporary Chrome flag above or a custom proxy. Native mobile/desktop builds are unaffected.
- **External Assets** – The design references image/icon assets that must be provided by the backend; broken URLs fall back to a soft gradient placeholder.

---

Feel free to reach out if you need environment scripts, additional tests, or deeper documentation.
