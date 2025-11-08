# Hotspot Host Onboarding

Hi there, and thanks for checking out the project. This is the code I put together for the Hotspot Host onboarding flow. It walks new hosts through two screens: first they pick the experiences they want to offer, then they answer a longer-form question with either text, audio, or video. I tried to keep things close to the design mocks while still being comfortable to work with in day-to-day development.

## Why Flutter and Quick Tech Notes

I chose Flutter so I could cover iOS, Android, and the web in one codebase. Riverpod handles state because I lean on its testability and the way it keeps business logic tidy. Networking is done with Dio, and media capture/playback relies on `record`, `image_picker`, `audioplayers`, and `video_player`. Temporary files live in the platform caches and the notifiers clean them up when they are no longer needed.

If you are poking around the codebase, the files worth opening first are:

```
lib/
 ├─ models/experience.dart
 ├─ services/experience_service.dart
 ├─ providers/experience_providers.dart
 ├─ screens/experience_selection_screen.dart
 ├─ screens/onboarding_question_screen.dart
 └─ widgets/
      ├─ experience_card.dart
      └─ audio_waveform.dart
```

## What the UI Does

**Experience selection screen.** The experience cards pull from the API, support multiple selection, and gray out when inactive. I added a notes field for context, capped at 250 characters. There is also a custom progress indicator up top and a “Next” button that responds to state changes.

**Onboarding question screen.** This one uses a darker theme, keeps content anchored near the bottom, and lets the host type up to 600 characters or record audio/video. The audio waveform is drawn with a custom painter, and the video preview has basic play and delete controls. After submission, there is a simple confirmation dialog.

## How Data and State Flow

- `experiencesProvider` (a `FutureProvider`) fetches the catalog with Dio.
- `ExperienceSelectionNotifier` tracks selected IDs and the notes field.
- `OnboardingAnswerNotifier` owns the text answer, audio/video lifecycle, paths to temp files, waveform samples, and playback controllers.
- Navigation and state sync happen through Riverpod overrides with `ConsumerWidget` rebuilds.

## Media Capture Details

Audio recording uses the `record` package and streams samples back into the notifier for the waveform. Video capture comes from `image_picker`, and `video_player` handles inline playback. Both media tiles collapse automatically when you delete a recording so the record buttons re-enable without the user needing to refresh anything.

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

The Chrome command disables web security so the staging API (which is missing CORS headers) can be reached while you are developing. Only use it for local testing.

## Extra Credit Items

- Pixel-perfect layout work to stay true to the mocks, especially spacing and typography.
- Responsive handling when the keyboard opens on mobile so fields stay visible.
- Riverpod is used consistently (`StateNotifierProvider` plus `FutureProvider`), and Dio is wired through providers rather than sitting in global singletons.
- Experience cards animate when toggled, and the question screen’s Next button adjusts as media tiles appear or disappear.

## Known Limitations

- CORS in Chrome: the staging API does not emit CORS headers, so you need the temporary Chrome flags above or a proxy for web testing. Mobile and desktop builds are fine.
- External assets: some design references lean on backend-hosted assets; if they are missing, the UI falls back to a soft gradient placeholder.

If you spin this up or want to extend it, feel free to reach out. Happy to provide scripts, add tests, or hop on a call to walk through any of the decisions.
