import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuctionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- CONFIGURACIÓN DE FASES ---
  static const List<Map<String, dynamic>> PHASES = [
    {'name': 'Porteros', 'position': 'PO', 'count': 1},
    {'name': 'Laterales Derechos', 'position': 'LD', 'count': 1},
    {'name': 'Laterales Izquierdos', 'position': 'LI', 'count': 1},
    {'name': 'Defensas Centrales', 'position': 'DEC', 'count': 2},
    {'name': 'Mediocentro Defensivo', 'position': 'MCD', 'count': 1},
    {'name': 'Mediocentro', 'position': 'MC', 'count': 1},
    {'name': 'Mediapunta', 'position': 'MO', 'count': 1},
    {'name': 'Extremo/Interior Derecho', 'position': 'EXD/MDD', 'count': 1},
    {'name': 'Extremo/Interior Izquierdo', 'position': 'EXI/MDI', 'count': 1},
    {'name': 'Delantero/Segunda Punta', 'position': 'CD/SD', 'count': 1},
    {'name': 'Banca de Suplentes', 'position': 'BANCA', 'count': 5},
  ];

  DocumentReference _auctionRef(String seasonId) =>
      _db.collection('seasons').doc(seasonId).collection('auction').doc('status');

  // 1. INICIALIZAR SUBASTA
  Future<void> initializeAuction(String seasonId) async {
    var users = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    WriteBatch batch = _db.batch();

    for (var doc in users.docs) {
      batch.update(doc.reference, {
        'budget': 1000000000,
        'roster': [],
        'auctionStatus': {
          'PO': 0, 'LD': 0, 'LI': 0, 'DEC': 0,
          'MCD': 0, 'MC': 0, 'MO': 0,
          'EXD/MDD': 0, 'EXI/MDI': 0, 'CD/SD': 0,
          'BANCA': 0
        }
      });
    }

    batch.set(_auctionRef(seasonId), {
      'state': 'BIDDING',
      'lastResult': '',
      'phaseIndex': 0,
      'phaseName': PHASES[0]['name'],
      'currentPosition': PHASES[0]['position'],
      'currentPlayer': null,
      'currentBid': 40000000,
      'highestBidderId': null,
      'highestBidderName': null,
      'timerEnd': null,
      'skipsConsecutive': 0,
      'active': true,
      'timestamp': FieldValue.serverTimestamp(),
      'takenPlayers': []
    });

    await batch.commit();
    await drawNextPlayer(seasonId);
  }

  // 2. SORTEAR SIGUIENTE JUGADOR
  Future<void> drawNextPlayer(String seasonId) async {
    var auctionDoc = await _auctionRef(seasonId).get();
    if (!auctionDoc.exists) return;
    var auctionData = auctionDoc.data() as Map<String, dynamic>;

    int phaseIndex = auctionData['phaseIndex'];
    if (phaseIndex >= PHASES.length) {
      await _auctionRef(seasonId).update({'active': false, 'phaseName': 'SUBASTA FINALIZADA'});
      return;
    }

    String positionNeeded = PHASES[phaseIndex]['position'];
    bool isBench = (positionNeeded == 'BANCA');

    Query query = _db.collection('players');

    if (isBench) {
      query = query.where('rating', isLessThan: 83);
    } else {
      if (positionNeeded == 'EXD/MDD') query = query.where('position', whereIn: ['EXD', 'MDD']);
      else if (positionNeeded == 'EXI/MDI') query = query.where('position', whereIn: ['EXI', 'MDI']);
      else if (positionNeeded == 'CD/SD') query = query.where('position', whereIn: ['CD', 'SD']);
      else query = query.where('position', isEqualTo: positionNeeded);
    }

    var snapshot = await query.limit(50).get();
    var available = snapshot.docs.toList();

    List takenIds = auctionData['takenPlayers'] ?? [];
    available.removeWhere((doc) => takenIds.contains(doc.id));

    if (available.isEmpty) {
      await advancePhase(seasonId);
      return;
    }

    var randomDoc = available[Random().nextInt(available.length)];

    await _auctionRef(seasonId).update({
      'state': 'BIDDING',
      'currentPlayer': randomDoc.data(),
      'currentPlayerId': randomDoc.id,
      'currentBid': 40000000,
      'highestBidderId': null,
      'highestBidderName': null,
      'timerEnd': DateTime.now().add(const Duration(seconds: 60)),
    });
  }

  // 3. PUJAR
  Future<void> placeBid(String seasonId, String userId, String userName, int amount) async {
    return _db.runTransaction((transaction) async {
      var auctionSnap = await transaction.get(_auctionRef(seasonId));
      var userSnap = await transaction.get(_db.collection('seasons').doc(seasonId).collection('participants').doc(userId));

      if (!auctionSnap.exists || !userSnap.exists) throw "Error de datos";

      var auctionData = auctionSnap.data() as Map<String, dynamic>;
      var userData = userSnap.data() as Map<String, dynamic>;

      if (auctionData['state'] == 'PAUSED') throw "La subasta está en pausa.";

      int phaseIndex = auctionData['phaseIndex'];
      String currentPos = PHASES[phaseIndex]['position'];
      int maxAllowed = PHASES[phaseIndex]['count'];

      Map userStatus = userData['auctionStatus'] ?? {};
      int myCount = userStatus[currentPos] ?? 0;

      if (myCount >= maxAllowed) throw "Ya completaste el cupo para esta posición.";

      int myBudget = userData['budget'] ?? 0;
      if (myBudget < amount) throw "No tienes fondos suficientes.";

      int currentBid = auctionData['currentBid'];
      if (amount <= currentBid && auctionData['highestBidderId'] != null) throw "La puja debe ser mayor a la actual.";

      transaction.update(_auctionRef(seasonId), {
        'currentBid': amount,
        'highestBidderId': userId,
        'highestBidderName': userName,
        'timerEnd': DateTime.now().add(const Duration(seconds: 20)),
      });
    });
  }

  // 4. RESOLVER SUBASTA
  Future<void> resolveAuction(String seasonId) async {
    var auctionDoc = await _auctionRef(seasonId).get();
    var data = auctionDoc.data() as Map<String, dynamic>;

    if (data['state'] == 'PAUSED') return;

    String? winnerId = data['highestBidderId'];
    String? winnerName = data['highestBidderName'];
    String? playerId = data['currentPlayerId'];
    Map<String, dynamic>? playerData = data['currentPlayer'] as Map<String, dynamic>?;

    String resultMessage = "";

    // ESCENARIO A: HUBO GANADOR
    if (winnerId != null && playerId != null) {
      int cost = data['currentBid'];
      resultMessage = "✅ VENDIDO a $winnerName\npor \$${(cost/1000000).toStringAsFixed(1)}M";

      WriteBatch batch = _db.batch();
      var userRef = _db.collection('seasons').doc(seasonId).collection('participants').doc(winnerId);
      batch.update(userRef, {
        'budget': FieldValue.increment(-cost),
        'roster': FieldValue.arrayUnion([playerId]),
        'auctionStatus.${data['currentPosition']}': FieldValue.increment(1)
      });

      batch.update(_auctionRef(seasonId), {
        'takenPlayers': FieldValue.arrayUnion([playerId]),
        'skipsConsecutive': 0, // ¡AQUÍ SÍ SE REINICIA! (Alguien compró)
        'state': 'PAUSED',
        'lastResult': resultMessage,
        'timerEnd': null
      });

      await batch.commit();
      await _checkBankruptcy(seasonId, winnerId);
    }
    // ESCENARIO B: NADIE PUJÓ
    else {
      int skips = (data['skipsConsecutive'] ?? 0) + 1;

      if (skips < 3) {
        // Skip normal (1 o 2)
        resultMessage = "⏭️ NADIE OFERTÓ (Skip $skips/3)\nEl jugador se descarta.";
        await _auctionRef(seasonId).update({
          'skipsConsecutive': skips,
          'takenPlayers': FieldValue.arrayUnion([playerId]),
          'state': 'PAUSED',
          'lastResult': resultMessage,
          'timerEnd': null
        });
      } else {
        // CASTIGO (Skip 3, 4, 5...)
        // Pasamos 'skips' para NO reiniciarlo en la base de datos
        String assignedUser = await _forceAssignRandomly(seasonId, playerId!, playerData!, skips);

        resultMessage = "🎲 ASIGNACIÓN FORZADA (Skip $skips)\nAsignado a: $assignedUser (+50M Bono)";

        await _auctionRef(seasonId).update({
          'state': 'PAUSED',
          'lastResult': resultMessage,
          'timerEnd': null
        });
      }
    }
  }

  // 5. CONTINUAR
  Future<void> continueAuction(String seasonId) async {
    await _checkPhaseCompletion(seasonId);
  }

  // --- MÉTODOS AUXILIARES ---

  Future<String> _forceAssignRandomly(String seasonId, String playerId, Map<String, dynamic> playerData, int currentSkips) async {
    var auctionData = (await _auctionRef(seasonId).get()).data() as Map<String, dynamic>;
    int phaseIndex = auctionData['phaseIndex'];
    String currentPos = PHASES[phaseIndex]['position'];
    int maxNeeded = PHASES[phaseIndex]['count'];

    var users = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    List<QueryDocumentSnapshot> needyUsers = [];

    for (var u in users.docs) {
      Map status = u.data()['auctionStatus'] ?? {};
      if ((status[currentPos] ?? 0) < maxNeeded) {
        needyUsers.add(u);
      }
    }

    if (needyUsers.isNotEmpty) {
      var luckyUser = needyUsers[Random().nextInt(needyUsers.length)];

      WriteBatch batch = _db.batch();
      batch.update(luckyUser.reference, {
        'roster': FieldValue.arrayUnion([playerId]),
        'budget': FieldValue.increment(50000000),
        'auctionStatus.$currentPos': FieldValue.increment(1)
      });

      batch.update(_auctionRef(seasonId), {
        'takenPlayers': FieldValue.arrayUnion([playerId]),
        'skipsConsecutive': currentSkips // <--- AQUÍ ESTÁ EL CAMBIO: NO SE REINICIA A 0
      });

      await batch.commit();
      return luckyUser['teamName'];
    } else {
      return "Nadie (Error lógico)";
    }
  }

  Future<void> _checkPhaseCompletion(String seasonId) async {
    var auctionData = (await _auctionRef(seasonId).get()).data() as Map<String, dynamic>;
    int phaseIndex = auctionData['phaseIndex'];
    String currentPos = PHASES[phaseIndex]['position'];
    int maxNeeded = PHASES[phaseIndex]['count'];

    var users = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    bool allDone = true;

    for (var u in users.docs) {
      Map status = u.data()['auctionStatus'] ?? {};
      if ((status[currentPos] ?? 0) < maxNeeded) {
        allDone = false;
        break;
      }
    }

    if (allDone) {
      await advancePhase(seasonId);
    } else {
      await drawNextPlayer(seasonId);
    }
  }

  Future<void> advancePhase(String seasonId) async {
    var auctionDoc = await _auctionRef(seasonId).get();
    var data = auctionDoc.data() as Map<String, dynamic>;
    int currentIdx = data['phaseIndex'];

    int nextIdx = currentIdx + 1;

    if (nextIdx < PHASES.length) {
      await _auctionRef(seasonId).update({
        'phaseIndex': nextIdx,
        'phaseName': PHASES[nextIdx]['name'],
        'currentPosition': PHASES[nextIdx]['position'],
        'skipsConsecutive': 0 // Se reinicia al cambiar de posición
      });
      await drawNextPlayer(seasonId);
    } else {
      await _auctionRef(seasonId).update({'active': false, 'phaseName': 'FIN DE SUBASTA'});
    }
  }

  Future<void> _checkBankruptcy(String seasonId, String userId) async {
    var userRef = _db.collection('seasons').doc(seasonId).collection('participants').doc(userId);
    var userSnap = await userRef.get();
    var userData = userSnap.data() as Map<String, dynamic>;

    int budget = userData['budget'] ?? 0;
    List roster = userData['roster'] ?? [];

    if (budget < 40000000) {
      int totalNeeded = 16;
      int currentCount = roster.length;

      if (currentCount < totalNeeded) {
        int missing = totalNeeded - currentCount;
        var worstQuery = await _db.collection('players').orderBy('rating', descending: false).limit(missing + 20).get();

        List<String> fillIds = [];
        for (var doc in worstQuery.docs) {
          if (fillIds.length >= missing) break;
          if (!roster.contains(doc.id)) fillIds.add(doc.id);
        }

        int penalty = fillIds.length * 20000000;

        WriteBatch batch = _db.batch();
        batch.update(userRef, {
          'roster': FieldValue.arrayUnion(fillIds),
          'budget': FieldValue.increment(-penalty),
        });

        Map<String, int> filledStatus = {};
        for(var p in PHASES) filledStatus[p['position']] = p['count'];
        batch.update(userRef, {'auctionStatus': filledStatus});

        await batch.commit();
      }
    }
  }
}