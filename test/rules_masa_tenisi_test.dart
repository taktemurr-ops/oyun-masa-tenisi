// Masa tenisi sayı ve servis kuralları (QA turu).
// Kaynak: ITTF El Kitabı 2.11 (oyun 11 sayı, 10-10 sonrası iki sayı fark),
// 2.13.3 (servis iki sayıda bir değişir; 10-10 sonrası her sayıda).
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:oyun_masa_tenisi/src/rally_engine.dart';
import 'package:oyun_masa_tenisi/src/rules.dart';

void main() {
  final rules = TableTennisRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  RallySim match11() {
    for (var n = 1; n < 60; n++) {
      final s = RallySim(rules.build(planner.spec(n)).puzzle);
      if (s.matchMode) {
        s
          ..ptsToWin = 11
          ..gamesToWin = 1
          ..lives = 99;
        return s;
      }
    }
    throw StateError('maç bölümü yok');
  }

  /// Sayıyı doğrudan sonuçlandır: top dünya dışına, son vuran ve sekme ayarlı.
  void point(RallySim s, bool mine) {
    s
      ..pause = 0
      ..live = true
      ..netChecked = true
      ..bx = 500
      ..by = mine ? -500 : kWorldH + 500
      ..bz = 50
      ..vx = 0
      ..vy = 0
      ..vz = 0
      ..lastHitter = mine ? 0 : 1
      ..bounces = 1;
    s.update(ArcadeInput.idle);
  }

  test('11 sayıda biter: 11-9 kazanılır', () {
    final s = match11();
    for (var i = 0; i < 9; i++) {
      point(s, false);
    }
    for (var i = 0; i < 10; i++) {
      point(s, true);
    }
    expect(s.won, isFalse);
    expect((s.myPts, s.cpuPts), (10, 9));
    point(s, true);
    expect(s.won, isTrue);
  });

  test('10-10 sonrası iki sayı fark gerekir, tavan yok (16-14)', () {
    final s = match11();
    for (var i = 0; i < 10; i++) {
      point(s, true);
      point(s, false);
    }
    // 10-10 → 11-10, 11-11 … 14-14: hâlâ bitmez (eskiden 15-14'te bitiyordu).
    for (var i = 0; i < 4; i++) {
      point(s, true);
      expect(s.won, isFalse, reason: '${s.myPts}-${s.cpuPts}');
      point(s, false);
    }
    point(s, true);
    expect(s.won, isFalse, reason: '15-14 bitmemeli');
    point(s, true);
    expect(s.won, isTrue);
  });

  test('servis iki sayıda bir, 10-10 sonrası her sayıda değişir', () {
    final s = match11();
    final seq = <int>[s.server];
    for (var i = 0; i < 10; i++) {
      point(s, true);
      seq.add(s.server);
      point(s, false);
      seq.add(s.server);
    }
    // 0-0 .. 9-10 arası: 0,0,1,1,0,0,...
    for (var k = 0; k < 20; k++) {
      expect(seq[k], (k ~/ 2) % 2 == 0 ? seq[0] : 1 - seq[0], reason: 'sayı $k');
    }
    final at1010 = s.server;
    point(s, true); // 11-10
    expect(s.server, 1 - at1010);
    point(s, false); // 11-11
    expect(s.server, at1010);
  });

  test('ağa takılan top vurana sayı kaybettirir', () {
    final s = match11();
    s
      ..live = true
      ..lastHitter = 0
      ..netChecked = false
      ..bx = 500
      ..by = s.g.net + 10
      ..bz = 5
      ..vx = 0
      ..vy = -20
      ..vz = 0
      ..bounces = 0
      ..pause = 0;
    s.update(ArcadeInput.idle);
    expect(s.cpuPts, 1);
  });
}
