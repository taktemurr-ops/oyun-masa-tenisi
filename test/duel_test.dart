import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_masa_tenisi/src/rally_engine.dart';
import 'package:oyun_masa_tenisi/src/rules.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/net_sync.dart';

/// Çevrimiçi düello: durum yazımı, ayna görünüm, karşı oyuncunun raketi,
/// servisi ve ev sahibi → misafir eşitlemesi (devralma dahil).
void main() {
  final rules = TableTennisRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);
  RallySim duel([int n = 5]) => RallySim(rules.build(planner.spec(n)).puzzle)..enableDuel();

  ArcadeInput rivalBot(RallySim s) {
    final m = RallySim(s.level)
      ..applyNetState(s.netState())
      ..mirrorView();
    return rallyBot(m);
  }

  test('iki kişilik oyun: çevrimiçi masa açık', () {
    expect(rules.localPlayers, 2);
  });

  test('durum yazılıp okununca aynı; iki kez aynalanınca aynı', () {
    final s = duel();
    for (var i = 0; i < 700; i++) {
      s.rivalInput = rivalBot(s);
      s.tick(rallyBot(s));
    }
    final wire = encodeNums(s.netState());
    final copy = duel()..applyNetState(decodeNums(wire));
    expect(encodeNums(copy.netState()), wire);
    copy
      ..mirrorView()
      ..mirrorView();
    expect(encodeNums(copy.netState()), wire);
  });

  test('ayna görünümde taraflar, skor ve servis yer değiştirir', () {
    final s = duel();
    s.myPts = 4;
    s.cpuPts = 1;
    s.server = 0;
    s.px = 300;
    s.py = 1400;
    s.mirrorView();
    expect(s.myPts, 1);
    expect(s.cpuPts, 4);
    expect(s.server, 1);
    expect(s.cx, kWorldW - 300);
    expect(s.cy, kWorldH - 1400);
  });

  test('karşı oyuncunun parmağı üst raketi ters masada sürer', () {
    final s = duel();
    for (var i = 0; i < 60; i++) {
      s.rivalInput = const ArcadeInput(down: true, x: 300, y: 1450);
      s.tick(const ArcadeInput(down: true, x: 500, y: 1450));
    }
    // ekranında (300, 1450) → masada (700, 150); raket parmağın biraz önünde
    expect(s.cx, closeTo(700, 0.01));
    expect(s.cy, closeTo(190, 0.01));
  });

  test('karşı oyuncu dokununca servis atar, top alt yarıya gider', () {
    final s = duel();
    s.server = 1;
    s.pause = 0;
    s.live = false;
    s.serveWait = 0;
    for (var i = 0; i < 40 && !s.live; i++) {
      s.rivalInput = ArcadeInput(down: true, x: 500, y: 1450, tap: i > 25);
      s.tick(const ArcadeInput(down: true, x: 500, y: 1450));
    }
    expect(s.live, isTrue);
    expect(s.lastHitter, 1);
    expect(s.vy, greaterThan(0));
  });

  test('rakip maçı alınca düello biter', () {
    final s = duel();
    s.cpuGames = s.gamesToWin - 1;
    s.cpuPts = s.ptsToWin - 1;
    s.myPts = 0;
    s.pause = 0;
    s.live = true;
    s.lastHitter = 1;
    s.bounces = 1;
    s.netChecked = true;
    s.bx = 500;
    s.by = 1100;
    s.bz = 1;
    s.vx = 0;
    s.vy = 0;
    s.vz = -5;
    s.px = 900;
    s.rivalInput = ArcadeInput.idle;
    s.tick(ArcadeInput.idle);
    expect(s.duelWinner, 1);
  });

  test('ev sahibi düşünce misafir son durumdan sürer', () {
    final host = duel(), guestSim = duel();
    final toGuest = <String>[];
    var now = 0;
    final hostSync = NetSync(mySeat: 0, seats: 2, humans: {0, 1}, send: toGuest.add);
    final gs = NetSync(mySeat: 1, seats: 2, humans: {0, 1}, send: (d) => hostSync.receive(1, d, now));
    var took = false;
    var tickAtTake = 0;
    for (var frame = 0; frame < 60 * 12; frame++) {
      now = frame * 1000 ~/ 60;
      gs.setAxes([1, 500, 1450, 0, 0]);
      gs.pump(now);
      if (frame < 60 * 3 && !host.over) {
        final a = hostSync.axesOf(1);
        host.rivalInput = a == null ? null : ArcadeInput(down: a[0] > 0.5, x: a[1], y: a[2]);
        host.tick(rallyBot(host));
        hostSync.publish((host.ticks * 1000 / 60).round(), encodeNums(host.netState()), now);
      }
      for (final m in toGuest) {
        gs.receive(0, m, now);
      }
      toGuest.clear();
      if (!took && gs.checkTakeover(now)) {
        took = true;
        guestSim.applyNetState(decodeNums(gs.latest!.payload));
        tickAtTake = guestSim.ticks;
      }
      if (took && !guestSim.over) {
        guestSim.rivalInput = const ArcadeInput(down: true, x: 500, y: 1450);
        guestSim.tick(rallyBot(guestSim));
      }
    }
    expect(took, isTrue);
    expect(tickAtTake, greaterThan(60 * 2));
    expect(guestSim.ticks, greaterThan(tickAtTake));
  });
}
