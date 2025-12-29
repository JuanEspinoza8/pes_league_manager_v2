import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../my_team_screen.dart'; // Asegúrate de que la ruta sea correcta

class StandingsTab extends StatefulWidget {
  final String seasonId;
  const StandingsTab({super.key, required this.seasonId});

  @override
  State<StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends State<StandingsTab> {
  String _tableFilter = 'LEAGUE';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- FILTRO DE TABLA (Dropdown Estilizado) ---
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _tableFilter,
              isExpanded: true,
              icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF0D1B2A)),
              items: const [
                DropdownMenuItem(value: 'LEAGUE', child: Text("🏆  Tabla General Liga", style: TextStyle(fontWeight: FontWeight.bold))),
                DropdownMenuItem(value: 'GROUP_A', child: Text("🇪🇺  Champions - Grupo A", style: TextStyle(fontWeight: FontWeight.bold))),
                DropdownMenuItem(value: 'GROUP_B', child: Text("🇪🇺  Champions - Grupo B", style: TextStyle(fontWeight: FontWeight.bold))),
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
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var participants = snapshot.data!.docs.toList();

              // Filtro por Grupo
              if (_tableFilter == 'GROUP_A') participants = participants.where((d) => (d.data() as Map)['championsGroup'] == 'A').toList();
              else if (_tableFilter == 'GROUP_B') participants = participants.where((d) => (d.data() as Map)['championsGroup'] == 'B').toList();

              // Ordenamiento (Puntos > Diferencia de Gol)
              participants.sort((a, b) {
                var dataA = a.data() as Map<String, dynamic>;
                var dataB = b.data() as Map<String, dynamic>;
                var sA = (_tableFilter == 'LEAGUE') ? (dataA['leagueStats'] ?? {}) : (dataA['championsStats'] ?? {});
                var sB = (_tableFilter == 'LEAGUE') ? (dataB['leagueStats'] ?? {}) : (dataB['championsStats'] ?? {});
                int ptsA = sA['pts'] ?? 0; int ptsB = sB['pts'] ?? 0;
                int difA = sA['dif'] ?? 0; int difB = sB['dif'] ?? 0;
                if (ptsA != ptsB) return ptsB.compareTo(ptsA);
                return difB.compareTo(difA);
              });

              if (participants.isEmpty) return const Center(child: Text("No hay equipos en esta tabla."));

              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Theme(
                    // Quitamos las líneas divisorias por defecto para usar colores de fila
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(const Color(0xFF0D1B2A)), // Cabecera Azul Oscuro
                      headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      dataRowMinHeight: 45,
                      dataRowMaxHeight: 45,
                      columnSpacing: 15,
                      horizontalMargin: 10,
                      columns: [
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
                      ],
                      rows: List.generate(participants.length, (index) {
                        var data = participants[index].data() as Map<String, dynamic>;
                        var s = (_tableFilter == 'LEAGUE') ? (data['leagueStats'] ?? {}) : (data['championsStats'] ?? {});

                        // --- ZONAS DE CLASIFICACIÓN (COLORES DE FILA) ---
                        Color? rowColor = index % 2 == 0 ? Colors.white : Colors.grey[50]; // Alternado base

                        if (_tableFilter != 'LEAGUE') {
                          // Champions: 1ro pasa (Verde), 2do/3ro repechaje (Azul)
                          if (index == 0) rowColor = Colors.green.withOpacity(0.1);
                          else if (index <= 2) rowColor = Colors.blue.withOpacity(0.05);
                        } else {
                          // Liga: 1ro Campeón (Oro), 2-4 Champions (Azul), Ultimos Descenso/Copa (Rojo suave)
                          if (index == 0) rowColor = Colors.amber.withOpacity(0.15);
                          else if (index <= 3) rowColor = Colors.blue.withOpacity(0.05);
                          else if (index >= participants.length - 2) rowColor = Colors.red.withOpacity(0.05);
                        }

                        return DataRow(
                          // Al tocar, ir al perfil del equipo
                          onSelectChanged: (selected) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: participants[index].id)));
                          },
                          color: MaterialStateProperty.resolveWith<Color?>((states) => rowColor),
                          cells: [
                            _cellText("${index + 1}", true),
                            DataCell(
                                Container(
                                  width: 110,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                      data['teamName'],
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)
                                  ),
                                )
                            ),
                            _cellText("${s['pts']??0}", true, color: const Color(0xFF0D1B2A)), // Puntos destacados
                            _cellText("${s['pj']??0}", false),
                            _cellText("${s['pg']??0}", false),
                            _cellText("${s['pe']??0}", false),
                            _cellText("${s['pp']??0}", false),
                            _cellText("${s['gf']??0}", false),
                            _cellText("${s['gc']??0}", false),
                            _cellText("${s['dif']??0}", false, color: (s['dif']??0) >= 0 ? Colors.green[700] : Colors.red[700]),
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

        // LEYENDA (Opcional, para explicar colores)
        if (_tableFilter == 'LEAGUE')
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(Colors.amber, "Campeón"),
                const SizedBox(width: 10),
                _LegendItem(Colors.blue, "Champions"),
                const SizedBox(width: 10),
                _LegendItem(Colors.red, "Descenso"),
              ],
            ),
          )
      ],
    );
  }

  // Helper para columnas con ancho fijo
  DataColumn _col(String label, double width, {TextAlign align = TextAlign.center}) {
    return DataColumn(
        label: SizedBox(
            width: width,
            child: Text(
                label,
                style: const TextStyle(fontSize: 11, letterSpacing: 0.5),
                textAlign: align
            )
        )
    );
  }

  // Helper para celdas de texto
  DataCell _cellText(String text, bool bold, {Color? color}) {
    return DataCell(
        Center(
            child: Text(
                text,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
                    fontSize: 12,
                    color: color ?? Colors.black87
                )
            )
        )
    );
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}