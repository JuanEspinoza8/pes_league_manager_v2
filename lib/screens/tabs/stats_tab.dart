import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StatsTab extends StatelessWidget {
  final String seasonId;
  const StatsTab({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return DefaultTabController(
      length: 2,
      child: Container(
        color: const Color(0xFF0B1120),
        child: Column(
          children: [
            // Barra de pestañas integrada
            Container(
              decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 5)]
              ),
              child: const TabBar(
                labelColor: goldColor,
                unselectedLabelColor: Colors.white38,
                indicatorColor: goldColor,
                indicatorWeight: 3,
                labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
                tabs: [
                  Tab(icon: Icon(Icons.person), text: "JUGADORES"),
                  Tab(icon: Icon(Icons.shield), text: "EQUIPOS"),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                children: [
                  _PlayersStatsView(seasonId: seasonId),
                  _TeamsStatsView(seasonId: seasonId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- VISTA JUGADORES ---
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
            margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            height: 45,
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white10)
            ),
            child: TabBar(
              indicator: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(25)
              ),
              labelColor: Colors.black,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: "GOLEADORES"), Tab(text: "ASISTIDORES")],
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        var docs = snapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatBox("MEJOR DEFENSA", "Vallas Invictas", docs, 'cleanSheets', true, Icons.security, Colors.blueAccent),
            _buildStatBox("MAQUINA DE GOLES", "Promedio Gol/P", docs, 'avgGoals', false, Icons.sports_soccer, Colors.greenAccent),
            _buildStatBox("REYES DE LA POSESION", "Promedio %", docs, 'avgPossession', false, Icons.pie_chart, Colors.purpleAccent, suffix: "%"),
            _buildStatBox("TIKI-TAKA", "Pases Completados", docs, 'avgPassesCompleted', false, Icons.check_circle_outline, Colors.tealAccent),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16))
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                    Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                )
              ],
            ),
          ),
          // Lista
          if (top3.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text("Sin datos suficientes", style: TextStyle(color: Colors.white24)))
          else
            ...top3.asMap().entries.map((entry) {
              int idx = entry.key;
              var item = entry.value;
              return ListTile(
                dense: true,
                leading: Text(
                  idx == 0 ? "🥇" : (idx == 1 ? "🥈" : "🥉"),
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(item['name'], style: TextStyle(color: Colors.white, fontWeight: idx == 0 ? FontWeight.bold : FontWeight.normal)),
                trailing: Text("${item['val']}$suffix", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white70)),
              );
            }).toList()
        ],
      ),
    );
  }
}

// --- RANKING LIST ---
class _RankingList extends StatelessWidget {
  final String seasonId;
  final String type;
  const _RankingList({required this.seasonId, required this.type});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));

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
            if (val > 0) ranking.add({'id': pid, 'value': val, 'team': teamName});
          });
        }
        ranking.sort((a, b) => b['value'].compareTo(a['value']));

        if (ranking.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.emoji_events_outlined, size: 50, color: Colors.white10), Text("Aún no hay registros.", style: TextStyle(color: Colors.white24))]));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ranking.length,
          itemBuilder: (context, index) {
            var item = ranking[index];
            bool isTop3 = index < 3;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: isTop3 ? Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)) : Border.all(color: Colors.white10),
                  boxShadow: isTop3 ? [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.1), blurRadius: 10)] : []
              ),
              child: ListTile(
                leading: Container(
                  width: 35, height: 35,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == 0 ? const Color(0xFFD4AF37) : (index == 1 ? Colors.grey : (index == 2 ? const Color(0xFFCD7F32) : Colors.white10)),
                  ),
                  child: Text("${index + 1}", style: TextStyle(color: index < 3 ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('players').doc(item['id']).get(),
                  builder: (c, s) => Text(s.data?['name'] ?? 'Cargando...', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                subtitle: Text(item['team'], style: const TextStyle(fontSize: 11, color: Colors.white54)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: Text("${item['value']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFD4AF37))),
                ),
              ),
            );
          },
        );
      },
    );
  }
}