import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../my_team_screen.dart';
import '../../services/ranking_service.dart'; // <--- AGREGAR ESTA LÍNEA
import 'dart:math'; // <--- IMPORTANTE: Agrega esto para usar "max"

class StandingsTab extends StatefulWidget {
  final String seasonId;
  const StandingsTab({super.key, required this.seasonId});

  @override
  State<StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends State<StandingsTab> {
  // Ahora el filtro incluye 'RANKING'
  String _tableFilter = 'LEAGUE';

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Container(
      color: const Color(0xFF0B1120),
      child: Column(
        children: [
          // --- FILTRO DE TABLA ---
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B), // Slate 800
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)]
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _tableFilter,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E293B),
                icon: const Icon(Icons.filter_list_rounded, color: goldColor),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'LEAGUE', child: Text("🏆  Tabla General Liga")),
                  DropdownMenuItem(value: 'RANKING', child: Text("📊  Ranking ELO")), // NUEVO
                  DropdownMenuItem(value: 'GROUP_A', child: Text("🇪🇺  Champions - Grupo A")),
                  DropdownMenuItem(value: 'GROUP_B', child: Text("🇪🇺  Champions - Grupo B")),
                ],
                onChanged: (val) { if (val != null) setState(() => _tableFilter = val); },
              ),
            ),
          ),

          // --- TABLA DE DATOS ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: goldColor));
                var participants = snapshot.data!.docs.toList();

                // 1. FILTRADO
                if (_tableFilter == 'GROUP_A') {
                  participants = participants.where((d) => (d.data() as Map)['championsGroup'] == 'A').toList();
                } else if (_tableFilter == 'GROUP_B') {
                  participants = participants.where((d) => (d.data() as Map)['championsGroup'] == 'B').toList();
                }
                // Nota: Para LEAGUE y RANKING usamos todos los participantes

                // 2. ORDENAMIENTO
                participants.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;

                  if (_tableFilter == 'RANKING') {
                    // Ordenar por ELO (Ranking Points)
                    int eloA = dataA['rankingPoints'] ?? 1000;
                    int eloB = dataB['rankingPoints'] ?? 1000;
                    return eloB.compareTo(eloA); // Mayor a menor
                  } else {
                    // Ordenar por Puntos de Liga/Champions
                    var sA = (_tableFilter == 'LEAGUE') ? (dataA['leagueStats'] ?? {}) : (dataA['championsStats'] ?? {});
                    var sB = (_tableFilter == 'LEAGUE') ? (dataB['leagueStats'] ?? {}) : (dataB['championsStats'] ?? {});
                    int ptsA = sA['pts'] ?? 0; int ptsB = sB['pts'] ?? 0;
                    int difA = sA['dif'] ?? 0; int difB = sB['dif'] ?? 0;
                    if (ptsA != ptsB) return ptsB.compareTo(ptsA);
                    return difB.compareTo(difA);
                  }
                });

                if (participants.isEmpty) return const Center(child: Text("No hay equipos en esta tabla.", style: TextStyle(color: Colors.white54)));

                // 3. DEFINICIÓN DE COLUMNAS SEGÚN VISTA
                bool isRankingView = _tableFilter == 'RANKING';
                List<DataColumn> columns = isRankingView
                    ? [
                  _col("#", 30),
                  _col("EQUIPO", 140, align: TextAlign.left),
                  _col("RKG", 50), // Ranking Points
                  _col("CAT", 60), // Categoría (Elite, Pro, etc)
                  _col("PREMIO", 80), // Estimado por victoria
                ]
                    : [
                  _col("#", 30),
                  _col("EQUIPO", 110, align: TextAlign.left),
                  _col("PTS", 40),
                  _col("PJ", 30),
                  _col("PG", 30),
                  _col("PE", 30),
                  _col("PP", 30),
                  _col("GF", 30),
                  _col("GC", 30),
                  _col("DIF", 40),
                ];

                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                        headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                        dataRowMinHeight: 50,
                        dataRowMaxHeight: 50,
                        columnSpacing: 15,
                        horizontalMargin: 10,
                        columns: columns,
                        rows: List.generate(participants.length, (index) {
                          var data = participants[index].data() as Map<String, dynamic>;
                          var s = (_tableFilter == 'LEAGUE') ? (data['leagueStats'] ?? {}) : (data['championsStats'] ?? {});

                          // Lógica de colores de fila
                          Color? rowColor = index % 2 == 0 ? Colors.white.withOpacity(0.02) : Colors.transparent;

                          if (_tableFilter == 'LEAGUE') {
                            if (index == 0) rowColor = goldColor.withOpacity(0.2);
                            else if (index <= 3) rowColor = Colors.blue.withOpacity(0.1);
                            else if (index >= participants.length - 2) rowColor = Colors.red.withOpacity(0.1);
                          } else if (_tableFilter == 'RANKING') {
                            // Top 3 del mundo en Dorado
                            if (index < 3) rowColor = goldColor.withOpacity(0.15);
                          }

                          return DataRow(
                            onSelectChanged: (selected) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: participants[index].id)));
                            },
                            color: MaterialStateProperty.resolveWith<Color?>((states) => rowColor),
                            cells: isRankingView
                                ? [
                              // --- CELDAS MODO RANKING ---
                              _cellText("${index + 1}", true, color: Colors.white54),
                              DataCell(
                                  Container(
                                    width: 140,
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(data['teamName'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                        // Mostramos DT debajo

                                      ],
                                    ),
                                  )
                              ),
                              _cellText("${data['rankingPoints'] ?? 1000}", true, color: goldColor),
                              _getCategoryCell(data['rankingPoints'] ?? 1000),
                              _cellText("${_calculateEstimatedPrize(data['rankingPoints'] ?? 1000)}", false, color: Colors.greenAccent),
                            ]
                                : [
                              // --- CELDAS MODO LIGA/GRUPOS (Originales) ---
                              _cellText("${index + 1}", true, color: Colors.white54),
                              DataCell(
                                  Container(
                                    width: 110,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        data['teamName'],
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)
                                    ),
                                  )
                              ),
                              _cellText("${s['pts']??0}", true, color: goldColor),
                              _cellText("${s['pj']??0}", false),
                              _cellText("${s['pg']??0}", false),
                              _cellText("${s['pe']??0}", false),
                              _cellText("${s['pp']??0}", false),
                              _cellText("${s['gf']??0}", false),
                              _cellText("${s['gc']??0}", false),
                              _cellText("${s['dif']??0}", false, color: (s['dif']??0) >= 0 ? Colors.greenAccent : Colors.redAccent),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // LEYENDA (Solo visible en modo LIGA)
          if (_tableFilter == 'LEAGUE')
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(goldColor, "Campeón"),
                  const SizedBox(width: 15),
                  _LegendItem(Colors.blueAccent, "Champions"),
                  const SizedBox(width: 15),
                  _LegendItem(Colors.redAccent, "Descenso"),
                ],
              ),
            )
        ],
      ),
    );
  }

  // Helpers de UI
  DataColumn _col(String label, double width, {TextAlign align = TextAlign.center}) {
    return DataColumn(label: SizedBox(width: width, child: Text(label, textAlign: align)));
  }

  DataCell _cellText(String text, bool bold, {Color? color}) {
    return DataCell(Center(child: Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.normal, fontSize: 12, color: color ?? Colors.white70))));
  }

  // Helper para mostrar una "Categoría" basada en el ELO
  DataCell _getCategoryCell(int points) {
    String text; Color color;
    if (points >= 1350) { text = "DON CHULO"; color = Colors.blueAccent; }
    else if (points >= 1250) { text = "LEYENDA"; color = Colors.purpleAccent; }
    else if (points >= 1150) { text = "ELITE"; color = Colors.cyanAccent; }
    else if (points >= 1050) { text = "PRO"; color = Colors.yellowAccent; }
    else if (points >= 950) { text = "MEDIOCRE"; color = Colors.orangeAccent; }
    else if (points >= 850) { text = "EQUIPO CHICO"; color = Colors.white; }
    else if (points >= 750) { text = "EX CHURRERO"; color = Colors.grey; }
    else { text = "CHURRERO"; color = Colors.brown; }

    return DataCell(Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    )));
  }

  // Estimado visual de cuánto ganan por victoria (Base 5M + Bonus)
  // Estimado de premio si le ganan a un equipo PROMEDIO (1000 pts)
  // Estimado de premio si le ganan a un equipo PROMEDIO (1000 pts)
  String _calculateEstimatedPrize(int myPoints) {
    // Simulamos victoria contra promedio (1000 pts)
    var simulation = RankingService.calculateNewRanking(myPoints, 1000, 1.0);
    int pointsGained = simulation['change']!;

    // Usamos los mismos valores nuevos: Base 4.5M + (Puntos * 500k)
    int money = 4500000 + (max(0, pointsGained) * 500000);

    return "\$${(money / 1000000).toStringAsFixed(1)}M";
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendItem(this.color, this.text);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 5)])),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
      ],
    );
  }
}