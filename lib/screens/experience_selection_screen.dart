import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/experience_providers.dart';
import '../widgets/experience_card.dart';
import 'onboarding_question_screen.dart';

class ExperienceSelectionScreen extends ConsumerStatefulWidget {
  const ExperienceSelectionScreen({super.key});

  @override
  ConsumerState<ExperienceSelectionScreen> createState() =>
      _ExperienceSelectionScreenState();
}

class _ExperienceSelectionScreenState
    extends ConsumerState<ExperienceSelectionScreen> {
  late final TextEditingController _notesController;

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
    final notes = ref.read(experienceSelectionProvider).notes;
    _notesController = TextEditingController(text: notes);
    _notesController.addListener(_handleNotesChanged);
  }

  @override
  void dispose() {
    _notesController.removeListener(_handleNotesChanged);
    _notesController.dispose();
    super.dispose();
  }

  void _handleNotesChanged() {
    ref
        .read(experienceSelectionProvider.notifier)
        .updateNotes(_notesController.text);
  }

  void _handleNext(ExperienceSelectionState selectionState) {
    debugPrint(
      'Selected experiences: ${selectionState.selectedExperienceIds.toList()}, notes: ${selectionState.notes}',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OnboardingQuestionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final experiencesAsync = ref.watch(experiencesProvider);
    final selectionState = ref.watch(experienceSelectionProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

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
                  trailing: const _ProgressIndicator(),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.only(
                          top: isKeyboardVisible ? 0 : 16,
                          bottom: isKeyboardVisible ? 16 : 24,
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
                              if (isKeyboardVisible)
                                const SizedBox(height: 8),
                              const Text(
                                '01',
                                style: TextStyle(
                                  color: Color(0xFFA1A1AC),
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'What kind of hotspots do you want to host?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                height: isKeyboardVisible ? 120 : 155,
                                child: experiencesAsync.when(
                                  data: (experiences) {
                                    if (experiences.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'No experiences are available right now.',
                                          style:
                                              TextStyle(color: Colors.white70),
                                        ),
                                      );
                                    }
                                    return ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: experiences.length,
                                      clipBehavior: Clip.none,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 16),
                                      itemBuilder: (context, index) {
                                        final experience = experiences[index];
                                        final isSelected = selectionState
                                            .selectedExperienceIds
                                            .contains(experience.id);
                                        return ExperienceCard(
                                          experience: experience,
                                          isSelected: isSelected,
                                          onTap: () => ref
                                              .read(
                                                  experienceSelectionProvider
                                                      .notifier)
                                              .toggleExperience(
                                                experience.id,
                                              ),
                                        );
                                      },
                                    );
                                  },
                                  error: (error, _) => _ErrorState(
                                    message: error.toString(),
                                    onRetry: () =>
                                        ref.refresh(experiencesProvider),
                                  ),
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              TextField(
                                controller: _notesController,
                                maxLength: 250,
                                maxLines: 4,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white,
                                decoration: InputDecoration(
                                  hintText: '/ Describe your perfect hotspot',
                                  counterStyle: const TextStyle(
                                    color: Color(0xFF7B7B87),
                                    fontSize: 12,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF7B7B87),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF1D1D23),
                                  contentPadding: const EdgeInsets.all(18),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF6B6BFF),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      gradient: RadialGradient(
                        center: const Alignment(-1.0, -0.85),
                        radius: 1.3,
                        colors: const [
                          Color.fromRGBO(34, 34, 34, 0.4),
                          Color.fromRGBO(153, 153, 153, 0.4),
                          Color.fromRGBO(34, 34, 34, 0.4),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: 0.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => _handleNext(selectionState),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('Next'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios_rounded, size: 18),
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
  const _ProgressIndicator();

  @override
  Widget build(BuildContext context) {
    const segments = 5;
    const activeIndex = 0;
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          segments,
          (index) => Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
            child: SizedBox(
              height: 8,
              width: 18,
              child: _WaveSegment(isActive: index <= activeIndex),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        const Text(
          'We had trouble loading experiences.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

