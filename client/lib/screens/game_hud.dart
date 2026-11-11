part of 'game_screen.dart';

const Color _armorColor = Color(0xFF8FD3FF);

// In-game HUD pieces: crosshair, scope, damage vignette, capture bar,
// kill feed, vitals, skill slots, ammo, banners, objective marker.

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
          Text(t == mine ? tr('우리 팀', 'Allies') : tr('적 팀', 'Enemies'), style: const TextStyle(fontSize: 11)),
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
          Text('${tr('거점', 'On point')} ${s.onPoint[mine]} : ${s.onPoint[other]}', style: const TextStyle(fontSize: 11)),
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
              Text(playerName(e.killer), style: TextStyle(color: Rps.team(e.killerTeam), fontWeight: FontWeight.w700)),
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
            Text(playerName(e.victim), style: TextStyle(color: Rps.team(e.victimTeam), fontWeight: FontWeight.w700)),
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
          Text(charName(c.id), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Text('${p.credits} ₵', style: const TextStyle(color: Rps.gold, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('${p.hp.ceil()}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          Text(' / ${p.maxHp.round()}', style: const TextStyle(fontSize: 14)),
        ]),
        if (p.armor > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              const Icon(Icons.shield, size: 14, color: _armorColor),
              const SizedBox(width: 4),
              SizedBox(
                width: 160,
                child: LinearProgressIndicator(
                  value: (p.armor / 100).clamp(0, 1),
                  minHeight: 5,
                  color: _armorColor,
                  backgroundColor: Colors.white12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text('${p.armor.ceil()}', style: const TextStyle(fontSize: 12, color: _armorColor, fontWeight: FontWeight.w800)),
            ]),
          ),
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

  static Map<String, (String, Color)> get _labels => {
        'slow': (tr('둔화', 'Slowed'), Rps.blue),
        'root': (tr('속박', 'Rooted'), const Color(0xFFB46BFF)),
        'sleep': (tr('수면', 'Asleep'), const Color(0xFFB46BFF)),
        'stun': (tr('기절', 'Stunned'), const Color(0xFFB46BFF)),
        'amp': (tr('공격력↑', 'Damage↑'), Rps.gold),
        'haste': (tr('가속', 'Haste'), Rps.gold),
        'prot': (tr('받는 피해↓', 'Dmg taken↓'), Rps.gold),
        'vuln': (tr('받는 피해↑', 'Dmg taken↑'), Rps.danger),
        'invuln': (tr('무적', 'Invulnerable'), Colors.white),
        'undying': (tr('불사', 'Undying'), Colors.white),
        'antiheal': (tr('치유 차단', 'Anti-heal'), Rps.danger),
        'healboost': (tr('치유 증가', 'Heal boost'), const Color(0xFF7DFFB0)),
      };

  @override
  Widget build(BuildContext context) {
    final chips = <(String, Color)>[];
    for (final e in _labels.entries) {
      if ((p.fx[e.key] ?? 0) > 0) chips.add(('${e.value.$1} ${p.fx[e.key]!.toStringAsFixed(1)}', e.value.$2));
    }
    if (p.alive && p.spawnProtect > 0) {
      chips.add(('${tr('부활 무적', 'Spawn invulnerable')} ${p.spawnProtect.toStringAsFixed(1)}', Colors.white));
    }
    final sh = p.fx['shield'] ?? 0;
    if (sh > 0) chips.add(('${tr('보호막', 'Shield')} ${sh.ceil()}', const Color(0xFF6FC3FF)));
    final mode = switch (p.mode) {
      'shuriken' => '${tr('표창', 'Shuriken')} ×${(p.fx['modeAmmo'] ?? 0).toInt()}',
      'twin' => tr('쌍날 개방', 'Twin Edge'),
      'roll' => tr('구르기: 이속↑ 받는 피해 -50% · 사격 불가 (E로 해제)', 'Rolling: faster, -50% damage taken, no shooting (E to stop)'),
      'guard' => tr('가시 방패 (Q로 해제)', 'Spike Guard (Q to stop)'),
      'deflect' => tr('튕겨내기', 'Deflect'),
      _ => null,
    };
    if (mode != null) chips.add(('$mode ${(p.fx['modeT'] ?? 0).toStringAsFixed(1)}', Rps.gold));
    if (p.fx.containsKey('linkTo')) chips.add((tr('치유 연결 중', 'Healing link'), const Color(0xFF7DFFB0)));
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
      message: '${skillName(sk)}: ${skillDesc(sk)}',
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
                ? tr('준비중', 'N/A')
                : ult
                    ? '${(frac * 100).floor()}%'
                    : (cd > 0 && charges == 0)
                        ? cd.toStringAsFixed(cd < 3 ? 1 : 0)
                        : (maxC > 1 ? '×$charges' : tr('준비', 'Ready')),
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
          Text(gunName(g.id), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        if (p.reloadTimer > 0)
          SizedBox(
            width: 140,
            child: LinearProgressIndicator(
                value: 1 - p.reloadTimer / g.stats.reloadTime, color: Rps.gold, backgroundColor: Colors.white12),
          ),
        const SizedBox(height: 4),
        Text(
          isEn
              ? '1 primary${p.primary == null ? ' (none)' : ''}  2 sidearm  R reload  ${inSpawn ? 'B shop' : ''}'
              : '1 주무기${p.primary == null ? '(없음)' : ''}  2 보조  R 재장전  ${inSpawn ? 'B 상점' : ''}',
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
              TextSpan(text: playerName(k.name), style: TextStyle(color: Rps.team(k.team), fontWeight: FontWeight.w800)),
              TextSpan(text: tr(' (${charName(k.charId)}, ${gunName(k.gunId)}) 에게 당했습니다', ' (${charName(k.charId)}, ${gunName(k.gunId)}) got you')),
            ])),
          const SizedBox(height: 4),
          Text(tr('${p.respawnIn.ceil()}초 후 부활', 'Respawn in ${p.respawnIn.ceil()}s'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('B 캐릭터 변경', 'B change character'), style: const TextStyle(fontSize: 12, color: Rps.gold)),
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
