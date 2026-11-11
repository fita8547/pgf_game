import 'package:flutter/material.dart';

import '../ui/i18n.dart';
import '../ui/theme.dart';

/// First page: logo, a progress bar and what is being loaded. The app shell
/// ([RpsApp]) runs the boot steps and feeds [progress]/[status].
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.progress, required this.status});
  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: RadialGradient(colors: [Rps.navyMid, Rps.navyDeep], radius: 1.1)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Opacity(
                opacity: v.clamp(0, 1),
                child: Transform.scale(scale: v, child: child),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/logo/origami.png', height: 260),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr('1인칭 팀 대전 히어로 슈터', 'First-person team hero shooter'),
              style: TextStyle(fontSize: 16, color: Rps.fg(0.8), letterSpacing: 1),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: Rps.gold,
                  backgroundColor: Rps.fg(0.12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(status, style: TextStyle(fontSize: 13, color: Rps.fg(0.6))),
          ],
        ),
      ),
    );
  }
}

/// Shown after a fatal network error: the app has stopped.
class ExitedScreen extends StatelessWidget {
  const ExitedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Rps.navyDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Rps.fg(0.5)),
            const SizedBox(height: 14),
            Text(
              tr('앱이 종료되었습니다', 'The app has closed'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Rps.cream),
            ),
            const SizedBox(height: 8),
            Text(
              tr('네트워크 연결을 확인한 뒤 페이지를 새로고침하세요.', 'Check your network connection, then reload the page.'),
              style: TextStyle(color: Rps.fg(0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
