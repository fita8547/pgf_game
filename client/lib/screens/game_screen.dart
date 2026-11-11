import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';

import '../engine/engine.dart';
import '../game/game_controller.dart';
import '../ui/settings.dart';
import '../ui/settings_dialog.dart';
import '../ui/i18n.dart';
import '../ui/theme.dart';

part 'game_hud.dart';
part 'game_overlays.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game, required this.onEnd, required this.onLeave});
  final GameController game;
  final void Function(MatchResult) onEnd;
  final VoidCallback onLeave;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Dev: `?nopause=1` hides the click-to-play overlay (headless screenshots).
final bool _noPause = Uri.base.queryParameters['nopause'] == '1';

class _GameScreenState extends State<GameScreen> {
  GameController get g => widget.game;

  @override
  void initState() {
    super.initState();
    g.onEnd = widget.onEnd;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        if (g.error != null) return _center(Text(g.error!, style: const TextStyle(color: Rps.danger)), back: true);
        if (g.loading) {
          return Container(
            color: Rps.navyDeep,
            child: _center(Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/logo/origami.png', height: 220),
              const SizedBox(height: 16),
              const SizedBox(width: 220, child: LinearProgressIndicator(color: Rps.gold)),
              const SizedBox(height: 10),
              Text(g.status),
            ])),
          );
        }
        final s = g.sim!, p = g.me!;
        return Stack(children: [
          if (g.scoped) const Positioned.fill(child: _ScopeOverlay()),
          if (g.damageFlash > 0) Positioned.fill(child: _DamageVignette(g.damageFlash, g.damageDir)),
          if (p.alive && p.hp / p.maxHp < 0.35) const Positioned.fill(child: _LowHp()),
          if (p.alive && !g.scoped) Center(child: _Crosshair(g)),
          if (s.phase != Phase.ended) Positioned.fill(child: _ObjectiveMarker(g)),
          if (p.alive && p.mag == 0 && p.reloadTimer <= 0)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 + 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text(p.reserve > 0 ? tr('R 재장전', 'R reload') : tr('탄약 없음 · 1/2 무기 교체', 'Out of ammo · 1/2 switch weapon'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Rps.danger, shadows: [
                      Shadow(blurRadius: 4, color: Colors.black),
                    ])),
              ),
            ),
          if (p.alive && !g.shopOpen && s.map.inSpawnRoom(p.team, p.pos) && s.phase != Phase.ended)
            Positioned(
              bottom: 110,
              left: 0,
              right: 0,
              child: Center(
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  opacity: 0.6,
                  child: Text(
                      tr('B 상점 열기 · ${p.credits} ₵ · 스폰룸: 사격 불가 · 체력 회복',
                              'B open shop · ${p.credits} ₵ · Spawn room: no shooting · healing') +
                          (p.spawnProtect > 0
                              ? tr(' · 보호 ${p.spawnProtect.ceil()}초', ' · protected ${p.spawnProtect.ceil()}s')
                              : ''),
                      style: const TextStyle(fontSize: 13, color: Rps.gold)),
                ),
              ),
            ),
          Positioned(top: 12, left: 0, right: 0, child: Center(child: _CaptureBar(s, p))),
          Positioned(top: 12, right: 16, width: 360, child: _KillFeed(g)),
          if (g.online)
            Positioned(
                top: 14,
                left: 16,
                child: Text('${tr('온라인', 'Online')} · ${g.ping}ms', style: const TextStyle(fontSize: 12, color: Colors.white70))),
          Positioned(left: 20, bottom: 20, child: _Vitals(p)),
          Positioned(right: 20, bottom: 20, child: _Ammo(p, s)),
          if (g.bannerTime > 0 && g.banner != null)
            Positioned(top: 120, left: 0, right: 0, child: Center(child: _Banner(g.banner!))),
          if (g.toastTime > 0 && g.toast != null)
            Positioned(bottom: 150, left: 0, right: 0, child: Center(child: Panel(child: Text(g.toast!)))),
          if (!p.alive && s.phase != Phase.ended) Positioned(bottom: 140, left: 0, right: 0, child: _DeathInfo(g, s, p)),
          if (s.phase == Phase.pregame)
            Positioned(
                top: 200,
                left: 0,
                right: 0,
                child: Center(child: _Banner(tr('${(s.cfg.pregame - s.phaseTime).ceil()}초 후 시작', 'Starting in ${(s.cfg.pregame - s.phaseTime).ceil()}s')))),
          if (g.shopOpen) Center(child: _Shop(g)),
          if (g.charPickerOpen && !p.alive) Center(child: _CharPicker(g)),
          if (g.scoreboard) Center(child: _Scoreboard(s, p)),
          if (!g.locked && !g.shopOpen && !g.charPickerOpen && s.phase != Phase.ended && !_noPause)
            Positioned.fill(child: _Pause(g, widget.onLeave)),
        ]);
      },
    );
  }

  Widget _center(Widget c, {bool back = false}) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          c,
          if (back) TextButton(onPressed: widget.onLeave, child: Text(tr('로비로', 'To lobby'))),
        ]),
      );
}
