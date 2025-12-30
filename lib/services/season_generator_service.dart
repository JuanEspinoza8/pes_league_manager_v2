import 'package:cloud_firestore/cloud_firestore.dart';

class SeasonGeneratorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> startSeason(String seasonId, List<String> supercopaIds) async {
    try {
      var pSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();
      if (pSnap.docs.length < 2) throw "Mínimo 2 jugadores.";

      await _autoFillSquads(seasonId, pSnap.docs);

      int numTeams = pSnap.docs.length;
      if (numTeams % 2 != 0) numTeams++;
      int totalLeagueRounds = (numTeams - 1) * 2;

      // 1. Supercopa
      await _generateSupercopa(seasonId, supercopaIds);

      // 2. Liga
      await _generateLeagueFixture(seasonId, pSnap.docs, totalLeagueRounds);

      // 3. Copa
      await _generateCupStructure(seasonId, pSnap.docs, totalLeagueRounds);

      // 4. Europa (Champions, Europa, Conference)
      if (pSnap.docs.length >= 4) {
        await _generateEuropeanStructure(seasonId, pSnap.docs, totalLeagueRounds);
      }

      await _db.collection('seasons').doc(seasonId).update({
        'status': 'ACTIVE',
        'currentRound': 1,
        'cupGenerated': false,
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error StartSeason: $e");
      rethrow;
    }
  }

  Future<void> _generateSupercopa(String seasonId, List<String> teams) async {
    if (teams.length != 4) return;
    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    teams.shuffle();
    // Semis
    _createMatch(batch, ref, 'SUPERCOPA_SEMI', 'Supercopa Semi 1', -2, teams[0], teams[1]);
    _createMatch(batch, ref, 'SUPERCOPA_SEMI', 'Supercopa Semi 2', -2, teams[2], teams[3]);
    // Final
    _createPlaceholder(batch, ref, 'SUPERCOPA_FINAL', 'Supercopa Final', -1, 'GANADOR Supercopa Semi 1', 'GANADOR Supercopa Semi 2');
    await batch.commit();
  }

  // --- ESTRUCTURA EUROPEA ---
  Future<void> _generateEuropeanStructure(String seasonId, List participants, int totalLeagueRounds) async {
    // 1. Fase de Grupos (CORREGIDO: Solo Ida, 5 fechas)
    await generateChampionsGroups(seasonId);

    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');

    // === REPECHAJES (IDA Y VUELTA) - Rondas 250 y 251 ===
    // UCL: 2do vs 3ro
    _createPlaceholder(batch, ref, 'UCL_PLAYOFF', 'Repechaje UCL 1 (Ida)', 250, '3ro Grupo B', '2do Grupo A');
    _createPlaceholder(batch, ref, 'UCL_PLAYOFF', 'Repechaje UCL 2 (Ida)', 250, '3ro Grupo A', '2do Grupo B');

    _createPlaceholder(batch, ref, 'UCL_PLAYOFF', 'Repechaje UCL 1 (Vuelta)', 251, '2do Grupo A', '3ro Grupo B');
    _createPlaceholder(batch, ref, 'UCL_PLAYOFF', 'Repechaje UCL 2 (Vuelta)', 251, '2do Grupo B', '3ro Grupo A');

    // UEL: 4to vs 5to
    _createPlaceholder(batch, ref, 'UEL_PLAYOFF', 'Repechaje UEL 1 (Ida)', 250, '5to Grupo B', '4to Grupo A');
    _createPlaceholder(batch, ref, 'UEL_PLAYOFF', 'Repechaje UEL 2 (Ida)', 250, '5to Grupo A', '4to Grupo B');

    _createPlaceholder(batch, ref, 'UEL_PLAYOFF', 'Repechaje UEL 1 (Vuelta)', 251, '4to Grupo A', '5to Grupo B');
    _createPlaceholder(batch, ref, 'UEL_PLAYOFF', 'Repechaje UEL 2 (Vuelta)', 251, '4to Grupo B', '5to Grupo A');

    // === SEMIFINALES (IDA Y VUELTA) - Rondas 260 y 261 ===

    // SEMIS CHAMPIONS (1ro Grupo vs Ganador Repechaje)
    _createPlaceholder(batch, ref, 'CHAMPIONS_SEMI', 'Semi UCL 1 (Ida)', 260, 'GANADOR UCL_PO 1', '1ro Grupo A');
    _createPlaceholder(batch, ref, 'CHAMPIONS_SEMI', 'Semi UCL 2 (Ida)', 260, 'GANADOR UCL_PO 2', '1ro Grupo B');

    _createPlaceholder(batch, ref, 'CHAMPIONS_SEMI', 'Semi UCL 1 (Vuelta)', 261, '1ro Grupo A', 'GANADOR UCL_PO 1');
    _createPlaceholder(batch, ref, 'CHAMPIONS_SEMI', 'Semi UCL 2 (Vuelta)', 261, '1ro Grupo B', 'GANADOR UCL_PO 2');

    // SEMIS EUROPA LEAGUE (Ganador Repechaje UEL vs Perdedor Repechaje UCL)
    _createPlaceholder(batch, ref, 'EUROPA_SEMI', 'Semi UEL 1 (Ida)', 260, 'GANADOR UEL_PO 1', 'PERDEDOR UCL_PO 1');
    _createPlaceholder(batch, ref, 'EUROPA_SEMI', 'Semi UEL 2 (Ida)', 260, 'GANADOR UEL_PO 2', 'PERDEDOR UCL_PO 2');

    _createPlaceholder(batch, ref, 'EUROPA_SEMI', 'Semi UEL 1 (Vuelta)', 261, 'PERDEDOR UCL_PO 1', 'GANADOR UEL_PO 1');
    _createPlaceholder(batch, ref, 'EUROPA_SEMI', 'Semi UEL 2 (Vuelta)', 261, 'PERDEDOR UCL_PO 2', 'GANADOR UEL_PO 2');

    // === FINALES (PARTIDO ÚNICO) - Ronda 270 ===

    // CONFERENCE (Perdedores Repechaje UEL)
    _createPlaceholder(batch, ref, 'CONFERENCE_FINAL', 'FINAL CONFERENCE', 270, 'PERDEDOR UEL_PO 1', 'PERDEDOR UEL_PO 2');

    // EUROPA LEAGUE
    _createPlaceholder(batch, ref, 'EUROPA_FINAL', 'FINAL EUROPA LEAGUE', 270, 'GANADOR Semi UEL 1', 'GANADOR Semi UEL 2');

    // CHAMPIONS
    _createPlaceholder(batch, ref, 'CHAMPIONS_FINAL', 'FINAL CHAMPIONS', 270, 'GANADOR Semi UCL 1', 'GANADOR Semi UCL 2');

    await batch.commit();
  }

  // --- LÓGICA DE GRUPOS CORREGIDA (SOLO IDA = 5 Fechas) ---
  Future<void> generateChampionsGroups(String seasonId) async {
    var pSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    var ids = pSnap.docs.map((d) => d.id).toList();
    ids.shuffle();
    int mid = (ids.length / 2).ceil();
    var groupA = ids.sublist(0, mid);
    var groupB = ids.sublist(mid);

    WriteBatch batch = _db.batch();
    for (var id in groupA) batch.update(_db.collection('seasons').doc(seasonId).collection('participants').doc(id), {'championsGroup': 'A'});
    for (var id in groupB) batch.update(_db.collection('seasons').doc(seasonId).collection('participants').doc(id), {'championsGroup': 'B'});

    // SOLO IDA (Rondas 201 a 205)
    _generateGroupFixture(seasonId, groupA, 'A', 201, batch);
    _generateGroupFixture(seasonId, groupB, 'B', 201, batch);

    await batch.commit();
  }

  void _generateGroupFixture(String seasonId, List<String> teamIds, String groupName, int startRound, WriteBatch batch) {
    List<String> rotation = List.from(teamIds);
    // Si son impares (ej: 5), agregamos BYE
    if (rotation.length % 2 != 0) rotation.add("BYE");
    int rounds = rotation.length - 1; // Para 5 equipos (+BYE=6) -> 5 fechas
    int half = rotation.length ~/ 2;
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');

    for (int r = 0; r < rounds; r++) {
      for (int i = 0; i < half; i++) {
        String a = rotation[i]; String b = rotation[rotation.length - 1 - i];
        if (a == "BYE" || b == "BYE") continue;

        batch.set(ref.doc(), {
          'type': 'CHAMPIONS_GROUP',
          'group': groupName,
          'roundName': 'Grupo $groupName F${r+1}',
          'round': startRound + r,
          'homeUser': (r%2==0)?a:b,
          'awayUser': (r%2==0)?b:a,
          'homeScore': null,
          'awayScore': null,
          'status': 'PENDING',
          'playedAt': null
        });
      }
      rotation.insert(1, rotation.removeLast());
    }
  }

  // --- MÉTODOS EXISTENTES (Liga, Copa, Autofill) SIN CAMBIOS ---
  Future<void> fillCupBracketFromStandings(String seasonId) async {
    var pSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();
    var teams = pSnap.docs.toList();
    teams.sort((a,b) {
      var sA = (a.data() as Map)['leagueStats'] ?? {};
      var sB = (b.data() as Map)['leagueStats'] ?? {};
      int ptsA = sA['pts']??0; int ptsB = sB['pts']??0;
      if (ptsA != ptsB) return ptsB.compareTo(ptsA);
      return (sB['dif']??0).compareTo(sA['dif']??0);
    });
    List<String> seeds = teams.map((d) => d.id).toList();
    var matchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches').where('type', isEqualTo: 'CUP').where('status', isEqualTo: 'SCHEDULED').get();
    WriteBatch batch = _db.batch();
    bool updatedSomething = false;
    for (var doc in matchesSnap.docs) {
      Map<String, dynamic> updateData = {};
      String hPlace = doc['homePlaceholder'] ?? '';
      String aPlace = doc['awayPlaceholder'] ?? '';
      if (hPlace.startsWith('Seed')) {
        try { int seedIdx = int.parse(hPlace.split(' ')[1]) - 1; if (seedIdx < seeds.length) updateData['homeUser'] = seeds[seedIdx]; } catch(e) {}
      }
      if (aPlace.startsWith('Seed')) {
        try { int seedIdx = int.parse(aPlace.split(' ')[1]) - 1; if (seedIdx < seeds.length) updateData['awayUser'] = seeds[seedIdx]; } catch(e) {}
      }
      String currentHome = updateData['homeUser'] ?? doc['homeUser'];
      String currentAway = updateData['awayUser'] ?? doc['awayUser'];
      bool homeReady = (currentHome != 'TBD' && !currentHome.startsWith('GANADOR'));
      bool awayReady = (currentAway != 'TBD' && !currentAway.startsWith('GANADOR'));
      if (homeReady && awayReady) { updateData['status'] = 'PENDING'; updatedSomething = true; }
      if (updateData.isNotEmpty) batch.update(doc.reference, updateData);
    }
    if (updatedSomething) { await batch.commit(); await _db.collection('seasons').doc(seasonId).update({'cupGenerated': true}); }
  }

  Future<void> _generateCupStructure(String seasonId, List participants, int totalLeagueRounds) async {
    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    int n = participants.length;
    int mainDrawSize = _getNearestPowerOfTwo(n);
    int numPreliminaries = n - mainDrawSize;
    int roundPrelim = 149; int roundMain = 150; int roundSemis = 151; int roundFinal = 152;
    int startSeedIndex = n - (numPreliminaries * 2);
    for (int i = 0; i < numPreliminaries; i++) {
      int seedHomeIdx = startSeedIndex + i; int seedAwayIdx = (n - 1) - i;
      _createPlaceholder(batch, ref, 'CUP', 'Preliminar ${i+1}', roundPrelim, 'Seed ${seedHomeIdx+1}', 'Seed ${seedAwayIdx+1}');
    }
    if (mainDrawSize == 8) {
      _createMatchOrWait(batch, ref, 'Cuartos A', roundMain, 1, 8, n, numPreliminaries, 1);
      _createMatchOrWait(batch, ref, 'Cuartos B', roundMain, 2, 7, n, numPreliminaries, 2);
      _createMatchOrWait(batch, ref, 'Cuartos C', roundMain, 3, 6, n, numPreliminaries, 3);
      _createMatchOrWait(batch, ref, 'Cuartos D', roundMain, 4, 5, n, numPreliminaries, 4);
      _createPlaceholder(batch, ref, 'CUP', 'Semifinal A', roundSemis, 'GANADOR Cuartos A', 'GANADOR Cuartos D');
      _createPlaceholder(batch, ref, 'CUP', 'Semifinal B', roundSemis, 'GANADOR Cuartos B', 'GANADOR Cuartos C');
    } else if (mainDrawSize <= 4) {
      _createMatchOrWait(batch, ref, 'Semifinal A', roundMain, 1, 4, n, numPreliminaries, 1);
      _createMatchOrWait(batch, ref, 'Semifinal B', roundMain, 2, 3, n, numPreliminaries, 2);
    }
    _createPlaceholder(batch, ref, 'CUP', 'Gran Final', roundFinal, 'FINALISTA A', 'FINALISTA B');
    await batch.commit();
  }

  void _createMatchOrWait(WriteBatch batch, CollectionReference ref, String name, int round, int seed1, int seed2, int totalTeams, int numPrelims, int prelimIndex) {
    String label1 = _getSeedLabel(seed1, totalTeams, numPrelims, prelimIndex);
    String label2 = _getSeedLabel(seed2, totalTeams, numPrelims, prelimIndex);
    _createPlaceholder(batch, ref, 'CUP', name, round, label1, label2);
  }
  String _getSeedLabel(int seedNumber, int totalTeams, int numPrelims, int prelimIndex) {
    int threshold = totalTeams - (numPrelims * 2); if (seedNumber > threshold) return "GANADOR P$prelimIndex"; return "Seed $seedNumber";
  }
  int _getNearestPowerOfTwo(int n) { int power = 1; while (power * 2 <= n) power *= 2; return power; }

  Future<void> _generateLeagueFixture(String seasonId, List participants, int totalRounds) async {
    List<String> ids = participants.map((d) => d.id.toString()).toList();
    if (ids.length % 2 != 0) ids.add("BYE");
    int nRounds = ids.length - 1; int half = ids.length ~/ 2;
    List<String> teams = List.from(ids);
    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    for (int r = 0; r < nRounds; r++) {
      for (int i = 0; i < half; i++) {
        if (teams[i] == "BYE" || teams[nRounds-i] == "BYE") continue;
        _createMatch(batch, ref, 'LEAGUE', null, r+1, teams[i], teams[nRounds-i]);
      }
      teams.insert(1, teams.removeLast());
    }
    teams = List.from(ids);
    for (int r = 0; r < nRounds; r++) {
      for (int i = 0; i < half; i++) {
        if (teams[i] == "BYE" || teams[nRounds-i] == "BYE") continue;
        _createMatch(batch, ref, 'LEAGUE', null, r+1+nRounds, teams[nRounds-i], teams[i]);
      }
      teams.insert(1, teams.removeLast());
    }
    await batch.commit();
  }

  Future<void> _autoFillSquads(String seasonId, List<QueryDocumentSnapshot> participants) async {
    var p1 = await _db.collection('players').where('rating', isLessThan: 75).limit(200).get();
    var p2 = await _db.collection('players').where('rating', isGreaterThanOrEqualTo: 75).where('rating', isLessThan: 82).limit(100).get();
    List<DocumentSnapshot> pool = [...p1.docs, ...p2.docs]..shuffle();
    WriteBatch batch = _db.batch();
    int idx = 0;
    for (var doc in participants) {
      List roster = doc['roster'] ?? [];
      int missing = 22 - roster.length;
      if (missing > 0) {
        List<String> adds = [];
        for(int k=0; k<missing; k++) if(idx < pool.length) adds.add(pool[idx++].id);
        batch.update(doc.reference, {'roster': FieldValue.arrayUnion(adds)});
      }
    }
    await batch.commit();
  }

  void _createMatch(WriteBatch b, CollectionReference r, String t, String? n, int ro, String h, String a) {
    b.set(r.doc(), {'type': t, 'roundName': n, 'round': ro, 'homeUser': h, 'awayUser': a, 'homeScore': null, 'awayScore': null, 'status': 'PENDING'});
  }
  void _createPlaceholder(WriteBatch b, CollectionReference r, String t, String n, int ro, String hL, String aL) {
    b.set(r.doc(), {'type': t, 'roundName': n, 'round': ro, 'homeUser': 'TBD', 'awayUser': 'TBD', 'homePlaceholder': hL, 'awayPlaceholder': aL, 'homeScore': null, 'awayScore': null, 'status': 'SCHEDULED'});
  }
}