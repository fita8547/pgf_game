import 'package:pgf_shared/pgf_shared.dart';
import 'package:test/test.dart';

void main() {
  test('bot-only match progresses through rounds', () {
    final sim = GameSim(cfg: const SimConfig(botSkill: 0.6))..fillBots();
    expect(sim.players.length, 10);
    var kills = 0, plants = 0, maxRound = 0;
    for (var i = 0; i < 60 * 60 * 6 && sim.phase != Phase.matchEnd; i++) {
      sim.update(1 / 60);
      for (final e in sim.events) {
        if (e['e'] == 'kill') kills++;
        if (e['e'] == 'plant') plants++;
      }
      sim.events.clear();
      if (sim.round > maxRound) maxRound = sim.round;
    }
    print('rounds=$maxRound score=${sim.scores} kills=$kills plants=$plants phase=${sim.phase}');
    expect(maxRound, greaterThan(2));
    expect(kills, greaterThan(0));
  });

  test('protocol round-trips inputs', () {
    final raw = encodeMsg(inputMsg([PlayerInput(seq: 3, dt: 0.016, moveZ: 1, buttons: Btn.fire)]));
    final back = parseInputs(decodeMsg(raw)!);
    expect(back.single.seq, 3);
    expect(back.single.has(Btn.fire), isTrue);
  });
}
