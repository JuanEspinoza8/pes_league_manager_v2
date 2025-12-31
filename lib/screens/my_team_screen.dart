import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'squad_builder_screen.dart';

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

  // Cache de partidos para calcular stats
  List<DocumentSnapshot> playedMatches = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      // 1. Cargar datos del equipo
      var teamDoc = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(widget.userId)
          .get();

      // 2. Cargar nombres de equipos (para el Fixture)
      var participantsSnap = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants')
          .get();

      Map<String, String> names = {};
      for (var p in participantsSnap.docs) {
        names[p.id] = p.data()['teamName'] ?? "Equipo";
      }

      // 3. Cargar Jugadores de la Plantilla
      List rosterIds = teamDoc.data()?['roster'] ?? [];
      List<DocumentSnapshot> players = [];
      if (rosterIds.isNotEmpty) {
        players = await _fetchPlayers(rosterIds);
      }

      // 4. Cargar HISTORIAL DE PARTIDOS (Para calcular stats en vivo)
      var matchesSnap = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('matches')
          .where('status', isEqualTo: 'PLAYED')
          .get();

      // Filtramos en memoria los que son mios
      var myPlayed = matchesSnap.docs.where((doc) {
        var d = doc.data();
        return d['homeUser'] == widget.userId || d['awayUser'] == widget.userId;
      }).toList();

      if (mounted) {
        setState(() {
          teamData = teamDoc.data();
          allTeamNames = names;
          rosterDocs = players;
          playedMatches = myPlayed;
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

  // --- CAMBIAR NOMBRE DEL EQUIPO ---
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

  // --- OFERTAR POR JUGADOR ---
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
            // Botón para cambiar nombre (Solo dueño)
            if (isMyTeam)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: "Cambiar nombre del equipo",
                onPressed: _showEditTeamNameDialog,
              )
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

        // --- BOTÓN FLOTANTE ESTRATEGIA (Solo Dueño) ---
        floatingActionButton: isMyTeam ? FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SquadBuilderScreen(
                seasonId: widget.seasonId,
                userId: widget.userId // <--- CORREGIDO: Se pasa el ID
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

  // 1. PESTAÑA RENDIMIENTO (Cálculo en vivo)
  Widget _buildPerformanceTab(String name, int budget) {
    // Calculamos estadísticas recorriendo los partidos jugados REALES
    int matchesPlayed = playedMatches.length;
    int wins = 0;
    int goalsScored = 0;
    int goalsConceded = 0; // Para vallas invictas
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

      // Goles
      goalsScored += myScore;
      goalsConceded += rivalScore;
      if (myScore > rivalScore) wins++;
      if (rivalScore == 0) cleanSheets++;

      // Stats avanzadas (si existen)
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

    // Promedios
    double avgGoals = matchesPlayed > 0 ? goalsScored / matchesPlayed : 0;
    double avgShots = matchesPlayed > 0 ? totalShots / matchesPlayed : 0;
    double avgPossession = matchesPlayed > 0 ? totalPossession / matchesPlayed : 0;
    double effectiveness = totalShots > 0 ? (goalsScored / totalShots * 100) : 0;
    double passAccuracy = totalPasses > 0 ? (totalPassesCompleted / totalPasses * 100) : 0;
    double winPercentage = matchesPlayed > 0 ? (wins / matchesPlayed * 100) : 0;
    double avgInterceptions = matchesPlayed > 0 ? totalInterceptions / matchesPlayed : 0;
    double avgFouls = matchesPlayed > 0 ? totalFouls / matchesPlayed : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // TARJETA CABECERA
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

          // GRID DE DATOS
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _statBox("Partidos Jugados", "$matchesPlayed", Icons.calendar_today, Colors.black),
              _statBox("% Victorias", "${winPercentage.toStringAsFixed(1)}%", Icons.emoji_events, Colors.amber[800]!), // NUEVO
              _statBox("Goles / Partido", avgGoals.toStringAsFixed(1), Icons.sports_soccer, Colors.green),
              _statBox("Tiros al Arco", avgShots.toStringAsFixed(1), Icons.gps_fixed, Colors.blue),
              _statBox("Efectividad", "${effectiveness.toStringAsFixed(0)}%", Icons.bolt, Colors.orange),
              _statBox("Posesión", "${avgPossession.toStringAsFixed(0)}%", Icons.pie_chart, Colors.purple),
              _statBox("Pases Totales", "$totalPasses", Icons.loop, Colors.grey),
              _statBox("Precisión Pases", "${passAccuracy.toStringAsFixed(0)}%", Icons.check_circle, Colors.teal),
              _statBox("Vallas Invictas", "$cleanSheets", Icons.lock_outline, Colors.indigo),
              _statBox("Intercepciones/PJ", avgInterceptions.toStringAsFixed(1), Icons.content_cut, Colors.redAccent),
              _statBox("Faltas/PJ", avgFouls.toStringAsFixed(1), Icons.mood_bad, Colors.brown),
            ],
          ),
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

  // 2. PESTAÑA PLANTILLA (Corregida)
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
            // Solo mostramos precio si vale algo y no es 0
            trailing: value > 0
                ? Text("\$${(value/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))
                : (!isMyTeam ? const Icon(Icons.monetization_on, color: Colors.green) : null), // Icono de oferta si es rival

            onTap: !isMyTeam ? () => _showOfferDialog(rosterDocs[index]) : null,
          ),
        );
      },
    );
  }

  // 3. PESTAÑA FIXTURE (Arreglada)
  Widget _buildFixtureTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('matches')
          .orderBy('round')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var allMatches = snapshot.data!.docs;

        // Filtramos: 1. Soy Yo, 2. NO está jugado (atrapa SCHEDULED, PENDING, etc)
        var myMatches = allMatches.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          bool soyYo = (d['homeUser'] == widget.userId || d['awayUser'] == widget.userId);
          bool noJugado = (d['status'] != 'PLAYED' && d['status'] != 'REPORTED');
          return soyYo && noJugado;
        }).toList();

        if (myMatches.isEmpty) {
          return const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available, size: 60, color: Colors.grey),
              SizedBox(height: 10),
              Text("Estás al día. ¡No hay partidos pendientes!", style: TextStyle(color: Colors.grey)),
            ],
          ));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: myMatches.length,
          itemBuilder: (context, index) {
            var data = myMatches[index].data() as Map<String, dynamic>;
            bool amHome = (data['homeUser'] == widget.userId);
            String opponentId = amHome ? data['awayUser'] : data['homeUser'];
            String opponentName = allTeamNames[opponentId] ?? "Rival Desconocido";

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          const Text("FECHA", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70)),
                          Text("${data['round']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("TU PRÓXIMO RIVAL", style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text(opponentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(amHome ? "(Juegas de LOCAL 🏠)" : "(Juegas de VISITA ✈️)", style: TextStyle(color: amHome ? Colors.blue[800] : Colors.orange[800], fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Icon(Icons.sports_soccer, color: Colors.grey, size: 30),
                  ],
                ),
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