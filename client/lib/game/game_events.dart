part of 'game_controller.dart';

/// Turns sim events (shots, hits, kills, skills, capture...) into effects,
/// sounds and HUD state. Split out of game_controller.dart; same library, so
/// it can use the controller's private state.
extension _GameEvents on GameController {
  void _handle(List<Map<String, Object?>> events, GameSim s, Player me) {
    final js = engine.js;
    for (final e in events) {
      switch (e['e']) {
        case 'shot':
          final shooter = s.players[e['s']];
          final o = e['o'] as List;
          if (shooter == null) {
            // Turrets / sentries.
            for (final h in (e['h'] as List? ?? const [])) {
              final l = h as List;
              js.tracer((o[0] as num).toDouble(), (o[1] as num).toDouble() + 0.08, (o[2] as num).toDouble(),
                  (l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble(), (l[3] as num).toInt(), null);
            }
            engine.sfx('gun_smg_fire', vol: 0.5, rate: 1.3, pos: [for (final v in o) (v as num).toDouble()]);
            break;
          }
          final gun = gunById(isGun(e['g'] as String) ? e['g'] as String : 'pistol');
          final isMe = shooter.id == me.id;
          if (isMe) {
            final follow = switch (gun.id) { 'shotgun' => 'gun_shotgun_pump', 'sniper' => 'gun_sniper_bolt', _ => null };
            if (shooter.mode == 'shuriken') {
              js.vmModeAttack();
            } else {
              js.vmFire(gun.stats.fireRate, follow, gun.id == 'shotgun' ? 0.35 : 0.30);
            }
            engine.sfx(shooter.mode == 'shuriken' ? 'dash' : 'gun_${gun.id}_fire', vol: 0.75);
          } else {
            js.playerAction(shooter.id, 'fire');
            engine.sfx('gun_${gun.id}_fire', vol: 0.9, pos: [for (final v in o) (v as num).toDouble()]);
          }
          final hits = e['h'] as List?;
          if (hits != null) {
            // Tracers start near the muzzle for the local view.
            final ox = (o[0] as num).toDouble() + (isMe ? math.cos(yaw) * 0.12 : 0);
            final oz = (o[2] as num).toDouble() + (isMe ? math.sin(yaw) * 0.12 : 0);
            for (final h in hits) {
              final l = h as List;
              final from = isMe ? (shooter.mode.isEmpty ? 'vm'.toJS : null) : shooter.id.toJS;
              js.tracer(ox, (o[1] as num).toDouble(), oz, (l[0] as num).toDouble(), (l[1] as num).toDouble(),
                  (l[2] as num).toDouble(), (l[3] as num).toInt(), from);
            }
          }
        case 'reload':
          final q = s.players[e['p']];
          if (q == null) break;
          final gs = q.gun.stats;
          if (q.id == me.id) {
            js.vmPlayFor('reload', gs.reloadTime);
            engine.sfx('gun_${q.gunId}_reload', vol: 0.7, rate: 1.85 / gs.reloadTime);
          } else {
            js.playerAction(q.id, 'reload');
            engine.sfx('gun_${q.gunId}_reload', vol: 0.6, rate: 1.85 / gs.reloadTime, pos: [q.pos.x, q.pos.y, q.pos.z]);
          }
        case 'hit':
          if (e['s'] == me.id) {
            hitmarker = 0.18;
            hitHead = e['h'] == true;
            final v = s.players[e['v']];
            // Damage numbers only for hits you land yourself, not for what
            // your turrets, traps, areas or reflects do on their own.
            if (v != null && !_autoDamage.contains(e['w'])) engine.sfx('hit_tick', vol: e['h'] == true ? 0.8 : 0.55);
            if (v != null && !_autoDamage.contains(e['w'])) {
              final kind = e['sh'] == 1 ? 2 : (e['h'] == true ? 1 : 0);
              js.damageNumber(v.id, v.pos.x, v.pos.y + v.body.headCenter + 0.35, v.pos.z, (e['a'] as num).toDouble(), kind);
            }
          }
          if (e['v'] != me.id) js.playerAction((e['v'] as num).toInt(), 'hit');
          if (e['v'] == me.id) {
            if (_t - _lastHurt > 0.18) {
              _lastHurt = _t;
              engine.sfx('hurt', vol: 0.6);
            }
            damageFlash = 0.6;
            final a = s.players[e['s']];
            if (a != null) damageDir = wrapAngle(yawTo(me.pos, a.pos) - yaw);
          }
        case 'kill':
          _onKill(s, me, e);
        case 'explode':
          final p = e['p'] as List;
          final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble(), z = (p[2] as num).toDouble();
          final g = e['g'] as String? ?? '';
          final heal = g == 'stitch_grenade';
          if (!heal) js.explosion(x, y, z, (e['r'] as num).toDouble());
          if (g == 'quake_trap') {
            engine.sfx('trap_trigger', vol: 0.9, pos: [x, y, z]);
          } else if (_bigBlasts.contains(g)) {
            engine.sfx('gun_launcher_explosion', vol: 1, pos: [x, y, z]);
          } else {
            engine.sfx(heal ? 'shield_up' : 'explosion_small', vol: 0.9, pos: [x, y, z]);
          }
        case 'spawn':
          if (e['p'] == me.id) {
            js.setGrayscale(false);
            killedBy = null;
            _deathEye = null;
            yaw = me.yaw;
            pitch = 0;
            _vmKey = '';
          }
        case 'blink' || 'rewind':
          final a = (e['a'] as List).map((v) => (v as num).toDouble()).toList();
          final b = (e['b'] as List).map((v) => (v as num).toDouble()).toList();
          engine.sfx('dash', vol: e['p'] == me.id ? 0.7 : 0.8, pos: e['p'] == me.id ? null : b);
          js.skillFx(e['e'] as String, a[0], a[1], a[2], b[0], b[1], b[2], 0);
          if (e['p'] == me.id && e['e'] == 'rewind') _toast(tr('되감기!', 'Rewind!'));
        case 'reveal':
          final a = (e['p'] as List).map((v) => (v as num).toDouble()).toList();
          final r = (e['r'] as num).toDouble();
          if (r <= 1.0) engine.sfx('trap_trigger', vol: 0.8, pos: a);
          if (e['t'] == me.team) {
            js.skillFx('reveal', a[0], a[1], a[2], 0, 0, 0, r);
            final n = (e['ids'] as List).length;
            _toast(n > 0 ? tr('정찰: 적 $n명 위치 공개', 'Recon: $n enemies revealed') : tr('정찰: 주변에 적 없음', 'Recon: no enemies nearby'));
          }
        case 'cone' || 'slam' || 'updraft':
          final a = (e[e['e'] == 'slam' ? 'p' : (e['e'] == 'updraft' ? 'a' : 'p')] as List)
              .map((v) => (v as num).toDouble())
              .toList();
          js.burst(a[0], a[1] + 0.3, a[2], e['e'] == 'updraft' ? 0xf4eee2 : 0xc9a26b,
              e['e'] == 'cone' ? 4.0 : 1.4, 0.4);
          if (e['e'] != 'updraft') engine.sfx('gun_launcher_explosion', vol: 0.7, rate: 0.8, pos: a);
        case 'pull':
          final b = (e['b'] as List).map((v) => (v as num).toDouble()).toList();
          js.burst(b[0], b[1] + 1, b[2], 0xe8b04a, 0.8, 0.3);
        case 'buff':
          final q = s.players[e['p']];
          if (q != null) {
            js.burst(q.pos.x, q.pos.y + 1, q.pos.z, e['k'] == 'sleep_dart' ? 0xb46bff : 0x7dffb0, 1.0, 0.45);
            if (q.id == me.id) _toast(_buffName(e['k'] as String));
            if (_shieldBuffs.contains(e['k'])) {
              engine.sfx('shield_up', vol: 0.8, pos: q.id == me.id ? null : [q.pos.x, q.pos.y, q.pos.z]);
            }
          }
        case 'deploy':
          if (e['t'] == me.team || !_hiddenTraps.contains(e['k'])) {
            final a = (e['p'] as List).map((v) => (v as num).toDouble()).toList();
            engine.sfx('deploy', vol: 0.8, pos: a);
            js.burst(a[0], a[1] + 0.3, a[2], e['t'] == me.team ? 0x4dc9ff : 0xff5a4a, 0.7, 0.3);
          }
        case 'stick':
          final a = (e['p'] as List).map((v) => (v as num).toDouble()).toList();
          js.skillFx('stick', a[0], a[1], a[2], 0, 0, 0, 0);
          if (e['on'] == me.id) _toast(tr('점착 폭약이 붙었습니다!', 'A sticky charge is stuck to you!'));
        case 'link':
          final q = s.players[e['t']];
          if (q != null) engine.sfx('heal_loop', vol: 0.5, pos: q.id == me.id ? null : [q.pos.x, q.pos.y, q.pos.z]);
        case 'easter':
          if (e['p'] == me.id && e['k'] == 'origami_snipe') {
            _banner(tr('이스터에그! 종이학 저격수 - 궁극기 2연속 (V)', 'Easter egg! Paper sniper - double ultimate (V)'));
            engine.sfx('ult_ready', vol: 0.9);
          }
        case 'skill':
          final q = s.players[e['p']];
          final sid = e['id'] as String? ?? '';
          if (q != null && q.id == me.id) {
            if (_throwSkills.contains(sid)) js.vmSkill('throw', skillFiles[sid] ?? '');
            if (_placeSkills.contains(sid)) js.vmSkill('place', skillFiles[sid] ?? '');
          }
          if (q != null && _dashSkills.contains(sid)) {
            engine.sfx('dash', vol: 0.8, pos: q.id == me.id ? null : [q.pos.x, q.pos.y, q.pos.z]);
          }
          if (q != null && q.id == me.id && e['k'] == SkillKey.ult.index) _banner('${skillName(q.character.info.skill(SkillKey.ult))}!');
        case 'swing':
          if (e['s'] == me.id) js.vmModeAttack();
          engine.sfx('dash', vol: 0.5, rate: 1.3);
        case 'live':
          _banner(tr('전투 시작! 중앙 거점을 점령하세요', 'Fight! Capture the central point'));
        case 'captured':
          final t = e['t'] as int;
          _banner(t == me.team ? tr('거점 점령!', 'Point captured!') : tr('적이 거점을 점령했습니다', 'The enemy captured the point'));
          engine.sfx(t == me.team ? 'point_captured' : 'point_lost', vol: 0.9);
        case 'end':
          final w = e['w'] as int;
          _banner(w < 0 ? tr('무승부', 'Draw') : (w == me.team ? tr('승리!', 'Victory!') : tr('패배', 'Defeat')));
          js.matchEnd(w == me.team);
          bannerTime = 99;
          ended = 0;
          engine.input.unlock();
      }
    }
  }

  void _onKill(GameSim s, Player me, Map<String, Object?> e) {
    final js = engine.js;
    final k = e['k'] == null ? null : s.players[e['k']];
    final v = s.players[e['v']];
    if (v == null) return;
    final head = e['h'] == true;
    final w = (e['w'] as String?) ?? '';
    feed.insert(
        0,
        KillFeedEntry(k?.name ?? '', k?.team ?? -1, v.name, v.team, isGun(w) ? gunName(w) : _deathName(w), head, _t)
          ..killerId = k?.id ?? -1
          ..victimId = v.id
          ..weaponId = w);
    if (feed.length > 6) feed.removeLast();
    if (k?.id == me.id) {
      js.killBadge(e['badge'] as String);
      engine.sfx(head ? 'headshot_ding' : 'kill_ding', vol: 0.9);
    }
    final fx = e['fx'] as String;
    if (v.id == me.id) {
      // Death: freeze camera, grey screen, a ghost floats up in front of us.
      killedBy = k?.id;
      final eye = v.eye;
      _deathEye = eye;
      _deathYaw = yaw;
      _deathPitch = clampD(pitch, -0.3, 0.2);
      js.setGrayscale(true);
      final f = dirFromAngles(yaw, 0);
      js.deathGhost(fx, eye.x + f.x * 2.2, eye.y - 0.9, eye.z + f.z * 2.2, -yaw);
      engine.sfx(fx, vol: 0.9);
      shopOpen = false;
    } else if (v.pos.distanceTo(me.pos) < 40) {
      js.deathGhost(fx, v.pos.x, v.pos.y, v.pos.z, -yawTo(v.pos, me.pos));
      engine.sfx(fx, vol: 0.5, pos: [v.pos.x, v.pos.y + 1, v.pos.z]);
    }
  }

  String _buffName(String k) => switch (k) {
        'cleanse_bell' => tr('정화! 잠시 무적', 'Cleansed! Briefly invulnerable'),
        'sleep_dart' => tr('잠들었습니다... 피해를 받으면 깨어납니다', 'Asleep... taking damage wakes you'),
        'nano_stitch' => tr('나노 봉합: 공격력↑ 받는 피해↓', 'Nano Stitch: damage↑ damage taken↓'),
        'ward_talisman' => tr('수호 부적 보호막', 'Ward Talisman shield'),
        'grand_scroll' => tr('대두루마리 보호막!', 'Grand Scroll shield!'),
        'overheat' => tr('과열! 가속', 'Overheat! Haste'),
        _ => k,
      };

  String _deathName(String w) => switch (w) {
        'fall' || 'fall_assist' => tr('낙사', 'Fell'),
        'spawn' => tr('스폰 보호구역', 'Spawn zone'),
        _ => _skillName(w) ?? w,
      };

  static String? _skillName(String id) {
    for (final c in characterInfos) {
      for (final s in c.skills) {
        if (s.id == id) return s.name;
      }
    }
    return null;
  }
}
