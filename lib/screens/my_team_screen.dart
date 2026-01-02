import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'squad_builder_screen.dart';
import 'sponsorship_screen.dart';

class MyTeamScreen extends StatefulWidget {
  final String seasonId;
  final String userId;

  const MyTeamScreen({super.key, required this.seasonId, required this.userId});

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends State<MyTeamScreen> {
  Map<String, dynamic>? teamData;
  List<DocumentSnapshot> rosterDocs = [];
  Map<String, String> allTeamNames = {};
  bool isLoading = true;
  String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // --- NUEVO: Variable para guardar si soy admin ---
  bool isSeasonAdmin = false;

  // Cache de partidos para calcular stats
  List<DocumentSnapshot> playedMatches = [];

  // Para el ordenamiento del fixture
  int _maxLeagueRound = 18; // Valor por defecto

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      // --- NUEVO: 1. Verificar si soy Admin de la Temporada ---
      // Consultamos el documento de la temporada para ver quién es el 'adminId'
      var seasonDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();
      String adminId = seasonDoc.data()?['adminId'] ?? '';
      bool adminCheck = (adminId == currentUserId);

      // 2. Cargar datos del equipo
      var teamDoc = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(widget.userId)
          .get();

      // 3. Cargar nombres de equipos
      var participantsSnap = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants')
          .get();

      Map<String, String> names = {};
      for (var p in participantsSnap.docs) {
        names[p.id] = p.data()['teamName'] ?? "Equipo";
      }

      // 4. Cargar Plantilla
      List rosterIds = teamDoc.data()?['roster'] ?? [];
      List<DocumentSnapshot> players = [];
      if (rosterIds.isNotEmpty) {
        players = await _fetchPlayers(rosterIds);
      }

      // 5. Cargar TODOS los partidos (Para stats y fixture)
      // Nota: Traemos todos para poder calcular el _maxLeagueRound correctamente
      var matchesSnap = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('matches')
          .get();

      var allDocs = matchesSnap.docs;

      // Filtramos los jugados MÍOS para stats
      var myPlayed = allDocs.where((doc) {
        var d = doc.data();
        bool isMine = d['homeUser'] == widget.userId || d['awayUser'] == widget.userId;
        bool isPlayed = d['status'] == 'PLAYED';
        return isMine && isPlayed;
      }).toList();

      // Calcular maxLeagueRound real para el ordenamiento
      int maxR = 18;
      for(var doc in allDocs) {
        int r = doc['round'] ?? 0;
        if(r < 100 && r > maxR) maxR = r;
      }

      if (mounted) {
        setState(() {
          isSeasonAdmin = adminCheck; // Guardamos el estado del admin
          teamData = teamDoc.data();
          allTeamNames = names;
          rosterDocs = players;
          playedMatches = myPlayed;
          _maxLeagueRound = maxR; // Actualizamos el máximo detectado
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error cargando MyTeam: $e");
      if(mounted) setState(() => isLoading = false);
    }
  }

  Future<List<DocumentSnapshot>> _fetchPlayers(List ids) async {
    if (ids.isEmpty) return [];
    List<String> sIds = ids.map((e) => e.toString()).toList();
    List<DocumentSnapshot> allDocs = [];

    for (var i = 0; i < sIds.length; i += 10) {
      var end = (i + 10 < sIds.length) ? i + 10 : sIds.length;
      var chunk = sIds.sublist(i, end);
      if (chunk.isNotEmpty) {
        var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: chunk).get();
        allDocs.addAll(q.docs);
      }
    }
    return allDocs;
  }

  // --- UI ACTIONS ---
  void _showEditTeamNameDialog() {
    TextEditingController _nameCtrl = TextEditingController(text: teamData?['teamName'] ?? "");
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Editar Nombre"),
          content: TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: "Nombre del Equipo", border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                if (_nameCtrl.text.trim().isEmpty) return;
                await FirebaseFirestore.instance
                    .collection('seasons').doc(widget.seasonId)
                    .collection('participants').doc(widget.userId)
                    .update({'teamName': _nameCtrl.text.trim()});

                Navigator.pop(context);
                _loadAllData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nombre actualizado")));
              },
              child: const Text("GUARDAR"),
            )
          ],
        )
    );
  }

  void _showOfferDialog(DocumentSnapshot playerDoc) {
    TextEditingController amountCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Ofertar por ${playerDoc['name']}"),
          content: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Monto (\$)", prefixText: "\$", border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () async {
                int amount = int.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('transfers').add({
                  'fromUserId': currentUserId,
                  'toUserId': widget.userId,
                  'targetPlayerId': playerDoc.id,
                  'targetPlayerName': playerDoc['name'],
                  'offeredAmount': amount,
                  'status': 'PENDING',
                  'timestamp': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Oferta enviada!")));
              },
              child: const Text("ENVIAR OFERTA"),
            )
          ],
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (teamData == null) return const Scaffold(body: Center(child: Text("Error cargando equipo")));

    String name = teamData!['teamName'] ?? "Sin Nombre";
    int budget = teamData!['budget'] ?? 0;
    bool isMyTeam = (widget.userId == currentUserId);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: Text(name.toUpperCase()),
          backgroundColor: const Color(0xFF0D1B2A),
          foregroundColor: Colors.white,
          centerTitle: true,
          actions: [
            if (isMyTeam) ...[
              // NUEVO BOTÓN PATROCINIOS
              IconButton(
                icon: const Icon(Icons.monetization_on_outlined, color: Colors.amber),
                tooltip: "Patrocinios",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SponsorshipScreen(
                    seasonId: widget.seasonId,
                    userId: widget.userId,
                    isAdmin: isSeasonAdmin, // --- CORREGIDO: Pasamos la variable real ---
                  )));
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: "Cambiar nombre del equipo",
                onPressed: _showEditTeamNameDialog,
              ),
            ]
          ],
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: "RENDIMIENTO"),
              Tab(text: "PLANTILLA"),
              Tab(text: "FIXTURE"),
            ],
          ),
        ),

        floatingActionButton: isMyTeam ? FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SquadBuilderScreen(
                seasonId: widget.seasonId,
                userId: widget.userId
            )));
          },
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.stadium),
          label: const Text("ESTRATEGIA"),
        ) : null,

        body: TabBarView(
          children: [
            _buildPerformanceTab(name, budget),
            _buildRosterTab(isMyTeam),
            _buildFixtureTab(),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: RENDIMIENTO ---
  Widget _buildPerformanceTab(String name, int budget) {
    int matchesPlayed = playedMatches.length;
    int wins = 0;
    int goalsScored = 0;
    int goalsConceded = 0;
    int totalShots = 0;
    int totalPossession = 0;
    int totalPasses = 0;
    int totalPassesCompleted = 0;
    int totalInterceptions = 0;
    int totalFouls = 0;
    int cleanSheets = 0;

    for (var doc in playedMatches) {
      var d = doc.data() as Map<String, dynamic>;
      bool amHome = (d['homeUser'] == widget.userId);

      int myScore = amHome ? (d['homeScore']??0) : (d['awayScore']??0);
      int rivalScore = amHome ? (d['awayScore']??0) : (d['homeScore']??0);

      goalsScored += myScore;
      goalsConceded += rivalScore;
      if (myScore > rivalScore) wins++;
      if (rivalScore == 0) cleanSheets++;

      if (d['stats'] != null) {
        var myStats = amHome ? d['stats']['home'] : d['stats']['away'];
        if (myStats != null) {
          totalShots += (myStats['shots'] as int? ?? 0);
          totalPossession += (myStats['possession'] as int? ?? 50);
          totalPasses += (myStats['passes'] as int? ?? 0);
          totalPassesCompleted += (myStats['passesCompleted'] as int? ?? 0);
          totalInterceptions += (myStats['interceptions'] as int? ?? 0);
          totalFouls += (myStats['fouls'] as int? ?? 0);
        }
      }
    }

    double avgGoals = matchesPlayed > 0 ? goalsScored / matchesPlayed : 0;
    double avgShots = matchesPlayed > 0 ? totalShots / matchesPlayed : 0;
    double avgPossession = matchesPlayed > 0 ? totalPossession / matchesPlayed : 0;
    double effectiveness = totalShots > 0 ? (goalsScored / totalShots * 100) : 0;
    double passAccuracy = totalPasses > 0 ? (totalPassesCompleted / totalPasses * 100) : 0;
    double winPercentage = matchesPlayed > 0 ? (wins / matchesPlayed * 100) : 0;
    double avgInterceptions = matchesPlayed > 0 ? totalInterceptions / matchesPlayed : 0;
    double avgFouls = matchesPlayed > 0 ? totalFouls / matchesPlayed : 0;
    double avgPasses = matchesPlayed > 0 ? totalPasses / matchesPlayed : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.shield, size: 60, color: Color(0xFF0D1B2A)),
                  const SizedBox(height: 10),
                  Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 5),
                  Text("Presupuesto: \$${(budget/1000000).toStringAsFixed(1)}M", style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: Text("ANÁLISIS TÁCTICO (Promedios)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey))),
          const SizedBox(height: 10),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _statBox("% Victorias", "${winPercentage.toStringAsFixed(1)}%", Icons.emoji_events, Colors.amber[800]!),
              _statBox("Goles / Partido", avgGoals.toStringAsFixed(1), Icons.sports_soccer, Colors.green),
              _statBox("Tiros al Arco", avgShots.toStringAsFixed(1), Icons.gps_fixed, Colors.blue),
              _statBox("Efectividad", "${effectiveness.toStringAsFixed(0)}%", Icons.bolt, Colors.orange),
              _statBox("Posesión", "${avgPossession.toStringAsFixed(0)}%", Icons.pie_chart, Colors.purple),
              _statBox("Pases por Partido", avgPasses.toStringAsFixed(0), Icons.loop, Colors.grey),
              _statBox("Precisión Pases", "${passAccuracy.toStringAsFixed(0)}%", Icons.check_circle, Colors.teal),
              _statBox("Vallas Invictas", "$cleanSheets", Icons.lock_outline, Colors.indigo),
              _statBox("Intercepciones/PJ", avgInterceptions.toStringAsFixed(1), Icons.content_cut, Colors.redAccent),
              _statBox("Faltas/PJ", avgFouls.toStringAsFixed(1), Icons.mood_bad, Colors.brown),
            ],
          ),
          const SizedBox(height: 100), // Espacio para FAB
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.1), radius: 18, child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  // --- TAB 2: PLANTILLA ---
  Widget _buildRosterTab(bool isMyTeam) {
    if (rosterDocs.isEmpty) return const Center(child: Text("Sin jugadores en plantilla"));

    rosterDocs.sort((a, b) {
      var dA = a.data() as Map<String, dynamic>;
      var dB = b.data() as Map<String, dynamic>;
      return (dB['rating'] ?? 0).compareTo(dA['rating'] ?? 0);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: rosterDocs.length,
      itemBuilder: (context, index) {
        var data = rosterDocs[index].data() as Map<String, dynamic>;
        int rating = data['rating'] ?? 0;
        String name = data['name'] ?? "Sin Nombre";
        String pos = data['position'] ?? "N/A";
        int age = data['age'] ?? 0;
        int value = data['value'] ?? 0;

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRatingColor(rating),
              child: Text("$rating", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("$pos • $age años"),
            trailing: value > 0
                ? Text("\$${(value/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))
                : (!isMyTeam ? const Icon(Icons.monetization_on, color: Colors.green) : null),

            onTap: !isMyTeam ? () => _showOfferDialog(rosterDocs[index]) : null,
          ),
        );
      },
    );
  }

  // --- TAB 3: FIXTURE ---
  double _getVirtualOrder(int round) {
    // 1. LIGA
    if (round < 100) return round.toDouble();

    // 2. SUPERCOPA
    if (round < 0) return round.toDouble();

    double midSeason = _maxLeagueRound / 2;

    // 3. COPA
    if (round == 149) return midSeason * 0.3; // Prelim
    if (round == 150) return midSeason * 0.8; // R1
    if (round == 151) return midSeason * 1.2; // R2
    if (round == 152) return midSeason * 1.6; // Semi
    if (round == 153) return _maxLeagueRound - 0.5; // Final

    // 4. CHAMPIONS GRUPOS
    if (round >= 201 && round <= 205) {
      int groupMatchNum = round - 200;
      return (groupMatchNum * 2) + 0.5;
    }

    // 5. ELIMINATORIAS EUROPEAS
    if (round >= 250) {
      double startOffset = midSeason + 1.0;

      if (round == 250) return startOffset + 1.5;
      if (round == 251) return startOffset + 2.5;

      if (round == 260) return startOffset + 4.5;
      if (round == 261) return startOffset + 5.5;

      if (round == 270) return _maxLeagueRound + 2.0;
    }

    return 999;
  }

  String _getFriendlyRoundName(Map<String, dynamic> data) {
    String type = data['type'] ?? '';
    int round = data['round'] ?? 0;
    String rawName = data['roundName'] ?? '';

    if (type == 'LEAGUE') return "LIGA - FECHA $round";
    if (type == 'CHAMPIONS_GROUP') return "UCL - ${rawName.toUpperCase()}";
    if (type.contains('CHAMPIONS')) return "UCL - ${rawName.toUpperCase()}";
    if (type == 'CUP') {
      if (round == 152) return "COPA - FINAL";
      if (round == 151) return "COPA - SEMIFINAL";
      if (round == 150) return "COPA - CUARTOS";
      if (round == 149) return "COPA - PRELIMINAR";
      return "COPA - ${rawName.toUpperCase()}";
    }
    return rawName.toUpperCase();
  }

  Widget _buildFixtureTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('matches')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var allMatches = snapshot.data!.docs;

        var myMatches = allMatches.where((doc) {
          var d = doc.data() as Map<String, dynamic>;

          bool amHome = (d['homeUser'] == widget.userId);
          bool amAway = (d['awayUser'] == widget.userId);
          bool isConfirmed = amHome || amAway;

          String opponentId = amHome ? d['awayUser'] : d['homeUser'];
          bool opponentDefined = (opponentId != 'TBD' && !opponentId.startsWith('GANADOR') && !opponentId.startsWith('FINALISTA'));

          bool noJugado = (d['status'] != 'PLAYED' && d['status'] != 'REPORTED');

          return isConfirmed && opponentDefined && noJugado;
        }).toList();

        if (myMatches.isEmpty) {
          return const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available, size: 60, color: Colors.grey),
              SizedBox(height: 10),
              Text("No tienes partidos próximos confirmados.", style: TextStyle(color: Colors.grey)),
            ],
          ));
        }

        myMatches.sort((a, b) {
          int rA = (a.data() as Map)['round'] ?? 0;
          int rB = (b.data() as Map)['round'] ?? 0;
          return _getVirtualOrder(rA).compareTo(_getVirtualOrder(rB));
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: myMatches.length,
          itemBuilder: (context, index) {
            var data = myMatches[index].data() as Map<String, dynamic>;
            bool amHome = (data['homeUser'] == widget.userId);
            String opponentId = amHome ? data['awayUser'] : data['homeUser'];

            String opponentName = allTeamNames[opponentId] ?? "Desconocido";
            String roundTitle = _getFriendlyRoundName(data);

            Color cardColor;
            if (data['type'] == 'LEAGUE') cardColor = const Color(0xFF0D1B2A);
            else if (data['type'] == 'CUP') cardColor = const Color(0xFFE63946);
            else cardColor = const Color(0xFF1E88E5);

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Text(
                      roundTitle,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    child: Row(
                      children: [
                        Icon(amHome ? Icons.home : Icons.flight_takeoff, color: Colors.grey, size: 24),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opponentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                amHome ? "Juegas de LOCAL" : "Juegas de VISITA",
                                style: TextStyle(
                                    color: amHome ? Colors.blue[800] : Colors.orange[800],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text("VS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.grey.withOpacity(0.3))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getRatingColor(int r) {
    if (r >= 90) return Colors.black;
    if (r >= 85) return const Color(0xFFD4AF37);
    if (r >= 80) return const Color(0xFFC0C0C0);
    return const Color(0xFFCD7F32);
  }
}