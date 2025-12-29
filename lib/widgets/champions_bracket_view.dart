import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChampionsBracketView extends StatelessWidget {
  final String seasonId;
  const ChampionsBracketView({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seasons').doc(seasonId)
          .collection('matches')
          .where('type', isEqualTo: 'CHAMPIONS')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var allDocs = snapshot.data!.docs;

        // FILTRADO EN MEMORIA (Seguro y sin índices complejos)
        var docs = allDocs.where((d) {
          int r = (d.data() as Map<String, dynamic>)['round'] ?? 0;
          return r >= 250; // Solo mostramos los playoffs
        }).toList();

        if (docs.isEmpty) return const Center(child: Text("Fase final no iniciada."));

        // Agrupar documentos por fase
        var repDocs = docs.where((d) => (d['roundName'] as String).contains('Repechaje')).toList();
        var semiDocs = docs.where((d) => (d['roundName'] as String).contains('Semifinal')).toList();
        var finalDocs = docs.where((d) => (d['roundName'] as String).contains('Final')).toList();

        // Convertir lista de partidos en lista de LLAVES (Ida + Vuelta agrupados)
        var repTies = _buildTies(repDocs, "Repechaje");
        var semiTies = _buildTies(semiDocs, "Semifinal");
        var finalTie = _buildTies(finalDocs, "Final");

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (repTies.isNotEmpty) ...[
                  _buildRoundColumn(context, "Repechaje", repTies),
                  _buildConnector(),
                ],
                if (semiTies.isNotEmpty) ...[
                  _buildRoundColumn(context, "Semifinales", semiTies),
                  _buildConnector(),
                ],
                if (finalTie.isNotEmpty)
                  _buildRoundColumn(context, "GRAN FINAL", finalTie, isFinal: true),
              ],
            ),
          ),
        );
      },
    );
  }

  // Convierte una lista de docs (Ida, Vuelta) en objetos _TieData
  List<_TieData> _buildTies(List<QueryDocumentSnapshot> docs, String baseName) {
    Map<String, _TieData> tiesMap = {};

    for (var doc in docs) {
      String name = doc['roundName'];
      // Extraer identificador: "Repechaje 1 Ida" -> "1"
      String id = "1";
      if (name.contains(" 1 ")) id = "1";
      if (name.contains(" 2 ")) id = "2";

      if (!tiesMap.containsKey(id)) {
        tiesMap[id] = _TieData(id: id, title: "$baseName $id");
      }

      var tie = tiesMap[id]!;
      if (name.contains("Ida")) tie.ida = doc;
      else if (name.contains("Vuelta")) tie.vuelta = doc;
      else tie.ida = doc;
    }

    var list = tiesMap.values.toList();
    list.sort((a,b) => a.id.compareTo(b.id));
    return list;
  }

  Widget _buildRoundColumn(BuildContext context, String title, List<_TieData> ties, {bool isFinal = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: isFinal ? Colors.amber[800] : Colors.blue[900], fontSize: isFinal ? 20 : 16)),
        ),
        ...ties.map((tie) => _TieCard(seasonId: seasonId, tie: tie, isFinal: isFinal)).toList(),
      ],
    );
  }

  Widget _buildConnector() {
    return SizedBox(width: 40, child: Divider(thickness: 2, color: Colors.grey[400]));
  }
}

class _TieData {
  String id;
  String title;
  DocumentSnapshot? ida;
  DocumentSnapshot? vuelta;
  _TieData({required this.id, required this.title});
}

class _TieCard extends StatelessWidget {
  final String seasonId;
  final _TieData tie;
  final bool isFinal;

  const _TieCard({required this.seasonId, required this.tie, required this.isFinal});

  @override
  Widget build(BuildContext context) {
    var dIda = tie.ida?.data() as Map<String, dynamic>?;
    var dVta = tie.vuelta?.data() as Map<String, dynamic>?;

    String homeId = dIda?['homeUser'] ?? dVta?['awayUser'] ?? 'TBD';
    String awayId = dIda?['awayUser'] ?? dVta?['homeUser'] ?? 'TBD';

    int h1 = dIda?['homeScore'] ?? 0;
    int a1 = dIda?['awayScore'] ?? 0;
    int h2 = dVta?['homeScore'] ?? 0;
    int a2 = dVta?['awayScore'] ?? 0;

    bool singleMatch = tie.vuelta == null;
    int globalHome = singleMatch ? h1 : h1 + a2;
    int globalAway = singleMatch ? a1 : a1 + h2;

    bool idaPlayed = dIda?['status'] == 'PLAYED';
    bool vtaPlayed = dVta?['status'] == 'PLAYED';
    bool finished = singleMatch ? idaPlayed : (idaPlayed && vtaPlayed);

    String winnerId = "";
    if (finished) {
      if (globalHome > globalAway) winnerId = homeId;
      else if (globalAway > globalHome) winnerId = awayId;
      else {
        if (!singleMatch) {
          if (a2 > a1) winnerId = homeId;
          else winnerId = awayId;
        }
      }
    }

    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isFinal ? Colors.amber : Colors.blue.shade200, width: isFinal?2:1),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(2,2))]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: isFinal ? Colors.amber : Colors.blue[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
            child: Text(isFinal ? "FINAL" : tie.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          _TeamRow(seasonId: seasonId, userId: homeId, score: finished ? globalHome : null, isWinner: finished && winnerId == homeId),
          const Divider(height: 1),
          _TeamRow(seasonId: seasonId, userId: awayId, score: finished ? globalAway : null, isWinner: finished && winnerId == awayId),
          if (!singleMatch && (idaPlayed || vtaPlayed))
            Container(
              padding: const EdgeInsets.all(4),
              color: Colors.grey[100],
              child: Text(
                "Ida: ${idaPlayed ? '$h1-$a1' : '-'}  |  Vta: ${vtaPlayed ? '$h2-$a2' : '-'}",
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            )
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final String seasonId; final String userId; final int? score; final bool isWinner;
  const _TeamRow({required this.seasonId, required this.userId, this.score, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: isWinner ? Colors.green[50] : null,
      child: Row(
        children: [
          Expanded(child: _AsyncTeamName(seasonId: seasonId, userId: userId, isBold: isWinner)),
          if (score != null)
            Text("$score", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isWinner ? Colors.green[800] : Colors.black))
        ],
      ),
    );
  }
}

class _AsyncTeamName extends StatelessWidget {
  final String seasonId; final String userId; final bool isBold;
  const _AsyncTeamName({required this.seasonId, required this.userId, required this.isBold});
  @override
  Widget build(BuildContext context) {
    if (userId.length < 5 || userId.contains('GANADOR') || userId.contains('Seed') || userId.contains('FINALISTA')) {
      return Text(userId == 'TBD' ? 'A Definir' : (userId.startsWith('GANADOR') ? 'Ganador prev.' : userId), style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12));
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(userId).get(),
      builder: (context, snap) {
        if (!snap.hasData) return const Text("...");
        return Text(snap.data!.get('teamName'), overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 13));
      },
    );
  }
}