import 'package:cloud_firestore/cloud_firestore.dart';

class StatsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> recalculateTeamStats(String seasonId) async {
    try {
      var matchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
          .where('status', isEqualTo: 'PLAYED')
          .get();

      var participantsSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();

      // Agregadores
      Map<String, Map<String, dynamic>> teamAggregator = {};

      // {UserId: {PlayerId: {goals: 5, assists: 2}}}
      Map<String, Map<String, Map<String, int>>> playerStatsAggregator = {};

      // Inicializar
      for (var doc in participantsSnap.docs) {
        teamAggregator[doc.id] = {
          'matches': 0, 'goals': 0, 'shots': 0, 'shotsOnTarget': 0, 'passes': 0,
          'passesCompleted': 0, 'possessionSum': 0, 'fouls': 0, 'offsides': 0,
          'interceptions': 0, 'cleanSheets': 0,
        };
        playerStatsAggregator[doc.id] = {};
      }

      // Procesar partidos
      for (var doc in matchesSnap.docs) {
        var m = doc.data();
        if (!m.containsKey('stats')) continue;

        Map<String, dynamic> stats = m['stats'];
        String hUser = m['homeUser'];
        String aUser = m['awayUser'];

        if (teamAggregator.containsKey(hUser)) _addTeamStats(teamAggregator[hUser]!, stats['home'], m['awayScore'] == 0);
        if (teamAggregator.containsKey(aUser)) _addTeamStats(teamAggregator[aUser]!, stats['away'], m['homeScore'] == 0);

        // Sumar Goles y Asistencias de Jugadores
        if (m.containsKey('player_actions')) {
          Map<String, dynamic> actions = m['player_actions']; // {home: {pid: {goals:1, assists:0}}, away: ...}

          if (actions['home'] != null && playerStatsAggregator.containsKey(hUser)) {
            _addPlayerActions(playerStatsAggregator[hUser]!, actions['home']);
          }
          if (actions['away'] != null && playerStatsAggregator.containsKey(aUser)) {
            _addPlayerActions(playerStatsAggregator[aUser]!, actions['away']);
          }
        }
      }

      // Guardar en Firestore
      WriteBatch batch = _db.batch();
      teamAggregator.forEach((uid, data) {
        int matches = data['matches'] == 0 ? 1 : data['matches'];

        Map<String, dynamic> finalStats = {
          'matchesPlayed': data['matches'],
          'totalGoals': data['goals'],
          'cleanSheets': data['cleanSheets'],
          'avgGoals': _avg(data['goals'], matches),
          'avgShots': _avg(data['shots'], matches),
          'avgShotsOnTarget': _avg(data['shotsOnTarget'], matches),
          'avgPasses': _avg(data['passes'], matches),
          'avgPassesCompleted': _avg(data['passesCompleted'], matches),
          'avgPossession': _avg(data['possessionSum'], matches),
          'avgFouls': _avg(data['fouls'], matches),
          'avgOffsides': _avg(data['offsides'], matches),
          'avgInterceptions': _avg(data['interceptions'], matches),
        };

        // Mapa de stats individuales
        Map<String, Map<String, int>> myPlayerStats = playerStatsAggregator[uid] ?? {};

        batch.update(
            _db.collection('seasons').doc(seasonId).collection('participants').doc(uid),
            {
              'advancedStats': finalStats,
              'playerStats': myPlayerStats // Guardamos estructura compleja {pid: {goals: x, assists: y}}
            }
        );
      });

      await batch.commit();
      print("Estadísticas recalculadas.");

    } catch (e) {
      print("Error recalculando stats: $e");
    }
  }

  void _addTeamStats(Map<String, dynamic> data, Map<String, dynamic> matchStats, bool isCleanSheet) {
    data['matches']++;
    data['goals'] += (matchStats['goals'] as int? ?? 0);
    data['shots'] += (matchStats['shots'] as int? ?? 0);
    data['shotsOnTarget'] += (matchStats['shotsOnTarget'] as int? ?? 0);
    data['passes'] += (matchStats['passes'] as int? ?? 0);
    data['passesCompleted'] += (matchStats['passesCompleted'] as int? ?? 0);
    data['possessionSum'] += (matchStats['possession'] as int? ?? 0);
    data['fouls'] += (matchStats['fouls'] as int? ?? 0);
    data['offsides'] += (matchStats['offsides'] as int? ?? 0);
    data['interceptions'] += (matchStats['interceptions'] as int? ?? 0);
    if (isCleanSheet) data['cleanSheets']++;
  }

  void _addPlayerActions(Map<String, Map<String, int>> teamActions, Map<String, dynamic> matchActions) {
    matchActions.forEach((playerId, data) {
      // data es {goals: 1, assists: 1}
      if (!teamActions.containsKey(playerId)) {
        teamActions[playerId] = {'goals': 0, 'assists': 0};
      }
      teamActions[playerId]!['goals'] = teamActions[playerId]!['goals']! + (data['goals'] as int? ?? 0);
      teamActions[playerId]!['assists'] = teamActions[playerId]!['assists']! + (data['assists'] as int? ?? 0);
    });
  }

  double _avg(num value, int matches) {
    return double.parse((value / matches).toStringAsFixed(1));
  }
}