import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import 'rally_engine.dart';

class TableTennisRules extends ArcadeRules<RallyLevel> {
  @override
  String get gameId => 'oyun-masa-tenisi';

  @override
  List<String> get optionalMechanics => const [];

  /// İki kişilik: "Bilgisayara karşı" ve "Çevrimiçi masa" (gerçek zamanlı düello).
  @override
  int get localPlayers => 2;

  @override
  List<GameStat> get gameStats => const [
        GameStat('points_won', 'Kazanılan sayı', 'Points won', scale: 500),
        GameStat('matches_won', 'Kazanılan maç', 'Matches won', scale: 40),
        GameStat('aces', 'Servis sayısı', 'Aces', scale: 50),
        GameStat('best_rally', 'En uzun ralli', 'Longest rally', scale: 30),
        GameStat('power_shots', 'Sert vuruş', 'Power shots', scale: 200),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('points_won', 'points_won', [125, 250, 500]),
        MissionTemplate('matches_won', 'matches_won', [5, 10, 20], coinReward: 80),
      ];

  @override
  RallyLevel generate(LevelSpec spec) => generateRally(RallyKind.tableTennis, spec);

  @override
  ArcadeMeta metaOf(RallyLevel l) => l.meta;

  @override
  ArcadeSim createSim(RallyLevel l) => RallySim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => rallyBot(sim);
}

ArcadeRules createRules() => TableTennisRules();
