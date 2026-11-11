import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../ui/settings.dart';
import '../ui/settings_dialog.dart';
import '../ui/i18n.dart';
import '../ui/theme.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  @override
  void initState() {
    super.initState();
    Engine.I.js.hideAll();
  }

  void _start() {
    // First user gesture: unlock Web Audio and start the menu music.
    Engine.I.audio.ensure();
    Engine.I.audio.playMusic('rps_arena');
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.2,
          colors: [Rps.navyMid, Rps.navyDeep],
        ),
      ),
      child: Center(
        child: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo/main.png', height: h * 0.62, filterQuality: FilterQuality.medium),
              SizedBox(height: h * 0.03),
              FilledButton(onPressed: _start, child: Text(tr('게임 시작', 'Start'))),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => showSettings(context, Settings.I),
                icon: Icon(Icons.settings, color: Rps.cream),
                label: Text(tr('설정', 'Settings'), style: TextStyle(color: Rps.cream)),
              ),
            ],
          );
        }),
      ),
    );
  }
}
