part of 'game_controller.dart';

/// Agent voice lines (song/voice -> web/game/voice): which line plays when,
/// who hears it, and the subtitle under the crosshair. The engine picks the
/// line, plays it on the "voice" volume bus and reports the caption.
///
/// Heard by: own lines and allies' radio lines (kill, death, respawn...) for
/// the team; skill shouts for everyone nearby (positional); ultimate lines
/// for everyone (ally line vs enemy line).
class _VoiceState {
  final Map<int, double> lastSkill = {}; // speaker -> time of last skill shout
  final Map<int, double> lastKill = {}; // killer -> time of last kill
  double lowHpAt = -99;
  double captureAt = -99;
  bool wasLowHp = false;
  bool wasInZone = false;
  int captionSeq = 0;
}

extension _GameVoice on GameController {
  /// [speaker] talks: line of [event] for their character. [pos]: heard from
  /// where they stand (null = radio / own voice).
  void _say(Player speaker, String event, {bool important = false, bool positional = false}) {
    final pos = positional && speaker.id != me?.id ? [speaker.pos.x, speaker.pos.y + 1.5, speaker.pos.z] : null;
    engine.audio.voice(speaker.charId, event, speaker.id, important, pos == null ? null : [for (final v in pos) v.toJS].toJS);
  }

  bool _ally(Player me, Player q) => q.team == me.team;

  // --------------------------------------------------------- from events --
  void _voiceSkill(Player me, Player q, int key) {
    if (key == SkillKey.ult.index) {
      _say(q, _ally(me, q) ? 'ult_ally' : 'ult_enemy', important: true);
      return;
    }
    // One shout per speaker every 2 s (charges, recasts).
    if (_t - (_voice.lastSkill[q.id] ?? -99) < 2) return;
    _voice.lastSkill[q.id] = _t;
    final ev = switch (key) { 0 => 'skill_q', 1 => 'skill_e', _ => 'skill_shift' };
    _say(q, ev, positional: true);
  }

  void _voiceKill(Player me, Player? k, Player v) {
    if (k != null && k.id != v.id && _ally(me, k)) {
      final multi = _t - (_voice.lastKill[k.id] ?? -99) < 4;
      _voice.lastKill[k.id] = _t;
      _say(k, multi ? 'multikill' : 'kill');
    } else if (_ally(me, v)) {
      _say(v, 'death');
    }
  }

  void _voiceSpawn(GameSim s, Player me, Player q) {
    if (s.phase != Phase.live || !_ally(me, q)) return; // not the pre-match spawn
    _say(q, 'respawn');
  }

  void _voiceLive(GameSim s, Player me) {
    _say(me, 'match_start', important: true);
    // A bit later: banter between two teammates, when their pair has some.
    final team = {for (final q in s.players.values) if (q.team == me.team) q.charId}.join(',');
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!_disposed) engine.audio.voiceTalk(team);
    });
  }

  void _voiceCaptured(Player me, int team) => _say(me, team == me.team ? 'point_captured' : 'point_losing', important: true);

  void _voiceEnd(Player me, int winner) {
    if (winner >= 0) _say(me, winner == me.team ? 'victory' : 'defeat', important: true);
  }

  void _voiceReload(Player me) {
    if (math.Random().nextDouble() < 0.25) _say(me, 'reload');
  }

  // ------------------------------------------------------------ per tick --
  void _voiceTick(GameSim s, Player me, bool ultJustReady) {
    if (ultJustReady) _say(me, 'ult_ready');
    final low = me.alive && me.hp < me.maxHp * 0.3;
    if (low && !_voice.wasLowHp && _t - _voice.lowHpAt > 12) {
      _voice.lowHpAt = _t;
      _say(me, 'low_hp');
    }
    _voice.wasLowHp = low;
    final inZone = me.alive && s.phase == Phase.live && s.map.inCapture(me.pos);
    if (inZone && !_voice.wasInZone && _t - _voice.captureAt > 20) {
      _voice.captureAt = _t;
      _say(me, 'capture_start');
    }
    _voice.wasInZone = inZone;

    // Subtitle of the line the engine just started.
    final c = engine.audio.voiceCaption();
    if (c.isNotEmpty) {
      final parts = c.split('|');
      final seq = int.tryParse(parts[0]) ?? 0;
      if (seq != _voice.captionSeq && parts.length >= 3) {
        _voice.captionSeq = seq;
        final who = isCharacter(parts[1]) ? charName(parts[1]) : parts[1];
        caption = '$who: ${parts.sublist(2).join('|')}';
        captionTime = 3.5;
      }
    }
  }
}
