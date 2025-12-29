import 'package:cloud_firestore/cloud_firestore.dart';

class CupProgressionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Lógica "Supervisor": Revisar y avanzar
  Future<void> checkForCupAdvances(String seasonId) async {
    // 1. Traer todos los partidos de Copa JUGADOS
    var playedMatchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CUP')
        .where('status', isEqualTo: 'PLAYED')
        .get();

    // 2. Traer los partidos de Copa PROGRAMADOS (pendientes de rival)
    var waitingMatchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CUP')
        .where('status', isEqualTo: 'SCHEDULED')
        .get();

    for (var playedMatch in playedMatchesSnap.docs) {
      String roundName = playedMatch['roundName'];
      String winnerId = _getWinnerFromDoc(playedMatch);

      // GENERAR ETIQUETA DEL GANADOR
      String winnerLabel = "";
      if (roundName.contains("Preliminar")) {
        // Extraer número: "Preliminar 1" -> "GANADOR P1"
        String num = roundName.split(" ").last;
        winnerLabel = "GANADOR P$num";
      } else {
        // "Cuartos A" -> "GANADOR Cuartos A"
        winnerLabel = "GANADOR $roundName";
      }

      // CASO ESPECIAL: FINAL (Mapeo Semis -> Finalista)
      String finalistLabel = "";
      if (roundName.contains("Semifinal")) {
        String letter = roundName.split(" ").last; // A o B
        finalistLabel = "FINALISTA $letter";
      }

      // 3. BUSCAR SI ALGUIEN ESPERA ESTA ETIQUETA
      for (var waitingMatch in waitingMatchesSnap.docs) {
        bool updated = false;
        Map<String, dynamic> updates = {};

        // Chequear Local
        String hPlace = waitingMatch['homePlaceholder'] ?? '';
        if (hPlace == winnerLabel || hPlace == finalistLabel) {
          updates['homeUser'] = winnerId;
          // Verificar si el otro ya estaba listo
          String currentAway = waitingMatch['awayUser'];
          if (currentAway != 'TBD' && !currentAway.startsWith('GANADOR') && !currentAway.startsWith('Seed')) {
            updates['status'] = 'PENDING';
          }
          updated = true;
        }

        // Chequear Visita
        String aPlace = waitingMatch['awayPlaceholder'] ?? '';
        if (aPlace == winnerLabel || aPlace == finalistLabel) {
          updates['awayUser'] = winnerId;
          // Verificar si el otro ya estaba listo
          String currentHome = waitingMatch['homeUser'];
          if (currentHome != 'TBD' && !currentHome.startsWith('GANADOR') && !currentHome.startsWith('Seed')) {
            updates['status'] = 'PENDING';
          }
          updated = true;
        }

        if (updated) {
          await waitingMatch.reference.update(updates);
          print("Actualizado partido ${waitingMatch['roundName']}: Entra $winnerId");
        }
      }
    }
  }

  // Mantenemos este para compatibilidad simple
  Future<void> advanceCupRound({
    required String seasonId,
    required String roundName,
    required String winnerId,
  }) async {
    // Simplemente llamamos al supervisor completo para asegurar consistencia
    await checkForCupAdvances(seasonId);
  }

  String _getWinnerFromDoc(DocumentSnapshot match) {
    var d = match.data() as Map<String, dynamic>;
    if ((d['homeScore'] ?? 0) > (d['awayScore'] ?? 0)) return d['homeUser'];
    return d['awayUser'];
  }
}