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
          backgroundColor: const Color(0xFF1E293B), // Fondo oscuro
          title: const Text("Editar Nombre", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: "Nombre del Equipo",
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
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
          backgroundColor: const Color(0xFF1E293B),
          title: Text("Ofertar por ${playerDoc['name']}", style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: "Monto (\$)",
                prefixText: "\$",
                labelStyle: TextStyle(color: Colors.white54),
                prefixStyle: TextStyle(color: Colors.greenAccent),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF0B1120), body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
    if (teamData == null) return const Scaffold(backgroundColor: Color(0xFF0B1120), body: Center(child: Text("Error cargando equipo", style: TextStyle(color: Colors.white))));

    String name = teamData!['teamName'] ?? "Sin Nombre";
    int budget = teamData!['budget'] ?? 0;
    bool isMyTeam = (widget.userId == currentUserId);
    final goldColor = const Color(0xFFD4AF37);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1120), // Fondo V2
        appBar: AppBar(
          title: Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          actions: [
            if (isMyTeam) ...[
              // NUEVO BOTÓN PATROCINIOS
              IconButton(
                icon: const Icon(Icons.monetization_on_outlined, color: Colors.greenAccent),
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
                icon: const Icon(Icons.edit_outlined),
                tooltip: "Cambiar nombre del equipo",
                onPressed: _showEditTeamNameDialog,
              ),
            ]
          ],
          bottom: TabBar(
            indicatorColor: goldColor,
            labelColor: goldColor,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(text: "ANÁLISIS"),
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
          backgroundColor: goldColor,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.sports_soccer),
          label: const Text("ESTRATEGIA", style: TextStyle(fontWeight: FontWeight.bold)),
        ) : null,

        body: TabBarView(
          children: [
            _buildPerformanceTab(name, budget, goldColor),
            _buildRosterTab(isMyTeam),
            _buildFixtureTab(),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: RENDIMIENTO ---
  Widget _buildPerformanceTab(String name, int budget, Color goldColor) {
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF1E293B), Colors.black.withOpacity(0.8)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Column(
              children: [
                Icon(Icons.shield, size: 50, color: goldColor),
                const SizedBox(height: 10),
                Text(name.toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text("PRESUPUESTO DISPONIBLE", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, letterSpacing: 1.5)),
                Text("\$${(budget/1000000).toStringAsFixed(1)}M", style: const TextStyle(fontSize: 24, color: Colors.greenAccent, fontWeight: FontWeight.w900)),
              ],
            ),
          ),

          const SizedBox(height: 30),
          const Align(alignment: Alignment.centerLeft, child: Text("ESTADÍSTICAS DE TEMPORADA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white30, letterSpacing: 1.5))),
          const SizedBox(height: 15),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.0,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _statBox("% VICTORIAS", "${winPercentage.toStringAsFixed(1)}%", Icons.emoji_events, goldColor),
              _statBox("GOLES / PJ", avgGoals.toStringAsFixed(1), Icons.sports_soccer, Colors.greenAccent),
              _statBox("TIROS / PJ", avgShots.toStringAsFixed(1), Icons.gps_fixed, Colors.blueAccent),
              _statBox("EFECTIVIDAD", "${effectiveness.toStringAsFixed(0)}%", Icons.bolt, Colors.orangeAccent),
              _statBox("POSESIÓN", "${avgPossession.toStringAsFixed(0)}%", Icons.pie_chart, Colors.purpleAccent),
              _statBox("PASES / PJ", avgPasses.toStringAsFixed(0), Icons.loop, Colors.grey),
              _statBox("PRECISIÓN", "${passAccuracy.toStringAsFixed(0)}%", Icons.check_circle, Colors.tealAccent),
              _statBox("VALLAS EN 0", "$cleanSheets", Icons.lock_outline, Colors.indigoAccent),
              _statBox("QUITES / PJ", avgInterceptions.toStringAsFixed(1), Icons.content_cut, Colors.redAccent),
              _statBox("FALTAS / PJ", avgFouls.toStringAsFixed(1), Icons.mood_bad, Colors.brown),
            ],
          ),
          const SizedBox(height: 100), // Espacio para FAB
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05))
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          )
        ],
      ),
    );
  }

  // --- TAB 2: PLANTILLA ---
  Widget _buildRosterTab(bool isMyTeam) {
    if (rosterDocs.isEmpty) return const Center(child: Text("Sin jugadores en plantilla", style: TextStyle(color: Colors.white54)));

    rosterDocs.sort((a, b) {
      var dA = a.data() as Map<String, dynamic>;
      var dB = b.data() as Map<String, dynamic>;
      return (dB['rating'] ?? 0).compareTo(dA['rating'] ?? 0);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rosterDocs.length,
      itemBuilder: (context, index) {
        var data = rosterDocs[index].data() as Map<String, dynamic>;
        int rating = data['rating'] ?? 0;
        String name = data['name'] ?? "Sin Nombre";
        String pos = data['position'] ?? "N/A";
        int age = data['age'] ?? 0;
        int value = data['value'] ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05))
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 42, height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _getRatingColor(rating),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1.5)
              ),
              child: Text("$rating", style: TextStyle(color: rating >= 80 ? Colors.black : Colors.white, fontWeight: FontWeight.w900)),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text("$pos • $age años", style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: value > 0
                ? Text("\$${(value/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold))
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));

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
              Icon(Icons.event_available, size: 50, color: Colors.white24),
              SizedBox(height: 15),
              Text("No tienes partidos próximos confirmados.", style: TextStyle(color: Colors.white24)),
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

            Color accentColor;
            if (data['type'] == 'LEAGUE') accentColor = Colors.white10;
            else if (data['type'] == 'CUP') accentColor = Colors.orangeAccent.withOpacity(0.3);
            else accentColor = Colors.indigoAccent.withOpacity(0.3);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Card BG
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05))
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Text(
                      roundTitle,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Row(
                      children: [
                        Icon(amHome ? Icons.home_filled : Icons.flight, color: Colors.white38, size: 20),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opponentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(
                                amHome ? "Juegas de LOCAL" : "Juegas de VISITA",
                                style: TextStyle(
                                    color: amHome ? Colors.blueAccent : Colors.orangeAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(8)
                          ),
                          child: const Text("VS", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white54)),
                        ),
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
    if (r >= 90) return Colors.cyanAccent; // Iconic V2
    if (r >= 85) return const Color(0xFFD4AF37); // Gold
    if (r >= 80) return Colors.grey; // Silver
    return const Color(0xFFCD7F32); // Bronze
  }
}