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
  // Controladores Marcador Regular
  final TextEditingController _homeScoreCtrl = TextEditingController();
  final TextEditingController _awayScoreCtrl = TextEditingController();

  // Controladores Penales (NUEVO)
  final TextEditingController _homePenaltiesCtrl = TextEditingController();
  final TextEditingController _awayPenaltiesCtrl = TextEditingController();

  final Map<String, TextEditingController> _hStats = _initStatsMap();
  final Map<String, TextEditingController> _aStats = _initStatsMap();

  Map<String, Map<String, int>> _homeActions = {};
  Map<String, Map<String, int>> _awayActions = {};

  List<DocumentSnapshot> _homeRoster = [];
  List<DocumentSnapshot> _awayRoster = [];

  // Disciplina
  List<String> _homeSuspended = [];
  List<String> _awaySuspended = [];
  bool _isLoadingSuspensions = true;

  // Estados de control
  bool _showPenaltiesInput = false; // Se activa si hay empate
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
    // Cargar Marcador
    if (widget.matchData['homeScore'] != null) {
      _homeScoreCtrl.text = widget.matchData['homeScore'].toString();
      _awayScoreCtrl.text = widget.matchData['awayScore'].toString();
    }

    // Cargar Penales si existen (Formato nuevo: Parsing del string "5-4")
    if (widget.matchData['definedByPenalties'] == true && widget.matchData['penaltyScore'] != null) {
      _showPenaltiesInput = true;
      try {
        String scores = widget.matchData['penaltyScore']; // Ej: "5-4"
        List<String> parts = scores.split('-');
        if (parts.length == 2) {
          _homePenaltiesCtrl.text = parts[0].trim();
          _awayPenaltiesCtrl.text = parts[1].trim();
        }
      } catch (e) {
        // Error parseando, dejar vacío
      }
    }

    if (widget.matchData['player_actions'] != null) {
      _loadActions(widget.matchData['player_actions']['home'], _homeActions);
      _loadActions(widget.matchData['player_actions']['away'], _awayActions);
    }

    _loadRosters();
    _checkSuspensions();

    // Listener para activar penales automáticamente si empatan
    _homeScoreCtrl.addListener(_checkDrawCondition);
    _awayScoreCtrl.addListener(_checkDrawCondition);
  }

  void _checkDrawCondition() {
    // Solo aplica para Copa y Champions (no Liga)
    if (widget.matchData['type'] == 'LEAGUE') return;

    int h = int.tryParse(_homeScoreCtrl.text) ?? -1;
    int a = int.tryParse(_awayScoreCtrl.text) ?? -1;

    // Si los números son validos y son iguales
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
        'goals': data['goals'] ?? 0,
        'assists': data['assists'] ?? 0,
        'yellowCards': data['yellowCards'] ?? 0,
        'redCards': data['redCards'] ?? 0,
      };
    });
  }

  Future<void> _checkSuspensions() async {
    if (widget.matchData['type'] == 'LEAGUE') {
      setState(() => _isLoadingSuspensions = false);
      return;
    }

    // INTENTO 1: Leer la info pre-calculada (la que se mostrará en el calendario)
    if (widget.matchData['preMatchInfo'] != null) {
      Map info = widget.matchData['preMatchInfo'];
      List<String> hSusp = List<String>.from(info['homeSuspended'] ?? []);
      List<String> aSusp = List<String>.from(info['awaySuspended'] ?? []);

      if (hSusp.isNotEmpty || aSusp.isNotEmpty) {
        setState(() {
          _homeSuspended = hSusp;
          _awaySuspended = aSusp;
          _isLoadingSuspensions = false;
        });
        Future.delayed(Duration.zero, _showSuspensionAlert);
        return;
      }
    }

    // INTENTO 2 (Respaldo): Calcular al vuelo si no hay info pre-calculada
    final discipline = DisciplineService();
    var hSusp = await discipline.getSuspendedPlayers(seasonId: widget.seasonId, teamId: widget.matchData['homeUser'], competitionType: widget.matchData['type'], currentRound: widget.matchData['round']);
    var aSusp = await discipline.getSuspendedPlayers(seasonId: widget.seasonId, teamId: widget.matchData['awayUser'], competitionType: widget.matchData['type'], currentRound: widget.matchData['round']);

    if (mounted) {
      setState(() {
        _homeSuspended = hSusp;
        _awaySuspended = aSusp;
        _isLoadingSuspensions = false;
      });
      if (_homeSuspended.isNotEmpty || _awaySuspended.isNotEmpty) {
        Future.delayed(Duration.zero, _showSuspensionAlert);
      }
    }
  }

  void _showSuspensionAlert() {
    // Función auxiliar para obtener nombres
    String getNames(List<String> ids, List<DocumentSnapshot> roster) {
      if (roster.isEmpty) return ids.join(", ");
      List<String> names = [];
      for (var id in ids) {
        var found = roster.where((doc) => doc.id == id);
        if (found.isNotEmpty) names.add(found.first['name']);
        else names.add(id);
      }
      return names.join(", ");
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ SANCIONES ACTIVAS"),
        backgroundColor: Colors.red.shade50,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Los siguientes jugadores NO pueden jugar este partido:", style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              if (_homeSuspended.isNotEmpty) ...[
                const Text("LOCAL:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text(getNames(_homeSuspended, _homeRoster), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 8),
              if (_awaySuspended.isNotEmpty) ...[
                const Text("VISITA:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text(getNames(_awaySuspended, _awayRoster), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendido"))],
      ),
    );
  }

  Future<void> _loadRosters() async {
    if (widget.matchData['homeUser'] != 'TBD' && !widget.matchData['homeUser'].toString().startsWith('GANADOR')) {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).get();
      List ids = doc.data()?['roster'] ?? [];
      if (ids.isNotEmpty) _homeRoster = await _fetchPlayers(ids);
    }
    if (widget.matchData['awayUser'] != 'TBD' && !widget.matchData['awayUser'].toString().startsWith('GANADOR')) {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['awayUser']).get();
      List ids = doc.data()?['roster'] ?? [];
      if (ids.isNotEmpty) _awayRoster = await _fetchPlayers(ids);
    }
    if (mounted) setState(() {});
  }

  Future<List<DocumentSnapshot>> _fetchPlayers(List ids) async {
    List<String> sIds = ids.map((e) => e.toString()).toList();
    List<DocumentSnapshot> all = [];
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
        // 1. PROPAGAR SUSPENSIONES AL FUTURO (La clave para la advertencia en el calendario)
        if (widget.matchData['type'] != 'LEAGUE') {
          var updatedSnapshot = await matchRef.get();
          // Aquí llamamos al DisciplineService para que "pegue" la etiqueta en el siguiente partido
          await DisciplineService().propagateSuspensionsToNextMatch(widget.seasonId, updatedSnapshot.data()!);
        }

        // 2. PROCESAR RESULTADO
        await _processAdminTasks(hGoals, aGoals, definedByPenalties, penaltyScoreStr);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) { setState(() => isSaving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    }
  }

  Future<void> _processAdminTasks(int hGoals, int aGoals, bool definedByPenalties, String? penaltyScoreStr) async {
    // 1. PREMIOS, STATS Y TORNEOS (Igual que antes)
    // ... [Aquí va tu código de premios y stats y progresión de torneos] ...
    // (Por brevedad, asumo que dejas el código que ya funcionaba aquí)
    // Si necesitas que te lo copie completo otra vez avísame, pero es lo mismo de antes.

    int winReward = 15000000; int drawReward = 7500000;
    int homePrize = (hGoals > aGoals) ? winReward : (aGoals > hGoals ? 0 : drawReward);
    int awayPrize = (aGoals > hGoals) ? winReward : (hGoals > aGoals ? 0 : drawReward);
    if (homePrize > 0 && !widget.matchData['homeUser'].startsWith('TBD')) {
      await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).update({'budget': FieldValue.increment(homePrize)});
    }
    if (awayPrize > 0 && !widget.matchData['awayUser'].startsWith('TBD')) {
      await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['awayUser']).update({'budget': FieldValue.increment(awayPrize)});
    }
    await StatsService().recalculateTeamStats(widget.seasonId);

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

    // --- NUEVA LÓGICA DE NOTICIAS ---

    String homeName = await _getTeamName(widget.matchData['homeUser']);
    String awayName = await _getTeamName(widget.matchData['awayUser']);

    // 2. Obtener Historial (Forma)
    String homeForm = await _getTeamForm(widget.matchData['homeUser']);
    String awayForm = await _getTeamForm(widget.matchData['awayUser']);

    // 3. Detalles del partido
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

    // 4. Clásico
    bool isDerby = false;
    try {
      var seasonDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();
      List rivalries = seasonDoc.data()?['rivalries'] ?? [];
      String key1 = "${widget.matchData['homeUser']}_${widget.matchData['awayUser']}";
      String key2 = "${widget.matchData['awayUser']}_${widget.matchData['homeUser']}";
      if (rivalries.contains(key1) || rivalries.contains(key2)) isDerby = true;
    } catch(e) {}

    // 5. Ganador
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

    // 6. Generar Noticia
    NewsService().createMatchNews(
      seasonId: widget.seasonId,
      homeName: homeName,
      awayName: awayName,
      homeScore: hGoals,
      awayScore: aGoals,
      competition: type,
      isPenalties: definedByPenalties,
      penaltyScore: penaltyScoreStr,
      winnerName: winnerName,
      matchDetails: detailsBuffer.toString(),
      isDerby: isDerby,
      homeForm: homeForm, // <--- Pasamos el contexto histórico
      awayForm: awayForm,
    );

    // 7. Notificación
    String bodyText = "$homeName $hGoals - $aGoals $awayName";
    if (definedByPenalties) bodyText += " (Penales: $penaltyScoreStr)";
    await NotificationService.sendGlobalNotification(seasonId: widget.seasonId, title: "FINALIZADO", body: bodyText, type: "MATCH");
  }

  // Helper para leer la forma (Historial)
  Future<String> _getTeamForm(String teamId) async {
    if (teamId == 'TBD' || teamId.startsWith('GANADOR')) return "";
    try {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(teamId).get();
      var stats = doc.data()?['leagueStats'];
      if (stats == null) return "Sin datos previos";

      int w = stats['w'] ?? 0;
      int l = stats['l'] ?? 0;
      int d = stats['d'] ?? 0;
      int pts = stats['pts'] ?? 0;

      return "En liga lleva $w ganados, $d empatados y $l perdidos ($pts puntos).";
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    int hGoals = int.tryParse(_homeScoreCtrl.text) ?? 0;
    int aGoals = int.tryParse(_awayScoreCtrl.text) ?? 0;
    int currentH = _countTotal(_homeActions, 'goals');
    int currentA = _countTotal(_awayActions, 'goals');
    int currentH_Assists = _countTotal(_homeActions, 'assists');
    int currentA_Assists = _countTotal(_awayActions, 'assists');
    bool valid = (hGoals == currentH) && (aGoals == currentA) && (currentH_Assists <= hGoals) && (currentA_Assists <= aGoals);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(title: const Text("Reporte de Partido"), centerTitle: true, backgroundColor: const Color(0xFF0D1B2A)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: isScanning ? null : _scanImage,
              icon: isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.camera_alt),
              label: Text(isScanning ? "PROCESANDO..." : "ESCANEAR FOTO IA"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A4C93), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(
                children: [
                  const Text("TIEMPO REGLAMENTARIO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_ScoreBox("LOCAL", _homeScoreCtrl, size: 60), const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Text("-", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: Colors.grey))), _ScoreBox("VISITA", _awayScoreCtrl, size: 60)]
                  ),
                  if (_showPenaltiesInput) ...[
                    const SizedBox(height: 20), const Divider(indent: 40, endIndent: 40),
                    const Text("DEFINICIÓN POR PENALES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.orange, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [_ScoreBox("PEN (L)", _homePenaltiesCtrl, size: 40, isPenalty: true), const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Text("vs", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey))), _ScoreBox("PEN (V)", _awayPenaltiesCtrl, size: 40, isPenalty: true)]),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildMatchEventsSummary(),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => setState(() => showAdvanced = !showAdvanced),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("📊 Estadísticas Detalladas (Posesión, Tiros...)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Icon(showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20)]),
              ),
            ),
            if (showAdvanced) Container(
              margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [_statHeader(), const Divider(), _statRow("Tiros (Total / Arco)", _hStats['shots']!, _hStats['target']!, _aStats['shots']!, _aStats['target']!), _statRow("Pases (Total / Comp)", _hStats['passes']!, _hStats['completed']!, _aStats['passes']!, _aStats['completed']!), _statRow("Posesión %", _hStats['possession']!, null, _aStats['possession']!, null), _statRow("Faltas / Offsides", _hStats['fouls']!, _hStats['offsides']!, _aStats['fouls']!, _aStats['offsides']!), _statRow("Intercepciones", _hStats['interceptions']!, null, _aStats['interceptions']!, null)]),
            ),
            const SizedBox(height: 25),
            const Align(alignment: Alignment.centerLeft, child: Text("DETALLE DE JUGADORES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0D1B2A), letterSpacing: 0.5))),
            const SizedBox(height: 10),
            _buildTeamRosterTile("Local", hGoals, currentH, currentH_Assists, _homeRoster, _homeActions, _homeSuspended),
            const SizedBox(height: 10),
            _buildTeamRosterTile("Visita", aGoals, currentA, currentA_Assists, _awayRoster, _awayActions, _awaySuspended),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                  onPressed: (isSaving || (widget.isAdmin && !valid)) ? null : _submitResult,
                  style: ElevatedButton.styleFrom(backgroundColor: valid ? const Color(0xFF2E7D32) : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2),
                  child: isSaving ? const CircularProgressIndicator(color: Colors.white) : Text(widget.isAdmin ? (valid ? "CONFIRMAR Y GUARDAR" : "FALTAN ASIGNAR GOLES/ASIST") : "ENVIAR REPORTE", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES (UI) ---
  Widget _buildTeamRosterTile(String label, int totalGoals, int assignedGoals, int assignedAssists, List<DocumentSnapshot> roster, Map<String, Map<String, int>> actions, List<String> suspended) {
    bool complete = (totalGoals == assignedGoals);
    return Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)), clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Row(children: [Text("$label ", style: const TextStyle(fontWeight: FontWeight.bold)), if(complete) const Icon(Icons.check_circle, color: Colors.green, size: 16), if(!complete) Text(" (Faltan ${totalGoals - assignedGoals})", style: const TextStyle(color: Colors.red, fontSize: 12))]),
        subtitle: Text("Asistencias: $assignedAssists", style: const TextStyle(fontSize: 12, color: Colors.grey)), backgroundColor: Colors.white, collapsedBackgroundColor: Colors.white,
        children: roster.map((p) => _playerRow(p, actions, totalGoals, assignedGoals, assignedAssists, suspended)).toList(),
      ),
    );
  }

  Widget _ScoreBox(String label, TextEditingController ctrl, {double size = 50, bool isPenalty = false}) {
    return Column(children: [Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isPenalty ? Colors.orange[800] : Colors.grey, fontSize: 11)), const SizedBox(height: 4), Container(width: size + 20, height: size, decoration: BoxDecoration(color: isPenalty ? Colors.orange.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: isPenalty ? Colors.orange.shade200 : Colors.transparent)), child: Center(child: TextField(controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w900, color: const Color(0xFF0D1B2A)), decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero), onChanged: (v) => setState((){}))),)]);
  }

  Widget _buildMatchEventsSummary() {
    List<Widget> getTeamEvents(Map<String, Map<String, int>> actions, List<DocumentSnapshot> roster) {
      List<Widget> events = [];
      actions.forEach((pid, stats) {
        bool hasEvent = (stats['goals']! > 0) || (stats['assists']! > 0) || (stats['yellowCards']! > 0) || (stats['redCards']! > 0);
        if (hasEvent) {
          String name = "Desconocido";
          try { var found = roster.where((doc) => doc.id == pid); if (found.isNotEmpty) name = found.first['name']; } catch (e) {}
          List<Widget> badges = [];
          for(int i=0; i<stats['goals']!; i++) badges.add(_eventBadge("⚽", Colors.green.shade100, Colors.black));
          for(int i=0; i<stats['assists']!; i++) badges.add(_eventBadge("👟", Colors.blue.shade100, Colors.black));
          if(stats['redCards']! > 0) badges.add(_eventBadge("🟥", Colors.red.shade100, Colors.red));
          if(stats['yellowCards']! > 0) badges.add(_eventBadge("🟨", Colors.yellow.shade100, Colors.orange));
          events.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))), const SizedBox(width: 4), ...badges])));
        }
      });
      if (events.isEmpty) return [const Text("-", style: TextStyle(color: Colors.grey, fontSize: 12))];
      return events;
    }
    return Card(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)), child: Padding(padding: const EdgeInsets.all(12), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("LOCAL", style: TextStyle(fontSize: 10, color: Colors.grey)), const SizedBox(height: 4), ...getTeamEvents(_homeActions, _homeRoster)])), VerticalDivider(width: 20, color: Colors.grey.shade300), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("VISITA", style: TextStyle(fontSize: 10, color: Colors.grey)), const SizedBox(height: 4), ...getTeamEvents(_awayActions, _awayRoster)]))]))));
  }

  Widget _eventBadge(String icon, Color bg, Color border) { return Container(margin: const EdgeInsets.only(left: 2), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: border, width: 0.5)), child: Text(icon, style: const TextStyle(fontSize: 10))); }

  Widget _playerRow(DocumentSnapshot p, Map<String, Map<String, int>> actions, int maxGoals, int assignedGoals, int assignedAssists, List<String> suspendedList) {
    String pid = p.id;
    if (!actions.containsKey(pid)) actions[pid] = {'goals': 0, 'assists': 0, 'yellowCards': 0, 'redCards': 0};
    int goals = actions[pid]!['goals']!; int assists = actions[pid]!['assists']!; int yellows = actions[pid]!['yellowCards'] ?? 0; int reds = actions[pid]!['redCards'] ?? 0;
    bool isSuspended = suspendedList.contains(pid);
    return Container(decoration: BoxDecoration(color: isSuspended ? Colors.red.shade50 : Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100))), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(children: [Row(children: [if (isSuspended) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.block, color: Colors.red, size: 16)), Expanded(child: Text(p['name'], style: TextStyle(fontWeight: FontWeight.w600, decoration: isSuspended ? TextDecoration.lineThrough : null, color: isSuspended ? Colors.grey : Colors.black87)))]), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_counterControl("⚽", goals, Colors.green, onRemove: goals > 0 ? () => setState(() => actions[pid]!['goals'] = goals - 1) : null, onAdd: (assignedGoals < maxGoals) ? () => setState(() => actions[pid]!['goals'] = goals + 1) : null), _counterControl("👟", assists, Colors.blue, onRemove: assists > 0 ? () => setState(() => actions[pid]!['assists'] = assists - 1) : null, onAdd: (assignedAssists < maxGoals) ? () => setState(() => actions[pid]!['assists'] = assists + 1) : null), Row(children: [InkWell(onTap: () => setState(() => actions[pid]!['yellowCards'] = (yellows + 1) > 2 ? 0 : (yellows + 1)), child: _cardIcon(Colors.yellow[700]!, yellows)), const SizedBox(width: 8), InkWell(onTap: () => setState(() => actions[pid]!['redCards'] = (reds + 1) > 1 ? 0 : 1), child: _cardIcon(Colors.red, reds))])])]),
    );
  }

  Widget _counterControl(String icon, int val, Color color, {VoidCallback? onRemove, VoidCallback? onAdd}) { return Container(decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(children: [Text(icon, style: const TextStyle(fontSize: 12)), const SizedBox(width: 4), InkWell(onTap: onRemove, child: Icon(Icons.remove_circle_outline, size: 20, color: onRemove != null ? Colors.grey : Colors.grey[200])), SizedBox(width: 20, child: Center(child: Text("$val", style: TextStyle(fontWeight: FontWeight.bold, color: val > 0 ? color : Colors.black)))), InkWell(onTap: onAdd, child: Icon(Icons.add_circle, size: 20, color: onAdd != null ? color : Colors.grey[200]))])); }
  Widget _cardIcon(Color color, int count) { return Container(width: 24, height: 30, decoration: BoxDecoration(color: count > 0 ? color : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)), child: Center(child: count > 0 ? Text("$count", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)) : Icon(Icons.style_outlined, size: 14, color: Colors.grey.shade400))); }

  Future<void> _scanImage() async {
    final ImagePicker picker = ImagePicker(); final XFile? image = await picker.pickImage(source: ImageSource.gallery); if (image == null) return;
    setState(() => isScanning = true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analizando imagen con IA...")));
    try { Uint8List bytes = await image.readAsBytes(); var result = await GeminiStatsService().extractStatsFromImage(bytes); if (result != null) { setState(() { _populateControllers(result['home'], _homeScoreCtrl, _hStats); _populateControllers(result['away'], _awayScoreCtrl, _aStats); showAdvanced = true; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Datos extraídos!"))); } } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error IA: $e"))); } finally { setState(() => isScanning = false); }
  }
  void _populateControllers(Map data, TextEditingController score, Map<String, TextEditingController> stats) { score.text = (data['goals'] ?? 0).toString(); stats['shots']!.text = (data['shots'] ?? 0).toString(); stats['target']!.text = (data['shotsOnTarget'] ?? 0).toString(); stats['passes']!.text = (data['passes'] ?? 0).toString(); stats['completed']!.text = (data['passesCompleted'] ?? 0).toString(); stats['possession']!.text = (data['possession'] ?? 50).toString(); stats['fouls']!.text = (data['fouls'] ?? 0).toString(); stats['offsides']!.text = (data['offsides'] ?? 0).toString(); stats['interceptions']!.text = (data['interceptions'] ?? 0).toString(); }
  int _countTotal(Map<String, Map<String, int>> map, String key) { return map.values.fold(0, (sum, val) => sum + (val[key] ?? 0)); }
  Map<String, int> _extractStatsMap(int goals, Map<String, TextEditingController> ctrls) { return { 'goals': goals, 'shots': int.tryParse(ctrls['shots']!.text) ?? 0, 'shotsOnTarget': int.tryParse(ctrls['target']!.text) ?? 0, 'passes': int.tryParse(ctrls['passes']!.text) ?? 0, 'passesCompleted': int.tryParse(ctrls['completed']!.text) ?? 0, 'possession': int.tryParse(ctrls['possession']!.text) ?? 50, 'fouls': int.tryParse(ctrls['fouls']!.text) ?? 0, 'offsides': int.tryParse(ctrls['offsides']!.text) ?? 0, 'interceptions': int.tryParse(ctrls['interceptions']!.text) ?? 0 }; }
  Future<void> _checkAndFillCup() async { await Future.delayed(const Duration(seconds: 2)); try { await SeasonGeneratorService().fillCupBracketFromStandings(widget.seasonId); } catch(e){} }
  Future<String> _getTeamName(String userId) async { if (userId == 'TBD' || userId.startsWith('GANADOR') || userId.startsWith('Seed') || userId.startsWith('FINALISTA')) return 'Por definir'; var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(userId).get(); return doc.data()?['teamName'] ?? 'Equipo'; }
  Widget _statHeader() { return const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("LOCAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)), Text("VISITA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))]); }
  Widget _statRow(String l, TextEditingController h1, TextEditingController? h2, TextEditingController a1, TextEditingController? a2) { return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Row(children: [Expanded(child: _miniInput(h1)), if(h2!=null) const Text("/"), if(h2!=null) Expanded(child: _miniInput(h2))])), Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))), Expanded(child: Row(children: [Expanded(child: _miniInput(a1)), if(a2!=null) const Text("/"), if(a2!=null) Expanded(child: _miniInput(a2))]))])); }
  Widget _miniInput(TextEditingController c) => TextField(controller: c, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(5), border: OutlineInputBorder()));
}