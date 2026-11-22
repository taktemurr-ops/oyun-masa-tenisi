import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:oyun_masa_tenisi/src/rally_engine.dart';
import 'package:oyun_masa_tenisi/src/rules.dart';

/// Generic arcade checks: determinism, resume by replay, every mode
/// playable, campaign levels finished by the bot.
void main() {
  final rules = TableTennisRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  (RallySim, List<List<int>>) play(RallyLevel l, int ticks) {
    final s = RallySim(l);
    final log = <List<int>>[];
    var last = ArcadeInput.idle;
    for (var t = 0; t < ticks && !s.over; t++) {
      final i = rules.bot(s).quantized();
      if (!i.sameAs(last)) {
        log.add([s.ticks + 1, ...i.encode()]);
        last = i;
      }
      s.tick(i);
    }
    return (s, log);
  }

  test('same seed => same level and same bot run', () {
    final a = play(rules.build(planner.spec(55)).puzzle, 1500).$1;
    final b = play(rules.build(planner.spec(55)).puzzle, 1500).$1;
    expect(b.score, a.score);
    expect(b.ticks, a.ticks);
  });

  test('resume: replaying the input log restores the round', () {
    final l = rules.build(planner.spec(73)).puzzle;
    final (a, log) = play(l, 1200);
    final b = RallySim(l);
    replayLog(b, log, a.ticks);
    expect(b.ticks, a.ticks);
    expect(b.score, a.score);
    expect(b.lives, a.lives);
    expect(b.stats, a.stats);
  });

  test('boosters and revive are replayable', () {
    final l = rules.build(planner.spec(12)).puzzle;
    final a = RallySim(l);
    final log = <List<int>>[];
    for (var t = 0; t < 400 && !a.over; t++) {
      if (t == 100) {
        a.useBooster();
        log.add([a.ticks + 1, -1, 1, 0, 0, -1, 0, 0]);
      }
      if (t == 200) {
        a.useSlow();
        log.add([a.ticks + 1, -1, 2, 0, 0, -1, 0, 0]);
      }
      a.tick(ArcadeInput.idle);
    }
    final b = RallySim(l);
    replayLog(b, log, a.ticks);
    expect(b.score, a.score);
    expect(b.shield, a.shield);
  });

  test('zen never ends by itself, endless and time attack are playable', () {
    final z = RallySim(rules.build(planner.run(GameModeId.zen, 1)).puzzle);
    for (var t = 0; t < 2400; t++) {
      z.tick(rules.bot(z));
    }
    expect(z.over, isFalse);
    final e = rules.build(planner.run(GameModeId.endless, 3));
    expect(e.validation.ok, isTrue);
    final ta = RallySim(rules.build(planner.run(GameModeId.timeAttack, 4)).puzzle);
    for (var t = 0; t < 60 * 95 && !ta.over; t++) {
      ta.tick(rules.bot(ta));
    }
    expect(ta.over, isTrue);
  });

  test('every campaign level 1..40 is finished by the bot; sample to 50.000', () {
    for (var n = 1; n <= 40; n++) {
      final g = rules.build(planner.spec(n));
      expect(g.validation.ok, isTrue, reason: 'level $n');
      expect(g.spec.difficulty, greaterThanOrEqualTo(1));
    }
    for (var n = 2000; n <= 50000; n += 8000) {
      expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: 'level $n');
    }
  });

  test('daily, weekly and challenges validate', () {
    expect(rules.build(planner.daily('2026-11-19')).validation.ok, isTrue);
    expect(rules.build(planner.weekly('2026-W47')).validation.ok, isTrue);
    for (var i = 1; i <= 150; i += 37) {
      expect(rules.build(planner.challenge(i)).validation.ok, isTrue, reason: 'challenge $i');
    }
  });
}
