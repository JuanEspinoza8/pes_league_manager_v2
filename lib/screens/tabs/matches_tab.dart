import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../match_result_screen.dart';
import '../../widgets/cup_bracket_view.dart';
import '../../widgets/champions_bracket_view.dart';

class MatchesTab extends StatefulWidget {
  final String seasonId;
  final bool isAdmin;
  const MatchesTab({super.key, required this.seasonId, required this.isAdmin});

  @override
  State<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<MatchesTab> {
  int _selectedRoundIndex = 1;
  List<int> _availableRounds = [];
  bool _showBracketView = false;
  int _maxLeagueRound = 18;

  @override
  void initState() {
    super.initState();
    _loadRounds();
  }

  Future<void> _loadRounds() async {
    FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('matches').snapshots().listen((snap) {
      Set<int> raw = {};
      for (var doc in snap.docs) raw.add(doc['round']);

      var leagueRounds = raw.where((r) => r < 100);
      if (leagueRounds.isNotEmpty) {
        _maxLeagueRound = leagueRounds.reduce(max);
      }

      List<int> finalTimeline = raw.toList();
      finalTimeline.sort((a, b) {
        double orderA = _getVirtualOrder(a);
        double orderB = _getVirtualOrder(b);
        return orderA.compareTo(orderB);
      });

      if(mounted) {
        setState(() {
          _availableRounds = finalTimeline;
          if (!_availableRounds.contains(_selectedRoundIndex) && _availableRounds.isNotEmpty) {
            _selectedRoundIndex = _availableRounds.first;
          }
        });
      }
    });
  }

  // --- LÓGICA DE ORDENAMIENTO VISUAL (CORREGIDA) ---
  double _getVirtualOrder(int round) {
    // 1. LIGA (Rondas 1 a 100) -> Se quedan en su lugar
    if (round < 100) return round.toDouble();

    // 2. SUPERCOPA (Rondas negativas) -> Al principio de todo
    if (round < 0) return round.toDouble();

    double midSeason = _maxLeagueRound / 2;

    // 3. COPA (Rondas 149-153) -> Mitad de temporada
    if (round == 149) return midSeason * 0.3; // Prelim
    if (round == 150) return midSeason * 0.8; // R1
    if (round == 151) return midSeason * 1.2; // R2
    if (round == 152) return midSeason * 1.6; // Semi
    if (round == 153) return _maxLeagueRound - 0.5; // Final

    // 4. CHAMPIONS GRUPOS (Rondas 201-205) - SOLO IDA
    // Intercaladas con la primera mitad de la liga (aprox cada 2 fechas)
    if (round >= 201 && round <= 205) {
      int groupMatchNum = round - 200;
      // round 201 (fecha 1) -> 2.5 (entre liga 2 y 3)
      // round 202 (fecha 2) -> 4.5 (entre liga 4 y 5)
      // round 203 (fecha 3) -> 6.5
      return (groupMatchNum * 2) + 0.5;
    }

    // 5. ELIMINATORIAS EUROPEAS (Rondas 250+)
    // Intercaladas con la segunda mitad de la liga
    if (round >= 250) {
      double startOffset = midSeason + 1.0;

      if (round == 250) return startOffset + 1.5; // Repechaje Ida
      if (round == 251) return startOffset + 2.5; // Repechaje Vuelta

      if (round == 260) return startOffset + 4.5; // Semis Ida
      if (round == 261) return startOffset + 5.5; // Semis Vuelta

      if (round == 270) return _maxLeagueRound + 2.0; // Finales
    }

    return 999;
  }

  String _getRoundLabel(int round) {
    if (round < 0) return "SUPERCOPA";
    if (round < 100) return "LIGA F$round";
    if (round == 149) return "COPA PRELIM";
    if (round == 150) return "COPA R1";
    if (round == 151) return "COPA R2";
    if (round == 152) return "COPA SEMI";
    if (round == 153) return "COPA FINAL";
    // Grupos
    if (round >= 201 && round <= 205) return "UCL G${round - 200}";
    // Repechajes
    if (round == 250) return "UCL/UEL REP (I)";
    if (round == 251) return "UCL/UEL REP (V)";
    // Semis
    if (round == 260) return "UCL/UEL SEMI (I)";
    if (round == 261) return "UCL/UEL SEMI (V)";
    // Finales
    if (round == 270) return "FINALES EUR";
    return "R$round";
  }

  @override
  Widget build(BuildContext context) {
    bool canShowBracket = (_selectedRoundIndex >= 149 && _selectedRoundIndex < 200) || (_selectedRoundIndex >= 250);

    Widget contentWidget;
    if (_showBracketView) {
      if (_selectedRoundIndex >= 250) {
        contentWidget = ChampionsBracketView(seasonId: widget.seasonId);
      } else {
        contentWidget = CupBracketView(seasonId: widget.seasonId);
      }
    } else {
      contentWidget = _buildMatchList();
    }

    return Column(children: [
      // --- BARRA DE FECHAS ---
      Container(
          height: 90,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))]
          ),
          child: _availableRounds.isEmpty
              ? const Center(child: Text("Cargando...", style: TextStyle(color: Colors.grey)))
              : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _availableRounds.length,
              separatorBuilder: (c, i) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                int round = _availableRounds[index];
                bool isSelected = round == _selectedRoundIndex;

                Color activeColor = const Color(0xFF0D1B2A);
                // Colores distintivos para competiciones
                if (round < 0) activeColor = Colors.amber[800]!; // Supercopa
                else if (round >= 149 && round < 200) activeColor = Colors.purple[800]!; // Copa
                else if (round >= 200) activeColor = Colors.blue[900]!; // Europa

                return GestureDetector(
                    onTap: () => setState(() {
                      _selectedRoundIndex = round;
                      if (!canShowBracket) _showBracketView = false;
                    }),
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                            color: isSelected ? activeColor : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected ? Border.all(color: Colors.amber, width: 2) : Border.all(color: Colors.transparent),
                            boxShadow: isSelected ? [BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0,4))] : null
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                _getRoundLabel(round).split(' ').first,
                                style: TextStyle(color: isSelected ? Colors.white70 : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)
                            ),
                            const SizedBox(height: 4),
                            Text(
                                _getRoundLabel(round).split(' ').last,
                                style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)
                            ),
                          ],
                        )
                    )
                );
              }
          )
      ),

      if (canShowBracket)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(_showBracketView ? "VISTA DE LLAVES" : "LISTA DE PARTIDOS", style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  Switch(
                      value: _showBracketView,
                      activeColor: Colors.amber,
                      onChanged: (val) => setState(() => _showBracketView = val)
                  ),
                ]
            )
        ),

      Expanded(child: contentWidget)
    ]);
  }

  Widget _buildMatchList() {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('matches').where('round', isEqualTo: _selectedRoundIndex).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sports_soccer, size: 60, color: Colors.grey[300]), const Text("No hay partidos programados.")]));

          return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var match = snapshot.data!.docs[index];
                var data = match.data() as Map<String, dynamic>;
                String status = data['status'];
                bool isPlayed = status == 'PLAYED' || status == 'REPORTED';

                // --- DETECCIÓN DE SANCIONES ---
                // Leemos la info que el DisciplineService propagó
                List<dynamic> homeSuspended = [];
                List<dynamic> awaySuspended = [];
                if (data['preMatchInfo'] != null) {
                  homeSuspended = data['preMatchInfo']['homeSuspended'] ?? [];
                  awaySuspended = data['preMatchInfo']['awaySuspended'] ?? [];
                }
                bool hasSuspensions = homeSuspended.isNotEmpty || awaySuspended.isNotEmpty;

                return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 4,
                    shadowColor: Colors.black12,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: (status != 'PLAYED' && status != 'SCHEDULED') ? () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => MatchResultScreen(seasonId: widget.seasonId, matchId: match.id, matchData: data, isAdmin: widget.isAdmin)));
                      } : null,
                      child: Column(
                        children: [
                          // --- 1. BANNER DE ADVERTENCIA (NUEVO) ---
                          if (hasSuspensions && !isPlayed)
                            Container(
                              width: double.infinity,
                              color: Colors.red.shade50,
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: _SuspensionNamesLoader(
                                          homeIds: homeSuspended,
                                          awayIds: awaySuspended
                                      )
                                  ),
                                ],
                              ),
                            ),

                          // CONTENIDO DE LA TARJETA
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                if (status == 'REPORTED') _StatusBadge("EN REVISIÓN", Colors.orange),
                                if (status == 'SCHEDULED') Text("POR JUGAR", style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                if (status == 'PLAYED') _StatusBadge("FINALIZADO", Colors.green),
                              ]),
                              const SizedBox(height: 15),

                              // --- MARCADOR ---
                              Row(children: [
                                Expanded(child: _TeamColumn(seasonId: widget.seasonId, userId: data['homeUser'], placeholder: data['homePlaceholder'], align: CrossAxisAlignment.end)),
                                Column(
                                  children: [
                                    Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 12),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isPlayed ? const Color(0xFF0D1B2A) : Colors.grey[100],
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                            isPlayed ? "${data['homeScore']} - ${data['awayScore']}" : "VS",
                                            style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: isPlayed ? 22 : 16,
                                                color: isPlayed ? Colors.amber : Colors.grey[400],
                                                letterSpacing: 1
                                            )
                                        )
                                    ),
                                    // --- 2. RESULTADO PENALES (NUEVO) ---
                                    if (isPlayed && data['definedByPenalties'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          "Pen: ${data['penaltyScore']}",
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                                        ),
                                      )
                                  ],
                                ),
                                Expanded(child: _TeamColumn(seasonId: widget.seasonId, userId: data['awayUser'], placeholder: data['awayPlaceholder'], align: CrossAxisAlignment.start)),
                              ]),

                              // --- 3. RESUMEN DETALLADO (NUEVO) ---
                              // Esto reemplaza la lista vieja de goleadores
                              if (isPlayed && data['player_actions'] != null) ...[
                                const SizedBox(height: 15),
                                const Divider(height: 1, color: Colors.black12),
                                const SizedBox(height: 8),
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: _DetailedStatsSummary(actionsMap: data['player_actions']['home'], align: TextAlign.right)),
                                  const SizedBox(width: 20),
                                  Expanded(child: _DetailedStatsSummary(actionsMap: data['player_actions']['away'], align: TextAlign.left)),
                                ]),
                              ],

                              if (status == 'REPORTED' && widget.isAdmin)
                                Padding(padding: const EdgeInsets.only(top: 15), child: Text("Toque para aprobar resultado", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)))
                            ]),
                          ),
                        ],
                      ),
                    )
                );
              }
          );
        }
    );
  }
}

// --- WIDGETS AUXILIARES ---

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  final String seasonId; final String userId; final String? placeholder; final CrossAxisAlignment align;
  const _TeamColumn({required this.seasonId, required this.userId, this.placeholder, required this.align});
  @override
  Widget build(BuildContext context) {
    bool isTBD = userId == 'TBD' || userId.startsWith('GANADOR') || userId.startsWith('Seed') || userId.startsWith('FINALISTA');
    return Column(crossAxisAlignment: align, children: [
      if (isTBD)
        Text(placeholder ?? "A Definir", textAlign: align == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500))
      else if (userId == 'BYE')
        Text("Libre", textAlign: align == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
      else
        FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(userId).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return Container(height: 10, width: 60, color: Colors.grey[200]);
              String name = snapshot.data!.get('teamName') ?? 'Equipo';
              return Text(name, textAlign: align == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0D1B2A)), maxLines: 2, overflow: TextOverflow.ellipsis);
            }
        )
    ]);
  }
}

class _DetailedStatsSummary extends StatelessWidget {
  final dynamic actionsMap;
  final TextAlign align;
  const _DetailedStatsSummary({required this.actionsMap, required this.align});

  @override
  Widget build(BuildContext context) {
    if (actionsMap == null) return const SizedBox();
    Map<String, dynamic> map = actionsMap as Map<String, dynamic>;
    if (map.isEmpty) return const SizedBox();

    return Column(
        crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: map.entries.map((entry) {
          Map stats = entry.value;
          int g = stats['goals'] ?? 0;
          int a = stats['assists'] ?? 0;
          int y = stats['yellowCards'] ?? 0;
          int r = stats['redCards'] ?? 0;

          if (g == 0 && a == 0 && y == 0 && r == 0) return const SizedBox();

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('players').doc(entry.key).get(),
            builder: (context, snapshot) {
              String name = snapshot.data?['name'] ?? '...';
              List<Widget> badges = [];
              if (g > 0) badges.add(_miniIcon("⚽", g > 1 ? "$g" : null, Colors.green));
              if (a > 0) badges.add(_miniIcon("👟", a > 1 ? "$a" : null, Colors.blue));
              if (r > 0) badges.add(_miniIcon("🟥", null, Colors.red));
              if (y > 0) badges.add(_miniIcon("🟨", null, Colors.orange));

              List<Widget> rowChildren = [
                Text(name, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(width: 4),
                ...badges
              ];
              if (align == TextAlign.right) rowChildren = rowChildren.reversed.toList();

              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: rowChildren
                ),
              );
            },
          );
        }).toList()
    );
  }

  Widget _miniIcon(String icon, String? count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          if (count != null) Text(count, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))
        ],
      ),
    );
  }
}

class _SuspensionNamesLoader extends StatelessWidget {
  final List<dynamic> homeIds;
  final List<dynamic> awayIds;
  const _SuspensionNamesLoader({required this.homeIds, required this.awayIds});
  Future<String> _getNames(List<dynamic> ids) async {
    if (ids.isEmpty) return "";
    List<String> names = [];
    for (var id in ids) {
      var doc = await FirebaseFirestore.instance.collection('players').doc(id.toString()).get();
      names.add(doc['name'] ?? 'Jugador');
    }
    return names.join(", ");
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: Future.wait([_getNames(homeIds), _getNames(awayIds)]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Text("Verificando sanciones...", style: TextStyle(color: Colors.red, fontSize: 10));
        String hNames = snapshot.data![0];
        String aNames = snapshot.data![1];
        String text = "Suspendidos: ";
        if (hNames.isNotEmpty) text += "(L) $hNames ";
        if (aNames.isNotEmpty) text += "(V) $aNames";
        return Text(text, style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis);
      },
    );
  }
}