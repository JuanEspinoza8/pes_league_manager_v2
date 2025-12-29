import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'squad_builder_screen.dart';

class MyTeamScreen extends StatelessWidget {
  final String seasonId;
  final String userId;

  const MyTeamScreen({super.key, required this.seasonId, required this.userId});

  void _editTeamName(BuildContext context, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);
    showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Renombrar Equipo"), content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () async {
            if(controller.text.isNotEmpty) {
              await FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(userId).update({'teamName': controller.text.trim()});
              Navigator.pop(c);
            }
          }, child: const Text("Guardar"))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final bool isMyProfile = (userId == currentUserId);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(userId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final String teamName = userData['teamName'] ?? 'Equipo';
        final List<dynamic> rosterIds = userData['roster'] ?? [];
        final int budget = userData['budget'] ?? 0;
        final Map<String, dynamic> stats = userData['advancedStats'] ?? {};

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(teamName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 16)),
              backgroundColor: Theme.of(context).primaryColor,
              centerTitle: true,
              actions: isMyProfile ? [IconButton(icon: const Icon(Icons.edit_outlined), tooltip: "Cambiar Nombre", onPressed: () => _editTeamName(context, teamName))] : [],
              bottom: const TabBar(
                  indicatorColor: Colors.amber,
                  labelColor: Colors.amber,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold),
                  tabs: [Tab(text: "PLANTILLA"), Tab(text: "RENDIMIENTO")]
              ),
            ),

            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SquadBuilderScreen(seasonId: seasonId, userId: userId, isReadOnly: !isMyProfile))),
              icon: Icon(isMyProfile ? Icons.shield : Icons.visibility),
              label: Text(isMyProfile ? "PIZARRA TÁCTICA" : "VER TÁCTICA"),
              backgroundColor: isMyProfile ? Colors.amber[700] : Colors.blue,
              foregroundColor: Colors.black,
              elevation: 4,
            ),

            body: Container(
              color: const Color(0xFFF0F2F5),
              child: TabBarView(
                children: [
                  Column(children: [
                    // Header de Resumen
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]),
                        child: Row(
                            children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("JUGADORES", style: TextStyle(color: Colors.white54, fontSize: 10)), Text("${rosterIds.length}/22", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                const Text("PRESUPUESTO", style: TextStyle(color: Colors.white54, fontSize: 10)),
                                FittedBox(fit: BoxFit.scaleDown, child: Text("\$${(budget / 1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Monospace')))
                              ])),
                            ]
                        )
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: rosterIds.isEmpty ? const Center(child: Text("Sin jugadores")) : FutureBuilder<List<DocumentSnapshot>>(
                        future: _fetchAllPlayers(rosterIds), builder: (context, playersSnap) {
                      if (playersSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final players = playersSnap.data ?? [];
                      players.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
                      return ListView.builder(padding: const EdgeInsets.fromLTRB(10, 0, 10, 80), itemCount: players.length, itemBuilder: (context, index) {
                        final p = players[index].data() as Map<String, dynamic>;
                        return _buildPlayerCard(p);
                      });
                    }))
                  ]),

                  // TAB 2: ESTADÍSTICAS (Con corrección de tipos)
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: stats.isEmpty
                        ? const Padding(padding: EdgeInsets.only(top: 100), child: Center(child: Column(children: [Icon(Icons.bar_chart, size: 50, color: Colors.grey), Text("Juega partidos para ver estadísticas.", style: TextStyle(color: Colors.grey))])))
                        : Column(
                      children: [
                        _buildStatSection("Ataque", [
                          _buildStatTile("Goles p/P", "${stats['avgGoals'] ?? 0}", Icons.sports_soccer, Colors.green),
                          _buildStatTile("Tiros al Arco", "${stats['avgShotsOnTarget'] ?? 0}", Icons.gps_fixed, Colors.blue),
                          _buildStatTile("Efectividad", "${_calcEfficiency(stats)}%", Icons.bolt, Colors.orange),
                        ]),
                        const SizedBox(height: 15),
                        _buildStatSection("Posesión & Juego", [
                          _buildStatTile("Posesión", "${stats['avgPossession'] ?? 0}%", Icons.pie_chart, Colors.purple),
                          _buildStatTile("Pases Totales", "${stats['avgPasses'] ?? 0}", Icons.compare_arrows, Colors.indigo),
                          _buildStatTile("Pases Comp.", "${stats['avgPassesCompleted'] ?? 0}", Icons.check_circle_outline, Colors.teal),
                        ]),
                        const SizedBox(height: 15),
                        _buildStatSection("Defensa", [
                          _buildStatTile("Vallas Invictas", "${stats['cleanSheets'] ?? 0}", Icons.shield, Colors.blueGrey),
                          _buildStatTile("Intercepciones", "${stats['avgInterceptions'] ?? 0}", Icons.content_cut, Colors.redAccent),
                          _buildStatTile("Faltas p/P", "${stats['avgFouls'] ?? 0}", Icons.warning_amber, Colors.amber),
                        ]),
                        const SizedBox(height: 80),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- WIDGETS ---
  Widget _buildPlayerCard(Map<String, dynamic> p) {
    int rating = p['rating'] ?? 75;
    Color color = _getColor(rating);
    return Container(margin: const EdgeInsets.only(bottom: 8), height: 70, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))], border: Border(left: BorderSide(color: color, width: 5))), child: Row(children: [
      Container(width: 60, alignment: Alignment.center, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("$rating", style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)), Text(p['position'] ?? '?', style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))])),
      const VerticalDivider(width: 1, indent: 10, endIndent: 10),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(p['name'].toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(p['team'] ?? 'Libre', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 12))])),
      Padding(padding: const EdgeInsets.only(right: 15), child: Icon(Icons.person, color: Colors.grey[300], size: 30))
    ]));
  }

  Widget _buildStatSection(String title, List<Widget> tiles) { return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 5, bottom: 8), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1))), Row(children: tiles.map((t) => Expanded(child: t)).toList())]); }

  Widget _buildStatTile(String label, String value, IconData icon, Color color) {
    return Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4), child: Column(children: [
      Icon(icon, color: color, size: 24), const SizedBox(height: 5), FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center, maxLines: 1)
    ])));
  }

  // CORRECCIÓN DE TIPO: Aseguramos que los valores sean double antes de operar
  String _calcEfficiency(Map stats) {
    double goals = (stats['avgGoals'] ?? 0).toDouble();
    double shots = (stats['avgShots'] ?? 0).toDouble();
    if (shots == 0) return "0";
    return ((goals / shots) * 100).toStringAsFixed(0);
  }

  Future<List<DocumentSnapshot>> _fetchAllPlayers(List<dynamic> ids) async {
    if (ids.isEmpty) return [];
    List<String> stringIds = ids.map((e) => e.toString()).toList();
    List<DocumentSnapshot> allDocs = [];
    for (var i = 0; i < stringIds.length; i += 10) {
      var end = (i + 10 < stringIds.length) ? i + 10 : stringIds.length;
      var chunk = stringIds.sublist(i, end);
      if(chunk.isNotEmpty) {
        var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: chunk).get();
        allDocs.addAll(q.docs);
      }
    }
    return allDocs;
  }

  Color _getColor(int rating) { if (rating >= 90) return Colors.black; if (rating >= 85) return const Color(0xFFD4AF37); if (rating >= 80) return Colors.grey; return const Color(0xFFCD7F32); }
}