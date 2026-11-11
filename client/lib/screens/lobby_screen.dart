import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';

import '../engine/engine.dart';
import '../game/net_client.dart';
import '../ui/settings.dart';
import '../ui/settings_dialog.dart';
import '../ui/i18n.dart';
import '../ui/theme.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.onPlay, required this.onPlayOnline, required this.onBack});
  final VoidCallback onPlay;
  final VoidCallback onPlayOnline;
  final VoidCallback onBack;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final s = Settings.I;
  String previewGun = 'rifle';
  late final TextEditingController _name = TextEditingController(text: playerName(s.name));
  late final TextEditingController _server = TextEditingController(text: s.server);

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    super.dispose();
  }

  void _saveFields() {
    final n = _name.text.trim();
    s.name = n.isEmpty ? tr('플레이어', 'Player') : (n.length > 16 ? n.substring(0, 16) : n);
    s.server = _server.text.trim();
    s.save();
  }

  @override
  void initState() {
    super.initState();
    if (!isCharacter(s.charId)) s.charId = characters.first.id;
    _show();
  }

  void _show() {
    Engine.I.js.showLobby(s.charId, previewGun);
    Engine.I.js.setLobbyOffset(0.42);
  }

  void _pick(String id) {
    setState(() => s.charId = id);
    s.save();
    _show();
  }

  @override
  Widget build(BuildContext context) {
    final ch = characterById(s.charId);
    return Stack(children: [
      // Soft vignette so the 3D model reads against the page background.
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Rps.navyDeep, Color(0xCC121842), Color(0x55121842)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
      ),
      Positioned(
        left: 24,
        top: 20,
        bottom: 20,
        width: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back, color: Rps.cream)),
            Image.asset('assets/logo/wide.png', height: 54),
          ]),
          const SizedBox(height: 10),
          Expanded(child: SingleChildScrollView(child: _roster())),
          const SizedBox(height: 10),
          _details(ch),
        ]),
      ),
      Positioned(
        right: 24,
        top: 20,
        child: IconButton(
          onPressed: () => showSettings(context, s),
          icon: const Icon(Icons.settings, color: Rps.cream),
          tooltip: tr('설정', 'Settings'),
        ),
      ),
      Positioned(right: 24, bottom: 20, width: 460, child: _matchPanel()),
      Positioned(right: 24, top: 80, width: 460, child: _gunPreview()),
    ]);
  }

  Widget _roster() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final role in Role.values) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            roleIcon(role, 22),
            const SizedBox(width: 6),
            Text(roleName(role), style: TextStyle(color: Rps.role(role), fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(roleTraits(role),
                style: TextStyle(color: Rps.cream.withValues(alpha: 0.6), fontSize: 12)),
          ]),
        ),
        Row(children: [
          for (final c in characters.where((c) => c.role == role)) Expanded(child: _card(c)),
        ]),
      ],
    ]);
  }

  Widget _card(CharacterDef c) {
    final sel = c.id == s.charId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => _pick(c.id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: sel ? Rps.navyMid : Rps.navy.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? Rps.gold : Rps.role(c.role).withValues(alpha: 0.4), width: sel ? 2 : 1),
          ),
          child: Row(children: [
            charIcon(c.id, 44),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(charName(c.id), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(charOrigin(c.info),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Rps.cream.withValues(alpha: 0.7))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _details(CharacterDef c) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          charIcon(c.id, 48),
          const SizedBox(width: 8),
          Text(charName(c.id), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Rps.gold)),
          const SizedBox(width: 10),
          Chip(
            label: Text(roleName(c.role)),
            avatar: roleIcon(c.role, 18),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          Text(_profile(c), style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        for (final sk in c.info.skills)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sk.key == SkillKey.ult ? Rps.gold : Rps.navyMid,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(skillKeyLabel(sk.key),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: sk.key == SkillKey.ult ? Rps.navyDeep : Rps.cream)),
              ),
              const SizedBox(width: 6),
              skillIcon(sk.id, 26),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${skillName(sk)}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: '${skillDesc(sk)} (${skillCd(sk)})',
                      style: TextStyle(color: Rps.cream.withValues(alpha: 0.75), fontSize: 13)),
                ])),
              ),
            ]),
          ),
        Text(tr('스킬 사용 · Q / E / C / V(궁극기)', 'Skills · Q / E / C / V (ultimate)'), style: const TextStyle(fontSize: 12, color: Rps.gold)),
      ]),
    );
  }

  /// "체력 300 · 받는 피해 75% · 주는 피해 80% ..." for the selected character.
  static String _profile(CharacterDef c) {
    final s = c.stats;
    String pct(double v) => '${(v * 100).round()}%';
    return [
      '${tr('체력', 'HP')} ${c.maxHp.round()}',
      '${tr('받는 피해', 'Dmg taken')} ${pct(s.damageTaken)}',
      '${tr('주는 피해', 'Dmg dealt')} ${pct(s.damageDealt * c.damageMul)}',
      if (s.skillPower != 1) '${tr('스킬 피해', 'Skill dmg')} ${pct(s.skillPower)}',
      if (s.skillCooldown != 1) '${tr('쿨타임', 'Cooldown')} ${pct(s.skillCooldown)}',
      if (s.healPower != 1) '${tr('치유', 'Healing')} ${pct(s.healPower)}',
      '${tr('속도', 'Speed')} ${c.speed}',
    ].join(' · ');
  }

  Widget _gunPreview() {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('총 미리보기 (게임 안 상점에서 구매)', 'Gun preview (buy them in the in-game shop)'), style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final g in guns)
            ChoiceChip(
              avatar: gunIcon(g.id, 34, 13),
              label: Text(gunName(g.id), style: const TextStyle(fontSize: 12)),
              selected: previewGun == g.id,
              onSelected: (_) {
                setState(() => previewGun = g.id);
                _show();
              },
            ),
        ]),
      ]),
    );
  }

  Widget _matchPanel() {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('맵', 'Map'), style: const TextStyle(fontWeight: FontWeight.w800, color: Rps.gold)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in maps)
            ChoiceChip(
              label: Text(mapName(m.id)),
              selected: s.mapId == m.id,
              onSelected: (_) {
                setState(() => s.mapId = m.id);
                s.save();
              },
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text(tr('봇 난이도', 'Bot skill')),
          Expanded(
            child: Slider(
              value: s.botSkill,
              divisions: 4,
              label: (isEn ? ['Very easy', 'Easy', 'Normal', 'Hard', 'Very hard'] : ['매우 쉬움', '쉬움', '보통', '어려움', '매우 어려움'])[(s.botSkill * 4).round()],
              onChanged: (v) => setState(() => s.botSkill = v),
              onChangeEnd: (_) => s.save(),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('닉네임', 'Nickname'), isDense: true),
              onChanged: (_) => _saveFields(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _server,
              decoration: InputDecoration(
                  labelText: tr('서버 주소 (비우면 이 페이지의 서버)', 'Server address (empty = this page\'s server)'), hintText: NetClient.defaultUrl(), isDense: true),
              onChanged: (_) => _saveFields(),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () {
                _saveFields();
                widget.onPlay();
              },
              child: Text(tr('봇 연습', 'Practice vs bots')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Rps.blue, foregroundColor: Colors.white),
              onPressed: () {
                _saveFields();
                widget.onPlayOnline();
              },
              child: Text(tr('온라인 참가', 'Join online')),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('봇 연습: 이 맵·난이도로 5대5 · 온라인: 서버의 맵 순환을 따름', 'Practice: 5v5 on this map and bot skill · Online: follows the server\'s map rotation'),
            style: TextStyle(fontSize: 11, color: Rps.cream.withValues(alpha: 0.6))),
      ]),
    );
  }
}
