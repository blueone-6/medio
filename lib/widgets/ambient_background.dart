import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Subtle film-grain overlay — breaks flat scaffold surfaces without assets.
///
/// Skipped on fullscreen player routes where grain would sit above video.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final cs = Theme.of(context).colorScheme;
    final grainAlpha = cs.brightness == Brightness.dark ? 0.028 : 0.022;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GrainPainter(
                color: cs.onSurface.withValues(alpha: grainAlpha),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.color});

  final Color color;
  static const _seed = 0x5EED;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()..color = color;
    final rng = math.Random(_seed);
    final area = size.width * size.height;
    // ~1 dot per 900 logical px² — cheap and barely visible.
    final count = (area / 900).round().clamp(120, 2800);

    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 0.85 + 0.35;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.color != color;
}
