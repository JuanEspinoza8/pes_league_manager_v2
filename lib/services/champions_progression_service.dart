import 'package:cloud_firestore/cloud_firestore.dart';

class ChampionsProgressionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- SUPERVISOR DE ELIMINATORIAS (NUEVO) ---
  // Revisa todos los partidos de vuelta jugados y actualiza las llaves siguientes.
  Future<void> checkForChampionsAdvances(String seasonId) async {
    print("--- SUPERVISOR CHAMPIONS: Revisando cruces ---");

    // 1. Traer TODOS los partidos de Champions
    var allMatchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CHAMPIONS')
        .get();

    var allMatches = allMatchesSnap.docs;

    // Filtramos en memoria
    var playedMatches = allMatches.where((d) => d['status'] == 'PLAYED').toList();
    var pendingMatches = allMatches.where((d) => d['status'] != 'PLAYED').toList();

    // 2. Iterar sobre partidos de VUELTA jugados (Ronda >= 250)
    var vueltasJugadas = playedMatches.where((d) => (d['roundName'] as String).contains('Vuelta')).toList();

    for (var vuelta in vueltasJugadas) {
      String roundName = vuelta['roundName'];
      String baseName = roundName.replaceAll(' Vuelta', ''); // Ej: "Repechaje 1"

      // Buscar la IDA correspondiente
      DocumentSnapshot? ida;
      try {
        ida = playedMatches.firstWhere((m) => m['roundName'] == '$baseName Ida');
      } catch (e) {
        continue; // Si no hay ida jugada, saltamos
      }

      // Calcular Ganador Global
      String winnerId = _calculateAggregateWinner(ida, vuelta);

      // Determinar la ETIQUETA que busca el siguiente partido
      String targetLabel = "";
      if (baseName == 'Repechaje 1') targetLabel = 'GANADOR REP 1';
      else if (baseName == 'Repechaje 2') targetLabel = 'GANADOR REP 2';
      else if (baseName == 'Semifinal 1') targetLabel = 'FINALISTA 1';
      else if (baseName == 'Semifinal 2') targetLabel = 'FINALISTA 2';

      if (targetLabel.isEmpty) continue;

      // 3. Buscar en los pendientes quién espera a este ganador
      for (var targetMatch in pendingMatches) {
        bool updated = false;
        Map<String, dynamic> updates = {};

        // Chequear LOCAL
        if (targetMatch['homePlaceholder'] == targetLabel) {
          updates['homeUser'] = winnerId;
          String currentAway = targetMatch['awayUser'];
          if (currentAway != 'TBD' && !currentAway.startsWith('GANADOR') && !currentAway.startsWith('FINALISTA')) {
            updates['status'] = 'PENDING';
          }
          updated = true;
        }

        // Chequear VISITA
        if (targetMatch['awayPlaceholder'] == targetLabel) {
          updates['awayUser'] = winnerId;
          String currentHome = targetMatch['homeUser'];
          if (currentHome != 'TBD' && !currentHome.startsWith('GANADOR') && !currentHome.startsWith('FINALISTA')) {
            updates['status'] = 'PENDING';
          }
          updated = true;
        }

        if (updated) {
          await targetMatch.reference.update(updates);
          print("Champions: $winnerId avanza a ${targetMatch['roundName']}");
        }
      }
    }
  }

  // --- 1. FIN DE GRUPOS -> Generar Repechaje ---
  Future<void> checkGroupStageEnd(String seasonId) async {
    var groupMatchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CHAMPIONS')
        .get(); // Traemos todos y filtramos en memoria

    // Solo partidos de grupos (ronda < 250) que NO estén jugados
    var pendingDocs = groupMatchesSnap.docs.where((doc) {
      int r = doc['round'] ?? 0;
      return r < 250 && doc['status'] != 'PLAYED';
    }).toList();

    // Si no hay pendientes (y hay partidos en la lista), generamos playoffs
    if (pendingDocs.isEmpty && groupMatchesSnap.docs.isNotEmpty) {
      await _fillPlayoffPlaceholders(seasonId);
    }
  }

  // Mantengo esta función para compatibilidad
  Future<void> advancePlayoffRound(String seasonId, String roundName) async {
    await checkForChampionsAdvances(seasonId);
  }

  // --- HELPERS ---

  Future<void> _fillPlayoffPlaceholders(String seasonId) async {
    var pSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    var groupA = pSnap.docs.where((d) => (d.data() as Map)['championsGroup'] == 'A').toList();
    var groupB = pSnap.docs.where((d) => (d.data() as Map)['championsGroup'] == 'B').toList();

    _sortGroup(groupA);
    _sortGroup(groupB);

    if (groupA.isEmpty || groupB.isEmpty) return;

    String a1 = groupA[0].id;
    String b1 = groupB[0].id;
    String? a2 = groupA.length > 1 ? groupA[1].id : null;
    String? a3 = groupA.length > 2 ? groupA[2].id : null;
    String? b2 = groupB.length > 1 ? groupB[1].id : null;
    String? b3 = groupB.length > 2 ? groupB[2].id : null;

    if (a2 != null && b3 != null) {
      await _updateMatchesByName(seasonId, 'Repechaje 1 Ida', a2, b3, setPending: true);
      await _updateMatchesByName(seasonId, 'Repechaje 1 Vuelta', b3, a2, setPending: true);
    } else if (a2 != null) {
      await _updateNextPlaceholder(seasonId, 'GANADOR REP 1', a2);
    }

    if (b2 != null && a3 != null) {
      await _updateMatchesByName(seasonId, 'Repechaje 2 Ida', b2, a3, setPending: true);
      await _updateMatchesByName(seasonId, 'Repechaje 2 Vuelta', a3, b2, setPending: true);
    } else if (b2 != null) {
      await _updateNextPlaceholder(seasonId, 'GANADOR REP 2', b2);
    }

    await _updateMatchesByName(seasonId, 'Semifinal 1 Ida', a1, null, setPending: false);
    await _updateMatchesByName(seasonId, 'Semifinal 1 Vuelta', null, a1, setPending: false);
    await _updateMatchesByName(seasonId, 'Semifinal 2 Ida', b1, null, setPending: false);
    await _updateMatchesByName(seasonId, 'Semifinal 2 Vuelta', null, b1, setPending: false);
  }

  Future<void> _updateMatchesByName(String seasonId, String name, String? home, String? away, {bool setPending = false}) async {
    var snap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CHAMPIONS').where('roundName', isEqualTo: name).get();

    for (var doc in snap.docs) {
      Map<String, dynamic> update = {};
      if (home != null) update['homeUser'] = home;
      if (away != null) update['awayUser'] = away;
      if (setPending) update['status'] = 'PENDING';
      await doc.reference.update(update);
    }
  }

  Future<void> _updateNextPlaceholder(String seasonId, String placeholderTag, String realId) async {
    var q1 = await _db.collection('seasons').doc(seasonId).collection('matches').where('homePlaceholder', isEqualTo: placeholderTag).get();
    for (var d in q1.docs) {
      Map<String, dynamic> up = {'homeUser': realId};
      if (d['awayUser'] != 'TBD') up['status'] = 'PENDING';
      d.reference.update(up);
    }
    var q2 = await _db.collection('seasons').doc(seasonId).collection('matches').where('awayPlaceholder', isEqualTo: placeholderTag).get();
    for (var d in q2.docs) {
      Map<String, dynamic> up = {'awayUser': realId};
      if (d['homeUser'] != 'TBD') up['status'] = 'PENDING';
      d.reference.update(up);
    }
  }

  String _calculateAggregateWinner(DocumentSnapshot ida, DocumentSnapshot vuelta) {
    int h1 = ida['homeScore']; int a1 = ida['awayScore'];
    int h2 = vuelta['homeScore']; int a2 = vuelta['awayScore'];
    int globalA = h1 + a2;
    int globalB = a1 + h2;

    if (globalA > globalB) return ida['homeUser'];
    if (globalB > globalA) return ida['awayUser'];
    if (a2 > a1) return ida['homeUser']; // Gol Visitante
    if (a1 > a2) return ida['awayUser'];
    return ida['awayUser'];
  }

  void _sortGroup(List<QueryDocumentSnapshot> group) {
    group.sort((a, b) {
      var sA = (a.data() as Map)['championsStats'] ?? {};
      var sB = (b.data() as Map)['championsStats'] ?? {};
      int ptsA = sA['pts']??0; int ptsB = sB['pts']??0;
      if (ptsA != ptsB) return ptsB.compareTo(ptsA);
      return (sB['dif']??0).compareTo(sA['dif']??0);
    });
  }
}