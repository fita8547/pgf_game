part of 'game_screen.dart';

// Full-screen/menu overlays: character picker, shop, scoreboard, pause.

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
          Text(tr('캐릭터 변경 (부활할 때 적용)', 'Change character (applies on respawn)'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Rps.goldText)),
          const SizedBox(height: 8),
          for (final role in Role.values) ...[
            Row(children: [
              Icon(Rps.roleIcon(role), size: 16, color: Rps.role(role)),
              const SizedBox(width: 6),
              Text(roleName(role), style: TextStyle(color: Rps.role(role), fontWeight: FontWeight.w800)),
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
                        side: BorderSide(color: c.id == p.charId ? Rps.gold : Rps.fg(0.24), width: c.id == p.charId ? 2 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        charIcon(c.id, 32),
                        const SizedBox(width: 6),
                        Text(charName(c.id)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ],
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: g.toggleShop, child: Text(tr('닫기 (B)', 'Close (B)')))),
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 700, maxHeight: MediaQuery.of(context).size.height - 24),
      child: Panel(
        opacity: 0.92,
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(tr('상점', 'Shop'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Rps.goldText)),
            const Spacer(),
            Text('${p.credits} ₵', style: TextStyle(fontSize: 20, color: Rps.goldText, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(tr('죽으면 주무기와 방어구를 잃습니다. 킬 +${Economy.kill} · 데스 +${Economy.death} · 어시스트 +${Economy.assist} · 거점 위 초당 +${Economy.capturePerSecond}',
                  'You lose your primary and armor on death. Kill +${Economy.kill} · Death +${Economy.death} · Assist +${Economy.assist} · On point +${Economy.capturePerSecond}/s'),
              style: TextStyle(fontSize: 12, color: Rps.fg(0.60))),
          const SizedBox(height: 10),
          for (final slot in GunSlot.values) ...[
            Text(slot == GunSlot.primary ? tr('주무기', 'Primary') : tr('보조무기', 'Sidearm'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final gun in guns.where((x) => x.slot == slot)) _item(p, gun),
            ]),
            const SizedBox(height: 10),
          ],
          Text(tr('방어구 (체력보다 먼저 피해를 받음)', 'Armor (takes damage before HP)'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final a in armors) _armor(p, a)]),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: g.toggleShop, child: Text(tr('닫기 (B)', 'Close (B)'))),
          ),
        ])),
      ),
    );
  }

  Widget _armor(Player p, ArmorDef a) {
    final have = p.armor >= a.amount;
    final can = !have && p.credits >= a.cost;
    return InkWell(
      onTap: can ? () => g.buy(a.id) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 208,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: have ? Rps.navyMid : Rps.navy,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: have ? Rps.gold : (can ? Rps.fg(0.30) : Rps.fg(0.10))),
        ),
        child: Row(children: [
          Icon(Icons.shield, color: can || have ? _armorColor : Rps.fg(0.24), size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(armorName(a), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('+${a.amount.round()}', style: TextStyle(fontSize: 12, color: Rps.fg(0.70))),
            ]),
          ),
          Text(have ? tr('보유', 'Owned') : '${a.cost}',
              style: TextStyle(color: can || have ? Rps.goldText : Rps.fg(0.38), fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _item(Player p, GunDef gun) {
    final owned = p.primary == gun.id || p.secondary == gun.id;
    final full = owned && GameSim.ammoFull(p, gun);
    final price = owned ? GameSim.refillCost(gun) : gun.stats.cost;
    final can = p.credits >= price && !full;
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
          border: Border.all(color: owned ? Rps.gold : (can ? Rps.fg(0.30) : Rps.fg(0.10))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: gunIcon(gun.id, 150, 50)),
          Row(children: [
            Expanded(child: Text(gunName(gun.id), style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(full ? tr('보유 · 탄약 가득', 'Owned · full') : (owned ? tr('탄약 보충 $price', 'Refill $price') : '${st.cost}'),
                style: TextStyle(color: can || owned ? Rps.goldText : Rps.fg(0.38), fontWeight: FontWeight.w700)),
          ]),
          Text(
            '${gunClass(gun)} · ${tr('피해', 'Dmg')} ${st.damage.round()}${st.pellets > 1 ? '×${st.pellets}' : ''} · '
            '${(st.fireRate * 60).round()}RPM · ${st.mag}${tr('발', ' rds')}',
            style: TextStyle(fontSize: 11, color: Rps.fg(0.70)),
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
        Text(t == p.team ? tr('우리 팀 (${Rps.teamName(t)})', 'Allies (${Rps.teamName(t)})') : tr('적 팀 (${Rps.teamName(t)})', 'Enemies (${Rps.teamName(t)})'),
            style: TextStyle(color: Rps.team(t), fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final q in rows)
          Container(
            color: q.id == p.id ? Rps.fg(0.10) : null,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 170, child: Text(playerName(q.name), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 70, child: Text(charName(q.charId), style: const TextStyle(fontSize: 12))),
              SizedBox(width: 90, child: Text('${q.kills} / ${q.deaths} / ${q.assists}')),
              SizedBox(width: 60, child: Text('${q.damageDealt.round()}', style: const TextStyle(fontSize: 12))),
              Icon(q.alive ? Icons.circle : Icons.close, size: 10, color: q.alive ? Colors.greenAccent : Rps.fg(0.38)),
            ]),
          ),
      ]);
    }

    return Panel(
      opacity: 0.9,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${mapName(s.map.def.id)} · ${tr('점령전', 'Capture')}', style: TextStyle(color: Rps.goldText, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        table(p.team),
        const SizedBox(height: 12),
        table(1 - p.team),
        const SizedBox(height: 6),
        Text(tr('이름 · 캐릭터 · 킬/데스/어시 · 피해', 'Name · Character · K/D/A · Damage'), style: TextStyle(fontSize: 11, color: Rps.fg(0.54))),
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
    final touch = Engine.I.input.isTouch();
    return GestureDetector(
      onTap: g.requestLock,
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Panel(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/logo/wide.png', height: touch ? 44 : 70),
              const SizedBox(height: 10),
              Text(touch ? tr('화면을 터치하면 게임으로 돌아갑니다', 'Tap the screen to return to the game') : tr('화면을 클릭하면 게임으로 돌아갑니다', 'Click the screen to return to the game'),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              Text(
                touch
                    ? tr(
                        '왼쪽 엄지: 이동 · 오른쪽 드래그: 시점 · 발사 버튼을 누른 채 끌면 조준하며 사격\n'
                            '조준·앉기는 눌러서 켜고 끄기 · Q/E/C 스킬 · 궁 = 궁극기 · ☰ 메뉴',
                        'Left thumb: move · Right drag: look · Hold and drag Fire to aim while shooting\n'
                            'ADS/crouch toggle on tap · Q/E/C skills · ULT = ultimate · ☰ menu')
                    : tr(
                        'WASD 이동 · 마우스 조준/사격 · 우클릭 정조준 · Space 점프 · Shift 앉기\n'
                            'Q / E / C 스킬 · V 궁극기 · R 재장전 · 1/2/휠 무기 교체\n'
                            'B 상점(스폰룸) · Tab 점수판 · Esc 메뉴',
                        'WASD move · Mouse aim/shoot · Right-click ADS · Space jump · Shift crouch\n'
                            'Q / E / C skills · V ultimate · R reload · 1/2/wheel switch weapon\n'
                            'B shop (spawn room) · Tab scoreboard · Esc menu'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Rps.fg(0.70)),
              ),
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton(onPressed: g.requestLock, child: Text(tr('계속', 'Resume'))),
                const SizedBox(width: 10),
                OutlinedButton(onPressed: () => showSettings(context, Settings.I), child: Text(tr('설정', 'Settings'))),
                const SizedBox(width: 10),
                OutlinedButton(onPressed: onLeave, child: Text(tr('나가기', 'Leave'))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
