import 'package:flutter/material.dart';

import 'theme.dart';

/// Skeleton UI: grey placeholder blocks with a moving shimmer, shown while
/// the real content (images, server data, the match) is loading.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 3 - 1; // -1..2: the light band sweeps across
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Rps.fg(0.08), Rps.fg(0.22), Rps.fg(0.08)],
            stops: [(t - 0.3).clamp(0.0, 1.0), t.clamp(0.0, 1.0), (t + 0.3).clamp(0.0, 1.0)],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}

/// One placeholder block. Put several inside a [Shimmer].
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 14, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: Rps.fg(0.12),
      borderRadius: circle ? null : BorderRadius.circular(radius),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
    ),
  );
}

/// Placeholder for a lobby character card (icon + two text lines).
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: Rps.navy.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
    child: const Row(
      children: [
        Bone(width: 44, height: 44, radius: 8),
        SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Bone(width: 70, height: 14), SizedBox(height: 6), Bone(width: 50, height: 10)],
          ),
        ),
      ],
    ),
  );
}

/// Placeholder of the in-game HUD shown while a match loads.
class HudSkeleton extends StatelessWidget {
  const HudSkeleton({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Widget panel(double w, double h, List<Widget> rows) => Container(
      width: w,
      height: h,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Rps.navyDeep.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
    return Container(
      color: Rps.navyDeep,
      child: Stack(
        children: [
          Positioned.fill(
            child: Shimmer(
              child: Stack(
                children: [
                  // capture bar
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: panel(210, 100, const [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Bone(width: 50, height: 26),
                            Bone(height: 40, circle: true),
                            Bone(width: 50, height: 26),
                          ],
                        ),
                        SizedBox(height: 10),
                        Center(child: Bone(width: 80, height: 12)),
                      ]),
                    ),
                  ),
                  // kill feed
                  Positioned(
                    top: 12,
                    right: 16,
                    child: Column(
                      children: [
                        for (var i = 0; i < 3; i++)
                          const Padding(padding: EdgeInsets.only(bottom: 6), child: Bone(width: 240, height: 26)),
                      ],
                    ),
                  ),
                  // vitals + skills
                  Positioned(
                    left: 20,
                    bottom: 20,
                    child: panel(260, 170, [
                      const Row(
                        children: [Bone(height: 34, circle: true), SizedBox(width: 8), Bone(width: 110, height: 16)],
                      ),
                      const SizedBox(height: 10),
                      const Bone(width: 120, height: 28),
                      const SizedBox(height: 8),
                      const Bone(width: 220, height: 8),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var i = 0; i < 4; i++)
                            const Padding(padding: EdgeInsets.only(right: 6), child: Bone(width: 48, height: 50)),
                        ],
                      ),
                    ]),
                  ),
                  // ammo
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: panel(230, 120, const [
                      Align(alignment: Alignment.centerRight, child: Bone(width: 90, height: 36)),
                      SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: Bone(width: 140, height: 16)),
                      SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: Bone(width: 180, height: 10)),
                    ]),
                  ),
                  const Center(child: Bone(height: 24, circle: true)),
                ],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 150),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 200, child: LinearProgressIndicator(color: Rps.gold)),
                  const SizedBox(height: 10),
                  Text(status, style: TextStyle(color: Rps.fg(0.75))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
