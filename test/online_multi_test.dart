// Çok istemcili çevrimiçi düello: studio_core'un bellek içi sunucusu
// (Firestore düzeni ve kurallarının aynısı) üzerinden iki gerçek oyun ekranı
// aynı masada maçı sonuna kadar oynar (her cihazın oyuncusunu yapay zekâ
// oynar). Ev sahibinin kopması → misafirin devralması → geri dönüş, gecikme
// ve Arapça masa da denenir; iki cihazın gördüğü sonuç karşılaştırılır.
@Tags(['online'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/online/online.dart';
import 'package:studio_core/online/online_service.dart';
import 'package:studio_core/online/online_testing.dart';
import 'package:studio_core/app/arcade_duel_stage.dart';
import 'package:oyun_masa_tenisi/oyun_masa_tenisi.dart';

PlayContext _ctx(GeneratedLevel gl, OnlineMatchLink link, String lang, void Function(RoundResult) fin) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D)],
      background: const [Color(0xFF1A2E5C), Color(0xFF3A6FC4)],
      colorBlind: false,
      reducedMotion: true,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: fin,
      saveResume: (_) {},
      requestHint: () async => false,
      requestBooster: () async => false,
      requestContinue: () async => false,
      sfx: (_) {},
      sound: (_) {},
      seats: [
        for (var i = 0; i < link.names.length; i++)
          i == link.mySeat ? SeatRole.local : (link.names[i].isEmpty ? SeatRole.ai : SeatRole.remote)
      ],
      match: link,
    );

class _Case {
  final String name;
  final GameRules rules;
  final Widget Function(PlayContext) view;
  const _Case(this.name, this.rules, this.view);
}

final _cases = <_Case>[
  _Case('Masa Tenisi', masaTenisiConfig.rules, (c) => masaTenisiConfig.buildPlay(c)),
];

class _Rig {
  final OnlineTestTable t;
  final GeneratedLevel gl;
  final _Case c;
  final String lang;
  final List<OnlineMatchLink?> links;
  final List<int> gen = [0, 0];
  final List<RoundResult?> results = [null, null];
  final Set<int> stale = {};
  _Rig(this.t, this.gl, this.c, this.lang) : links = [t.link(0), t.link(1)] {
    watch(0);
    watch(1);
  }

  void watch(int i) {
    final m = links[i]?.m;
    m?.rejections.listen((_) async {
      if (links[i]?.m != m) return;
      final fresh = await t.backends[i].rejoin(t.matchId, ended: true);
      if (fresh == null) return;
      t.matches[i] = fresh;
      links[i] = OnlineMatchLink(fresh);
      gen[i]++;
      stale.add(i);
      watch(i);
    });
  }

  Widget build() => MaterialApp(
        home: Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: links[i] == null
                    ? const SizedBox()
                    : KeyedSubtree(
                        key: ValueKey('c$i-${gen[i]}'),
                        child: Scaffold(body: c.view(_ctx(gl, links[i]!, lang, (r) => results[i] ??= r))),
                      ),
              ),
          ]),
        ),
      );

  bool get done => results.every((r) => r != null);
}

Future<_Rig> _open(WidgetTester tester, _Case c, {String lang = 'tr', List<String>? names}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 820);
  addTearDown(tester.view.reset);
  final t = await OnlineTestTable.open(gameId: c.rules.gameId, seats: 2, humans: 2, names: names);
  final spec = LevelPlanner(gameId: c.rules.gameId, optionalMechanics: const []).run(GameModeId.online, t.seed, difficulty: 4);
  final gl = c.rules.build(spec);
  final rig = _Rig(t, gl, c, lang);
  await tester.pumpWidget(rig.build());
  return rig;
}

Future<void> _play(WidgetTester tester, _Rig rig, {int maxSeconds = 900, Future<void> Function(int sec)? at}) async {
  var ms = 0;
  while (!rig.done && ms < maxSeconds * 1000) {
    await tester.pump(const Duration(milliseconds: 50));
    ms += 50;
    if (rig.stale.isNotEmpty) {
      rig.stale.clear();
      await tester.pumpWidget(rig.build());
    }
    if (at != null && ms % 1000 == 0) await at(ms ~/ 1000);
  }
  expect(rig.done, isTrue, reason: '${rig.c.name}: maç ${maxSeconds}s içinde bitmedi (hamle: ${rig.t.moveCount})');
  // Ayrışma denetimi: iki cihaz aynı maçı gördüyse ikisi birden kazanmış olamaz.
  final won = rig.results.where((r) => r!.won).length;
  expect(won, lessThanOrEqualTo(1), reason: '${rig.c.name}: iki cihaz da kazandığını gördü (ayrışma)');
  expect(rig.t.status, MatchStatus.done);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() {
    ArcadeDuelStage.autopilot = true;
  });
  tearDown(() {
    ArcadeDuelStage.autopilot = false;
  });

  for (final c in _cases) {
    testWidgets('${c.name}: iki cihaz maçı sonuna kadar oynar, aynı sonucu görür', (tester) async {
      final rig = await _open(tester, c);
      await _play(tester, rig);
    });

    testWidgets('${c.name}: ev sahibi kopar (misafir devralır / bot oynar), sonra geri döner', (tester) async {
      final rig = await _open(tester, c);
      var dropped = false, back = false;
      await _play(tester, rig, at: (sec) async {
        if (sec == 8 && !dropped) {
          dropped = true;
          rig.t.drop(0);
          rig.t.advance(const Duration(seconds: 50));
        }
        if (sec == 20 && !back) {
          back = true;
          await rig.t.back(0);
        }
      });
    });

    testWidgets('${c.name}: 80 ms gecikme ve Arapça masa', (tester) async {
      final rig = await _open(tester, c, lang: 'ar', names: ['نسر ذهبي', 'Mavi Tilki']);
      rig.t.latency = const Duration(milliseconds: 80);
      await _play(tester, rig);
    });
  }
}
