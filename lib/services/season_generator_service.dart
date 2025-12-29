import 'package:cloud_firestore/cloud_firestore.dart';

class SeasonGeneratorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- 1. INICIAR TEMPORADA ---
  Future<void> startSeason(String seasonId) async {
    try {
      var pSnap = await _db.collection('seasons').doc(seasonId).collection('participants').get();
      if (pSnap.docs.length < 2) throw "Mínimo 2 jugadores.";

      await _autoFillSquads(seasonId, pSnap.docs);

      int numTeams = pSnap.docs.length;
      if (numTeams % 2 != 0) numTeams++;
      int totalLeagueRounds = (numTeams - 1) * 2;

      await _generateLeagueFixture(seasonId, pSnap.docs, totalLeagueRounds);
      await _generateCupStructure(seasonId, pSnap.docs, totalLeagueRounds);

      if (pSnap.docs.length >= 4) {
        await _generateChampionsStructure(seasonId, pSnap.docs, totalLeagueRounds);
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

  // --- 2. RELLENAR COPA (Trigger Fecha 4) ---
  Future<void> fillCupBracketFromStandings(String seasonId) async {
    // 1. Obtener seeds
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

    // 2. Buscar partidos NO iniciados
    var matchesSnap = await _db.collection('seasons').doc(seasonId).collection('matches')
        .where('type', isEqualTo: 'CUP')
        .where('status', isEqualTo: 'SCHEDULED')
        .get();

    WriteBatch batch = _db.batch();
    bool updatedSomething = false;

    for (var doc in matchesSnap.docs) {
      Map<String, dynamic> updateData = {};
      String hPlace = doc['homePlaceholder'] ?? '';
      String aPlace = doc['awayPlaceholder'] ?? '';

      // Resolver LOCAL
      if (hPlace.startsWith('Seed')) {
        try {
          int seedIdx = int.parse(hPlace.split(' ')[1]) - 1;
          if (seedIdx < seeds.length) updateData['homeUser'] = seeds[seedIdx];
        } catch(e) {}
      }

      // Resolver VISITA
      if (aPlace.startsWith('Seed')) {
        try {
          int seedIdx = int.parse(aPlace.split(' ')[1]) - 1;
          if (seedIdx < seeds.length) updateData['awayUser'] = seeds[seedIdx];
        } catch(e) {}
      }

      // ACTIVAR PARTIDO SI AMBOS ESTÁN LISTOS
      String currentHome = updateData['homeUser'] ?? doc['homeUser'];
      String currentAway = updateData['awayUser'] ?? doc['awayUser'];

      bool homeReady = (currentHome != 'TBD' && !currentHome.startsWith('GANADOR'));
      bool awayReady = (currentAway != 'TBD' && !currentAway.startsWith('GANADOR'));

      if (homeReady && awayReady) {
        updateData['status'] = 'PENDING';
        updatedSomething = true;
      }

      if (updateData.isNotEmpty) {
        batch.update(doc.reference, updateData);
      }
    }

    if (updatedSomething) {
      await batch.commit();
      await _db.collection('seasons').doc(seasonId).update({'cupGenerated': true});
    }
  }

  // --- 3. GENERAR ESTRUCTURA COPA ---
  Future<void> _generateCupStructure(String seasonId, List participants, int totalLeagueRounds) async {
    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    int n = participants.length;

    int mainDrawSize = _getNearestPowerOfTwo(n);
    int numPreliminaries = n - mainDrawSize;

    int roundPrelim = 149;
    int roundMain = 150;
    int roundSemis = 151;
    int roundFinal = 152;

    // --- CORRECCIÓN AQUÍ --- FASE PRELIMINAR (REPECHAJE)
    // Total de equipos involucrados en preliminares = numPreliminaries * 2
    // Si n=10, numPrel=2. Total involucrados=4.
    // Los seeds involucrados son los últimos 4: Seeds 7, 8, 9, 10.
    // Índice de inicio (base 0) = n - (numPrel * 2) = 10 - 4 = 6.
    int startSeedIndex = n - (numPreliminaries * 2);

    for (int i = 0; i < numPreliminaries; i++) {
      // Emparejamos de afuera hacia adentro:
      // i=0: El mejor de los peores (idx 6) vs El peor absoluto (idx 9)
      // i=1: El segundo mejor (idx 7) vs El segundo peor (idx 8)

      int seedHomeIdx = startSeedIndex + i;
      int seedAwayIdx = (n - 1) - i;

      _createPlaceholder(batch, ref, 'CUP', 'Preliminar ${i+1}', roundPrelim,
          'Seed ${seedHomeIdx+1}', 'Seed ${seedAwayIdx+1}');
    }
    // --- FIN CORRECCIÓN ---

    // CUADRO PRINCIPAL
    if (mainDrawSize == 8) {
      _createMatchOrWait(batch, ref, 'Cuartos A', roundMain, 1, 8, n, numPreliminaries, 1);
      _createMatchOrWait(batch, ref, 'Cuartos B', roundMain, 2, 7, n, numPreliminaries, 2);
      _createMatchOrWait(batch, ref, 'Cuartos C', roundMain, 3, 6, n, numPreliminaries, 3);
      _createMatchOrWait(batch, ref, 'Cuartos D', roundMain, 4, 5, n, numPreliminaries, 4);

      // Semis
      _createPlaceholder(batch, ref, 'CUP', 'Semifinal A', roundSemis, 'GANADOR Cuartos A', 'GANADOR Cuartos D');
      _createPlaceholder(batch, ref, 'CUP', 'Semifinal B', roundSemis, 'GANADOR Cuartos B', 'GANADOR Cuartos C');
    }
    else if (mainDrawSize <= 4) {
      _createMatchOrWait(batch, ref, 'Semifinal A', roundMain, 1, 4, n, numPreliminaries, 1);
      _createMatchOrWait(batch, ref, 'Semifinal B', roundMain, 2, 3, n, numPreliminaries, 2);
    }

    // FINAL
    _createPlaceholder(batch, ref, 'CUP', 'Gran Final', roundFinal, 'FINALISTA A', 'FINALISTA B');

    await batch.commit();
  }

  void _createMatchOrWait(WriteBatch batch, CollectionReference ref, String name, int round, int seed1, int seed2, int totalTeams, int numPrelims, int prelimIndex) {
    String label1 = _getSeedLabel(seed1, totalTeams, numPrelims, prelimIndex);
    String label2 = _getSeedLabel(seed2, totalTeams, numPrelims, prelimIndex);
    _createPlaceholder(batch, ref, 'CUP', name, round, label1, label2);
  }

  String _getSeedLabel(int seedNumber, int totalTeams, int numPrelims, int prelimIndex) {
    int threshold = totalTeams - (numPrelims * 2);
    if (seedNumber > threshold) {
      return "GANADOR P$prelimIndex";
    }
    return "Seed $seedNumber";
  }

  int _getNearestPowerOfTwo(int n) {
    int power = 1;
    while (power * 2 <= n) power *= 2;
    return power;
  }

  // --- CHAMPIONS & LIGA (Sin cambios) ---
  Future<void> _generateChampionsStructure(String seasonId, List participants, int totalLeagueRounds) async {
    await generateChampionsGroups(seasonId);
    WriteBatch batch = _db.batch();
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Repechaje 1 Ida', 250, '2do A', '3ro B');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Repechaje 2 Ida', 250, '2do B', '3ro A');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Repechaje 1 Vuelta', 251, '3ro B', '2do A');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Repechaje 2 Vuelta', 251, '3ro A', '2do B');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Semifinal 1 Ida', 252, '1er A', 'GANADOR REP 2');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Semifinal 2 Ida', 252, '1er B', 'GANADOR REP 1');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Semifinal 1 Vuelta', 253, 'GANADOR REP 2', '1er A');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Semifinal 2 Vuelta', 253, 'GANADOR REP 1', '1er B');
    _createPlaceholder(batch, ref, 'CHAMPIONS', 'Gran Final', 254, 'FINALISTA 1', 'FINALISTA 2');
    await batch.commit();
  }

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
    _generateGroupFixture(seasonId, groupA, 'A', 201, batch);
    _generateGroupFixture(seasonId, groupB, 'B', 201, batch);
    await batch.commit();
  }

  void _generateGroupFixture(String seasonId, List<String> teamIds, String groupName, int startRound, WriteBatch batch) {
    List<String> rotation = List.from(teamIds);
    if (rotation.length % 2 != 0) rotation.add("BYE");
    int rounds = rotation.length - 1;
    int half = rotation.length ~/ 2;
    var ref = _db.collection('seasons').doc(seasonId).collection('matches');
    for (int r = 0; r < rounds; r++) {
      for (int i = 0; i < half; i++) {
        String a = rotation[i]; String b = rotation[rotation.length - 1 - i];
        if (a == "BYE" || b == "BYE") continue;
        batch.set(ref.doc(), {'type': 'CHAMPIONS', 'group': groupName, 'roundName': 'Grupo $groupName F${r+1}', 'round': startRound + r, 'homeUser': (r%2==0)?a:b, 'awayUser': (r%2==0)?b:a, 'homeScore': null, 'awayScore': null, 'status': 'PENDING', 'playedAt': null});
      }
      rotation.insert(1, rotation.removeLast());
    }
  }

  Future<void> _generateLeagueFixture(String seasonId, List participants, int totalRounds) async {
    List<String> ids = participants.map((d) => d.id.toString()).toList();
    if (ids.length % 2 != 0) ids.add("BYE");
    int nRounds = ids.length - 1;
    int half = ids.length ~/ 2;
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