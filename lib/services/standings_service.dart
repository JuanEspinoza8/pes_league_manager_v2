import 'package:cloud_firestore/cloud_firestore.dart';

class StandingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> recalculateLeagueStandings(String seasonId) async {
    await _recalculateTable(seasonId, 'LEAGUE', 'leagueStats');
  }

  Future<void> recalculateChampionsStandings(String seasonId) async {
    // CORRECCIÓN: El tipo correcto guardado en la DB es 'CHAMPIONS_GROUP'
    await _recalculateTable(seasonId, 'CHAMPIONS_GROUP', 'championsStats', maxRound: 249);
  }

  Future<void> _recalculateTable(String seasonId, String type, String fieldName, {int maxRound = 999}) async {
    try {
      // Traemos partidos SOLO por tipo para evitar problemas de índice con 'status'
      var matchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
          .where('type', isEqualTo: type)
          .get();

      var participantsSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();

      // Inicializar tabla a 0
      Map<String, Map<String, int>> stats = {};
      for (var doc in participantsSnap.docs) {
        stats[doc.id] = {'pts': 0, 'pj': 0, 'pg': 0, 'pe': 0, 'pp': 0, 'gf': 0, 'gc': 0, 'dif': 0};
      }

      // Procesar partidos
      for (var doc in matchesSnap.docs) {
        var m = doc.data() as Map<String, dynamic>;

        // Filtros en memoria (Seguro)
        if (m['status'] != 'PLAYED') continue;
        if ((m['round'] as int) > maxRound) continue;

        String h = m['homeUser'];
        String a = m['awayUser'];

        // Ignorar partidos contra 'BYE' o no definidos
        if (!stats.containsKey(h) || !stats.containsKey(a)) continue;

        int hs = m['homeScore'] ?? 0;
        int as = m['awayScore'] ?? 0;

        _updateStats(stats[h]!, hs, as);
        _updateStats(stats[a]!, as, hs);
      }

      // Guardar en Firestore
      WriteBatch batch = _db.batch();
      stats.forEach((uid, data) {
        // fieldName será 'leagueStats' o 'championsStats'
        batch.update(_db.collection('seasons').doc(seasonId).collection('participants').doc(uid), {fieldName: data});
      });
      await batch.commit();

    } catch (e) {
      print("Error calculando tabla: $e");
    }
  }

  void _updateStats(Map<String, int> s, int gf, int gc) {
    s['pj'] = s['pj']! + 1;
    s['gf'] = s['gf']! + gf;
    s['gc'] = s['gc']! + gc;
    s['dif'] = s['gf']! - s['gc']!;

    if (gf > gc) {
      s['pts'] = s['pts']! + 3;
      s['pg'] = s['pg']! + 1;
    } else if (gf == gc) {
      s['pts'] = s['pts']! + 1;
      s['pe'] = s['pe']! + 1;
    } else {
      s['pp'] = s['pp']! + 1;
    }
  }
}