import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pack_reveal_screen.dart';
import 'pandora_box_screen.dart';

class MidSeasonShop extends StatefulWidget {
  final String seasonId;
  const MidSeasonShop({super.key, required this.seasonId});

  @override
  State<MidSeasonShop> createState() => _MidSeasonShopState();
}

class _MidSeasonShopState extends State<MidSeasonShop> {
  // --- VARIABLES DE ESTADO ---
  final User currentUser = FirebaseAuth.instance.currentUser!;
  bool isOpening = false;
  int myBudget = 0;
  List<DocumentSnapshot> myRoster = []; // Necesario para el descarte

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- 1. CARGA DE DATOS (PRESERVADO) ---
  void _loadData() {
    // Escuchar presupuesto en tiempo real
    FirebaseFirestore.instance
        .collection('seasons').doc(widget.seasonId)
        .collection('participants').doc(currentUser.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() => myBudget = doc['budget'] ?? 0);
      }
    });
    // Cargar plantilla para poder descartar
    _fetchMyRoster();
  }

  // Trae los jugadores del usuario en lotes (Chunking) para evitar errores de query
  Future<void> _fetchMyRoster() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUser.uid).get();
      List rosterIds = doc.data()?['roster'] ?? [];

      if (rosterIds.isNotEmpty) {
        List<String> ids = rosterIds.map((e) => e.toString()).toList();
        List<DocumentSnapshot> allDocs = [];

        // Firestore solo permite 'whereIn' de hasta 10 elementos
        for (var i = 0; i < ids.length; i += 10) {
          var end = (i + 10 < ids.length) ? i + 10 : ids.length;
          var chunk = ids.sublist(i, end);
          if (chunk.isNotEmpty) {
            var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: chunk).get();
            allDocs.addAll(q.docs);
          }
        }

        if (mounted) {
          setState(() {
            // Ordenar por media para facilitar el descarte
            allDocs.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
            myRoster = allDocs;
          });
        }
      }
    } catch (e) {
      debugPrint("Error cargando plantilla: $e");
    }
  }

  // --- 2. LÓGICA NUEVA: CUBOS ---
  Future<void> _buyCube(String name, int cost, double chance, int taps, List<int> tiers, List<Color> colors) async {
    if (myBudget < cost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fondos insuficientes."), backgroundColor: Colors.red));
      return;
    }

    // Confirmación
    bool? confirm = await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text("COMPRAR $name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text("Precio: \$${(cost/1000000).toStringAsFixed(1)}M\nIntentos: $taps\nProbabilidad Mejora: ${(chance*100).toInt()}%\n¿Proceder?", style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("NO")),
            TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("SÍ", style: TextStyle(color: Colors.greenAccent))),
          ],
        )
    );

    if (confirm != true) return;

    setState(() => isOpening = true);

    try {
      // Cobrar entrada inmediatamente
      await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUser.uid).update({
        'budget': FieldValue.increment(-cost)
      });

      setState(() => isOpening = false);

      // Navegar a la pantalla del Cubo
      if(mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PandoraBoxScreen(
          seasonId: widget.seasonId,
          userId: currentUser.uid,
          boxName: name,
          successChance: chance,
          totalTaps: taps,
          tierRatings: tiers,
          boxColors: colors,
        )));
      }

    } catch (e) {
      setState(() => isOpening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  // --- 3. LÓGICA PRESERVADA Y ACTUALIZADA: COMPRA CON DESCARTE ---
  Future<void> _buyWithDiscardRule(int cost, int quantity, int minBase, int maxBase, double upgradeChance, {List<String>? positionFilter, required int minDiscardRating}) async {
    // Validación de Dinero
    if (myBudget < cost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fondos insuficientes."), backgroundColor: Colors.red));
      return;
    }

    // Validación de Jugadores para Sacrificio
    var eligibleToDiscard = myRoster.where((d) => (d['rating'] ?? 0) >= minDiscardRating).toList();
    if (eligibleToDiscard.length < quantity) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Requisito: Debes tener al menos $quantity jugadores de media +$minDiscardRating para descartar."), backgroundColor: Colors.red));
      return;
    }

    // Diálogo de Selección de Sacrificio
    List<String> selectedIdsToDiscard = [];
    bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(builder: (context, setDialogState) {
            return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                title: Text("SACRIFICIO: ELIGE $quantity", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                content: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: Column(children: [
                      Text("Debes entregar jugadores +$minDiscardRating", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                      Text("Seleccionados: ${selectedIdsToDiscard.length} / $quantity", style: const TextStyle(color: Color(0xFFD4AF37))),
                      const Divider(color: Colors.white24),
                      Expanded(
                        child: ListView.builder(
                            itemCount: eligibleToDiscard.length,
                            itemBuilder: (context, index) {
                              var p = eligibleToDiscard[index];
                              bool isSel = selectedIdsToDiscard.contains(p.id);
                              return CheckboxListTile(
                                title: Text(p['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                subtitle: Text("Media: ${p['rating']} - ${p['position']}", style: const TextStyle(color: Colors.white54)),
                                value: isSel,
                                activeColor: Colors.redAccent,
                                checkColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      if (selectedIdsToDiscard.length < quantity) selectedIdsToDiscard.add(p.id);
                                    } else {
                                      selectedIdsToDiscard.remove(p.id);
                                    }
                                  });
                                },
                              );
                            }
                        ),
                      ),
                    ])),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
                  ElevatedButton(
                      onPressed: selectedIdsToDiscard.length == quantity ? () => Navigator.pop(context, true) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      child: const Text("CONFIRMAR SACRIFICIO")
                  )
                ]
            );
          });
        }
    );

    if (confirmed == true) {
      // Llamamos a la función central de compra
      _executePurchase(
          cost: cost,
          quantity: quantity,
          minBase: minBase,
          maxBase: maxBase,
          upgradeChance: upgradeChance,
          discardedIds: selectedIdsToDiscard,
          positionFilter: positionFilter
      );
    }
  }

  // --- 4. CEREBRO DE LA TIENDA (PRESERVADO: Transacciones, Trampas y Subastas) ---
  Future<void> _executePurchase({
    required int cost,
    required int quantity,
    required int minBase,
    required int maxBase,
    required double upgradeChance,
    required List<String> discardedIds,
    List<String>? positionFilter
  }) async {
    setState(() => isOpening = true);
    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(widget.seasonId);
    final userRef = seasonRef.collection('participants').doc(currentUser.uid);
    final Random rnd = Random();

    try {
      // 4.1. Validaciones Previas (Lecturas)
      DocumentSnapshot userSnap = await userRef.get();
      if ((userSnap['budget'] ?? 0) < cost) throw "Fondos insuficientes.";

      DocumentSnapshot seasonSnap = await seasonRef.get();
      List takenIds = seasonSnap['takenPlayerIds'] ?? [];

      // 4.2. Lógica de "Trampa" (Rigged Pack) - PRESERVADA
      String? riggedPlayerId = (userSnap.data() as Map).containsKey('rigged_next_pack') ? (userSnap.data() as Map)['rigged_next_pack'] : null;
      DocumentSnapshot? riggedDoc;
      if (riggedPlayerId != null) {
        riggedDoc = await db.collection('players').doc(riggedPlayerId).get();
      }

      // 4.3. Preparar Pools de Jugadores
      // Traemos un pool amplio para poder filtrar en memoria si hay positions o takenIds
      var queryBase = await db.collection('players')
          .where('rating', isGreaterThanOrEqualTo: minBase)
          .where('rating', isLessThanOrEqualTo: maxBase)
          .limit(500)
          .get();

      List<DocumentSnapshot> poolBase = queryBase.docs.where((d) => !takenIds.contains(d.id)).toList();

      List<DocumentSnapshot> poolUpgrade = [];
      if (upgradeChance > 0) {
        var queryUp = await db.collection('players')
            .where('rating', isGreaterThan: maxBase)
            .limit(200)
            .get();
        poolUpgrade = queryUp.docs.where((d) => !takenIds.contains(d.id)).toList();
      }

      // 4.4. Filtro Posicional (NUEVO)
      if (positionFilter != null && positionFilter.isNotEmpty) {
        poolBase = poolBase.where((d) => positionFilter.contains(d['position'])).toList();
        poolUpgrade = poolUpgrade.where((d) => positionFilter.contains(d['position'])).toList();
      }

      // 4.5. Selección de Cartas
      List<DocumentSnapshot> selectedDocs = [];
      List<String> selectedIds = [];
      bool trampaUsada = false;

      for (int i = 0; i < quantity; i++) {
        DocumentSnapshot picked;

        // Si hay trampa activa y es la primera carta
        if (i == 0 && riggedDoc != null && riggedDoc.exists) {
          picked = riggedDoc;
          trampaUsada = true;
        } else {
          // Lógica Normal de Probabilidad
          bool triggerUpgrade = (upgradeChance > 0 && poolUpgrade.isNotEmpty) ? rnd.nextDouble() < upgradeChance : false;

          if (triggerUpgrade) {
            poolUpgrade.shuffle();
            picked = poolUpgrade.first;
            poolUpgrade.removeAt(0); // Evitar repetidos en el mismo sobre
          } else {
            if (poolBase.isEmpty) {
              if (poolUpgrade.isNotEmpty) {
                // Si no hay base, damos upgrade
                poolUpgrade.shuffle();
                picked = poolUpgrade.first;
                poolUpgrade.removeAt(0);
              } else {
                throw "Stock agotado para estos criterios.";
              }
            } else {
              poolBase.shuffle();
              picked = poolBase.first;
              poolBase.removeAt(0);
            }
          }
        }
        selectedDocs.add(picked);
        selectedIds.add(picked.id);
      }

      List<Map<String, dynamic>> finalData = selectedDocs.map((d) => d.data() as Map<String, dynamic>).toList();

      // 4.6. TRANSACCIÓN ATÓMICA (CRÍTICO: PRESERVADO)
      await db.runTransaction((tx) async {
        DocumentSnapshot freshSeasonSnap = await tx.get(seasonRef);
        DocumentSnapshot freshUserSnap = await tx.get(userRef);

        // Verificar concurrencia (si alguien lo compró mientras pensábamos)
        List freshTaken = freshSeasonSnap['takenPlayerIds'] ?? [];
        for (String id in selectedIds) {
          if (!trampaUsada && freshTaken.contains(id)) throw "Error de stock concurrente. Reintenta.";
        }

        int currentBudget = freshUserSnap['budget'] ?? 0;
        int newBudget = currentBudget - cost;
        if (newBudget < 0) throw "Fondos insuficientes.";

        // Actualizar Roster (Quitar sacrificados, Poner nuevos)
        List currentRoster = List.from(freshUserSnap['roster'] ?? []);
        currentRoster.removeWhere((id) => discardedIds.contains(id));
        currentRoster.addAll(selectedIds);

        Map<String, dynamic> userUpdates = {
          'budget': newBudget,
          'roster': currentRoster
        };

        // Si usamos la trampa, la borramos para que no salga siempre
        if (trampaUsada) {
          userUpdates['rigged_next_pack'] = FieldValue.delete();
        }

        tx.update(userRef, userUpdates);
        tx.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion(selectedIds)});
      });

      // 4.7. Crear Subastas de Descarte (PRESERVADO)
      var auctionCol = seasonRef.collection('discard_auctions');
      for (String pid in discardedIds) {
        var pDoc = myRoster.firstWhere((d) => d.id == pid, orElse: () => myRoster.first);
        await auctionCol.add({
          'playerId': pid,
          'playerName': pDoc['name'],
          'rating': pDoc['rating'],
          'position': pDoc['position'],
          'photoUrl': (pDoc.data() as Map).containsKey('photoUrl') ? pDoc['photoUrl'] : "",
          'originalOwnerId': currentUser.uid,
          'highestBid': 0,
          'highestBidderId': null,
          'endTime': DateTime.now().add(const Duration(hours: 10)),
          'status': 'ACTIVE'
        });
      }

      // Refrescar y mostrar
      _fetchMyRoster();
      setState(() => isOpening = false);
      if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PackRevealScreen(players: finalData)));

    } catch (e) {
      setState(() => isOpening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"), backgroundColor: Colors.red));
    }
  }

  // --- HELPERS DE UI (Diálogos) ---
  Future<List<String>?> _selectPositionFilter(BuildContext context) async {
    return await showDialog<List<String>>(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: const Text('Elige la posición', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1E293B),
            children: [
              _positionOption(context, "Portero", ['PO'], Icons.sports_handball),
              _positionOption(context, "Defensa", ['LD', 'LI', 'DEC'], Icons.shield),
              _positionOption(context, "Mediocampo", ['MCD', 'MC', 'MO'], Icons.linear_scale),
              _positionOption(context, "Delantera", ['CD', 'SD', 'EXD', 'EXI', 'MDD','MDI',], Icons.sports_soccer),
            ],
          );
        }
    );
  }

  Widget _positionOption(BuildContext context, String label, List<String> codes, IconData icon) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, codes),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isOpening) return const Scaffold(backgroundColor: Color(0xFF0B1120), body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
    const goldColor = Color(0xFFD4AF37);

    // PRECIOS
    const int p1Cost = 170000000;
    const int p2Cost = 250000000;
    const int p3Cost = 350000000;
    const int pos1Cost = 220000000;
    const int pos2Cost = 300000000;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(title: const Text("BOUTIQUE EXCLUSIVA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)), backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, centerTitle: true, elevation: 0),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black, Colors.blueGrey.shade900]), borderRadius: BorderRadius.circular(20), border: Border.all(color: goldColor.withOpacity(0.3)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)]),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("TU CAPITAL", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text("\$${(myBudget/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.w900)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // --- SECCIÓN CUBOS ---
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Text("CUBOS DE FORJA (Suerte)", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),

                // 1. CHURRERO (45M) - 15% - 3 Intentos
                _buildCubeCard(
                    title: "CHURRERO",
                    desc: "Start: 75+\n3 Intentos (15%)\nPasos: 80 -> 85 -> 90",
                    cost: 45000000,
                    colors: [Colors.brown.shade800, Colors.orangeAccent.shade700],
                    icon: Icons.casino,
                    onTap: () => _buyCube("Churrero", 45000000, 0.15, 3, [75, 80, 85, 90], [Colors.brown, Colors.orange])
                ),

                // 2. CUBO NORMAL (90M) - 30% - 3 Intentos
                _buildCubeCard(
                    title: "CUBO NORMAL",
                    desc: "Start: 75+\n3 Intentos (30%)\nPasos: 80 -> 85 -> 90",
                    cost: 90000000,
                    colors: [Colors.blue.shade900, Colors.cyanAccent.shade700],
                    icon: Icons.casino,
                    onTap: () => _buyCube("Cubo Normal", 90000000, 0.30, 3, [75, 80, 85, 90], [Colors.blue, Colors.cyan])
                ),

                // 3. KARINA (150M) - 30% - 5 Intentos
                _buildCubeCard(
                    title: "KARINA",
                    desc: "Start: 75+\n5 Intentos (30%)\nPasos: 80 -> 85 -> 90",
                    cost: 150000000,
                    colors: [Colors.purple.shade900, Colors.pinkAccent.shade400],
                    icon: Icons.auto_awesome,
                    onTap: () => _buyCube("Karina", 150000000, 0.30, 5, [75, 80, 85, 90], [Colors.purple, Colors.pinkAccent])
                ),

                const SizedBox(height: 20),
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Text("SOBRES CLÁSICOS", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),

                // Pack 1: Pide +80
                _buildPackCard(title: "PACK REFUERZO", desc: "3 Jugadores (80-84)\nSacrificio: 3 (+80)", cost: p1Cost, colors: [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)], icon: Icons.bolt, onTap: () => _buyWithDiscardRule(p1Cost, 3, 80, 84, 0.10, minDiscardRating: 80)),
                // Pack 2: Pide +81
                _buildPackCard(title: "PACK ESTRELLA", desc: "2 Jugadores (85-89)\nSacrificio: 2 (+81)", cost: p2Cost, colors: [const Color(0xFF581C87), const Color(0xFFA855F7)], icon: Icons.star, onTap: () => _buyWithDiscardRule(p2Cost, 2, 85, 89, 0.10, minDiscardRating: 81)),
                // Pack 3: Pide +82
                _buildPackCard(title: "PACK LEYENDA", desc: "1 Jugador (+90)\nSacrificio: 1 (+82)", cost: p3Cost, colors: [Colors.black, const Color(0xFFD4AF37)], icon: Icons.emoji_events, isLegend: true, onTap: () => _buyWithDiscardRule(p3Cost, 1, 90, 99, 0.0, minDiscardRating: 82)),

                const SizedBox(height: 20),
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Text("SCOUTING POSICIONAL", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),

                _buildPackCard(
                    title: "REFUERZO X ZONA", desc: "3 Jugadores (80-84)\nSacrificio: +80", cost: pos1Cost, colors: [Colors.teal.shade900, Colors.tealAccent.shade700], icon: Icons.gps_fixed,
                    onTap: () async { var pos = await _selectPositionFilter(context); if(pos!=null) _buyWithDiscardRule(pos1Cost, 3, 80, 84, 0.10, positionFilter: pos, minDiscardRating: 80); }
                ),
                _buildPackCard(
                    title: "ESTRELLA X ZONA", desc: "2 Jugadores (85-89)\nSacrificio: +81", cost: pos2Cost, colors: [Colors.deepOrange.shade900, Colors.deepOrangeAccent], icon: Icons.auto_awesome,
                    onTap: () async { var pos = await _selectPositionFilter(context); if(pos!=null) _buyWithDiscardRule(pos2Cost, 2, 85, 89, 0.10, positionFilter: pos, minDiscardRating: 81); }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TEMPLATES DE UI ---
  Widget _buildPackCard({required String title, required String desc, required int cost, required List<Color> colors, required IconData icon, required VoidCallback onTap, bool isLegend = false}) {
    return _cardTemplate(title, desc, cost, colors, icon, onTap, isLegend);
  }

  Widget _buildCubeCard({required String title, required String desc, required int cost, required List<Color> colors, required IconData icon, required VoidCallback onTap}) {
    return _cardTemplate(title, desc, cost, colors, icon, onTap, false);
  }

  Widget _cardTemplate(String title, String desc, int cost, List<Color> colors, IconData icon, VoidCallback onTap, bool isLegend) {
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: colors.first.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))]
      ),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Stack(
        children: [
          Positioned(right: -15, bottom: -15, child: Icon(icon, size: 100, color: Colors.white.withOpacity(0.1))),
          Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: isLegend ? const Color(0xFFD4AF37) : Colors.white, size: 24)),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(color: isLegend ? const Color(0xFFD4AF37) : Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
            const SizedBox(height: 15),
            Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Text("\$${(cost/1000000).toStringAsFixed(0)}M", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ])),
        ],
      ))),
    );
  }
}