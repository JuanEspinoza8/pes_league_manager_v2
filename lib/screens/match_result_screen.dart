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
  final TextEditingController _homeScoreCtrl = TextEditingController();
  final TextEditingController _awayScoreCtrl = TextEditingController();

  final Map<String, TextEditingController> _hStats = _initStatsMap();
  final Map<String, TextEditingController> _aStats = _initStatsMap();

  Map<String, Map<String, int>> _homeActions = {};
  Map<String, Map<String, int>> _awayActions = {};

  List<DocumentSnapshot> _homeRoster = [];
  List<DocumentSnapshot> _awayRoster = [];

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
    if (widget.matchData['player_actions'] != null) {
      _loadActions(widget.matchData['player_actions']['home'], _homeActions);
      _loadActions(widget.matchData['player_actions']['away'], _awayActions);
    }
    _loadRosters();
  }

  void _loadActions(dynamic source, Map<String, Map<String, int>> target) {
    if (source == null) return;
    (source as Map).forEach((pid, data) {
      target[pid.toString()] = {
        'goals': data['goals'] ?? 0,
        'assists': data['assists'] ?? 0
      };
    });
  }

  Future<void> _loadRosters() async {
    if (widget.matchData['homeUser'] != 'TBD') {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).get();
      List ids = doc.data()?['roster'] ?? [];
      if (ids.isNotEmpty) _homeRoster = await _fetchPlayers(ids);
    }
    if (widget.matchData['awayUser'] != 'TBD') {
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

  Future<void> _scanImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => isScanning = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analizando imagen con IA...")));
    try {
      Uint8List bytes = await image.readAsBytes();
      var result = await GeminiStatsService().extractStatsFromImage(bytes);
      if (result != null) {
        setState(() {
          _populateControllers(result['home'], _homeScoreCtrl, _hStats);
          _populateControllers(result['away'], _awayScoreCtrl, _aStats);
          showAdvanced = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Datos extraídos!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error IA: $e")));
    } finally {
      setState(() => isScanning = false);
    }
  }

  void _populateControllers(Map data, TextEditingController score, Map<String, TextEditingController> stats) {
    score.text = (data['goals'] ?? 0).toString();
    stats['shots']!.text = (data['shots'] ?? 0).toString();
    stats['target']!.text = (data['shotsOnTarget'] ?? 0).toString();
    stats['passes']!.text = (data['passes'] ?? 0).toString();
    stats['completed']!.text = (data['passesCompleted'] ?? 0).toString();
    stats['possession']!.text = (data['possession'] ?? 50).toString();
    stats['fouls']!.text = (data['fouls'] ?? 0).toString();
    stats['offsides']!.text = (data['offsides'] ?? 0).toString();
    stats['interceptions']!.text = (data['interceptions'] ?? 0).toString();
  }

  Future<void> _submitResult() async {
    if (_homeScoreCtrl.text.isEmpty || _awayScoreCtrl.text.isEmpty) return;

    int hGoals = int.tryParse(_homeScoreCtrl.text) ?? 0;
    int aGoals = int.tryParse(_awayScoreCtrl.text) ?? 0;

    int assignedH_Goals = _countTotal(_homeActions, 'goals');
    int assignedA_Goals = _countTotal(_awayActions, 'goals');

    if (assignedH_Goals != hGoals || assignedA_Goals != aGoals) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Faltan asignar goles (Locales: $assignedH_Goals/$hGoals, Visita: $assignedA_Goals/$aGoals)."), backgroundColor: Colors.red));
      return;
    }

    int assignedH_Assists = _countTotal(_homeActions, 'assists');
    int assignedA_Assists = _countTotal(_awayActions, 'assists');
    if (assignedH_Assists > hGoals || assignedA_Assists > aGoals) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Demasiadas asistencias."), backgroundColor: Colors.red));
      return;
    }

    setState(() => isSaving = true);

    try {
      Map<String, dynamic> advancedStats = {
        'home': _extractStatsMap(hGoals, _hStats),
        'away': _extractStatsMap(aGoals, _aStats)
      };

      Map<String, dynamic> actionsMap = {
        'home': _homeActions,
        'away': _awayActions
      };

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
        'scorers': {'home': scorersSimpleH, 'away': scorersSimpleA}
      };

      if (!widget.isAdmin) updateData['reportedBy'] = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('matches').doc(widget.matchId).update(updateData);

      if (widget.isAdmin) {
        // Recompensas
        int winReward = 15000000;
        int drawReward = 7500000;
        int homePrize = 0;
        int awayPrize = 0;

        if (hGoals > aGoals) { homePrize = winReward; }
        else if (aGoals > hGoals) { awayPrize = winReward; }
        else { homePrize = drawReward; awayPrize = drawReward; }

        if (homePrize > 0 && widget.matchData['homeUser'] != 'TBD') {
          await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['homeUser']).update({'budget': FieldValue.increment(homePrize)});
        }
        if (awayPrize > 0 && widget.matchData['awayUser'] != 'TBD') {
          await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.matchData['awayUser']).update({'budget': FieldValue.increment(awayPrize)});
        }

        await StatsService().recalculateTeamStats(widget.seasonId);

        String type = widget.matchData['type'];
        if (type == 'LEAGUE') {
          await StandingsService().recalculateLeagueStandings(widget.seasonId);
          if (widget.matchData['round'] == 4) _checkAndFillCup();
        } else if (type == 'CUP') {
          await CupProgressionService().checkForCupAdvances(widget.seasonId);
        } else if (type == 'CHAMPIONS') {
          if (widget.matchData['round'] < 250) {
            await StandingsService().recalculateChampionsStandings(widget.seasonId);
            await ChampionsProgressionService().checkGroupStageEnd(widget.seasonId);
          } else {
            await ChampionsProgressionService().checkForChampionsAdvances(widget.seasonId);
          }
        }

        String homeName = await _getTeamName(widget.matchData['homeUser']);
        String awayName = await _getTeamName(widget.matchData['awayUser']);
        await NotificationService.sendGlobalNotification(seasonId: widget.seasonId, title: "FINALIZADO", body: "$homeName $hGoals - $aGoals $awayName", type: "MATCH");
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) { setState(() => isSaving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    }
  }

  int _countTotal(Map<String, Map<String, int>> map, String key) {
    return map.values.fold(0, (sum, val) => sum + (val[key] ?? 0));
  }

  Map<String, int> _extractStatsMap(int goals, Map<String, TextEditingController> ctrls) {
    return {
      'goals': goals,
      'shots': int.tryParse(ctrls['shots']!.text) ?? 0,
      'shotsOnTarget': int.tryParse(ctrls['target']!.text) ?? 0,
      'passes': int.tryParse(ctrls['passes']!.text) ?? 0,
      'passesCompleted': int.tryParse(ctrls['completed']!.text) ?? 0,
      'possession': int.tryParse(ctrls['possession']!.text) ?? 50,
      'fouls': int.tryParse(ctrls['fouls']!.text) ?? 0,
      'offsides': int.tryParse(ctrls['offsides']!.text) ?? 0,
      'interceptions': int.tryParse(ctrls['interceptions']!.text) ?? 0,
    };
  }

  Future<void> _checkAndFillCup() async { await Future.delayed(const Duration(seconds: 2)); try { await SeasonGeneratorService().fillCupBracketFromStandings(widget.seasonId); } catch(e){} }

  Future<String> _getTeamName(String userId) async {
    if (userId == 'TBD' || userId.startsWith('GANADOR') || userId.startsWith('Seed') || userId.startsWith('FINALISTA')) return 'Por definir';
    var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(userId).get();
    return doc.data()?['teamName'] ?? 'Equipo';
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
      appBar: AppBar(title: const Text("Cargar Resultado"), backgroundColor: Colors.blue[900]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: isScanning ? null : _scanImage,
              icon: isScanning ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.camera_alt),
              label: const Text("ESCANEAR FOTO IA"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A4C93), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
            ),
            const SizedBox(height: 20),

            // SCOREBOARD CORREGIDO CON FLEXIBLE
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _ScoreBox("LOCAL", _homeScoreCtrl)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("-", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.grey)),
                    ),
                    Expanded(child: _ScoreBox("VISITA", _awayScoreCtrl)),
                  ]
              ),
            ),

            const SizedBox(height: 20),

            InkWell(
              onTap: () => setState(() => showAdvanced = !showAdvanced),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Estadísticas Detalladas", style: TextStyle(fontWeight: FontWeight.bold)), Icon(showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down)]),
              ),
            ),

            if (showAdvanced)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  _statHeader(), const Divider(),
                  _statRow("Tiros (Total / Arco)", _hStats['shots']!, _hStats['target']!, _aStats['shots']!, _aStats['target']!),
                  _statRow("Pases (Total / Comp)", _hStats['passes']!, _hStats['completed']!, _aStats['passes']!, _aStats['completed']!),
                  _statRow("Posesión %", _hStats['possession']!, null, _aStats['possession']!, null),
                  _statRow("Faltas / Offsides", _hStats['fouls']!, _hStats['offsides']!, _aStats['fouls']!, _aStats['offsides']!),
                  _statRow("Intercepciones", _hStats['interceptions']!, null, _aStats['interceptions']!, null),
                ]),
              ),

            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft, child: Text("INCIDENCIAS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0D1B2A)))),
            const SizedBox(height: 10),

            if (hGoals > 0)
              ExpansionTile(
                title: Text("Local (G:$currentH/$hGoals - A:$currentH_Assists)"),
                collapsedBackgroundColor: Colors.white,
                textColor: (currentH == hGoals) ? Colors.green : Colors.red,
                children: _homeRoster.map((p) => _playerRow(p, _homeActions, hGoals, currentH, currentH_Assists)).toList(),
              ),

            if (aGoals > 0)
              ExpansionTile(
                title: Text("Visita (G:$currentA/$aGoals - A:$currentA_Assists)"),
                collapsedBackgroundColor: Colors.white,
                textColor: (currentA == aGoals) ? Colors.green : Colors.red,
                children: _awayRoster.map((p) => _playerRow(p, _awayActions, aGoals, currentA, currentA_Assists)).toList(),
              ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                  onPressed: (isSaving || (widget.isAdmin && !valid)) ? null : _submitResult,
                  style: ElevatedButton.styleFrom(backgroundColor: valid ? const Color(0xFF2E7D32) : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(widget.isAdmin ? (valid ? "APROBAR Y GUARDAR" : "REVISAR GOLES/ASIST") : "ENVIAR REPORTE", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _playerRow(DocumentSnapshot p, Map<String, Map<String, int>> actions, int maxGoals, int curGoals, int curAssists) {
    String pid = p.id;
    if (!actions.containsKey(pid)) actions[pid] = {'goals': 0, 'assists': 0};
    int goals = actions[pid]!['goals']!;
    int assists = actions[pid]!['assists']!;

    return ListTile(
      tileColor: Colors.white,
      dense: true,
      title: Text(p['name'], style: TextStyle(fontWeight: (goals > 0 || assists > 0) ? FontWeight.bold : FontWeight.normal)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("⚽", style: TextStyle(fontSize: 12)),
          IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: goals > 0 ? () => setState(() => actions[pid]!['goals'] = goals - 1) : null),
          Text("$goals", style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add, size: 16, color: Colors.blue), onPressed: (curGoals < maxGoals) ? () => setState(() => actions[pid]!['goals'] = goals + 1) : null),
          const SizedBox(width: 10),
          const Text("👟", style: TextStyle(fontSize: 12)),
          IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: assists > 0 ? () => setState(() => actions[pid]!['assists'] = assists - 1) : null),
          Text("$assists", style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add, size: 16, color: Colors.orange), onPressed: (curAssists < maxGoals) ? () => setState(() => actions[pid]!['assists'] = assists + 1) : null),
        ],
      ),
    );
  }

  Widget _ScoreBox(String label, TextEditingController ctrl) {
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
      SizedBox(
          width: 80,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 80,
              child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Color(0xFF0D1B2A)),
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (v) => setState((){})
              ),
            ),
          )
      )
    ]);
  }

  Widget _statHeader() { return const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("LOCAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)), Text("VISITA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))]); }

  Widget _statRow(String l, TextEditingController h1, TextEditingController? h2, TextEditingController a1, TextEditingController? a2) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Row(children: [Expanded(child: _miniInput(h1)), if(h2!=null) const Text("/"), if(h2!=null) Expanded(child: _miniInput(h2))])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
      Expanded(child: Row(children: [Expanded(child: _miniInput(a1)), if(a2!=null) const Text("/"), if(a2!=null) Expanded(child: _miniInput(a2))])),
    ]));
  }

  Widget _miniInput(TextEditingController c) => TextField(controller: c, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(5), border: OutlineInputBorder()));
}