import 'dart:math' as math;
import 'package:flutter/material.dart';

class AudioWaveform extends StatelessWidget {
  const AudioWaveform({
    super.key,
    required this.samples,
  });

  final List<double> samples;

  static const double _maxAmplitude = 160.0;
  static const int _maxBars = 48;

  @override
  Widget build(BuildContext context) {
    final normalizedSamples = samples.isEmpty
        ? List<double>.filled(12, 0.0)
        : samples.map((value) => value.abs().clamp(0.0, _maxAmplitude)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final renderSamples =
            _downsample(normalizedSamples, _maxBars).map((value) {
          final normalized = (value / _maxAmplitude).clamp(0.0, 1.0);
          return normalized;
        }).toList(growable: false);

        return RepaintBoundary(
          child: CustomPaint(
            size: Size(width, height),
            painter: _WaveformPainter(
              samples: renderSamples,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  static List<double> _downsample(List<double> source, int maxLength) {
    if (source.isEmpty) {
      return const <double>[];
    }
    if (source.length <= maxLength) {
      return source;
    }

    final bucketSize = (source.length / maxLength).ceil();
    final result = <double>[];
    for (var i = 0; i < source.length; i += bucketSize) {
      final end = math.min(i + bucketSize, source.length);
      final bucket = source.sublist(i, end);
      final average =
          bucket.fold<double>(0, (sum, value) => sum + value) / bucket.length;
      result.add(average);
      if (result.length >= maxLength) {
        break;
      }
    }
    return result;
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.color,
  });

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      return;
    }

    final barCount = samples.length;
    final paint = Paint()..color = color;

    if (barCount == 1) {
      final barHeight = (samples.first.clamp(0.1, 1.0)) * size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (size.width - size.width * 0.1) / 2,
          size.height - barHeight,
          size.width * 0.1,
          barHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
      return;
    }

    final gapFactor = 1.0; // gap equal to bar width
    final unit = size.width / (barCount + (barCount - 1) * gapFactor);
    final barWidth = unit;
    final gapWidth = unit * gapFactor;

    double dx = 0;
    for (var i = 0; i < barCount; i++) {
      final normalized = samples[i].clamp(0.1, 1.0);
      final barHeight = normalized * size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          dx,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
      dx += barWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    if (identical(this, oldDelegate)) {
      return false;
    }
    if (samples.length != oldDelegate.samples.length || color != oldDelegate.color) {
      return true;
    }
    for (var i = 0; i < samples.length; i++) {
      if (samples[i] != oldDelegate.samples[i]) {
        return true;
      }
    }
    return false;
  }
}

