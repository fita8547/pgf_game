import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'i18n.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context, Settings s) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: 500,
        child: Panel(child: SingleChildScrollView(child: _SettingsBody(s))),
      ),
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
  /// null = not saved yet, true = saved on the server, false = server failed.
  bool? _synced;

  /// Theme / font size: apply now, save locally and on the server.
  Future<void> _applyServerSetting(void Function() change) async {
    setState(() {
      change();
      _synced = null;
    });
    Settings.langChanged.value++;
    final ok = await widget.s.pushToServer();
    if (mounted) setState(() => _synced = ok);
  }

  Widget _slider(
    String label,
    double v,
    double min,
    double max,
    String Function(double) fmt,
    void Function(double) on,
  ) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: (x) => setState(() => on(x))),
        ),
        SizedBox(width: 52, child: Text(fmt(v), textAlign: TextAlign.right)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    void vol() => Engine.I.audio.setVolumes(s.sfxVolume, s.musicVolume);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('설정', 'Settings'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Rps.goldText),
        ),
        const SizedBox(height: 12),
        _slider(
          tr('마우스 감도', 'Mouse sens.'),
          s.sensitivity * 1000,
          0.5,
          6,
          (v) => v.toStringAsFixed(1),
          (v) => s.sensitivity = v / 1000,
        ),
        _slider(tr('시야각(FOV)', 'Field of view'), s.fov, 60, 100, (v) => v.toStringAsFixed(0), (v) => s.fov = v),
        _slider(tr('효과음', 'Sound FX'), s.sfxVolume, 0, 1, (v) => '${(v * 100).round()}', (v) {
          s.sfxVolume = v;
          vol();
        }),
        _slider(tr('배경음악', 'Music'), s.musicVolume, 0, 1, (v) => '${(v * 100).round()}', (v) {
          s.musicVolume = v;
          vol();
        }),
        Row(
          children: [
            SizedBox(width: 110, child: Text(tr('다크 모드', 'Dark mode'))),
            Semantics(
              label: tr('다크 모드 스위치', 'Dark mode switch'),
              child: Switch(
                value: s.dark,
                activeThumbColor: Rps.gold,
                onChanged: (v) => _applyServerSetting(() => s.dark = v),
              ),
            ),
            const SizedBox(width: 8),
            Text(s.dark ? tr('어둡게', 'Dark') : tr('밝게', 'Light'), style: TextStyle(color: Rps.fg(0.7))),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 110, child: Text(tr('글자 크기', 'Text size'))),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (f, label) in [
                    (0.85, tr('작게', 'Small')),
                    (1.0, tr('보통', 'Normal')),
                    (1.15, tr('크게', 'Large')),
                    (1.3, tr('아주 크게', 'Huge')),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: (s.fontScale - f).abs() < 0.01,
                      onSelected: (_) => _applyServerSetting(() => s.fontScale = f),
                    ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 110, top: 2, bottom: 6),
          child: Text(Settings.standalone ? tr('이 브라우저에 저장됩니다', 'Saved in this browser') : switch (_synced) {
            null => tr('다크 모드·글자 크기는 서버에 저장되어 다시 켜도 유지됩니다', 'Dark mode and text size are saved on the server'),
            true => tr('서버에 저장됨', 'Saved on the server'),
            false => tr('서버 저장 실패 (이 기기에만 저장됨)', 'Server save failed (saved on this device only)'),
          }, style: TextStyle(fontSize: 11, color: _synced == false ? Rps.danger : Rps.fg(0.55))),
        ),
        Row(
          children: [
            SizedBox(width: 110, child: Text(tr('그래픽', 'Graphics'))),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (q, label) in [(0, tr('낮음', 'Low')), (1, tr('보통', 'Medium')), (2, tr('높음', 'High'))])
                    ChoiceChip(
                      label: Text(label),
                      selected: s.quality == q,
                      onSelected: (_) => setState(() {
                        s.quality = q;
                        Engine.I.js.setQuality(q);
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 110, top: 2),
          child: Text(
            tr('낮음: 그림자·빛번짐 끄고 해상도 낮춤 (느린 PC용)', 'Low: no shadows/bloom, lower resolution (slow PCs)'),
            style: TextStyle(fontSize: 11, color: Rps.fg(0.54)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(width: 110, child: Text(tr('언어', 'Language'))),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (code, label) in const [('ko', '한국어'), ('en', 'English')])
                    ChoiceChip(
                      label: Text(label),
                      selected: s.lang == code,
                      onSelected: (_) => setState(() {
                        s.lang = code;
                        s.save();
                        Settings.langChanged.value++;
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('닫기', 'Close'))),
        ),
      ],
    );
  }
}
