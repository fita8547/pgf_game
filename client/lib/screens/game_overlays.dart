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
          border: Border.all(color: owned ? Rps.gold : (can ? Colors.white30 : Colors.white10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: gunIcon(gun.id, 150, 50)),
          Row(children: [
            Expanded(child: Text(gun.name, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(full ? '보유 · 탄약 가득' : (owned ? '탄약 보충 $price' : '${st.cost}'),
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
              Text(touch ? '화면을 터치하면 게임으로 돌아갑니다' : '화면을 클릭하면 게임으로 돌아갑니다',
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              Text(
                touch
                    ? '왼쪽 엄지: 이동 · 오른쪽 드래그: 시점 · 발사 버튼을 누른 채 끌면 조준하며 사격\n'
                        '조준·앉기는 눌러서 켜고 끄기 · Q/E/C 스킬 · 궁 = 궁극기 · ☰ 메뉴'
                    : 'WASD 이동 · 마우스 조준/사격 · 우클릭 정조준 · Space 점프 · Shift 앉기\n'
                        'Q / E / C 스킬 · V 궁극기 · R 재장전 · 1/2/휠 무기 교체\n'
                        'B 상점(스폰룸) · Tab 점수판 · Esc 메뉴',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
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
