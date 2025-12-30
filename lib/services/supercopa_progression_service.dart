import 'package:cloud_firestore/cloud_firestore.dart';

class SupercopaProgressionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Se llama cuando termina un partido de SUPERCOPA_SEMI
  Future<void> checkForSupercopaAdvances(String seasonId, String matchId) async {
    var matchDoc = await _db.collection('seasons').doc(seasonId).collection('matches').doc(matchId).get();
    if (!matchDoc.exists) return;

    var data = matchDoc.data()!;
    String matchType = data['type'];

    // Solo nos interesa si es una semifinal
    if (matchType != 'SUPERCOPA_SEMI') return;

    // Determinar ganador
    String winnerId = "";
    if (data['homeScore'] > data['awayScore']) {
      winnerId = data['homeUser'];
    } else if (data['awayScore'] > data['homeScore']) {
      winnerId = data['awayUser'];
    } else {
      // Si hubo penales
      if (data['definedByPenalties'] == true && data['penaltyWinner'] != null) {
        winnerId = data['penaltyWinner'];
      } else {
        // Fallback raro si no cargaron penales: pasa el local
        winnerId = data['homeUser'];
      }
    }

    // Identificar cuál semi fue (1 o 2) basado en el roundName o placeholder original
    // Como no guardamos el "seed" en el match final, usamos el nombre de la ronda
    String roundName = data['roundName'].toString(); // "Supercopa Semi 1" o "Supercopa Semi 2"
    String placeholderTarget = "";

    if (roundName.contains("1")) {
      placeholderTarget = "GANADOR Supercopa Semi 1";
    } else if (roundName.contains("2")) {
      placeholderTarget = "GANADOR Supercopa Semi 2";
    }

    if (placeholderTarget.isNotEmpty) {
      await _updateFinalPlaceholder(seasonId, placeholderTarget, winnerId);
    }
  }

  Future<void> _updateFinalPlaceholder(String seasonId, String placeholder, String teamId) async {
    // Buscamos la FINAL (round -1) que tenga ese placeholder
    var queryH = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'SUPERCOPA_FINAL')
        .where('homePlaceholder', isEqualTo: placeholder)
        .get();

    var queryA = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'SUPERCOPA_FINAL')
        .where('awayPlaceholder', isEqualTo: placeholder)
        .get();

    // Actualizamos si encontramos
    for (var doc in queryH.docs) {
      await doc.reference.update({
        'homeUser': teamId,
        'status': _checkIfReady(doc, homeId: teamId)
      });
    }
    for (var doc in queryA.docs) {
      await doc.reference.update({
        'awayUser': teamId,
        'status': _checkIfReady(doc, awayId: teamId)
      });
    }
  }

  String _checkIfReady(DocumentSnapshot doc, {String? homeId, String? awayId}) {
    String h = homeId ?? doc['homeUser'];
    String a = awayId ?? doc['awayUser'];
    // Si ambos ya tienen ID real (no TBD, no GANADOR...)
    if (h != 'TBD' && !h.startsWith('GANADOR') && a != 'TBD' && !a.startsWith('GANADOR')) {
      return 'PENDING';
    }
    return 'SCHEDULED';
  }
}