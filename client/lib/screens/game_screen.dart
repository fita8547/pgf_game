import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';

import '../game/game_controller.dart';
import '../ui/settings.dart';
import '../ui/settings_dialog.dart';
import '../ui/theme.dart';

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
                child: Text(p.reserve > 0 ? 'R 재장전' : '탄약 없음 · 1/2 무기 교체',
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
                      'B 상점 열기 · ${p.credits} ₵ · 스폰룸: 사격 불가 · 체력 회복'
                      '${p.spawnProtect > 0 ? ' · 보호 ${p.spawnProtect.ceil()}초' : ''}',
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
                child: Text('온라인 · ${g.ping}ms', style: const TextStyle(fontSize: 12, color: Colors.white70))),
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
                child: Center(child: _Banner('${(s.cfg.pregame - s.phaseTime).ceil()}초 후 시작'))),
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
          if (back) TextButton(onPressed: widget.onLeave, child: const Text('로비로')),
        ]),
      );
}

// ---------------------------------------------------------------- pieces --

class _Crosshair extends StatelessWidget {
  const _Crosshair(this.g);
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final p = g.me!;
    final spread = g.sim!.spreadFor(p);
    // Gap follows the real spread cone (pixels at the current FOV).
    final h = MediaQuery.of(context).size.height;
    final gap = 4 + math.tan(spread) / math.tan(70 * math.pi / 360) * h / 2;
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
          painter: _CrossPainter(gap.clamp(3, 50).toDouble(), g.hitmarker, g.hitHead, 1 - p.adsT * 0.7,
              optic: p.gun.info.scope && !p.gun.info.overlay ? p.adsT : 0)),
    );
  }
}

class _CrossPainter extends CustomPainter {
  _CrossPainter(this.gap, this.hit, this.head, this.alpha, {this.optic = 0});
  final double gap, hit, alpha;

  /// ADS amount for optic sights (rifle, launcher): draws a red-dot reticle.
  final double optic;
  final bool head;

  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.5 * alpha)
      ..strokeWidth = 4;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * alpha)
      ..strokeWidth = 2;
    const len = 7.0;
    for (final d in [const Offset(1, 0), const Offset(-1, 0), const Offset(0, 1), const Offset(0, -1)]) {
      final a = o + d * gap, b = o + d * (gap + len);
      c.drawLine(a, b, shadow);
      c.drawLine(a, b, line);
    }
    c.drawCircle(o, 1.5, line);
    if (optic > 0.6) {
      final a = ((optic - 0.6) / 0.4).clamp(0.0, 1.0);
      c.drawCircle(o, 2.6, Paint()..color = Rps.danger.withValues(alpha: a));
      c.drawCircle(o, 11, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Rps.danger.withValues(alpha: a * 0.8));
    }
    if (hit > 0) {
      final hp = Paint()
        ..color = (head ? Rps.danger : Colors.white).withValues(alpha: math.min(1, hit * 6))
        ..strokeWidth = 2.5;
      for (final d in [const Offset(1, 1), const Offset(-1, 1), const Offset(1, -1), const Offset(-1, -1)]) {
        c.drawLine(o + d * 6, o + d * 13, hp);
      }
    }
  }

  @override
  bool shouldRepaint(_CrossPainter o) => true;
}

class _ScopeOverlay extends StatelessWidget {
  const _ScopeOverlay();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ScopePainter());
}

class _ScopePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero);
    final r = s.shortestSide * 0.46;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & s)
      ..addOval(Rect.fromCircle(center: o, radius: r));
    c.drawPath(path, Paint()..color = Colors.black);
    c.drawCircle(o, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF111111));
    final l = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;
    c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), l);
    c.drawLine(Offset(o.dx, o.dy - r), Offset(o.dx, o.dy + r), l);
    final thick = Paint()
      ..color = Colors.black
      ..strokeWidth = 5;
    c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx - r * 0.3, o.dy), thick);
    c.drawLine(Offset(o.dx + r * 0.3, o.dy), Offset(o.dx + r, o.dy), thick);
    c.drawLine(Offset(o.dx, o.dy + r * 0.3), Offset(o.dx, o.dy + r), thick);
    c.drawCircle(o, 2, Paint()..color = Rps.danger);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DamageVignette extends StatelessWidget {
  const _DamageVignette(this.t, this.dir);
  final double t, dir;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _DamagePainter(t, dir)),
      );
}

class _DamagePainter extends CustomPainter {
  _DamagePainter(this.t, this.dir);
  final double t, dir;
  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero);
    c.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.transparent,
            Rps.danger.withValues(alpha: 0.35 * t),
          ], stops: const [0.6, 1]).createShader(Rect.fromCircle(center: o, radius: s.longestSide * 0.6)));
    // Arc pointing at the attacker (dir: radians, 0 = straight ahead).
    final r = s.shortestSide * 0.18;
    final a = dir - math.pi / 2;
    c.drawArc(Rect.fromCircle(center: o, radius: r), a - 0.35, 0.7, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Rps.danger.withValues(alpha: math.min(1, t * 1.6)));
  }

  @override
  bool shouldRepaint(_) => true;
}

class _CaptureBar extends StatelessWidget {
  const _CaptureBar(this.s, this.p);
  final GameSim s;
  final Player p;

  @override
  Widget build(BuildContext context) {
    // No time limit: show elapsed match time instead of a countdown.
    final played = math.max(0.0, s.time - s.cfg.pregame);
    final left = s.cfg.timeLimit > 0 ? (s.cfg.timeLimit - played).clamp(0, 9999) : played;
    final mm = (left ~/ 60).toString(), ss = (left.toInt() % 60).toString().padLeft(2, '0');
    final mine = p.team, other = 1 - p.team;
    Widget score(int t) => Column(children: [
          Text('${(s.score[t] * 100).floor()}%',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Rps.team(t))),
          Text(t == mine ? '우리 팀' : '적 팀', style: const TextStyle(fontSize: 11)),
        ]);
    final ownerColor = s.owner < 0 ? Colors.white54 : Rps.team(s.owner);
    final capColor = s.capTeam < 0 ? Colors.white : Rps.team(s.capTeam);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      opacity: 0.7,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        score(mine),
        const SizedBox(width: 18),
        Column(children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: s.capProgress,
                strokeWidth: 5,
                color: capColor,
                backgroundColor: ownerColor.withValues(alpha: 0.35),
              ),
              Icon(s.contested ? Icons.warning_amber : Icons.flag, color: s.contested ? Rps.gold : ownerColor),
            ]),
          ),
          const SizedBox(height: 2),
          Text('$mm:$ss', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('거점 ${s.onPoint[mine]} : ${s.onPoint[other]}', style: const TextStyle(fontSize: 11)),
        ]),
        const SizedBox(width: 18),
        score(other),
      ]),
    );
  }
}

class _KillFeed extends StatelessWidget {
  const _KillFeed(this.g);
  final GameController g;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final e in g.feed)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(6),
            border: e.killerId == g.me?.id
                ? Border.all(color: Rps.gold, width: 1.5)
                : (e.victimId == g.me?.id ? Border.all(color: Rps.danger, width: 1.5) : null),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (e.killer.isNotEmpty)
              Text(e.killer, style: TextStyle(color: Rps.team(e.killerTeam), fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: isGun(e.weaponId)
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      gunIcon(e.weaponId, 54, 20),
                      if (e.head) const Text(' ◎', style: TextStyle(fontSize: 12, color: Rps.gold)),
                    ])
                  : (skillImpls.containsKey(e.weaponId)
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          skillIcon(e.weaponId, 20),
                          const SizedBox(width: 3),
                          Text(e.weapon, style: const TextStyle(fontSize: 11)),
                        ])
                      : Text('[${e.weapon}]', style: const TextStyle(fontSize: 12))),
            ),
            Text(e.victim, style: TextStyle(color: Rps.team(e.victimTeam), fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}

class _Vitals extends StatelessWidget {
  const _Vitals(this.p);
  final Player p;

  @override
  Widget build(BuildContext context) {
    final c = p.character;
    final frac = (p.hp / p.maxHp).clamp(0.0, 1.0);
    return Panel(
      opacity: 0.65,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          charIcon(c.id, 34),
          const SizedBox(width: 4),
          roleIcon(c.role, 18),
          const SizedBox(width: 6),
          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Text('${p.credits} ₵', style: const TextStyle(color: Rps.gold, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('${p.hp.ceil()}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          Text(' / ${p.maxHp.round()}', style: const TextStyle(fontSize: 14)),
        ]),
        SizedBox(
          width: 220,
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            color: frac > 0.35 ? Rps.cream : Rps.danger,
            backgroundColor: Colors.white12,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [for (final sk in c.info.skills) _SkillSlot(p, sk)]),
        _StatusChips(p),
      ]),
    );
  }
}

/// Own status effects and weapon mode, as small chips.
class _StatusChips extends StatelessWidget {
  const _StatusChips(this.p);
  final Player p;

  static const _labels = {
    'slow': ('둔화', Rps.blue),
    'root': ('속박', Color(0xFFB46BFF)),
    'sleep': ('수면', Color(0xFFB46BFF)),
    'stun': ('기절', Color(0xFFB46BFF)),
    'amp': ('공격력↑', Rps.gold),
    'haste': ('가속', Rps.gold),
    'prot': ('받는 피해↓', Rps.gold),
    'vuln': ('받는 피해↑', Rps.danger),
    'invuln': ('무적', Colors.white),
    'undying': ('불사', Colors.white),
    'antiheal': ('치유 차단', Rps.danger),
    'healboost': ('치유 증가', Color(0xFF7DFFB0)),
  };

  @override
  Widget build(BuildContext context) {
    final chips = <(String, Color)>[];
    for (final e in _labels.entries) {
      if ((p.fx[e.key] ?? 0) > 0) chips.add(('${e.value.$1} ${p.fx[e.key]!.toStringAsFixed(1)}', e.value.$2));
    }
    final sh = p.fx['shield'] ?? 0;
    if (sh > 0) chips.add(('보호막 ${sh.ceil()}', const Color(0xFF6FC3FF)));
    final mode = switch (p.mode) {
      'shuriken' => '표창 ×${(p.fx['modeAmmo'] ?? 0).toInt()}',
      'twin' => '쌍날 개방',
      'roll' => '구르기: 이속↑ 받는 피해 -50% · 사격 불가 (E로 해제)',
      'guard' => '가시 방패 (Q로 해제)',
      'deflect' => '튕겨내기',
      _ => null,
    };
    if (mode != null) chips.add(('$mode ${(p.fx['modeT'] ?? 0).toStringAsFixed(1)}', Rps.gold));
    if (p.fx.containsKey('linkTo')) chips.add(('치유 연결 중', const Color(0xFF7DFFB0)));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: 240,
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (t, c) in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4), border: Border.all(color: c)),
              child: Text(t, style: TextStyle(fontSize: 10, color: c)),
            ),
        ]),
      ),
    );
  }
}

/// One skill key: name, cooldown / charges, ult percentage.
class _SkillSlot extends StatelessWidget {
  const _SkillSlot(this.p, this.sk);
  final Player p;
  final SkillInfo sk;

  @override
  Widget build(BuildContext context) {
    final impl = skillImpls[sk.id];
    final k = skillSlot(sk.key);
    final ult = k < 0;
    final cost = p.character.stats.ultCost;
    final frac = ult ? (p.ult / cost).clamp(0.0, 1.0) : 1.0;
    final charges = ult ? 0 : p.skillCharges[k];
    final ready = impl != null && (ult ? frac >= 1 : charges > 0);
    final cd = ult ? 0.0 : p.skillCd[k];
    final maxC = impl?.maxCharges ?? 1;
    final label = skillKeyLabel(sk.key);
    return Tooltip(
      message: '${sk.name}: ${sk.desc}',
      child: Container(
        width: 52,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: ready ? (ult ? Rps.gold.withValues(alpha: 0.25) : Colors.white12) : Colors.black26,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ready ? (ult ? Rps.gold : Colors.white54) : Colors.white12),
        ),
        child: Column(children: [
          skillIcon(sk.id, 30, dim: !ready),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ready ? Rps.cream : Colors.white38)),
          Text(
            impl == null
                ? '준비중'
                : ult
                    ? '${(frac * 100).floor()}%'
                    : (cd > 0 && charges == 0)
                        ? cd.toStringAsFixed(cd < 3 ? 1 : 0)
                        : (maxC > 1 ? '×$charges' : '준비'),
            style: TextStyle(fontSize: 10, color: ready ? Rps.gold : Colors.white38),
          ),
        ]),
      ),
    );
  }
}

class _Ammo extends StatelessWidget {
  const _Ammo(this.p, this.s);
  final Player p;
  final GameSim s;

  @override
  Widget build(BuildContext context) {
    final g = p.gun;
    final inSpawn = p.alive && s.map.inSpawnRoom(p.team, p.pos);
    return Panel(
      opacity: 0.65,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${p.mag}',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w900, color: p.mag == 0 ? Rps.danger : Rps.cream)),
          Text(' / ${p.reserve}', style: const TextStyle(fontSize: 16)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          gunIcon(g.id, 80, 30),
          const SizedBox(width: 6),
          Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        if (p.reloadTimer > 0)
          SizedBox(
            width: 140,
            child: LinearProgressIndicator(
                value: 1 - p.reloadTimer / g.stats.reloadTime, color: Rps.gold, backgroundColor: Colors.white12),
          ),
        const SizedBox(height: 4),
        Text(
          '1 주무기${p.primary == null ? '(없음)' : ''}  2 보조  R 재장전  ${inSpawn ? 'B 상점' : ''}',
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: Rps.cream,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Rps.gold, width: 2),
        ),
        child: Text(text, style: const TextStyle(color: Rps.navy, fontSize: 24, fontWeight: FontWeight.w900)),
      );
}

class _DeathInfo extends StatelessWidget {
  const _DeathInfo(this.g, this.s, this.p);
  final GameController g;
  final GameSim s;
  final Player p;

  @override
  Widget build(BuildContext context) {
    final k = g.killedBy == null ? null : s.players[g.killedBy];
    return Center(
      child: Panel(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (k != null)
            Text.rich(TextSpan(children: [
              TextSpan(text: k.name, style: TextStyle(color: Rps.team(k.team), fontWeight: FontWeight.w800)),
              TextSpan(text: ' (${k.character.name}, ${k.gun.name}) 에게 당했습니다'),
            ])),
          const SizedBox(height: 4),
          Text('${p.respawnIn.ceil()}초 후 부활', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('B 캐릭터 변경', style: TextStyle(fontSize: 12, color: Rps.gold)),
        ]),
      ),
    );
  }
}

class _LowHp extends StatelessWidget {
  const _LowHp();
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.0,
              colors: [Colors.transparent, Rps.danger.withValues(alpha: 0.35)],
              stops: const [0.55, 1],
            ),
          ),
        ),
      );
}

/// Capture point marker: diamond + distance, clamped to the screen edge.
class _ObjectiveMarker extends StatelessWidget {
  const _ObjectiveMarker(this.g);
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final o = g.objectiveOnScreen(size.width / size.height);
    final s = g.sim!;
    if (o == null) return const SizedBox.shrink();
    final (x, y, dist, on) = o;
    if (on && dist < s.map.captureRadius) return const SizedBox.shrink();
    final color = s.owner < 0 ? Rps.cream : (s.owner == g.me!.team ? Rps.teamB : Rps.danger);
    return IgnorePointer(
      child: Stack(children: [
        Positioned(
          left: x * size.width - 30,
          top: y * size.height - 22,
          width: 60,
          child: Column(children: [
            Transform.rotate(
              angle: 0.785,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: s.contested ? 0.9 : 0.6),
                  border: Border.all(color: Colors.black54),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${dist.round()}m',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, shadows: [
                  Shadow(blurRadius: 3, color: Colors.black),
                ])),
          ]),
        ),
      ]),
    );
  }
}

/// Character change while dead (applies at respawn).
class _CharPicker extends StatelessWidget {
  const _CharPicker(this.g);
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final p = g.me!;
    return SizedBox(
      width: 640,
      child: Panel(
        opacity: 0.92,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('캐릭터 변경 (부활할 때 적용)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Rps.gold)),
          const SizedBox(height: 8),
          for (final role in Role.values) ...[
            Row(children: [
              Icon(Rps.roleIcon(role), size: 16, color: Rps.role(role)),
              const SizedBox(width: 6),
              Text(role.label, style: TextStyle(color: Rps.role(role), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              for (final c in characters.where((c) => c.role == role))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => g.pickCharacter(c.id),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        side: BorderSide(color: c.id == p.charId ? Rps.gold : Colors.white24, width: c.id == p.charId ? 2 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        charIcon(c.id, 32),
                        const SizedBox(width: 6),
                        Text(c.name),
                      ]),
                    ),
                  ),
                ),
            ]),
          ],
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: g.toggleShop, child: const Text('닫기 (B)'))),
        ]),
      ),
    );
  }
}

class _Shop extends StatelessWidget {
  const _Shop(this.g);
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final p = g.me!;
    return SizedBox(
      width: 700,
      child: Panel(
        opacity: 0.92,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('상점', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Rps.gold)),
            const Spacer(),
            Text('${p.credits} ₵', style: const TextStyle(fontSize: 20, color: Rps.gold, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('죽으면 주무기를 잃습니다. 킬 +${Economy.kill} · 데스 +${Economy.death} · 어시스트 +${Economy.assist} · 거점 위 초당 +${Economy.capturePerSecond}',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 10),
          for (final slot in GunSlot.values) ...[
            Text(slot == GunSlot.primary ? '주무기' : '보조무기', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final gun in guns.where((x) => x.slot == slot)) _item(p, gun),
            ]),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: g.toggleShop, child: const Text('닫기 (B)')),
          ),
        ]),
      ),
    );
  }

  Widget _item(Player p, GunDef gun) {
    final owned = p.primary == gun.id || p.secondary == gun.id;
    final can = p.credits >= gun.stats.cost && !owned;
    final st = gun.stats;
    return InkWell(
      onTap: can ? () => g.buy(gun.id) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 208,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: owned ? Rps.navyMid : Rps.navy,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: owned ? Rps.gold : (can ? Colors.white30 : Colors.white10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: gunIcon(gun.id, 150, 50)),
          Row(children: [
            Expanded(child: Text(gun.name, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(owned ? '보유' : '${st.cost}',
                style: TextStyle(color: can || owned ? Rps.gold : Colors.white38, fontWeight: FontWeight.w700)),
          ]),
          Text(
            '${gun.info.gunClass} · 피해 ${st.damage.round()}${st.pellets > 1 ? '×${st.pellets}' : ''} · '
            '${(st.fireRate * 60).round()}RPM · ${st.mag}발',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ]),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard(this.s, this.p);
  final GameSim s;
  final Player p;

  @override
  Widget build(BuildContext context) {
    Widget table(int t) {
      final rows = s.team(t).toList()..sort((a, b) => b.kills.compareTo(a.kills));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t == p.team ? '우리 팀 (${Rps.teamName(t)})' : '적 팀 (${Rps.teamName(t)})',
            style: TextStyle(color: Rps.team(t), fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final q in rows)
          Container(
            color: q.id == p.id ? Colors.white10 : null,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 170, child: Text(q.name, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 70, child: Text(q.character.name, style: const TextStyle(fontSize: 12))),
              SizedBox(width: 90, child: Text('${q.kills} / ${q.deaths} / ${q.assists}')),
              SizedBox(width: 60, child: Text('${q.damageDealt.round()}', style: const TextStyle(fontSize: 12))),
              Icon(q.alive ? Icons.circle : Icons.close, size: 10, color: q.alive ? Colors.greenAccent : Colors.white38),
            ]),
          ),
      ]);
    }

    return Panel(
      opacity: 0.9,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${mapById(s.map.def.id).name} · 점령전', style: const TextStyle(color: Rps.gold, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        table(p.team),
        const SizedBox(height: 12),
        table(1 - p.team),
        const SizedBox(height: 6),
        const Text('이름 · 캐릭터 · 킬/데스/어시 · 피해', style: TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
    );
  }
}

class _Pause extends StatelessWidget {
  const _Pause(this.g, this.onLeave);
  final GameController g;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: g.requestLock,
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Panel(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/logo/wide.png', height: 70),
              const SizedBox(height: 10),
              const Text('화면을 클릭하면 게임으로 돌아갑니다', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              const Text(
                'WASD 이동 · 마우스 조준/사격 · 우클릭 정조준 · Space 점프 · Shift 앉기\n'
                'Q / E / C 스킬 · V 궁극기 · R 재장전 · 1/2/휠 무기 교체\n'
                'B 상점(스폰룸) · Tab 점수판 · Esc 메뉴',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton(onPressed: g.requestLock, child: const Text('계속')),
                const SizedBox(width: 10),
                OutlinedButton(onPressed: () => showSettings(context, Settings.I), child: const Text('설정')),
                const SizedBox(width: 10),
                OutlinedButton(onPressed: onLeave, child: const Text('나가기')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
