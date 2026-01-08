import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pack_reveal_screen.dart';

class MidSeasonShop extends StatefulWidget {
  final String seasonId;
  const MidSeasonShop({super.key, required this.seasonId});

  @override
  State<MidSeasonShop> createState() => _MidSeasonShopState();
}

class _MidSeasonShopState extends State<MidSeasonShop> {
  final User currentUser = FirebaseAuth.instance.currentUser!;
  bool isOpening = false;
  int myBudget = 0;
  List<DocumentSnapshot> myRoster = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUser.uid).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        setState(() => myBudget = doc['budget'] ?? 0);
      }
    });
    _fetchMyRoster();
  }

  Future<void> _fetchMyRoster() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUser.uid).get();
      List rosterIds = doc.data()?['roster'] ?? [];
      if (rosterIds.isNotEmpty) {
        List<String> ids = rosterIds.map((e) => e.toString()).toList();
        List<DocumentSnapshot> allDocs = [];
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
            allDocs.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
            myRoster = allDocs;
          });
        }
      }
    } catch (e) {
      debugPrint("Error cargando plantilla: $e");
    }
  }

  Future<void> _buyWithDiscardRule(int cost, int quantity, int minBase, int maxBase, double upgradeChance) async {
    var eligibleToDiscard = myRoster.where((d) => (d['rating'] ?? 0) >= 80).toList();
    if (eligibleToDiscard.length < quantity) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No tienes suficientes jugadores +80 para sacrificar."), backgroundColor: Colors.red));
      return;
    }
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
      _executePurchase(cost: cost, quantity: quantity, minBase: minBase, maxBase: maxBase, upgradeChance: upgradeChance, discardedIds: selectedIdsToDiscard);
    }
  }

  Future<void> _executePurchase({required int cost, required int quantity, required int minBase, required int maxBase, required double upgradeChance, required List<String> discardedIds}) async {
    setState(() => isOpening = true);
    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(widget.seasonId);
    final userRef = seasonRef.collection('participants').doc(currentUser.uid);
    final Random rnd = Random();

    try {
      // Validaciones previas
      DocumentSnapshot userSnap = await userRef.get();
      if ((userSnap['budget'] ?? 0) < cost) throw "Fondos insuficientes.";

      DocumentSnapshot seasonSnap = await seasonRef.get();
      List takenIds = seasonSnap['takenPlayerIds'] ?? [];

      String? riggedPlayerId = (userSnap.data() as Map).containsKey('rigged_next_pack') ? (userSnap.data() as Map)['rigged_next_pack'] : null;
      DocumentSnapshot? riggedDoc;
      if (riggedPlayerId != null) {
        riggedDoc = await db.collection('players').doc(riggedPlayerId).get();
      }

      var queryBase = await db.collection('players').where('rating', isGreaterThanOrEqualTo: minBase).where('rating', isLessThanOrEqualTo: maxBase).limit(300).get();
      List<DocumentSnapshot> poolBase = queryBase.docs.where((d) => !takenIds.contains(d.id)).toList();

      List<DocumentSnapshot> poolUpgrade = [];
      if (upgradeChance > 0) {
        var queryUp = await db.collection('players').where('rating', isGreaterThan: maxBase).limit(100).get();
        poolUpgrade = queryUp.docs.where((d) => !takenIds.contains(d.id)).toList();
      }

      List<DocumentSnapshot> selectedDocs = [];
      List<String> selectedIds = [];
      bool trampaUsada = false;

      for (int i = 0; i < quantity; i++) {
        DocumentSnapshot picked;
        if (i == 0 && riggedDoc != null && riggedDoc.exists) {
          picked = riggedDoc;
          trampaUsada = true;
        } else {
          bool triggerUpgrade = (upgradeChance > 0 && poolUpgrade.isNotEmpty) ? rnd.nextDouble() < upgradeChance : false;
          if (triggerUpgrade) {
            poolUpgrade.shuffle();
            picked = poolUpgrade.first;
            poolUpgrade.removeAt(0);
          } else {
            if (poolBase.isEmpty) {
              if(poolUpgrade.isNotEmpty) {
                poolUpgrade.shuffle();
                picked = poolUpgrade.first;
                poolUpgrade.removeAt(0);
              } else throw "Stock agotado.";
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

      // --- TRANSACCIÓN CORREGIDA (Reads antes de Writes) ---
      await db.runTransaction((tx) async {
        // 1. LEER TODO PRIMERO
        DocumentSnapshot freshSeasonSnap = await tx.get(seasonRef);
        DocumentSnapshot freshUserSnap = await tx.get(userRef);

        // 2. VERIFICACIONES LÓGICAS
        List freshTaken = freshSeasonSnap['takenPlayerIds'] ?? [];
        for (String id in selectedIds) {
          if (!trampaUsada && freshTaken.contains(id)) throw "Error de stock. Reintenta.";
        }

        // 3. CALCULAR NUEVO ESTADO DEL USUARIO (en memoria)
        // Presupuesto
        int currentBudget = freshUserSnap['budget'] ?? 0;
        int newBudget = currentBudget - cost;
        if (newBudget < 0) throw "Fondos insuficientes.";

        // Roster
        List currentRoster = List.from(freshUserSnap['roster'] ?? []);
        // Quitar sacrificados
        currentRoster.removeWhere((id) => discardedIds.contains(id));
        // Agregar nuevos
        currentRoster.addAll(selectedIds);

        // 4. ESCRIBIR TODO AL FINAL
        Map<String, dynamic> userUpdates = {
          'budget': newBudget,
          'roster': currentRoster
        };

        if (trampaUsada) {
          userUpdates['rigged_next_pack'] = FieldValue.delete();
        }

        tx.update(userRef, userUpdates); // Write User
        tx.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion(selectedIds)}); // Write Season
      });
      // -----------------------------------------------------

      // Crear subastas de descarte (fuera de la transacción principal para no bloquear)
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

      _fetchMyRoster();
      setState(() => isOpening = false);
      if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PackRevealScreen(players: finalData)));

    } catch (e) {
      setState(() => isOpening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isOpening) return const Scaffold(backgroundColor: Color(0xFF0B1120), body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
    const goldColor = Color(0xFFD4AF37);

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
                _buildPackCard(title: "PACK REFUERZO", desc: "3 Jugadores (80-84)\nSacrificio: 3 (+80)", cost: 120000000, colors: [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)], icon: Icons.bolt, onTap: () => _buyWithDiscardRule(120000000, 3, 80, 84, 0.10)),
                _buildPackCard(title: "PACK ESTRELLA", desc: "2 Jugadores (85-89)\nSacrificio: 2 (+80)", cost: 200000000, colors: [const Color(0xFF581C87), const Color(0xFFA855F7)], icon: Icons.star, onTap: () => _buyWithDiscardRule(200000000, 2, 85, 89, 0.10)),
                _buildPackCard(title: "PACK LEYENDA", desc: "1 Jugador (+90)\nSacrificio: 1 (+80)", cost: 300000000, colors: [Colors.black, const Color(0xFFD4AF37)], icon: Icons.emoji_events, isLegend: true, onTap: () => _buyWithDiscardRule(300000000, 1, 90, 99, 0.0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard({required String title, required String desc, required int cost, required List<Color> colors, required IconData icon, required VoidCallback onTap, bool isLegend = false}) {
    return Container(
      height: 150, margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: colors.first.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))]
      ),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: Stack(
        children: [
          Positioned(right: -20, bottom: -20, child: Icon(icon, size: 120, color: Colors.white.withOpacity(0.1))),
          Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: isLegend ? const Color(0xFFD4AF37) : Colors.white, size: 28)),
              const SizedBox(width: 15),
              Text(title, style: TextStyle(color: isLegend ? const Color(0xFFD4AF37) : Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
            const Spacer(),
            Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            Text("\$${(cost/1000000).toStringAsFixed(0)}M", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          ])),
        ],
      ))),
    );
  }
}