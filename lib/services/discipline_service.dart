import 'package:cloud_firestore/cloud_firestore.dart';

class DisciplineService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- FUNCIÓN EXISTENTE (La usa MatchResultScreen al abrir) ---
  Future<List<String>> getSuspendedPlayers({
    required String seasonId,
    required String teamId,
    required String competitionType,
    required int currentRound,
  }) async {
    if (competitionType == 'LEAGUE') return [];
    List<String> suspendedPlayers = [];
    Map<String, int> yellowCardsAccumulated = {};

    try {
      // Busca en el historial (requiere índice compuesto en Firebase)
      var matchesSnap = await _db
          .collection('seasons')
          .doc(seasonId)
          .collection('matches')
          .where('type', isEqualTo: competitionType)
          .where('status', isEqualTo: 'PLAYED')
          .orderBy('round')
          .get();

      for (var doc in matchesSnap.docs) {
        if (doc['round'] >= currentRound) continue;
        var data = doc.data();
        String side = '';
        if (data['homeUser'] == teamId) side = 'home';
        else if (data['awayUser'] == teamId) side = 'away';
        else continue;

        if (data['player_actions'] != null && data['player_actions'][side] != null) {
          Map<String, dynamic> actions = data['player_actions'][side];
          actions.forEach((playerId, stats) {
            // ROJA DIRECTA (Suspende inmediato)
            if ((stats['redCards'] ?? 0) >= 1) {
              suspendedPlayers.add(playerId);
            }
            // ACUMULACIÓN AMARILLAS
            int yellows = stats['yellowCards'] ?? 0;
            if (yellows > 0) {
              int current = (yellowCardsAccumulated[playerId] ?? 0) + yellows;
              if (current >= 2) {
                suspendedPlayers.add(playerId);
                yellowCardsAccumulated[playerId] = 0; // Reset
              } else {
                yellowCardsAccumulated[playerId] = current;
              }
            }
          });
        }
      }
      return suspendedPlayers.toSet().toList();
    } catch (e) {
      print("Error DisciplineService (getSuspended): $e. ¡Verifica los índices en Firebase!");
      return [];
    }
  }

  // --- NUEVA FUNCIÓN CLAVE: Propagar suspensiones al futuro ---
  // Se llama cuando se GUARDA un resultado de Copa/Champions.
  Future<void> propagateSuspensionsToNextMatch(String seasonId, Map<String, dynamic> finishedMatchData) async {
    String type = finishedMatchData['type'];
    if (type == 'LEAGUE') return; // Liga no propaga

    String homeId = finishedMatchData['homeUser'];
    String awayId = finishedMatchData['awayUser'];
    int currentRound = finishedMatchData['round'];

    // 1. Calcular quiénes quedaron suspendidos tras ESTE partido
    List<String> homeSuspendedNow = await getSuspendedPlayers(seasonId: seasonId, teamId: homeId, competitionType: type, currentRound: currentRound + 1);
    List<String> awaySuspendedNow = await getSuspendedPlayers(seasonId: seasonId, teamId: awayId, competitionType: type, currentRound: currentRound + 1);

    // 2. Buscar el SIGUIENTE partido del local en esta competición y pegarle la etiqueta
    if (homeSuspendedNow.isNotEmpty && !homeId.startsWith('TBD')) {
      await _updateNextMatchInfo(seasonId, homeId, type, currentRound, homeSuspendedNow);
    }

    // 3. Buscar el SIGUIENTE partido del visitante en esta competición y pegarle la etiqueta
    if (awaySuspendedNow.isNotEmpty && !awayId.startsWith('TBD')) {
      await _updateNextMatchInfo(seasonId, awayId, type, currentRound, awaySuspendedNow);
    }
  }

  Future<void> _updateNextMatchInfo(String seasonId, String teamId, String type, int roundFinished, List<String> suspendedIds) async {
    try {
      // Buscar próximo partido donde este equipo sea local O visitante
      var nextMatchQuery = await _db.collection('seasons').doc(seasonId).collection('matches')
          .where('type', isEqualTo: type)
          .where('round', isGreaterThan: roundFinished)
          .orderBy('round')
          .limit(1)
          .get();

      if (nextMatchQuery.docs.isNotEmpty) {
        var nextMatchDoc = nextMatchQuery.docs.first;
        var data = nextMatchDoc.data();

        // Determinar de qué lado juega en el próximo partido
        String sideField = '';
        if (data['homeUser'] == teamId || data['homeUser'].toString().contains('GANADOR')) sideField = 'homeSuspended';
        if (data['awayUser'] == teamId || data['awayUser'].toString().contains('GANADOR')) sideField = 'awaySuspended';

        if (sideField.isNotEmpty) {
          print("Propagando suspensiones para $teamId al partido ${nextMatchDoc.id} (Lado: $sideField)");
          await nextMatchDoc.reference.update({
            'preMatchInfo.$sideField': suspendedIds // Guardamos los IDs en un campo especial
          });
        }
      }
    } catch (e) {
      print("Error propagando suspensiones: $e");
    }
  }
}