import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:oyun_masa_tenisi/src/rally_engine.dart';
import 'package:oyun_masa_tenisi/src/rules.dart';

void main() {
  final rules = TableTennisRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  RallySim fresh([int n = 1]) => RallySim(rules.build(planner.spec(n)).puzzle);

  test('a serve clears the net and lands in the rival half', () {
    final s = fresh();
    for (var i = 0; i < 30; i++) {
      s.tick(const ArcadeInput(tap: true));
    }
    expect(s.live, isTrue);
    var bounced = false;
    for (var i = 0; i < 200 && s.live && !bounced; i++) {
      s.tick(ArcadeInput.idle);
      if (s.bounces == 1) bounced = true;
    }
    expect(bounced, isTrue);
    expect(s.by, lessThan(s.g.net));
    expect(s.g.inside(s.bx, s.by), isTrue);
  });

  test('a ball you do not reach gives the rival the point', () {
    final s = fresh();
    s.server = 1;
    s.lastHitter = 1;
    s.bx = 500;
    s.by = 900;
    s.bz = 40;
    s.vx = 0;
    s.vy = 6;
    s.vz = 0;
    s.live = true;
    s.bounces = 0;
    s.netChecked = true;
    s.px = 120;
    final before = s.pointsLost;
    for (var i = 0; i < 400 && s.pointsLost == before; i++) {
      s.tick(const ArcadeInput(down: true, x: 100, y: 1500));
    }
    expect(s.pointsLost, before + 1);
  });

  test('autopilot wins the first matches', () {
    for (var n = 1; n <= 6; n++) {
      final s = fresh(n);
      expect(runBot(s, rules.bot, 60 * 60 * 6).won, isTrue, reason: 'level $n');
    }
  });
}
