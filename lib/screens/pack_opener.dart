import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PackOpener extends StatefulWidget {
  final String seasonId;
  const PackOpener({super.key, required this.seasonId});

  @override
  State<PackOpener> createState() => _PackOpenerState();
}

class _PackOpenerState extends State<PackOpener> {
  // --- LÓGICA INTACTA ---
  final User currentUser = FirebaseAuth.instance.currentUser!;
  bool isOpening = false;
  bool packOpened = false;
  String statusMessage = "";

  List<Map<String, dynamic>> generatedSquad = [];
  int currentCardIndex = 0;
  bool isCardRevealed = false;

  final List<Map<String, dynamic>> squadRequirements = [
    {'label': 'Arqueros', 'pos': ['PO'], 'count': 2},
    {'label': 'Def. Derecho', 'pos': ['LD'], 'count': 2},
    {'label': 'Def. Izquierdo', 'pos': ['LI'], 'count': 2},
    {'label': 'Centrales', 'pos': ['DEC'], 'count': 4},
    {'label': 'MCD', 'pos': ['MCD'], 'count': 2},
    {'label': 'MC', 'pos': ['MC'], 'count': 2},
    {'label': 'MO', 'pos': ['MO'], 'count': 2},
    {'label': 'Banda Der.', 'pos': ['EXD', 'MDD'], 'count': 2},
    {'label': 'Banda Izq.', 'pos': ['EXI', 'MDI'], 'count': 2},
    {'label': 'Delanteros', 'pos': ['CD', 'SD'], 'count': 2},
  ];

  Future<void> _openStarterPack() async {
    setState(() { isOpening = true; statusMessage = "Analizando mercado..."; });
    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(widget.seasonId);

    bool success = false;
    int attempts = 0;

    while (!success && attempts < 5) {
      attempts++;
      List<String> myNewRosterIds = [];
      List<Map<String, dynamic>> tempSquadDisplay = [];
      int specialCardsCount = 0;

      try {
        DocumentSnapshot seasonSnap = await seasonRef.get();
        List<dynamic> takenIds = seasonSnap['takenPlayerIds'] ?? [];

        for (var req in squadRequirements) {
          QuerySnapshot query = await db.collection('players').where('position', whereIn: req['pos']).get();
          List<DocumentSnapshot> candidates = query.docs.where((doc) => !takenIds.contains(doc.id) && !myNewRosterIds.contains(doc.id)).toList();

          for (int i = 0; i < req['count']; i++) {
            if (candidates.isEmpty) break;
            bool limitReached = specialCardsCount >= 2;
            List<DocumentSnapshot> pool = candidates;

            if (limitReached) {
              var normalPlayers = candidates.where((doc) => !_isSpecial(doc)).toList();
              if (normalPlayers.isNotEmpty) {
                pool = normalPlayers;
              }
            }

            DocumentSnapshot selected = _selectWeightedPlayer(pool, !limitReached);
            if (_isSpecial(selected)) specialCardsCount++;

            myNewRosterIds.add(selected.id);
            tempSquadDisplay.add(selected.data() as Map<String, dynamic>);
            candidates.removeWhere((doc) => doc.id == selected.id);
          }
        }

        if (myNewRosterIds.length < 5) throw "Error: No hay suficientes jugadores disponibles";

        await db.runTransaction((transaction) async {
          DocumentSnapshot freshSnap = await transaction.get(seasonRef);
          List<dynamic> freshTaken = freshSnap['takenPlayerIds'] ?? [];
          for (String id in myNewRosterIds) {
            if (freshTaken.contains(id)) throw "Collision";
          }
          transaction.update(seasonRef.collection('participants').doc(currentUser.uid), {'roster': myNewRosterIds, 'budget': 100000000});
          transaction.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion(myNewRosterIds)});
        });

        success = true;
        setState(() {
          generatedSquad = tempSquadDisplay;
          generatedSquad.sort((a, b) => (a['rating'] ?? 0).compareTo(b['rating'] ?? 0));
          isOpening = false;
          packOpened = true;
          currentCardIndex = 0;
          isCardRevealed = false;
        });

      } catch (e) {
        await Future.delayed(Duration(milliseconds: Random().nextInt(500)));
      }
    }

    if (!success) {
      setState(() { isOpening = false; statusMessage = "Error de red o mercado saturado. Intenta de nuevo."; });
    }
  }

  DocumentSnapshot _selectWeightedPlayer(List<DocumentSnapshot> candidates, bool tryLuck) {
    Random rnd = Random();
    if (tryLuck) {
      double tierRoll = rnd.nextDouble();
      if (tierRoll < 0.0025) {
        var l = candidates.where((d) => _checkTier(d, 'LEYENDA')).toList();
        if (l.isNotEmpty) return l[rnd.nextInt(l.length)];
      }
      if (tierRoll < 0.0075) {
        var p = candidates.where((d) => _checkTier(d, 'PRIME')).toList();
        if (p.isNotEmpty) return p[rnd.nextInt(p.length)];
      }
    }
    double totalWeight = 0;
    Map<String, double> weights = {};
    for (var doc in candidates) {
      int rating = doc['rating'] ?? 75;
      double w = (100 - rating).toDouble();
      if (w <= 1) w = 1;
      weights[doc.id] = w;
      totalWeight += w;
    }
    double randomWeight = rnd.nextDouble() * totalWeight;
    double currentSum = 0;
    for (var doc in candidates) {
      currentSum += weights[doc.id]!;
      if (randomWeight <= currentSum) return doc;
    }
    return candidates.first;
  }

  bool _isSpecial(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    String tier = (data['tier'] ?? '').toString().toUpperCase();
    int rating = data['rating'] ?? 0;
    return tier == 'LEYENDA' || tier == 'PRIME' || rating >= 90;
  }

  bool _checkTier(DocumentSnapshot doc, String targetTier) {
    var data = doc.data() as Map<String, dynamic>;
    return (data['tier'] ?? '').toString().toUpperCase() == targetTier;
  }

  void _handleCardTap() {
    if (!isCardRevealed) {
      setState(() => isCardRevealed = true);
    } else {
      setState(() {
        if (currentCardIndex < generatedSquad.length) {
          currentCardIndex++;
          isCardRevealed = false;
        }
      });
    }
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    bool finishedAll = packOpened && currentCardIndex >= generatedSquad.length;
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("APERTURA DE EQUIPO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !packOpened,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment.center, radius: 1.5, colors: [Color(0xFF1E293B), Color(0xFF0B1120)])
        ),
        child: Column(
          children: [
            if (!packOpened) ...[
              const Spacer(),

              // PACK VISUAL
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 250, height: 350,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [goldColor, Colors.orange.shade900]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: goldColor.withOpacity(0.4), blurRadius: 40, spreadRadius: 5)]
                    ),
                  ),
                  Container(
                    width: 240, height: 340,
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: goldColor.withOpacity(0.5))
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield, size: 80, color: goldColor),
                        const SizedBox(height: 20),
                        const Text("STARTER PACK", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const SizedBox(height: 10),
                        Text("22 JUGADORES", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 4)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              if (isOpening)
                Column(
                  children: [
                    CircularProgressIndicator(color: goldColor),
                    const SizedBox(height: 20),
                    Text(statusMessage, style: TextStyle(color: goldColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                )
              else
                SizedBox(
                  width: 260,
                  height: 65,
                  child: ElevatedButton(
                    onPressed: _openStarterPack,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 15,
                        shadowColor: goldColor.withOpacity(0.6)
                    ),
                    child: const Text("ABRIR SOBRE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2)),
                  ),
                ),
              const Spacer(),
            ] else if (!finishedAll) ...[
              const SizedBox(height: 20),
              // CONTADOR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30)),
                child: Text("CARTA ${currentCardIndex + 1} / ${generatedSquad.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
              const Spacer(),

              // CARTA
              GestureDetector(
                onTap: _handleCardTap,
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    transitionBuilder: (w, a) {
                      return RotationTransition(turns: Tween(begin: 0.5, end: 1.0).animate(a), child: w);
                    },
                    child: isCardRevealed
                        ? _buildFrontCard(generatedSquad[currentCardIndex])
                        : _buildBackCard(generatedSquad[currentCardIndex])
                ),
              ),

              const Spacer(),
              AnimatedOpacity(
                opacity: isCardRevealed ? 1.0 : 0.5,
                duration: const Duration(seconds: 1),
                child: Text(isCardRevealed ? "TOCA PARA CONTINUAR" : "TOCA PARA REVELAR", style: const TextStyle(color: Colors.white24, letterSpacing: 3, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(height: 40),
            ] else ...[
              const Spacer(),
              Icon(Icons.check_circle, size: 100, color: goldColor),
              const SizedBox(height: 30),
              const Text("¡PLANTILLA COMPLETA!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                child: Text("Tus jugadores han sido enviados al club. Es hora de definir la táctica.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5)),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 250,
                height: 60,
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text("IR AL VESTUARIO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1))
                ),
              ),
              const Spacer(),
            ]
          ],
        ),
      ),
    );
  }

  // --- UI DE CARTAS (Premium V2) ---

  BoxDecoration _getCardDecoration(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();

    if (tier == 'LEYENDA') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700), width: 2),
          gradient: const LinearGradient(
              colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
              begin: Alignment.topLeft, end: Alignment.bottomRight
          ),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.5), blurRadius: 20)]
      );
    }

    if (tier == 'PRIME') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.cyanAccent, width: 2),
          color: Colors.black,
          boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 15)]
      );
    }

    Color bgColor;
    Color borderColor;

    if (rating >= 90) { // Black Ball
      bgColor = const Color(0xFF101010);
      borderColor = Colors.white38;
    } else if (rating >= 85) { // Gold
      bgColor = const Color(0xFFD4AF37);
      borderColor = const Color(0xFFFFE082);
    } else if (rating >= 80) { // Silver
      bgColor = const Color(0xFFB0BEC5);
      borderColor = Colors.white70;
    } else { // Bronze
      bgColor = const Color(0xFF8D6E63);
      borderColor = const Color(0xFFD7CCC8);
    }

    return BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)]
    );
  }

  Color _getTextColor(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();
    if (tier == 'LEYENDA' || tier == 'PRIME' || rating >= 90) return Colors.white;
    return Colors.black;
  }

  Widget _buildBackCard(Map<String, dynamic> p) {
    return Container(
      key: const ValueKey(1), width: 280, height: 420,
      decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 4),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)]
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
          child: const Icon(Icons.sports_soccer, size: 60, color: Colors.white10),
        ),
      ),
    );
  }

  Widget _buildFrontCard(Map<String, dynamic> p) {
    Color txtColor = _getTextColor(p);
    return Container(
      key: const ValueKey(2), width: 280, height: 420,
      decoration: _getCardDecoration(p),
      child: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.1, child: Icon(Icons.shield, size: 200, color: txtColor))),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${p['rating']}", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: txtColor)),
                Text(p['position'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: txtColor)),
                const Spacer(),
                Center(
                  child: Text(
                      p['name'].toString().toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, color: txtColor, fontWeight: FontWeight.w900, letterSpacing: 1)
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}