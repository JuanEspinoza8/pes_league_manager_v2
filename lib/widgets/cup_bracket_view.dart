import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CupBracketView extends StatelessWidget {
  final String seasonId;
  const CupBracketView({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seasons')
          .doc(seasonId)
          .collection('matches')
          .where('type', isEqualTo: 'CUP')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Copa no iniciada."));

        var docs = snapshot.data!.docs;

        // Filtrar y ordenar
        var prelims = docs.where((d) => (d['roundName'] as String).contains('Preliminar')).toList();
        var octavos = docs.where((d) => (d['roundName'] as String).contains('Octavos')).toList()..sort((a,b) => a['roundName'].compareTo(b['roundName']));
        var cuartos = docs.where((d) => (d['roundName'] as String).contains('Cuartos')).toList()..sort((a,b) => a['roundName'].compareTo(b['roundName']));
        var semis = docs.where((d) => (d['roundName'] as String).contains('Semifinal')).toList()..sort((a,b) => a['roundName'].compareTo(b['roundName']));
        var finalMatch = docs.where((d) => (d['roundName'] as String).contains('Final')).toList();

        // SCROLL BIDIRECCIONAL (Para que no explote la pantalla)
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, // Centrado verticalmente
                children: [
                  if (prelims.isNotEmpty) ...[_buildRoundColumn(context, "REPECHAJE", prelims), _buildConnector()],
                  if (octavos.isNotEmpty) ...[_buildRoundColumn(context, "OCTAVOS", octavos), _buildConnector()],
                  if (cuartos.isNotEmpty) ...[_buildRoundColumn(context, "CUARTOS", cuartos), _buildConnector()],
                  if (semis.isNotEmpty) ...[_buildRoundColumn(context, "SEMIFINALES", semis), _buildConnector()],
                  if (finalMatch.isNotEmpty) _buildRoundColumn(context, "GRAN FINAL", finalMatch, isFinal: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoundColumn(BuildContext context, String title, List<QueryDocumentSnapshot> matches, {bool isFinal = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          decoration: BoxDecoration(
              color: isFinal ? Colors.amber : const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5)]
          ),
          child: Text(
              title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isFinal ? Colors.black : Colors.white,
                  fontSize: 12,
                  letterSpacing: 1
              )
          ),
        ),
        ...matches.map((m) => _buildMatchCard(context, m.data() as Map<String, dynamic>, isFinal: isFinal)).toList(),
      ],
    );
  }

  Widget _buildMatchCard(BuildContext context, Map<String, dynamic> data, {bool isFinal = false}) {
    String status = data['status'];
    bool played = status == 'PLAYED';
    int? hScore = data['homeScore'];
    int? aScore = data['awayScore'];

    String winnerId = '';
    if (played) {
      winnerId = (hScore! > aScore!) ? data['homeUser'] : data['awayUser'];
    }

    return Container(
      width: 180,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isFinal ? Colors.amber : Colors.grey[300]!, width: isFinal ? 2 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]
      ),
      child: Column(
        children: [
          // HEADER (Nombre Ronda)
          Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              width: double.infinity,
              decoration: BoxDecoration(
                  color: isFinal ? Colors.amber.withOpacity(0.2) : Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12))
              ),
              child: Text(
                  data['roundName'].replaceAll('CUP ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isFinal ? Colors.amber[900] : Colors.grey[600]
                  )
              )
          ),
          // LOCAL
          _buildTeamRow(seasonId, data['homeUser'], data['homePlaceholder'], hScore, winnerId),
          const Divider(height: 1, thickness: 0.5),
          // VISITANTE
          _buildTeamRow(seasonId, data['awayUser'], data['awayPlaceholder'], aScore, winnerId),
        ],
      ),
    );
  }

  Widget _buildTeamRow(String seasonId, String userId, String? placeholder, int? score, String winnerId) {
    bool isWinner = userId == winnerId && winnerId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isWinner ? Colors.green.withOpacity(0.05) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // AQUI ESTABA EL ERROR: Ahora usamos un Widget inteligente que busca el nombre
          Expanded(child: _AsyncTeamName(
              seasonId: seasonId,
              userId: userId,
              placeholder: placeholder,
              isWinner: isWinner
          )),

          if (score != null)
            Text("$score", style: TextStyle(fontWeight: FontWeight.bold, color: isWinner ? Colors.green[800] : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildConnector() {
    return SizedBox(
        width: 25,
        child: Icon(Icons.arrow_right_alt, color: Colors.amber[700], size: 24)
    );
  }
}

// --- WIDGET AUXILIAR PARA LEER NOMBRES REALES ---
class _AsyncTeamName extends StatelessWidget {
  final String seasonId;
  final String userId;
  final String? placeholder;
  final bool isWinner;

  const _AsyncTeamName({required this.seasonId, required this.userId, this.placeholder, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    // Si es un ID de sistema (TBD, GANADOR, etc.), mostramos texto simple
    if (userId == 'TBD' || userId.startsWith('GANADOR') || userId.startsWith('Seed') || userId.startsWith('FINALISTA')) {
      return Text(
          placeholder ?? (userId.startsWith('GANADOR') ? "Ganador Prev." : "A Definir"),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 11)
      );
    }

    // Si es un ID real, buscamos el nombre en Firebase
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Text("...", style: TextStyle(fontSize: 11, color: Colors.grey));

        String name = snapshot.data!.exists ? (snapshot.data!.get('teamName') ?? 'Equipo') : 'Desconocido';

        return Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: isWinner ? FontWeight.w900 : FontWeight.w500,
                fontSize: 12,
                color: isWinner ? Colors.black : Colors.black87
            )
        );
      },
    );
  }
}