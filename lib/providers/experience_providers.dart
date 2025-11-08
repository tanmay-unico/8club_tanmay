import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/experience.dart';
import '../services/experience_service.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
});

final experienceServiceProvider = Provider<ExperienceService>((ref) {
  return ExperienceService(ref.read(dioProvider));
});

final experiencesProvider = FutureProvider<List<Experience>>((ref) async {
  try {
    final service = ref.read(experienceServiceProvider);
    return await service.fetchExperiences();
  } catch (error, stackTrace) {
    log('Failed to load experiences', error: error, stackTrace: stackTrace);
    rethrow;
  }
});

class ExperienceSelectionState {
  const ExperienceSelectionState({
    this.selectedExperienceIds = const <int>{},
    this.notes = '',
  });

  final Set<int> selectedExperienceIds;
  final String notes;

  ExperienceSelectionState copyWith({
    Set<int>? selectedExperienceIds,
    String? notes,
  }) {
    return ExperienceSelectionState(
      selectedExperienceIds:
          selectedExperienceIds ?? this.selectedExperienceIds,
      notes: notes ?? this.notes,
    );
  }
}

class ExperienceSelectionNotifier
    extends StateNotifier<ExperienceSelectionState> {
  ExperienceSelectionNotifier() : super(const ExperienceSelectionState());

  void toggleExperience(int id) {
    final isSelected = state.selectedExperienceIds.contains(id);
    final updatedIds = <int>{...state.selectedExperienceIds};
    if (isSelected) {
      updatedIds.remove(id);
    } else {
      updatedIds.add(id);
    }
    state = state.copyWith(selectedExperienceIds: updatedIds);
  }

  void updateNotes(String value) {
    state = state.copyWith(notes: value);
  }
}

final experienceSelectionProvider = StateNotifierProvider<
    ExperienceSelectionNotifier, ExperienceSelectionState>((ref) {
  return ExperienceSelectionNotifier();
});

const _unset = Object();

class OnboardingAnswerState {
  const OnboardingAnswerState({
    this.answer = '',
    this.audioPath,
    this.videoPath,
    this.isRecordingAudio = false,
    this.waveform = const <double>[],
    this.recordingDuration,
    this.audioDuration,
    this.videoDuration,
  });

  final String answer;
  final String? audioPath;
  final String? videoPath;
  final bool isRecordingAudio;
  final List<double> waveform;
  final Duration? recordingDuration;
  final Duration? audioDuration;
  final Duration? videoDuration;

  OnboardingAnswerState copyWith({
    String? answer,
    Object? audioPath = _unset,
    Object? videoPath = _unset,
    bool? isRecordingAudio,
    List<double>? waveform,
    Object? recordingDuration = _unset,
    Object? audioDuration = _unset,
    Object? videoDuration = _unset,
  }) {
    return OnboardingAnswerState(
      answer: answer ?? this.answer,
      audioPath: identical(audioPath, _unset)
          ? this.audioPath
          : audioPath as String?,
      videoPath: identical(videoPath, _unset)
          ? this.videoPath
          : videoPath as String?,
      isRecordingAudio: isRecordingAudio ?? this.isRecordingAudio,
      waveform: waveform ?? this.waveform,
      recordingDuration: identical(recordingDuration, _unset)
          ? this.recordingDuration
          : recordingDuration as Duration?,
      audioDuration: identical(audioDuration, _unset)
          ? this.audioDuration
          : audioDuration as Duration?,
      videoDuration: identical(videoDuration, _unset)
          ? this.videoDuration
          : videoDuration as Duration?,
    );
  }
}

class OnboardingAnswerNotifier extends StateNotifier<OnboardingAnswerState> {
  OnboardingAnswerNotifier() : super(const OnboardingAnswerState());

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _pendingRecordingPath;
  bool _recorderActive = false;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;

  void updateAnswer(String value) {
    if (!mounted) return;
    state = state.copyWith(answer: value);
  }

  Future<void> startAudioRecording() async {
    if (!mounted) return;
    if (state.isRecordingAudio) {
      return;
    }
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw MicrophonePermissionDenied();
    }

    final directory = await _recordingDirectory();
    final filePath =
        '${directory.path}/hotspot_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    if (state.audioPath != null) {
      await deleteAudioRecording();
    }

    await _audioRecorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: filePath,
    );

    _recorderActive = true;
    _pendingRecordingPath = filePath;
    if (mounted) {
      state = state.copyWith(
        isRecordingAudio: true,
        waveform: <double>[],
        audioPath: null,
        audioDuration: null,
        recordingDuration: Duration.zero,
      );
    }

    _recordingStartedAt = DateTime.now();
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final started = _recordingStartedAt;
      if (started == null) return;
      final duration = DateTime.now().difference(started);
      state = state.copyWith(recordingDuration: duration);
    });

    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((event) {
      if (!mounted) return;
      final samples = List<double>.from(state.waveform);
      samples.add(event.current);
      if (samples.length > 40) {
        samples.removeAt(0);
      }
      state = state.copyWith(waveform: samples);
    });
  }

  Future<void> stopAudioRecording() async {
    if (!mounted) return;
    if (!state.isRecordingAudio || !_recorderActive) {
      return;
    }

    final recordedPath = await _audioRecorder.stop();
    _recorderActive = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartedAt = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    if (recordedPath == null) {
      if (!mounted) return;
      state = state.copyWith(
        isRecordingAudio: false,
        waveform: <double>[],
        recordingDuration: null,
      );
      return;
    }

    final finalDuration = state.recordingDuration ?? Duration.zero;

    if (!mounted) return;
    state = state.copyWith(
      isRecordingAudio: false,
      audioPath: recordedPath,
      waveform: <double>[],
      recordingDuration: null,
      audioDuration: finalDuration == Duration.zero ? null : finalDuration,
    );
    _pendingRecordingPath = null;
  }

  Future<void> cancelAudioRecording() async {
    if (!mounted) return;
    if (!state.isRecordingAudio || !_recorderActive) {
      return;
    }
    try {
      await _audioRecorder.cancel();
    } catch (_) {
      // no-op: cancel can throw if recording was never started
    }
    _recorderActive = false;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartedAt = null;

    final pendingPath = _pendingRecordingPath;
    if (!kIsWeb && pendingPath != null) {
      final file = File(pendingPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (!mounted) return;
    state = state.copyWith(
      isRecordingAudio: false,
      waveform: <double>[],
      audioPath: null,
      recordingDuration: null,
      audioDuration: null,
    );
    _pendingRecordingPath = null;
  }

  Future<void> deleteAudioRecording() async {
    if (!mounted) return;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recorderActive = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartedAt = null;

    final audioPath = state.audioPath;
    if (!kIsWeb && audioPath != null) {
      try {
        final file = File(audioPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // ignore file system failures; state reset will continue
      }
    }
    _pendingRecordingPath = null;
    if (!mounted) return;
    state = state.copyWith(
      audioPath: null,
      isRecordingAudio: false,
      waveform: <double>[],
      recordingDuration: null,
      audioDuration: null,
    );
  }

  Future<void> updateVideoPath(String? path) async {
    if (!mounted) return;
    state = state.copyWith(videoPath: path, videoDuration: null);
  }

  void setVideoDuration(Duration? duration) {
    if (!mounted) return;
    state = state.copyWith(videoDuration: duration);
  }

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartedAt = null;
    if (_recorderActive) {
      unawaited(
        _audioRecorder.dispose().catchError((_) {}),
      );
    }
    super.dispose();
  }

  Future<Directory> _recordingDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Recording is not supported on the web');
    }
    final directory = await getTemporaryDirectory();
    final folder = Directory('${directory.path}/hotspot_recordings');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }
}

final onboardingAnswerProvider = StateNotifierProvider.autoDispose<
    OnboardingAnswerNotifier, OnboardingAnswerState>((ref) {
  final notifier = OnboardingAnswerNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});

class MicrophonePermissionDenied implements Exception {}

