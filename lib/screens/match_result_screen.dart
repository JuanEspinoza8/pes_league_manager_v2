import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/standings_service.dart';
import '../services/season_generator_service.dart';
import '../services/notification_service.dart';
import '../services/cup_progression_service.dart';
import '../services/champions_progression_service.dart';
import '../services/gemini_stats_service.dart';
import '../services/stats_service.dart';
import '../services/discipline_service.dart';
import '../services/news_service.dart';
import '../services/supercopa_progression_service.dart';
import '../services/sponsorship_service.dart';
import '../services/ranking_service.dart';

class MatchResultScreen extends StatefulWidget {
  final String seasonId;
  final String matchId;
  final Map<String, dynamic> matchData;
  final bool isAdmin;

  const MatchResultScreen({super.key, required this.seasonId, required this.matchId, required this.matchData, this.isAdmin = false});

  @override
  State<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends State<MatchResultScreen> {
  // --- LÓGICA ORIGINAL INTACTA ---
  final TextEditingController _homeScoreCtrl = TextEditingController();
  final TextEditingController _awayScoreCtrl = TextEditingController();
  final TextEditingController _homePenaltiesCtrl = TextEditingController();
  final TextEditingController _awayPenaltiesCtrl = TextEditingController();

  final Map<String, TextEditingController> _hStats = _initStatsMap();
  final Map<String, TextEditingController> _aStats = _initStatsMap();

  Map<String, Map<String, int>> _homeActions = {};
  Map<String, Map<String, int>> _awayActions = {};

  List<DocumentSnapshot> _homeRoster = [];
  List<DocumentSnapshot> _awayRoster = [];

  List<String> _homeSuspended = [];
  List<String> _awaySuspended = [];
  bool _isLoadingSuspensions = true;

  bool _showPenaltiesInput = false;
  bool isSaving = false;
  bool isScanning = false;
  bool showAdvanced = false;

  static Map<String, TextEditingController> _initStatsMap() {
    return {
      'shots': TextEditingController(text: "0"), 'target': TextEditingController(text: "0"),
      'passes': TextEditingController(text: "0"), 'completed': TextEditingController(text: "0"),
      'possession': TextEditingController(text: "50"), 'fouls': TextEditingController(text: "0"),
      'offsides': TextEditingController(text: "0"), 'interceptions': TextEditingController(text: "0"),
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.matchData['homeScore'] != null) {
      _homeScoreCtrl.text = widget.matchData['homeScore'].toString();
      _awayScoreCtrl.text = widget.matchData['awayScore'].toString();
    }
    if (widget.matchData['definedByPenalties'] == true && widget.matchData['penaltyScore'] != null) {
      _showPenaltiesInput = true;
      try {
        String scores = widget.matchData['penaltyScore'];
        List<String> parts = scores.split('-');
        if (parts.length == 2) {
          _homePenaltiesCtrl.text = parts[0].trim();
          _awayPenaltiesCtrl.text = parts[1].trim();
        }
      } catch (e) {}
    }
    if (widget.matchData['player_actions'] != null) {
      _loadActions(widget.matchData['player_actions']['home'], _homeActions);
      _loadActions(widget.matchData['player_actions']['away'], _awayActions);
    }
    _loadRosters();
    _checkSuspensions();
    _homeScoreCtrl.addListener(_checkDrawCondition);
    _awayScoreCtrl.addListener(_checkDrawCondition);
  }

  void _checkDrawCondition() {
    if (widget.matchData['type'] == 'LEAGUE') return;
    int h = int.tryParse(_homeScoreCtrl.text) ?? -1;
    int a = int.tryParse(_awayScoreCtrl.text) ?? -1;
    if (h >= 0 && a >= 0 && h == a) {
      setState(() => _showPenaltiesInput = true);
    } else {
      setState(() {
        _showPenaltiesInput = false;
        _homePenaltiesCtrl.clear();
        _awayPenaltiesCtrl.clear();
      });
    }
  }

  void _loadActions(dynamic source, Map<String, Map<String, int>> target) {
    if (source == null) return;
    (source as Map).forEach((pid, data) {
      target[pid.toString()] = {
        'goals': data['goals'] ?? 0, 'assists': data['assists'] ?? 0, 'yellowCards': data['yellowCards'] ?? 0, 'redCards': data['redCards'] ?? 0,
      };
    });
  }

  Future<void> _checkSuspensions() async {
    if (widget.matchData['type'] == 'LEAGUE') {
      setState(() => _isLoadingSuspensions = false);
      return;
    }
    if (widget.matchData['preMatchInfo'] != null) {
      Map info = widget.matchData['preMatchInfo'];
      List<String> hSusp = List<String>.from(info['homeSuspended'] ?? []);
      List<String> aSusp = List<String>.from(info['awaySuspended'] ?? []);
      if (hSusp.isNotEmpty || aSusp.isNotEmpty) {
        setState(() { _homeSuspended = hSusp; _awaySuspended = aSusp; _isLoadingSuspensions = false; });
        Future.delayed(Duration.zero, _showSuspensionAlert);
        return;
      }
    }
    final discipline = DisciplineService();
    var hSusp = await discipline.getSuspendedPlayers(seasonId: widget.seasonId, teamId: widget.matchData['homeUser'], competitionType: widget.matchData['type'], currentRound: widget.matchData['round']);
    var aSusp = await discipline.getSuspendedPlayers(seasonId: widget.seasonId, teamId: widget.matchData['awayUser'], competitionType: widget.matchData['type'], currentRound: widget.matchData['round']);
    if (mounted) {
      setState(() { _homeSuspended = hSusp; _awaySuspended = aSusp; _isLoadingSuspensions = false; });
      if (_homeSuspended.isNotEmpty || _awaySuspended.isNotEmpty) Future.delayed(Duration.zero, _showSuspensionAlert);
    }
  }

  void _showSuspensionAlert() {
    String getNames(List<String> ids, List<DocumentSnapshot> roster) {
      if (roster.isEmpty) return ids.join(", ");
      List<String> names = [];
      for (var id in ids) {
        var found = roster.where((doc) => doc.id == id);
        if (found.isNotEmpty) names.add(found.first['name']); else names.add(id);
      }
      return names.join(", ");
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text("⚠️ SANCIONES ACTIVAS", style: TextStyle(color: Colors.redAccent)), backgroundColor: const Color(0xFF1E293B),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Jugadores inhabilitados:", style: TextStyle(fontSize: 12, color: Colors.white70)), const SizedBox(height: 10),
          if (_homeSuspended.isNotEmpty) ...[const Text("LOCAL:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), Text(getNames(_homeSuspended, _homeRoster), style: const TextStyle(color: Colors.redAccent))],
          const SizedBox(height: 8),
          if (_awaySuspended.isNotEmpty) ...[const Text("VISITA:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), Text(getNames(_awaySuspended, _awayRoster), style: const TextStyle(color: Colors.redAccent))]
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ENTENDIDO", style: TextStyle(color: Colors.white54)))]
    ));
  }

  Future<void> _loadRosters() async {
    if (widget.matchData['homeUser'] != 'TBD' && !widget.matchData['homeUser'].toString().startsWith('GANADOR')) {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).get();
      List ids = doc.data()?['roster'] ?? []; if (ids.isNotEmpty) _homeRoster = await _fetchPlayers(ids);
    }
    if (widget.matchData['awayUser'] != 'TBD' && !widget.matchData['awayUser'].toString().startsWith('GANADOR')) {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['awayUser']).get();
      List ids = doc.data()?['roster'] ?? []; if (ids.isNotEmpty) _awayRoster = await _fetchPlayers(ids);
    }
    if (mounted) setState(() {});
  }

  Future<List<DocumentSnapshot>> _fetchPlayers(List ids) async {
    List<String> sIds = ids.map((e) => e.toString()).toList(); List<DocumentSnapshot> all = [];
    for (var i = 0; i < sIds.length; i += 10) {
      var end = (i + 10 < sIds.length) ? i + 10 : sIds.length;
      var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: sIds.sublist(i, end)).get();
      all.addAll(q.docs);
    }
    return all;
  }

  Future<void> _submitResult() async {
    if (_homeScoreCtrl.text.isEmpty || _awayScoreCtrl.text.isEmpty) return;
    int hGoals = int.tryParse(_homeScoreCtrl.text) ?? 0;
    int aGoals = int.tryParse(_awayScoreCtrl.text) ?? 0;

    int assignedH_Goals = _countTotal(_homeActions, 'goals');
    int assignedA_Goals = _countTotal(_awayActions, 'goals');

    if (assignedH_Goals != hGoals || assignedA_Goals != aGoals) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Goles asignados incorrectos ($assignedH_Goals/$hGoals - $assignedA_Goals/$aGoals)."), backgroundColor: Colors.red));
      return;
    }

    String? penaltyWinnerId;
    String? penaltyScoreStr;
    bool definedByPenalties = false;

    if (_showPenaltiesInput) {
      if (_homePenaltiesCtrl.text.isEmpty || _awayPenaltiesCtrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Ingresa el resultado de los penales."), backgroundColor: Colors.orange));
        return;
      }
      int hPen = int.tryParse(_homePenaltiesCtrl.text) ?? 0;
      int aPen = int.tryParse(_awayPenaltiesCtrl.text) ?? 0;
      if (hPen == aPen) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Penales no pueden ser empate."), backgroundColor: Colors.red));
        return;
      }
      definedByPenalties = true;
      penaltyScoreStr = "$hPen-$aPen";
      penaltyWinnerId = (hPen > aPen) ? widget.matchData['homeUser'] : widget.matchData['awayUser'];
    }

    setState(() => isSaving = true);

    try {
      Map<String, dynamic> advancedStats = { 'home': _extractStatsMap(hGoals, _hStats), 'away': _extractStatsMap(aGoals, _aStats) };
      Map<String, dynamic> actionsMap = { 'home': _homeActions, 'away': _awayActions };

      Map<String, int> scorersSimpleH = {};
      _homeActions.forEach((k, v) { if(v['goals']! > 0) scorersSimpleH[k] = v['goals']!; });

      Map<String, int> scorersSimpleA = {};
      _awayActions.forEach((k, v) { if(v['goals']! > 0) scorersSimpleA[k] = v['goals']!; });

      Map<String, dynamic> updateData = {
        'homeScore': hGoals, 'awayScore': aGoals,
        'status': widget.isAdmin ? 'PLAYED' : 'REPORTED',
        'playedAt': FieldValue.serverTimestamp(),
        'stats': advancedStats,
        'player_actions': actionsMap,
        'scorers': {'home': scorersSimpleH, 'away': scorersSimpleA},
        'definedByPenalties': definedByPenalties,
        'penaltyWinner': penaltyWinnerId,
        'penaltyScore': penaltyScoreStr,
      };

      if (!widget.isAdmin) updateData['reportedBy'] = FirebaseAuth.instance.currentUser!.uid;

      var matchRef = FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('matches').doc(widget.matchId);
      await matchRef.update(updateData);

      if (widget.isAdmin) {
        if (widget.matchData['type'] != 'LEAGUE') {
          var updatedSnapshot = await matchRef.get();
          await DisciplineService().propagateSuspensionsToNextMatch(widget.seasonId, updatedSnapshot.data()!);
        }
        await _processAdminTasks(hGoals, aGoals, definedByPenalties, penaltyScoreStr);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) { setState(() => isSaving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    }
  }

  Future<void> _processAdminTasks(int hGoals, int aGoals, bool definedByPenalties, String? penaltyScoreStr) async {
    // --- 1. RANKING Y PREMIOS DINÁMICOS (ELO) ---

    // Obtener documentos de los equipos para leer su ranking actual
    var homeDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).get();
    var awayDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['awayUser']).get();

    // Si no tienen ranking (primera vez), asumimos 1000 puntos
    int homeRating = homeDoc.data()?['rankingPoints'] ?? 1000;
    int awayRating = awayDoc.data()?['rankingPoints'] ?? 1000;

    // Determinar resultado (1.0 = Gana, 0.5 = Empate, 0.0 = Pierde)
    double homeResult, awayResult;
    bool homeWon = false, awayWon = false, isDraw = false;

    if (hGoals > aGoals) {
      homeResult = 1.0; awayResult = 0.0; homeWon = true;
    } else if (aGoals > hGoals) {
      homeResult = 0.0; awayResult = 1.0; awayWon = true;
    } else {
      // Si hay penales, el ganador se lleva un poco más de mérito (0.75 vs 0.25 o mantener empate 0.5)
      // Para ranking FIFA puro, empate sigue siendo empate (0.5) en 120mins, pero aquí premiamos al ganador de penales
      if (definedByPenalties && penaltyScoreStr != null) {
        List<String> parts = penaltyScoreStr.split('-');
        int hPen = int.parse(parts[0]);
        int aPen = int.parse(parts[1]);
        if (hPen > aPen) { homeResult = 0.75; awayResult = 0.25; homeWon = true; } // Victoria por penales vale menos que normal
        else { homeResult = 0.25; awayResult = 0.75; awayWon = true; }
      } else {
        homeResult = 0.5; awayResult = 0.5; isDraw = true;
      }
    }

    // Calcular nuevos rankings
    var newHomeStats = RankingService.calculateNewRanking(homeRating, awayRating, homeResult);
    var newAwayStats = RankingService.calculateNewRanking(awayRating, homeRating, awayResult);

    // Calcular dinero ganado
    int homeMoney = RankingService.calculateBudgetReward(homeWon, isDraw, newHomeStats['change']!);
    int awayMoney = RankingService.calculateBudgetReward(awayWon, isDraw, newAwayStats['change']!);

    // ACTUALIZAR BASE DE DATOS (Ranking + Dinero)
    WriteBatch batch = FirebaseFirestore.instance.batch();

    // Update Local
    if (!widget.matchData['homeUser'].startsWith('TBD')) {
      batch.update(homeDoc.reference, {
        'rankingPoints': newHomeStats['newRating'],
        'budget': FieldValue.increment(homeMoney)
      });
    }

    // Update Visita
    if (!widget.matchData['awayUser'].startsWith('TBD')) {
      batch.update(awayDoc.reference, {
        'rankingPoints': newAwayStats['newRating'],
        'budget': FieldValue.increment(awayMoney)
      });
    }

    // Guardar historial del cambio de ranking en el partido (opcional, para mostrarlo luego)
    batch.update(FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('matches').doc(widget.matchId), {
      'rankingChange': {
        'home': newHomeStats['change'],
        'away': newAwayStats['change']
      },
      'rewards': {
        'home': homeMoney,
        'away': awayMoney
      }
    });

    await batch.commit();

    await StatsService().recalculateTeamStats(widget.seasonId);

    // 2. COMPETICIONES
    String type = widget.matchData['type'];
    if (type == 'LEAGUE') {
      await StandingsService().recalculateLeagueStandings(widget.seasonId);
      if (widget.matchData['round'] == 4) await _checkAndFillCup();
    } else if (type == 'CUP') {
      await CupProgressionService().checkForCupAdvances(widget.seasonId);
    } else if (type.contains('SUPERCOPA')) {
      await SupercopaProgressionService().checkForSupercopaAdvances(widget.seasonId, widget.matchId);
    } else if (type.contains('CHAMPIONS') || type.contains('EUROPA') || type.contains('CONFERENCE')) {
      if (widget.matchData['round'] < 250) {
        await StandingsService().recalculateChampionsStandings(widget.seasonId);
        await ChampionsProgressionService().checkGroupStageEnd(widget.seasonId);
      } else {
        await ChampionsProgressionService().checkForChampionsAdvances(widget.seasonId);
      }
    }

    // 3. SPONSORSHIPS
    try {
      String winnerId = "";
      if (hGoals > aGoals) winnerId = widget.matchData['homeUser'];
      else if (aGoals > hGoals) winnerId = widget.matchData['awayUser'];
      else if (definedByPenalties && penaltyScoreStr != null) {
        List<String> parts = penaltyScoreStr.split('-');
        if (int.parse(parts[0]) > int.parse(parts[1])) winnerId = widget.matchData['homeUser'];
        else winnerId = widget.matchData['awayUser'];
      }
      if (winnerId.isNotEmpty && !winnerId.startsWith('TBD') && !winnerId.startsWith('GANADOR')) {
        String wName = await _getTeamName(winnerId);
        await SponsorshipService().tryGenerateSponsorshipOffer(widget.seasonId, winnerId, wName);
      }
    } catch (e) {
      print("Error generando sponsor: $e");
    }

    // 4. NEWS
    String homeName = await _getTeamName(widget.matchData['homeUser']);
    String awayName = await _getTeamName(widget.matchData['awayUser']);
    String homeForm = await _getTeamForm(widget.matchData['homeUser']);
    String awayForm = await _getTeamForm(widget.matchData['awayUser']);

    StringBuffer detailsBuffer = StringBuffer();
    void processActions(Map<String, Map<String, int>> actions, String teamName, List<DocumentSnapshot> roster) {
      actions.forEach((pid, stats) {
        if ((stats['goals']??0) > 0 || (stats['redCards']??0) > 0) {
          String pName = "Un jugador";
          try { pName = roster.firstWhere((d) => d.id == pid)['name']; } catch(e) {}
          List<String> feats = [];
          if ((stats['goals']??0) > 0) feats.add("${stats['goals']} goles");
          if ((stats['redCards']??0) > 0) feats.add("Expulsado");
          if (feats.isNotEmpty) detailsBuffer.write("$pName ($teamName): ${feats.join(', ')}. ");
        }
      });
    }
    processActions(_homeActions, homeName, _homeRoster);
    processActions(_awayActions, awayName, _awayRoster);

    bool isDerby = false;
    try {
      var seasonDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();
      List rivalries = seasonDoc.data()?['rivalries'] ?? [];
      String key1 = "${widget.matchData['homeUser']}_${widget.matchData['awayUser']}";
      String key2 = "${widget.matchData['awayUser']}_${widget.matchData['homeUser']}";
      if (rivalries.contains(key1) || rivalries.contains(key2)) isDerby = true;
    } catch(e) {}

    String? winnerName;
    if (hGoals > aGoals) winnerName = homeName;
    else if (aGoals > hGoals) winnerName = awayName;
    else if (definedByPenalties && penaltyScoreStr != null) {
      try {
        List<String> parts = penaltyScoreStr.split('-');
        if (int.parse(parts[0].trim()) > int.parse(parts[1].trim())) winnerName = homeName;
        else winnerName = awayName;
      } catch (e) {}
    }

    NewsService().createMatchNews(
      seasonId: widget.seasonId,
      homeName: homeName,
      awayName: awayName,
      homeId: widget.matchData['homeUser'],
      awayId: widget.matchData['awayUser'],
      homeScore: hGoals,
      awayScore: aGoals,
      competition: type,
      isPenalties: definedByPenalties,
      penaltyScore: penaltyScoreStr,
      winnerName: winnerName,
      matchDetails: detailsBuffer.toString(),
      isDerby: isDerby,
      homeForm: homeForm,
      awayForm: awayForm,
    );

    String bodyText = "$homeName $hGoals - $aGoals $awayName";
    if (definedByPenalties) bodyText += " (Penales: $penaltyScoreStr)";
    await NotificationService.sendGlobalNotification(seasonId: widget.seasonId, title: "FINALIZADO", body: bodyText, type: "MATCH");
  }

  Future<String> _getTeamForm(String teamId) async {
    if (teamId == 'TBD' || teamId.startsWith('GANADOR')) return "";
    try {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(teamId).get();
      var stats = doc.data()?['leagueStats'];
      if (stats == null) return "Sin datos previos";
      int w = stats['w'] ?? 0; int l = stats['l'] ?? 0; int d = stats['d'] ?? 0; int pts = stats['pts'] ?? 0;
      return "En liga lleva $w ganados, $d empatados y $l perdidos ($pts puntos).";
    } catch (e) { return ""; }
  }

  Future<void> _checkAndFillCup() async { await Future.delayed(const Duration(seconds: 2)); try { await SeasonGeneratorService().fillCupBracketFromStandings(widget.seasonId); } catch(e){} }
  Future<String> _getTeamName(String userId) async { if (userId == 'TBD' || userId.startsWith('GANADOR') || userId.startsWith('Seed') || userId.startsWith('FINALISTA')) return 'Por definir'; var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(userId).get(); return doc.data()?['teamName'] ?? 'Equipo'; }
  int _countTotal(Map<String, Map<String, int>> map, String key) { return map.values.fold(0, (sum, val) => sum + (val[key] ?? 0)); }
  Map<String, int> _extractStatsMap(int goals, Map<String, TextEditingController> ctrls) { return { 'goals': goals, 'shots': int.tryParse(ctrls['shots']!.text)??0, 'shotsOnTarget': int.tryParse(ctrls['target']!.text)??0, 'passes': int.tryParse(ctrls['passes']!.text)??0, 'passesCompleted': int.tryParse(ctrls['completed']!.text)??0, 'possession': int.tryParse(ctrls['possession']!.text)??50, 'fouls': int.tryParse(ctrls['fouls']!.text)??0, 'offsides': int.tryParse(ctrls['offsides']!.text)??0, 'interceptions': int.tryParse(ctrls['interceptions']!.text)??0 }; }

  Future<void> _scanImage() async {
    final ImagePicker picker = ImagePicker(); final XFile? image = await picker.pickImage(source: ImageSource.gallery); if (image == null) return;
    setState(() => isScanning = true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analizando imagen con IA...")));
    try { Uint8List bytes = await image.readAsBytes(); var result = await GeminiStatsService().extractStatsFromImage(bytes); if (result != null) { setState(() { _populateControllers(result['home'], _homeScoreCtrl, _hStats); _populateControllers(result['away'], _awayScoreCtrl, _aStats); showAdvanced = true; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Datos extraídos!"), backgroundColor: Colors.green)); } } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error IA: $e"))); } finally { setState(() => isScanning = false); }
  }
  void _populateControllers(Map data, TextEditingController score, Map<String, TextEditingController> stats) { score.text = (data['goals'] ?? 0).toString(); stats['shots']!.text = (data['shots'] ?? 0).toString(); stats['target']!.text = (data['shotsOnTarget'] ?? 0).toString(); stats['passes']!.text = (data['passes'] ?? 0).toString(); stats['completed']!.text = (data['passesCompleted'] ?? 0).toString(); stats['possession']!.text = (data['possession'] ?? 50).toString(); stats['fouls']!.text = (data['fouls'] ?? 0).toString(); stats['offsides']!.text = (data['offsides'] ?? 0).toString(); stats['interceptions']!.text = (data['interceptions'] ?? 0).toString(); }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    int hGoals = int.tryParse(_homeScoreCtrl.text) ?? 0;
    int aGoals = int.tryParse(_awayScoreCtrl.text) ?? 0;
    int currentH = _countTotal(_homeActions, 'goals');
    int currentA = _countTotal(_awayActions, 'goals');
    int currentH_Assists = _countTotal(_homeActions, 'assists');
    int currentA_Assists = _countTotal(_awayActions, 'assists');
    bool valid = (hGoals == currentH) && (aGoals == currentA) && (currentH_Assists <= hGoals) && (currentA_Assists <= aGoals);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(title: const Text("ACTA DE PARTIDO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)), centerTitle: true, backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: isScanning ? null : _scanImage,
              icon: isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Icon(Icons.qr_code_scanner, color: Colors.black),
              label: Text(isScanning ? "PROCESANDO IMAGEN..." : "ESCANEAR CAPTURA (IA)", style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: goldColor, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 15),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Slate 800
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)]
              ),
              child: Column(
                children: [
                  const Text("TIEMPO REGLAMENTARIO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 2)),
                  const SizedBox(height: 15),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ScoreBox("LOCAL", _homeScoreCtrl, size: 70),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text("-", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: Colors.white.withOpacity(0.2)))),
                        _ScoreBox("VISITA", _awayScoreCtrl, size: 70)
                      ]
                  ),
                  if (_showPenaltiesInput) ...[
                    const SizedBox(height: 25),
                    Divider(color: Colors.white.withOpacity(0.1), indent: 40, endIndent: 40),
                    const SizedBox(height: 10),
                    const Text("PENALES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.orangeAccent, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [_ScoreBox("PEN (L)", _homePenaltiesCtrl, size: 45, isPenalty: true), const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Text("vs", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white24))), _ScoreBox("PEN (V)", _awayPenaltiesCtrl, size: 45, isPenalty: true)]),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildMatchEventsSummary(),
            const SizedBox(height: 20),

            InkWell(
              onTap: () => setState(() => showAdvanced = !showAdvanced),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  // CORRECCIÓN: Usamos Expanded y TextOverflow para evitar el overflow derecho de 22 pixels
                  const Expanded(
                      child: Text("📊 Estadísticas Avanzadas (Posesión, Tiros...)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70), overflow: TextOverflow.ellipsis, maxLines: 1)
                  ),
                  const SizedBox(width: 8),
                  Icon(showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: goldColor)
                ]),
              ),
            ),
            if (showAdvanced) Container(
              margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [_statHeader(), Divider(color: Colors.white.withOpacity(0.1)), _statRow("Tiros (Total / Arco)", _hStats['shots']!, _hStats['target']!, _aStats['shots']!, _aStats['target']!), _statRow("Pases (Total / Comp)", _hStats['passes']!, _hStats['completed']!, _aStats['passes']!, _aStats['completed']!), _statRow("Posesión %", _hStats['possession']!, null, _aStats['possession']!, null), _statRow("Faltas / Offsides", _hStats['fouls']!, _hStats['offsides']!, _aStats['fouls']!, _aStats['offsides']!), _statRow("Intercepciones", _hStats['interceptions']!, null, _aStats['interceptions']!, null)]),
            ),

            const SizedBox(height: 30),
            const Align(alignment: Alignment.centerLeft, child: Text("DETALLE DE JUGADORES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white54, letterSpacing: 1.5))),
            const SizedBox(height: 15),

            _buildTeamRosterTile("Local", hGoals, currentH, currentH_Assists, _homeRoster, _homeActions, _homeSuspended),
            const SizedBox(height: 15),
            _buildTeamRosterTile("Visita", aGoals, currentA, currentA_Assists, _awayRoster, _awayActions, _awaySuspended),

            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity, height: 60,
              child: ElevatedButton(
                  onPressed: (isSaving || (widget.isAdmin && !valid)) ? null : _submitResult,
                  style: ElevatedButton.styleFrom(backgroundColor: valid ? Colors.green : Colors.grey[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 5),
                  child: isSaving ? const CircularProgressIndicator(color: Colors.white) : Text(widget.isAdmin ? (valid ? "CONFIRMAR RESULTADO" : "FALTAN ASIGNAR GOLES") : "ENVIAR REPORTE", style: TextStyle(color: valid ? Colors.white : Colors.white38, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1))
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamRosterTile(String label, int totalGoals, int assignedGoals, int assignedAssists, List<DocumentSnapshot> roster, Map<String, Map<String, int>> actions, List<String> suspended) {
    bool complete = (totalGoals == assignedGoals);
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: Colors.white54, iconColor: const Color(0xFFD4AF37),
          title: Row(children: [Text("$label ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), if(complete) const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16), if(!complete) Text(" (Faltan ${totalGoals - assignedGoals})", style: const TextStyle(color: Colors.redAccent, fontSize: 12))]),
          subtitle: Text("Asistencias: $assignedAssists", style: const TextStyle(fontSize: 12, color: Colors.white38)),
          children: roster.map((p) => _playerRow(p, actions, totalGoals, assignedGoals, assignedAssists, suspended)).toList(),
        ),
      ),
    );
  }

  Widget _ScoreBox(String label, TextEditingController ctrl, {double size = 50, bool isPenalty = false}) {
    return Column(children: [Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isPenalty ? Colors.orangeAccent : Colors.white38, fontSize: 10, letterSpacing: 1)), const SizedBox(height: 8), Container(width: size + 20, height: size, decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(12), border: Border.all(color: isPenalty ? Colors.orange.withOpacity(0.5) : Colors.white12)), child: Center(child: TextField(controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w900, color: Colors.white), decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero), onChanged: (v) => setState((){}))),)]);
  }

  Widget _buildMatchEventsSummary() {
    List<Widget> getTeamEvents(Map<String, Map<String, int>> actions, List<DocumentSnapshot> roster) {
      List<Widget> events = [];
      actions.forEach((pid, stats) {
        if ((stats['goals']??0)>0 || (stats['assists']??0)>0 || (stats['redCards']??0)>0 || (stats['yellowCards']??0)>0) {
          String name = "Desconocido"; try { var found = roster.where((doc) => doc.id == pid); if (found.isNotEmpty) name = found.first['name']; } catch (e) {}
          List<Widget> badges = [];
          for(int i=0; i<stats['goals']!; i++) badges.add(_eventBadge("⚽", Colors.greenAccent));
          for(int i=0; i<stats['assists']!; i++) badges.add(_eventBadge("👟", Colors.blueAccent));
          if(stats['redCards']! > 0) badges.add(_eventBadge("🟥", Colors.redAccent));
          if(stats['yellowCards']! > 0) badges.add(_eventBadge("🟨", Colors.yellowAccent));
          events.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70))), const SizedBox(width: 6), ...badges])));
        }
      });
      if (events.isEmpty) return [const Text("-", style: TextStyle(color: Colors.white24, fontSize: 12))];
      return events;
    }
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("LOCAL", style: TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...getTeamEvents(_homeActions, _homeRoster)])), VerticalDivider(width: 30, color: Colors.white.withOpacity(0.1)), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("VISITA", style: TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...getTeamEvents(_awayActions, _awayRoster)]))])));
  }

  Widget _eventBadge(String icon, Color color) { return Container(margin: const EdgeInsets.only(left: 4), padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.5))), child: Text(icon, style: const TextStyle(fontSize: 8))); }

  Widget _playerRow(DocumentSnapshot p, Map<String, Map<String, int>> actions, int maxGoals, int assignedGoals, int assignedAssists, List<String> suspendedList) {
    String pid = p.id;
    if (!actions.containsKey(pid)) actions[pid] = {'goals': 0, 'assists': 0, 'yellowCards': 0, 'redCards': 0};
    int goals = actions[pid]!['goals']!; int assists = actions[pid]!['assists']!; int yellows = actions[pid]!['yellowCards'] ?? 0; int reds = actions[pid]!['redCards'] ?? 0;
    bool isSuspended = suspendedList.contains(pid);
    return Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(children: [Row(children: [if (isSuspended) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.block, color: Colors.redAccent, size: 16)), Expanded(child: Text(p['name'], style: TextStyle(fontWeight: FontWeight.w600, decoration: isSuspended ? TextDecoration.lineThrough : null, color: isSuspended ? Colors.redAccent.withOpacity(0.5) : Colors.white)))]), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_counterControl("⚽", goals, Colors.greenAccent, onRemove: goals > 0 ? () => setState(() => actions[pid]!['goals'] = goals - 1) : null, onAdd: (assignedGoals < maxGoals) ? () => setState(() => actions[pid]!['goals'] = goals + 1) : null), _counterControl("👟", assists, Colors.blueAccent, onRemove: assists > 0 ? () => setState(() => actions[pid]!['assists'] = assists - 1) : null, onAdd: (assignedAssists < maxGoals) ? () => setState(() => actions[pid]!['assists'] = assists + 1) : null), Row(children: [InkWell(onTap: () => setState(() => actions[pid]!['yellowCards'] = (yellows + 1) > 2 ? 0 : (yellows + 1)), child: _cardIcon(Colors.yellowAccent, yellows)), const SizedBox(width: 10), InkWell(onTap: () => setState(() => actions[pid]!['redCards'] = (reds + 1) > 1 ? 0 : 1), child: _cardIcon(Colors.redAccent, reds))])])]),
    );
  }

  Widget _counterControl(String icon, int val, Color color, {VoidCallback? onRemove, VoidCallback? onAdd}) { return Container(decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Row(children: [Text(icon, style: const TextStyle(fontSize: 12)), const SizedBox(width: 8), InkWell(onTap: onRemove, child: Icon(Icons.remove, size: 16, color: onRemove != null ? Colors.white54 : Colors.white12)), SizedBox(width: 20, child: Center(child: Text("$val", style: TextStyle(fontWeight: FontWeight.bold, color: val > 0 ? color : Colors.white70)))), InkWell(onTap: onAdd, child: Icon(Icons.add, size: 16, color: onAdd != null ? color : Colors.white12))])); }
  Widget _cardIcon(Color color, int count) { return Container(width: 24, height: 32, decoration: BoxDecoration(color: count > 0 ? color : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: count > 0 ? color : Colors.white24)), child: Center(child: count > 0 ? Text("$count", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)) : Icon(Icons.style_outlined, size: 14, color: Colors.white24))); }
  Widget _statHeader() { return const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("LOCAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white54)), Text("VISITA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white54))]); }
  Widget _statRow(String l, TextEditingController h1, TextEditingController? h2, TextEditingController a1, TextEditingController? a2) { return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Row(children: [Expanded(child: _miniInput(h1)), if(h2!=null) const Text("/", style: TextStyle(color: Colors.white38)), if(h2!=null) Expanded(child: _miniInput(h2))])), Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38))), Expanded(child: Row(children: [Expanded(child: _miniInput(a1)), if(a2!=null) const Text("/", style: TextStyle(color: Colors.white38)), if(a2!=null) Expanded(child: _miniInput(a2))]))])); }
  Widget _miniInput(TextEditingController c) => TextField(controller: c, textAlign: TextAlign.center, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.all(8), filled: true, fillColor: Colors.black26, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)));
}