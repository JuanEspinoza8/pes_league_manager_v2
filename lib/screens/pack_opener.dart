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

    // BUCLE DE REINTENTO (Manejo de concurrencia)
    // Si la transacción falla porque alguien te ganó un jugador, esto vuelve a empezar
    while (!success && attempts < 5) {
      attempts++;
      List<String> myNewRosterIds = [];
      List<Map<String, dynamic>> tempSquadDisplay = [];

      // Reiniciamos el contador en cada intento de generación
      int specialCardsCount = 0;

      try {
        DocumentSnapshot seasonSnap = await seasonRef.get();
        List<dynamic> takenIds = seasonSnap['takenPlayerIds'] ?? [];

        for (var req in squadRequirements) {
          QuerySnapshot query = await db.collection('players').where('position', whereIn: req['pos']).get();

          // Filtramos los que ya están ocupados
          List<DocumentSnapshot> candidates = query.docs.where((doc) => !takenIds.contains(doc.id) && !myNewRosterIds.contains(doc.id)).toList();

          for (int i = 0; i < req['count']; i++) {
            if (candidates.isEmpty) break;

            // --- LÓGICA DE LÍMITE ESTRICTO ---
            bool limitReached = specialCardsCount >= 2;
            List<DocumentSnapshot> pool = candidates;

            if (limitReached) {
              // FILTRO FUERTE: Si llegamos al límite, eliminamos las especiales de la lista
              var normalPlayers = candidates.where((doc) => !_isSpecial(doc)).toList();
              // Solo aplicamos el filtro si quedan jugadores normales disponibles (para no romper el código si solo hay leyendas)
              if (normalPlayers.isNotEmpty) {
                pool = normalPlayers;
              }
            }

            // Seleccionamos usando el pool filtrado
            // Pasamos !limitReached para saber si "intentamos suerte" con los porcentajes
            DocumentSnapshot selected = _selectWeightedPlayer(pool, !limitReached);

            if (_isSpecial(selected)) {
              specialCardsCount++;
            }

            myNewRosterIds.add(selected.id);
            tempSquadDisplay.add(selected.data() as Map<String, dynamic>);
            candidates.removeWhere((doc) => doc.id == selected.id);
          }
        }

        if (myNewRosterIds.length < 5) throw "Error: No hay suficientes jugadores disponibles";

        // TRANSACCIÓN ATÓMICA
        await db.runTransaction((transaction) async {
          DocumentSnapshot freshSnap = await transaction.get(seasonRef);
          List<dynamic> freshTaken = freshSnap['takenPlayerIds'] ?? [];

          // Verificación final de concurrencia
          for (String id in myNewRosterIds) {
            if (freshTaken.contains(id)) throw "Collision"; // Alguien lo tomó hace milisegundos -> Reintentar
          }

          transaction.update(seasonRef.collection('participants').doc(currentUser.uid), {'roster': myNewRosterIds, 'budget': 100000000});
          transaction.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion(myNewRosterIds)});
        });

        success = true;
        setState(() {
          generatedSquad = tempSquadDisplay;
          generatedSquad.sort((a, b) => (a['rating'] ?? 0).compareTo(b['rating'] ?? 0)); // Ordenar por media para el reveal
          isOpening = false;
          packOpened = true;
          currentCardIndex = 0;
          isCardRevealed = false;
        });

      } catch (e) {
        // Si falló (Collision), esperamos un poco y reintentamos el bucle
        await Future.delayed(Duration(milliseconds: Random().nextInt(500)));
      }
    }

    if (!success) {
      setState(() { isOpening = false; statusMessage = "Error de red o mercado saturado. Intenta de nuevo."; });
    }
  }

  DocumentSnapshot _selectWeightedPlayer(List<DocumentSnapshot> candidates, bool tryLuck) {
    Random rnd = Random();

    // SOLO si no hemos llegado al límite, tiramos los dados
    if (tryLuck) {
      double tierRoll = rnd.nextDouble();

      // 0.25% LEYENDA
      if (tierRoll < 0.0025) {
        var l = candidates.where((d) => _checkTier(d, 'LEYENDA')).toList();
        if (l.isNotEmpty) return l[rnd.nextInt(l.length)];
      }

      // 0.75% PRIME (Total 1% de especial top)
      if (tierRoll < 0.0075) {
        var p = candidates.where((d) => _checkTier(d, 'PRIME')).toList();
        if (p.isNotEmpty) return p[rnd.nextInt(p.length)];
      }
    }

    // SELECCIÓN POR PESO (Normal)
    // Damos más peso a los jugadores de media baja para equilibrar, pero los buenos siguen saliendo
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

  @override
  Widget build(BuildContext context) {
    bool finishedAll = packOpened && currentCardIndex >= generatedSquad.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Fondo Premium
      appBar: AppBar(
        title: const Text("APERTURA DE EQUIPO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !packOpened,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)]
            )
        ),
        child: Column(
          children: [
            if (!packOpened) ...[
              const Spacer(),
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.shield, size: 200, color: Colors.white.withOpacity(0.05)),
                  const Icon(Icons.card_giftcard, size: 100, color: Colors.amber),
                ],
              ),
              const SizedBox(height: 40),

              const Text("STARTER PACK", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const Text("Tu plantilla inicial garantizada", style: TextStyle(color: Colors.white54, fontSize: 14)),

              const SizedBox(height: 50),

              if (isOpening)
                Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 20),
                    Text(statusMessage, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                )
              else
                SizedBox(
                  width: 250,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _openStarterPack,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 10,
                        shadowColor: Colors.amber.withOpacity(0.5)
                    ),
                    child: const Text("ABRIR AHORA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
                  ),
                ),
              const Spacer(),
            ] else if (!finishedAll) ...[
              const SizedBox(height: 20),
              // CONTADOR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                child: Text("CARTA ${currentCardIndex + 1} / ${generatedSquad.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),

              // CARTA
              GestureDetector(
                onTap: _handleCardTap,
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                    child: isCardRevealed
                        ? _buildFrontCard(generatedSquad[currentCardIndex])
                        : _buildBackCard(generatedSquad[currentCardIndex])
                ),
              ),

              const Spacer(),
              AnimatedOpacity(
                opacity: isCardRevealed ? 1.0 : 0.5,
                duration: const Duration(seconds: 1),
                child: Text(isCardRevealed ? "Toca para siguiente" : "Toca para revelar", style: const TextStyle(color: Colors.white54, letterSpacing: 2)),
              ),
              const SizedBox(height: 40),
            ] else ...[
              const Spacer(),
              const Icon(Icons.check_circle_outline, size: 120, color: Colors.greenAccent),
              const SizedBox(height: 20),
              const Text("¡EQUIPO LISTO!", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                child: Text("Has completado tu plantilla inicial. Ve a 'Mi Equipo' para organizar tu táctica.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 250,
                height: 55,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0D1B2A)),
                    child: const Text("IR AL VESTUARIO", style: TextStyle(fontWeight: FontWeight.bold))
                ),
              ),
              const Spacer(),
            ]
          ],
        ),
      ),
    );
  }

  // --- UI DE CARTAS (ESTILO FUT) ---

  BoxDecoration _getCardDecoration(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();

    if (tier == 'LEYENDA') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
          gradient: const LinearGradient(
              colors: [Color(0xFFB71C1C), Color(0xFF880E4F), Color(0xFF4A148C), Color(0xFFFFD700)],
              begin: Alignment.topLeft, end: Alignment.bottomRight
          ),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.6), blurRadius: 20)]
      );
    }

    if (tier == 'PRIME') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.cyanAccent, width: 2),
          gradient: const LinearGradient(
              colors: [Color(0xFFCFD8DC), Color(0xFF546E7A), Color(0xFF263238)],
              begin: Alignment.topLeft, end: Alignment.bottomRight
          ),
          boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.4), blurRadius: 15)]
      );
    }

    Color bgColor;
    Color borderColor;

    if (rating >= 90) { // Bola Negra
      bgColor = const Color(0xFF101010);
      borderColor = Colors.white54;
    } else if (rating >= 85) { // Oro Brillante
      bgColor = const Color(0xFFFFD700);
      borderColor = Colors.orange;
    } else if (rating >= 80) { // Oro Opaco
      bgColor = const Color(0xFFC5A000);
      borderColor = Colors.brown;
    } else { // Silver
      bgColor = const Color(0xFF9E9E9E);
      borderColor = Colors.blueGrey;
    }

    return BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [BoxShadow(color: bgColor.withOpacity(0.5), blurRadius: 10)]
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
      key: const ValueKey(1), width: 300, height: 450,
      decoration: _getCardDecoration(p).copyWith(gradient: null, color: const Color(0xFF0D1B2A)), // Reverso oscuro
      child: Container(
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 5),
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF000000)], begin: Alignment.topRight, end: Alignment.bottomLeft)
        ),
        child: const Center(child: Icon(Icons.star, size: 80, color: Colors.white24)),
      ),
    );
  }

  Widget _buildFrontCard(Map<String, dynamic> p) {
    Color txtColor = _getTextColor(p);
    return Container(
      key: const ValueKey(2), width: 300, height: 450,
      decoration: _getCardDecoration(p),
      child: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.1, child: Icon(Icons.shield, size: 200, color: txtColor))),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 20),
                  Column(
                    children: [
                      Text("${p['rating']}", style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: txtColor)),
                      Text(p['position'], style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: txtColor)),
                    ],
                  )
                ],
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: Colors.black54,
                child: Text(
                    p['name'].toString().toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }
}