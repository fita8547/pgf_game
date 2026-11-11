import 'package:flutter/material.dart';
import 'package:rps_shared/rps_shared.dart';

import '../engine/engine.dart';
import '../game/game_controller.dart';
import '../ui/theme.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result, required this.onContinue});
  final MatchResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    Engine.I.js.hideAll();
    final r = result;
    final won = r.winner == r.myTeam;
    final title = r.winner < 0 ? '무승부' : (won ? '승리!' : '패배');
    final mm = (r.seconds ~/ 60), ss = (r.seconds.toInt() % 60).toString().padLeft(2, '0');
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(colors: [Rps.navyMid, Rps.navyDeep], radius: 1.2),
      ),
      child: Center(
        child: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w900, color: won ? Rps.gold : Rps.cream, letterSpacing: 4)),
            Text('${mapById(r.mapId).name} · $mm:$ss · '
                '${(r.score[r.myTeam] * 100).floor()}% : ${(r.score[1 - r.myTeam] * 100).floor()}%'),
            const SizedBox(height: 16),
            Panel(
              child: Column(children: [
                for (final row in r.rows)
                  Container(
                    color: row.me ? Colors.white10 : null,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 6, height: 18, color: Rps.team(row.team)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(row.name)),
                      SizedBox(width: 80, child: Text(characterById(row.charId).name)),
                      SizedBox(width: 100, child: Text('${row.kills} / ${row.deaths} / ${row.assists}')),
                      SizedBox(width: 60, child: Text('${row.damage}', textAlign: TextAlign.right)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onContinue, child: const Text('로비로')),
          ]),
        ),
      ),
    );
  }
}
