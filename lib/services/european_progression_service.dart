import 'package:cloud_firestore/cloud_firestore.dart';
import 'news_service.dart'; // <--- IMPORT NUEVO

class EuropeanProgressionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. CHEQUEAR FIN DE FASE DE GRUPOS
  Future<void> checkGroupStageEnd(String seasonId) async {
    // Verificamos si todos los partidos de grupos (5 fechas) se jugaron
    var pending = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CHAMPIONS_GROUP')
        .where('status', isNotEqualTo: 'PLAYED')
        .get();

    bool anyPending = pending.docs.any((d) => d['status'] != 'PLAYED');
    if (anyPending) return;

    List<Map<String, dynamic>> tableA = await _calculateGroupTable(seasonId, 'A');
    List<Map<String, dynamic>> tableB = await _calculateGroupTable(seasonId, 'B');

    if (tableA.length < 5 || tableB.length < 5) return;

    // --- ASIGNACIONES ---
    // 1ros -> A Semis de Champions
    await _replacePlaceholder(seasonId, '1ro Grupo A', tableA[0]['id']);
    await _replacePlaceholder(seasonId, '1ro Grupo B', tableB[0]['id']);

    // 2dos y 3ros -> A Repechaje Champions
    await _replacePlaceholder(seasonId, '2do Grupo A', tableA[1]['id']);
    await _replacePlaceholder(seasonId, '2do Grupo B', tableB[1]['id']);
    await _replacePlaceholder(seasonId, '3ro Grupo A', tableA[2]['id']);
    await _replacePlaceholder(seasonId, '3ro Grupo B', tableB[2]['id']);

    // 4tos y 5tos -> A Repechaje Europa League
    await _replacePlaceholder(seasonId, '4to Grupo A', tableA[3]['id']);
    await _replacePlaceholder(seasonId, '4to Grupo B', tableB[3]['id']);
    await _replacePlaceholder(seasonId, '5to Grupo A', tableA[4]['id']);
    await _replacePlaceholder(seasonId, '5to Grupo B', tableB[4]['id']);
  }

  // 2. CHEQUEAR FIN DE REPECHAJES (CON NOTICIAS DE DESCENSO)
  Future<void> checkForPlayoffAdvances(String seasonId, String matchType, String matchId, Map<String, dynamic> matchData) async {
    // Solo actuamos si es partido de VUELTA
    if (!matchData['roundName'].toString().contains('Vuelta')) return;

    int currentRound = matchData['round'];
    String homeId = matchData['homeUser'];
    String awayId = matchData['awayUser'];

    // Buscar partido de IDA (currentRound - 1, equipos invertidos)
    var idaQuery = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: matchType)
        .where('round', isEqualTo: currentRound - 1)
        .where('homeUser', isEqualTo: awayId)
        .where('awayUser', isEqualTo: homeId)
        .get();

    if (idaQuery.docs.isEmpty) return;
    var idaData = idaQuery.docs.first.data();

    // Calcular Global
    int scoreHomeGlobal = (matchData['homeScore'] as int) + (idaData['awayScore'] as int);
    int scoreAwayGlobal = (matchData['awayScore'] as int) + (idaData['homeScore'] as int);

    String winnerId = "";
    String loserId = "";

    if (scoreHomeGlobal > scoreAwayGlobal) {
      winnerId = homeId; loserId = awayId;
    } else if (scoreAwayGlobal > scoreHomeGlobal) {
      winnerId = awayId; loserId = homeId;
    } else {
      if (matchData['definedByPenalties'] == true && matchData['penaltyWinner'] != null) {
        winnerId = matchData['penaltyWinner'];
        loserId = (winnerId == homeId) ? awayId : homeId;
      } else {
        winnerId = homeId; loserId = awayId; // Fallback
      }
    }

    String placeholderBase = "";
    if (matchData['roundName'].toString().contains("1")) placeholderBase = "1";
    if (matchData['roundName'].toString().contains("2")) placeholderBase = "2";

    if (matchType == 'UCL_PLAYOFF') {
      // Ganador -> Semis Champions
      await _replacePlaceholder(seasonId, 'GANADOR UCL_PO $placeholderBase', winnerId);
      // Perdedor -> Semis Europa League (NOTICIA)
      await _replacePlaceholder(seasonId, 'PERDEDOR UCL_PO $placeholderBase', loserId);

      String loserName = await _getTeamName(seasonId, loserId);
      NewsService().createCompetitionNews(
          seasonId: seasonId,
          teamName: loserName,
          eventType: 'DROP_TO_EUROPA'
      );
    }
    else if (matchType == 'UEL_PLAYOFF') {
      // Ganador -> Semis Europa League
      await _replacePlaceholder(seasonId, 'GANADOR UEL_PO $placeholderBase', winnerId);
      // Perdedor -> Final Conference (NOTICIA)
      await _replacePlaceholder(seasonId, 'PERDEDOR UEL_PO $placeholderBase', loserId);

      String loserName = await _getTeamName(seasonId, loserId);
      NewsService().createCompetitionNews(
          seasonId: seasonId,
          teamName: loserName,
          eventType: 'DROP_TO_CONFERENCE'
      );
    }
  }

  // 3. CHEQUEAR SEMIFINALES
  Future<void> checkForSemiAdvances(String seasonId, String matchType, String matchId, Map<String, dynamic> matchData) async {
    if (!matchData['roundName'].toString().contains('Vuelta')) return;

    int currentRound = matchData['round'];
    String homeId = matchData['homeUser'];
    String awayId = matchData['awayUser'];

    var idaQuery = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: matchType)
        .where('round', isEqualTo: currentRound - 1)
        .where('homeUser', isEqualTo: awayId)
        .where('awayUser', isEqualTo: homeId)
        .get();

    if (idaQuery.docs.isEmpty) return;
    var idaData = idaQuery.docs.first.data();

    int scoreHomeGlobal = (matchData['homeScore'] as int) + (idaData['awayScore'] as int);
    int scoreAwayGlobal = (matchData['awayScore'] as int) + (idaData['homeScore'] as int);

    String winnerId = "";
    if (scoreHomeGlobal > scoreAwayGlobal) winnerId = homeId;
    else if (scoreAwayGlobal > scoreHomeGlobal) winnerId = awayId;
    else {
      if (matchData['definedByPenalties'] == true && matchData['penaltyWinner'] != null) {
        winnerId = matchData['penaltyWinner'];
      } else {
        winnerId = homeId;
      }
    }

    String placeholderBase = "";
    if (matchData['roundName'].toString().contains("1")) placeholderBase = "1";
    if (matchData['roundName'].toString().contains("2")) placeholderBase = "2";

    if (matchType == 'CHAMPIONS_SEMI') {
      await _replacePlaceholder(seasonId, 'GANADOR Semi UCL $placeholderBase', winnerId);
    } else if (matchType == 'EUROPA_SEMI') {
      await _replacePlaceholder(seasonId, 'GANADOR Semi UEL $placeholderBase', winnerId);
    }
  }

  // --- HELPERS ---
  Future<void> _replacePlaceholder(String seasonId, String placeholderTag, String realTeamId) async {
    var queryH = await _db.collection('seasons').doc(seasonId).collection('matches').where('homePlaceholder', isEqualTo: placeholderTag).get();
    var queryA = await _db.collection('seasons').doc(seasonId).collection('matches').where('awayPlaceholder', isEqualTo: placeholderTag).get();

    for (var doc in queryH.docs) {
      await doc.reference.update({'homeUser': realTeamId, 'status': _checkIfReady(doc, homeId: realTeamId)});
    }
    for (var doc in queryA.docs) {
      await doc.reference.update({'awayUser': realTeamId, 'status': _checkIfReady(doc, awayId: realTeamId)});
    }
  }

  String _checkIfReady(DocumentSnapshot doc, {String? homeId, String? awayId}) {
    String h = homeId ?? doc['homeUser'];
    String a = awayId ?? doc['awayUser'];
    if (h != 'TBD' && !h.startsWith('GANADOR') && !h.startsWith('PERDEDOR') &&
        a != 'TBD' && !a.startsWith('GANADOR') && !a.startsWith('PERDEDOR')) {
      return 'PENDING';
    }
    return 'SCHEDULED';
  }

  Future<String> _getTeamName(String seasonId, String teamId) async {
    var doc = await _db.collection('seasons').doc(seasonId).collection('participants').doc(teamId).get();
    return doc.data()?['teamName'] ?? 'Equipo';
  }

  Future<List<Map<String, dynamic>>> _calculateGroupTable(String seasonId, String group) async {
    var matches = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CHAMPIONS_GROUP')
        .where('group', isEqualTo: group)
        .where('status', isEqualTo: 'PLAYED')
        .get();

    Map<String, Map<String, dynamic>> stats = {};

    for (var doc in matches.docs) {
      var d = doc.data();
      String h = d['homeUser']; String a = d['awayUser'];
      int hs = d['homeScore']; int as = d['awayScore'];

      if (!stats.containsKey(h)) stats[h] = {'id': h, 'pts': 0, 'gf': 0, 'gc': 0};
      if (!stats.containsKey(a)) stats[a] = {'id': a, 'pts': 0, 'gf': 0, 'gc': 0};

      stats[h]!['gf'] += hs; stats[h]!['gc'] += as;
      stats[a]!['gf'] += as; stats[a]!['gc'] += hs;

      if (hs > as) stats[h]!['pts'] += 3;
      else if (as > hs) stats[a]!['pts'] += 3;
      else { stats[h]!['pts'] += 1; stats[a]!['pts'] += 1; }
    }

    List<Map<String, dynamic>> table = stats.values.toList();
    table.sort((a, b) {
      int pts = b['pts'].compareTo(a['pts']);
      if (pts != 0) return pts;
      int difA = a['gf'] - a['gc'];
      int difB = b['gf'] - b['gc'];
      return difB.compareTo(difA);
    });
    return table;
  }
}