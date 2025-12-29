import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/standings_service.dart';
import '../services/season_generator_service.dart';
import '../services/cup_progression_service.dart';
import '../services/champions_progression_service.dart';

class DebugTools {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. RELLENAR LIGA CON BOTS (Hasta llegar a targetCount)
  Future<void> fillLeagueWithBots(String seasonId, int targetCount) async {
    var participantsRef = _db.collection('seasons').doc(seasonId).collection('participants');
    var snap = await participantsRef.get();
    int current = snap.docs.length;

    if (current >= targetCount) return;

    // Pre-cargar IDs de jugadores
    var playersSnap = await _db.collection('players').limit(300).get();
    List<String> pool = playersSnap.docs.map((d) => d.id).toList();
    pool.shuffle();
    int poolIdx = 0;

    WriteBatch batch = _db.batch();

    for (int i = current + 1; i <= targetCount; i++) {
      String botId = "bot_${DateTime.now().millisecondsSinceEpoch}_$i";

      // Asignar 22 jugadores al bot
      List<String> botRoster = [];
      for(int k=0; k<22; k++) {
        if (poolIdx < pool.length) botRoster.add(pool[poolIdx++]);
      }

      batch.set(participantsRef.doc(botId), {
        'uid': botId,
        'email': "cpu$i@ai.com",
        'teamName': "CPU FC $i",
        'budget': 50000000,
        'roster': botRoster,
        'points_league': 0,
        'role': 'BOT',
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(_db.collection('seasons').doc(seasonId), {
        'participantIds': FieldValue.arrayUnion([botId])
      });
    }

    await batch.commit();
  }

  // 2. SIMULAR JORNADA COMPLETA
  Future<void> simulateRound(String seasonId, int round) async {
    var matchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('round', isEqualTo: round)
        .where('status', isNotEqualTo: 'PLAYED')
        .get();

    if (matchesSnap.docs.isEmpty) return;

    Random rnd = Random();

    for (var doc in matchesSnap.docs) {
      // Simular resultado
      int homeGoals = rnd.nextInt(4);
      int awayGoals = rnd.nextInt(3);

      // Actualizar partido
      await doc.reference.update({
        'homeScore': homeGoals,
        'awayScore': awayGoals,
        'status': 'PLAYED',
        'playedAt': FieldValue.serverTimestamp(),
      });

      // EJECUTAR TRIGGERS
      String type = doc['type'];
      String roundName = doc['roundName'] ?? '';

      if (type == 'LEAGUE') {
        // 1. Recalcular tabla
        await StandingsService().recalculateLeagueStandings(seasonId);

        // 2. Trigger Copa (Fecha 4 o 2)
        if (round == 4 || round == 2) {
          await _checkLeagueTrigger(seasonId, round);
        }
      }
      else if (type == 'CUP') {
        String winnerId = homeGoals > awayGoals ? doc['homeUser'] : doc['awayUser'];
        await CupProgressionService().advanceCupRound(
            seasonId: seasonId,
            roundName: roundName,
            winnerId: winnerId
        );
      }
      else if (type == 'CHAMPIONS') {
        await ChampionsProgressionService().checkGroupStageEnd(seasonId);
      }
    }
  }

  Future<void> _checkLeagueTrigger(String seasonId, int round) async {
    // Verificar si ya no quedan pendientes en esta fecha
    var pending = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('round', isEqualTo: round)
        .where('status', isNotEqualTo: 'PLAYED')
        .get();

    if (pending.docs.isEmpty) {
      try {
        // AQUÍ ESTABA EL ERROR: Nombre de función corregido
        await SeasonGeneratorService().fillCupBracketFromStandings(seasonId);
      } catch (e) {
        print("Copa ya existe o error: $e");
      }
    }
  }
}