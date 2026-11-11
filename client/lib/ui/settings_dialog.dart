import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context, Settings s) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(width: 420, child: Panel(child: _SettingsBody(s))),
    ),
  ).then((_) => s.save());
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody(this.s);
  final Settings s;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  Widget _slider(String label, double v, double min, double max, String Function(double) fmt, void Function(double) on) {
    return Row(children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: (x) => setState(() => on(x)))),
      SizedBox(width: 52, child: Text(fmt(v), textAlign: TextAlign.right)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    void vol() => Engine.I.audio.setVolumes(s.sfxVolume, s.musicVolume);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('설정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Rps.gold)),
      const SizedBox(height: 12),
      _slider('마우스 감도', s.sensitivity * 1000, 0.5, 6, (v) => v.toStringAsFixed(1), (v) => s.sensitivity = v / 1000),
      _slider('시야각(FOV)', s.fov, 60, 100, (v) => v.toStringAsFixed(0), (v) => s.fov = v),
      _slider('효과음', s.sfxVolume, 0, 1, (v) => '${(v * 100).round()}', (v) {
        s.sfxVolume = v;
        vol();
      }),
      _slider('배경음악', s.musicVolume, 0, 1, (v) => '${(v * 100).round()}', (v) {
        s.musicVolume = v;
        vol();
      }),
      Row(children: [
        const SizedBox(width: 110, child: Text('그래픽')),
        for (final (q, label) in const [(0, '낮음'), (1, '보통'), (2, '높음')])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label),
              selected: s.quality == q,
              onSelected: (_) => setState(() {
                s.quality = q;
                Engine.I.js.setQuality(q);
              }),
            ),
          ),
      ]),
      const Padding(
        padding: EdgeInsets.only(left: 110, top: 2),
        child: Text('낮음: 그림자·빛번짐 끄고 해상도 낮춤 (느린 PC용)', style: TextStyle(fontSize: 11, color: Colors.white54)),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
      ),
    ]);
  }
}
