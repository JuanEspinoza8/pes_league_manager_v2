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

  double _getVirtualOrder(int round) {
    if (round < 100) return round.toDouble();
    double midSeason = _maxLeagueRound / 2;
    if (round == 149) return midSeason * 0.3;
    if (round == 150) return midSeason * 0.8;
    if (round == 151) return midSeason * 1.2;
    if (round == 152) return midSeason * 1.6;
    if (round == 153) return _maxLeagueRound - 0.5;
    if (round >= 201 && round < 250) {
      int groupMatchIndex = round - 201;
      return 2.5 + (groupMatchIndex * 1.5);
    }
    if (round >= 250) {
      if (round == 254) return _maxLeagueRound + 1.0;
      int playoffIndex = round - 250;
      return (midSeason + 1.5) + (playoffIndex * 2.0);
    }
    return 999;
  }

  String _getRoundLabel(int round) {
    if (round < 100) return "LIGA F$round";
    if (round == 149) return "COPA PRELIM";
    if (round == 150) return "COPA R1";
    if (round == 151) return "COPA R2";
    if (round == 152) return "COPA SEMI";
    if (round == 153) return "COPA FINAL";
    if (round >= 201 && round < 250) return "UCL G${round - 200}";
    if (round == 250) return "UCL REP IDA";
    if (round == 251) return "UCL REP VTA";
    if (round == 252) return "UCL SEMI IDA";
    if (round == 253) return "UCL SEMI VTA";
    if (round == 254) return "UCL FINAL";
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
      // --- BARRA DE FECHAS (ALTURA CORREGIDA) ---
      Container(
          height: 90, // AUMENTADO DE 70 A 90 PARA EVITAR OVERFLOW
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
                if (round >= 149 && round < 200) activeColor = Colors.purple[800]!;
                else if (round >= 200) activeColor = Colors.black;

                return GestureDetector(
                    onTap: () => setState(() {
                      _selectedRoundIndex = round;
                      if (!canShowBracket) _showBracketView = false;
                    }),
                    child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Padding ajustado
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
                            const SizedBox(height: 4), // Espacio extra
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

                return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 4,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: (status != 'PLAYED' && status != 'SCHEDULED') ? () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => MatchResultScreen(seasonId: widget.seasonId, matchId: match.id, matchData: data, isAdmin: widget.isAdmin)));
                      } : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            if (status == 'REPORTED') _StatusBadge("EN REVISIÓN", Colors.orange),
                            if (status == 'SCHEDULED') Text("POR JUGAR", style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                            if (status == 'PLAYED') _StatusBadge("FINALIZADO", Colors.green),
                          ]),
                          const SizedBox(height: 15),
                          Row(children: [
                            Expanded(child: _TeamColumn(seasonId: widget.seasonId, userId: data['homeUser'], placeholder: data['homePlaceholder'], align: CrossAxisAlignment.end)),
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
                            Expanded(child: _TeamColumn(seasonId: widget.seasonId, userId: data['awayUser'], placeholder: data['awayPlaceholder'], align: CrossAxisAlignment.start)),
                          ]),
                          if (isPlayed && data['scorers'] != null) ...[
                            const SizedBox(height: 15),
                            const Divider(height: 1, color: Colors.black12),
                            const SizedBox(height: 8),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: _ScorersList(seasonId: widget.seasonId, scorersMap: data['scorers']['home'], align: TextAlign.right)),
                              const SizedBox(width: 40),
                              Expanded(child: _ScorersList(seasonId: widget.seasonId, scorersMap: data['scorers']['away'], align: TextAlign.left)),
                            ]),
                          ],
                          if (status == 'REPORTED' && widget.isAdmin)
                            Padding(padding: const EdgeInsets.only(top: 15), child: Text("Toque para aprobar resultado", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)))
                        ]),
                      ),
                    )
                );
              }
          );
        }
    );
  }
}

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

class _ScorersList extends StatelessWidget {
  final String seasonId; final dynamic scorersMap; final TextAlign align;
  const _ScorersList({required this.seasonId, required this.scorersMap, required this.align});
  @override
  Widget build(BuildContext context) {
    if (scorersMap == null) return const SizedBox();
    Map<String, dynamic> map = scorersMap as Map<String, dynamic>;
    if (map.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: map.entries.map((entry) {
      if (entry.value == 0) return const SizedBox();
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('players').doc(entry.key).get(),
        builder: (context, snapshot) {
          String name = snapshot.data?['name'] ?? 'Jugador';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: align == TextAlign.right
                ? [Text("$name ", style: const TextStyle(fontSize: 11, color: Colors.grey)), Text("(${entry.value})", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(width: 4), const Icon(Icons.sports_soccer, size: 10, color: Colors.black54)]
                : [const Icon(Icons.sports_soccer, size: 10, color: Colors.black54), const SizedBox(width: 4), Text("(${entry.value}) ", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Text(name, style: const TextStyle(fontSize: 11, color: Colors.grey))]),
          );
        },
      );
    }).toList());
  }
}