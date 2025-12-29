import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StatsTab extends StatelessWidget {
  final String seasonId;
  const StatsTab({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Barra de pestañas integrada
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))]
            ),
            child: const TabBar(
              labelColor: Color(0xFF0D1B2A),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.amber,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(icon: Icon(Icons.person), text: "JUGADORES"),
                Tab(icon: Icon(Icons.shield), text: "EQUIPOS"),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              children: [
                // PESTAÑA 1: JUGADORES (Sub-tabs)
                _PlayersStatsView(seasonId: seasonId),

                // PESTAÑA 2: EQUIPOS (Lista)
                _TeamsStatsView(seasonId: seasonId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- VISTA JUGADORES (Goleadores / Asistidores) ---
class _PlayersStatsView extends StatelessWidget {
  final String seasonId;
  const _PlayersStatsView({required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            height: 40,
            decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20)
            ),
            child: TabBar(
              indicator: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(20)
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.black54,
              tabs: const [Tab(text: "MÁX. GOLEADORES"), Tab(text: "MÁX. ASISTIDORES")],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RankingList(seasonId: seasonId, type: 'GOALS'),
                _RankingList(seasonId: seasonId, type: 'ASSISTS'),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// --- VISTA EQUIPOS ---
class _TeamsStatsView extends StatelessWidget {
  final String seasonId;
  const _TeamsStatsView({required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatBox("MEJOR DEFENSA", "Vallas Invictas", docs, 'cleanSheets', true, Icons.security, Colors.blueGrey),
            _buildStatBox("MÁQUINA DE GOLES", "Promedio Gol/P", docs, 'avgGoals', false, Icons.sports_soccer, Colors.green),
            _buildStatBox("REYES DE LA POSESIÓN", "Promedio %", docs, 'avgPossession', false, Icons.timelapse, Colors.purple, suffix: "%"),
            _buildStatBox("TIKI-TAKA", "Pases Completados", docs, 'avgPassesCompleted', false, Icons.compare_arrows, Colors.indigo),
          ],
        );
      },
    );
  }

  Widget _buildStatBox(String title, String subtitle, List<QueryDocumentSnapshot> docs, String key, bool isInt, IconData icon, Color color, {String suffix = ""}) {
    List<Map<String, dynamic>> ranking = [];
    for (var d in docs) {
      var data = d.data() as Map<String, dynamic>;
      var stats = data['advancedStats'] ?? {};
      num val = stats[key] ?? 0;
      if (val > 0) ranking.add({'name': data['teamName'], 'val': val});
    }
    ranking.sort((a, b) => b['val'].compareTo(a['val']));
    var top3 = ranking.take(3).toList();

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Header del Ranking
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16))
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                )
              ],
            ),
          ),
          // Lista Top 3
          if (top3.isEmpty)
            const Padding(padding: EdgeInsets.all(15), child: Text("Sin datos suficientes", style: TextStyle(color: Colors.grey)))
          else
            ...top3.asMap().entries.map((entry) {
              int idx = entry.key;
              var item = entry.value;
              return ListTile(
                dense: true,
                leading: Text(
                  idx == 0 ? "🥇" : (idx == 1 ? "🥈" : "🥉"),
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(item['name'], style: TextStyle(fontWeight: idx == 0 ? FontWeight.bold : FontWeight.normal)),
                trailing: Text("${item['val']}$suffix", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              );
            }).toList()
        ],
      ),
    );
  }
}

// --- LISTA RANKING JUGADORES ---
class _RankingList extends StatelessWidget {
  final String seasonId;
  final String type; // GOALS, ASSISTS

  const _RankingList({required this.seasonId, required this.type});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var participants = snapshot.data!.docs;
        List<Map<String, dynamic>> ranking = [];

        for (var userDoc in participants) {
          var data = userDoc.data() as Map<String, dynamic>;
          String teamName = data['teamName'] ?? 'Equipo';
          Map<String, dynamic> playerStats = data['playerStats'] ?? {};

          playerStats.forEach((pid, stats) {
            int val = 0;
            if (type == 'GOALS') val = stats['goals'] ?? 0;
            if (type == 'ASSISTS') val = stats['assists'] ?? 0;

            if (val > 0) {
              ranking.add({
                'id': pid,
                'value': val,
                'team': teamName
              });
            }
          });
        }

        ranking.sort((a, b) => b['value'].compareTo(a['value']));

        if (ranking.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.emoji_events_outlined, size: 50, color: Colors.grey), Text("Aún no hay registros.", style: TextStyle(color: Colors.grey))]));

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: ranking.length,
          itemBuilder: (context, index) {
            var item = ranking[index];
            bool isTop3 = index < 3;

            return Card(
              elevation: isTop3 ? 4 : 1,
              shadowColor: isTop3 ? Colors.amber.withOpacity(0.3) : null,
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isTop3 ? Colors.amber.withOpacity(0.5) : Colors.transparent)),
              child: ListTile(
                leading: Container(
                  width: 35, height: 35,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == 0 ? Colors.amber : (index == 1 ? Colors.grey[400] : (index == 2 ? const Color(0xFFCD7F32) : Colors.grey[100])),
                  ),
                  child: Text("${index + 1}", style: TextStyle(color: index < 3 ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)),
                ),
                title: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('players').doc(item['id']).get(),
                  builder: (c, s) => Text(s.data?['name'] ?? 'Cargando...', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                subtitle: Text(item['team'], style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text("${item['value']}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Theme.of(context).primaryColor)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}