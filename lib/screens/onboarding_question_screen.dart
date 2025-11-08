import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

import '../providers/experience_providers.dart';
import '../widgets/audio_waveform.dart';

const List<Color> _ctaGradientColors = [
  Color.fromRGBO(34, 34, 34, 0.4),
  Color.fromRGBO(153, 153, 153, 0.4),
  Color.fromRGBO(34, 34, 34, 0.4),
];

const List<Color> _ctaGradientDisabledColors = [
  Color.fromRGBO(40, 40, 40, 0.25),
  Color.fromRGBO(90, 90, 90, 0.25),
  Color.fromRGBO(40, 40, 40, 0.25),
];

const List<double> _ctaGradientStops = [0.0, 0.5, 1.0];

RadialGradient _ctaRadialGradient({
  bool enabled = true,
  Alignment center = const Alignment(-1.0, -0.85),
}) {
  return RadialGradient(
    center: center,
    radius: 1.3,
    colors: enabled ? _ctaGradientColors : _ctaGradientDisabledColors,
    stops: _ctaGradientStops,
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class OnboardingQuestionScreen extends ConsumerStatefulWidget {
  const OnboardingQuestionScreen({super.key});

  @override
  ConsumerState<OnboardingQuestionScreen> createState() =>
      _OnboardingQuestionScreenState();
}

class _OnboardingQuestionScreenState
    extends ConsumerState<OnboardingQuestionScreen> {
  late final TextEditingController _answerController;
  final _imagePicker = ImagePicker();
  late final AudioPlayer _audioPlayer;
  StreamSubscription<void>? _audioCompleteSub;
  bool _isAudioPlaying = false;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  bool _isVideoPlaying = false;
  String? _lastAudioPath;
  String? _lastVideoPath;

  static const _backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0E0E10),
      Color(0xFF121216),
      Color(0xFF16161B),
    ],
  );


  @override
  void initState() {
    super.initState();
    final answer = ref.read(onboardingAnswerProvider).answer;
    _answerController = TextEditingController(text: answer);
    _answerController.addListener(_handleAnswerChanged);

    _audioPlayer = AudioPlayer();
    _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isAudioPlaying = false);
      }
    });

    final initialState = ref.read(onboardingAnswerProvider);
    _lastAudioPath = initialState.audioPath;
    _lastVideoPath = initialState.videoPath;
    _initializeVideoController(initialState.videoPath);
  }

  @override
  void dispose() {
    _answerController.removeListener(_handleAnswerChanged);
    _answerController.dispose();
    _audioCompleteSub?.cancel();
    _audioPlayer.dispose();
    _stopAudioPlayback();
    _disposeVideoController();
    super.dispose();
  }

  void _handleAnswerChanged() {
    ref
        .read(onboardingAnswerProvider.notifier)
        .updateAnswer(_answerController.text);
  }

  Future<void> _startAudioRecording() async {
    final current = ref.read(onboardingAnswerProvider);
    if (current.videoPath != null) {
      _showSnackBar(
        'Please remove the video response before recording audio.',
      );
      return;
    }
    final notifier = ref.read(onboardingAnswerProvider.notifier);
    try {
      await notifier.startAudioRecording();
    } on MicrophonePermissionDenied {
      _showSnackBar(
        'Microphone permission was denied. Please enable it in settings.',
      );
    } on UnsupportedError {
      _showSnackBar('Audio recording is not supported on this platform.');
    } catch (error) {
      _showSnackBar('Failed to start recording: $error');
    }
  }

  Future<void> _stopAudioRecording() async {
    final notifier = ref.read(onboardingAnswerProvider.notifier);
    try {
      await notifier.stopAudioRecording();
    } catch (error) {
      _showSnackBar('Unable to stop the recording: $error');
    }
  }

  Future<void> _cancelAudioRecording() async {
    final notifier = ref.read(onboardingAnswerProvider.notifier);
    try {
      await notifier.cancelAudioRecording();
    } catch (error) {
      _showSnackBar('Unable to cancel the recording: $error');
    }
  }

  Future<void> _deleteAudio() async {
    await ref.read(onboardingAnswerProvider.notifier).deleteAudioRecording();
    await _stopAudioPlayback();
    if (mounted) {
      _showSnackBar('Audio response removed. You can record a new answer.');
    }
  }

  Future<void> _recordVideo() async {
    if (kIsWeb) {
      _showSnackBar('Video recording is not supported on this platform.');
      return;
    }
    final current = ref.read(onboardingAnswerProvider);
    if (current.isRecordingAudio || current.audioPath != null) {
      _showSnackBar(
        'Please finish or remove the audio response before recording video.',
      );
      return;
    }
    try {
      final result = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (result != null) {
        await ref
            .read(onboardingAnswerProvider.notifier)
            .updateVideoPath(result.path);
      }
    } catch (error) {
      _showSnackBar('Unable to record video: $error');
    }
  }

  Future<void> _deleteVideo() async {
    final current = ref.read(onboardingAnswerProvider);
    final videoPath = current.videoPath;
    if (!kIsWeb && videoPath != null) {
      try {
        final file = File(videoPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // ignore file system errors; we'll still clear the reference
      }
    }
    await _videoController?.pause();
    if (mounted) setState(() => _isVideoPlaying = false);
    await ref.read(onboardingAnswerProvider.notifier).updateVideoPath(null);
    if (mounted) {
      _showSnackBar('Video response removed. You can record a new answer.');
    }
  }

  Future<void> _submit(OnboardingAnswerState state) async {
    debugPrint(
      'Questionnaire answer: ${state.answer}\naudioPath: ${state.audioPath}\nvideoPath: ${state.videoPath}',
    );
    if (!mounted) return;
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.78,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.16)),
                gradient: _ctaRadialGradient(enabled: true),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Response recorded!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thank you for sharing your story. You can now continue to the next step.',
                    style: TextStyle(
                      color: Color(0xFFA7A7B2),
                      fontSize: 14,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 120,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _isNextEnabled(OnboardingAnswerState state) {
    return state.answer.trim().isNotEmpty ||
        state.audioPath != null ||
        state.videoPath != null;
  }

  void _handleAudioPathChange(String? path) {
    if (path == null) {
      _stopAudioPlayback();
    } else {
      _stopAudioPlayback();
    }
  }

  Future<void> _stopAudioPlayback() async {
    await _audioPlayer.stop();
    if (mounted) {
      setState(() => _isAudioPlaying = false);
    }
  }

  Future<void> _toggleAudioPlayback(String path) async {
    if (_isAudioPlaying) {
      await _stopAudioPlayback();
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    if (mounted) {
      setState(() => _isAudioPlaying = true);
    }
  }

  Future<void> _initializeVideoController(String? path) async {
    if (path == null) {
      _disposeVideoController();
      return;
    }

    await _videoInitFuture;
    _videoController?.removeListener(_videoListener);
    await _videoController?.dispose();
    _videoController = null;
    _videoInitFuture = null;
    _isVideoPlaying = false;

    final controller = VideoPlayerController.file(File(path));
    _videoInitFuture = controller.initialize().then((_) {
      if (!mounted) return;
      ref.read(onboardingAnswerProvider.notifier)
          .setVideoDuration(controller.value.duration);
      setState(() {});
    });
    controller.setLooping(false);
    controller.addListener(_videoListener);
    if (mounted) {
      setState(() {
        _videoController = controller;
        _isVideoPlaying = false;
      });
    }
  }

  void _disposeVideoController() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
    _videoInitFuture = null;
    _isVideoPlaying = false;
  }

  void _videoListener() {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    final playing = controller.value.isPlaying;
    if (playing != _isVideoPlaying) {
      setState(() => _isVideoPlaying = playing);
    }
    if (!playing &&
        controller.value.isInitialized &&
        controller.value.position >= controller.value.duration &&
        controller.value.duration != Duration.zero) {
      controller.seekTo(Duration.zero);
    }
  }

  Future<void> _toggleVideoPlayback() async {
    await _videoInitFuture;
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isVideoPlaying) {
      await controller.pause();
      if (mounted) setState(() => _isVideoPlaying = false);
    } else {
      await controller.play();
      if (mounted) setState(() => _isVideoPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingAnswerProvider);
    final isNextEnabled = _isNextEnabled(state);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    if (state.audioPath != _lastAudioPath) {
      _handleAudioPathChange(state.audioPath);
      _lastAudioPath = state.audioPath;
    }
    if (state.videoPath != _lastVideoPath) {
      _initializeVideoController(state.videoPath);
      _lastVideoPath = state.videoPath;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                _Header(
                  onBack: () => Navigator.of(context).maybePop(),
                  onClose: () => Navigator.of(context).maybePop(),
                  trailing: const _ProgressIndicator(currentStep: 1),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.only(
                          top: isKeyboardVisible ? 0 : 20,
                          bottom: isKeyboardVisible ? 16 : 32,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: isKeyboardVisible
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '02',
                                style: TextStyle(
                                  color: Color(0xFFA1A1AC),
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Why do you want to host with us?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Tell us about your intent and what motivates you to create experiences.',
                                style: TextStyle(
                                  color: Color(0xFFA7A7B2),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _AnswerField(controller: _answerController),
                              const SizedBox(height: 24),
                              _ResponseAttachments(
                                state: state,
                                onDeleteAudio: _deleteAudio,
                                onDeleteVideo: _deleteVideo,
                                waveform: state.waveform,
                                onStopRecording: _stopAudioRecording,
                                onCancelRecording: _cancelAudioRecording,
                                isAudioPlaying: _isAudioPlaying,
                                onToggleAudioPlayback: () {
                                  final path = state.audioPath;
                                  if (path != null) {
                                    _toggleAudioPlayback(path);
                                  }
                                },
                                isVideoPlaying: _isVideoPlaying,
                                onToggleVideoPlayback: _toggleVideoPlayback,
                                videoController: _videoController,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _ResponseActions(
                  state: state,
                  onRecordAudio: _startAudioRecording,
                  onRecordVideo: _recordVideo,
                  onDeleteAudio: _deleteAudio,
                  onDeleteVideo: _deleteVideo,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      gradient: _ctaRadialGradient(enabled: true),
                    ),
                    child: FilledButton(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(Colors.transparent),
                        shadowColor: WidgetStateProperty.all(Colors.transparent),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        iconColor: WidgetStateProperty.all(Colors.white),
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.3,
                          ),
                        ),
                        overlayColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.pressed)) {
                            return Colors.white.withValues(alpha: 0.08);
                          }
                          return Colors.transparent;
                        }),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      onPressed: isNextEnabled ? () => _submit(state) : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Next',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseAttachments extends StatelessWidget {
  const _ResponseAttachments({
    required this.state,
    required this.onDeleteAudio,
    required this.onDeleteVideo,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.waveform,
    required this.isAudioPlaying,
    required this.onToggleAudioPlayback,
    required this.isVideoPlaying,
    required this.onToggleVideoPlayback,
    required this.videoController,
  });

  final OnboardingAnswerState state;
  final VoidCallback onDeleteAudio;
  final VoidCallback onDeleteVideo;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final List<double> waveform;
  final bool isAudioPlaying;
  final VoidCallback onToggleAudioPlayback;
  final bool isVideoPlaying;
  final VoidCallback onToggleVideoPlayback;
  final VideoPlayerController? videoController;

  @override
  Widget build(BuildContext context) {
    if (state.isRecordingAudio) {
      return _RecordingCard(
        waveform: waveform,
        duration: state.recordingDuration ?? Duration.zero,
        onStop: onStopRecording,
        onCancel: onCancelRecording,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.audioPath != null)
          _RecordedGradientTile(
            duration: state.audioDuration,
            isPlaying: isAudioPlaying,
            onToggle: onToggleAudioPlayback,
            onDelete: onDeleteAudio,
          ),
        if (state.audioPath != null && state.videoPath != null)
          const SizedBox(height: 12),
        if (state.videoPath != null)
          _VideoAttachmentTile(
            title: 'Video recorded',
            duration: state.videoDuration ?? videoController?.value.duration,
            controller: videoController,
            isPlaying: isVideoPlaying,
            onToggle: onToggleVideoPlayback,
            onDelete: onDeleteVideo,
          ),
        if (state.audioPath == null && state.videoPath == null)
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: const Text(
              'Add an audio or video to make your story stand out.',
              style: TextStyle(
                color: Color(0xFFA7A7B2),
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

class _ResponseActions extends StatelessWidget {
  const _ResponseActions({
    required this.state,
    required this.onRecordAudio,
    required this.onRecordVideo,
    required this.onDeleteAudio,
    required this.onDeleteVideo,
  });

  final OnboardingAnswerState state;
  final VoidCallback onRecordAudio;
  final VoidCallback onRecordVideo;
  final VoidCallback onDeleteAudio;
  final VoidCallback onDeleteVideo;

  @override
  Widget build(BuildContext context) {
    final bool audioActive = state.isRecordingAudio || state.audioPath != null;
    final bool videoActive = state.videoPath != null;

    final VoidCallback? audioTap =
        (!state.isRecordingAudio && state.audioPath == null && !videoActive)
            ? onRecordAudio
            : null;

    final VoidCallback? videoTap =
        (state.videoPath == null && !audioActive) ? onRecordVideo : null;

    final audioLabel = state.isRecordingAudio
        ? 'Recording…'
        : state.audioPath != null
            ? 'Audio added'
            : 'Audio';
    final videoLabel = videoActive ? 'Video added' : 'Video';

    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.mic_outlined,
            label: audioLabel,
            onTap: audioTap,
            isActive: audioActive,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.videocam_outlined,
            label: videoLabel,
            onTap: videoTap,
            isActive: videoActive,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final borderColor = isActive
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: isEnabled ? 0.18 : 0.06);
    final gradientColors = isActive
        ? const [
            Color.fromRGBO(90, 90, 150, 0.55),
            Color.fromRGBO(45, 45, 80, 0.55),
          ]
        : isEnabled
            ? const [
                Color.fromRGBO(36, 36, 36, 0.65),
                Color.fromRGBO(24, 24, 24, 0.65),
              ]
            : const [
                Color.fromRGBO(24, 24, 24, 0.4),
                Color.fromRGBO(18, 18, 18, 0.4),
              ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white.withValues(
                alpha: (isEnabled || isActive) ? 1 : 0.4,
              ),
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(
                  alpha: (isEnabled || isActive) ? 0.95 : 0.4,
                ),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.waveform,
    required this.duration,
    required this.onStop,
    required this.onCancel,
  });

  final List<double> waveform;
  final Duration duration;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        gradient: _ctaRadialGradient(
          enabled: true,
          center: const Alignment(-0.6, -0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recording audio…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF6B6BFF),
                      Color(0xFF4E4EF3),
                    ],
                  ),
                ),
                child: const Icon(Icons.mic, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: AudioWaveform(samples: waveform),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Color(0xFF8F8FA5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: onStop,
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordedGradientTile extends StatelessWidget {
  const _RecordedGradientTile({
    required this.duration,
    required this.onToggle,
    required this.isPlaying,
    required this.onDelete,
  });

  final Duration? duration;
  final VoidCallback onToggle;
  final bool isPlaying;
  final VoidCallback onDelete;

  static const List<double> _staticWaveform = [
    24,
    82,
    46,
    96,
    30,
    110,
    58,
    90,
    42,
    72,
    28,
    88,
    52,
    104,
    64,
  ];

  @override
  Widget build(BuildContext context) {
    final formatted = duration != null ? _formatDuration(duration!) : '--:--';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        gradient:
            _ctaRadialGradient(enabled: true, center: const Alignment(-0.4, -0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Audio recorded',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• $formatted',
                style: const TextStyle(
                  color: Color(0xFF8F8FA5),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
                tooltip: 'Delete audio',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF6B6BFF),
                        Color(0xFF4E4EF3),
                      ],
                    ),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: AudioWaveform(samples: _staticWaveform),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoAttachmentTile extends StatelessWidget {
  const _VideoAttachmentTile({
    required this.title,
    required this.duration,
    required this.controller,
    required this.isPlaying,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final Duration? duration;
  final VideoPlayerController? controller;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final formatted = duration != null ? _formatDuration(duration!) : '--:--';
    final videoReady = controller != null && controller!.value.isInitialized;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        gradient: _ctaRadialGradient(enabled: true, center: const Alignment(-0.3, -0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• $formatted',
                style: const TextStyle(
                  color: Color(0xFF8F8FA5),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
                tooltip: 'Delete video',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: videoReady ? onToggle : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 72,
                    height: 56,
                    color: Colors.black.withValues(alpha: 0.25),
                    child: videoReady
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: controller!.value.size.width,
                                    height: controller!.value.size.height,
                                    child: VideoPlayer(controller!),
                                  ),
                                ),
                              ),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.45),
                                ),
                                child: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : const Center(
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Tap the preview to ${isPlaying ? 'pause' : 'play'} and review your video response.',
                  style: const TextStyle(
                    color: Color(0xFF8F8FA5),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: controller,
        maxLength: 600,
        maxLines: 8,
        style: const TextStyle(color: Colors.white, height: 1.5),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: '/ Start typing here',
          hintStyle: const TextStyle(color: Color(0xFF6F6F7C)),
          counterStyle: const TextStyle(color: Color(0xFF6F6F7C)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.onClose,
    required this.trailing,
  });

  final VoidCallback onBack;
  final VoidCallback onClose;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          tooltip: 'Back',
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AspectRatio(
              aspectRatio: 6,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  height: 12,
                  child: trailing,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const totalSegments = 5;
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          totalSegments,
          (index) => Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
            child: SizedBox(
              height: 8,
              width: 18,
              child: _WaveSegment(isActive: index <= currentStep),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveSegment extends StatelessWidget {
  const _WaveSegment({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? const Color(0xFF6B6BFF)
        : Colors.white.withValues(alpha: 0.2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _WavePainter(color),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height * 0.5;
    final amplitude = size.height * 0.4;
    const segments = 12;
    for (int i = 0; i <= segments; i++) {
      final progress = i / segments;
      final x = progress * size.width;
      final y = midY + math.sin(progress * math.pi * 2) * amplitude;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

