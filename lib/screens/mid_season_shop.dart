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
    FirebaseFirestore.instance
        .collection('seasons').doc(widget.seasonId)
        .collection('participants').doc(currentUser.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() => myBudget = doc['budget'] ?? 0);
      }
    });
    _fetchMyRoster();
  }

  Future<void> _fetchMyRoster() async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(currentUser.uid)
          .get();

      List rosterIds = doc.data()?['roster'] ?? [];

      if (rosterIds.isNotEmpty) {
        List<String> ids = rosterIds.map((e) => e.toString()).toList();
        List<DocumentSnapshot> allDocs = [];

        for (var i = 0; i < ids.length; i += 10) {
          var end = (i + 10 < ids.length) ? i + 10 : ids.length;
          var chunk = ids.sublist(i, end);
          if (chunk.isNotEmpty) {
            var q = await FirebaseFirestore.instance
                .collection('players').where(FieldPath.documentId, whereIn: chunk).get();
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
                backgroundColor: const Color(0xFF1B263B),
                title: Text("SACRIFICIO: Selecciona $quantity", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: Column(
                      children: [
                        Text("Seleccionados: ${selectedIdsToDiscard.length} / $quantity", style: const TextStyle(color: Colors.amber)),
                        const Divider(color: Colors.white24),
                        Expanded(
                          child: ListView.builder(
                              itemCount: eligibleToDiscard.length,
                              itemBuilder: (context, index) {
                                var p = eligibleToDiscard[index];
                                bool isSel = selectedIdsToDiscard.contains(p.id);
                                return CheckboxListTile(
                                  title: Text(p['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  subtitle: Text("Media: ${p['rating']} - ${p['position']}", style: const TextStyle(color: Colors.grey)),
                                  value: isSel,
                                  activeColor: Colors.red,
                                  checkColor: Colors.white,
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
                      ],
                    )
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
                  ElevatedButton(
                      onPressed: selectedIdsToDiscard.length == quantity ? () => Navigator.pop(context, true) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      child: const Text("CONFIRMAR SACRIFICIO")
                  )
                ]
            );
          });
        }
    );

    if (confirmed == true) {
      _executePurchase(
          cost: cost,
          quantity: quantity,
          minBase: minBase,
          maxBase: maxBase,
          upgradeChance: upgradeChance,
          discardedIds: selectedIdsToDiscard
      );
    }
  }

  Future<void> _executePurchase({
    required int cost, required int quantity, required int minBase, required int maxBase,
    required double upgradeChance, required List<String> discardedIds
  }) async {
    setState(() => isOpening = true);
    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(widget.seasonId);
    final userRef = seasonRef.collection('participants').doc(currentUser.uid);
    final Random rnd = Random();

    try {
      DocumentSnapshot userSnap = await userRef.get();
      if ((userSnap['budget'] ?? 0) < cost) throw "Fondos insuficientes.";

      DocumentSnapshot seasonSnap = await seasonRef.get();
      List takenIds = seasonSnap['takenPlayerIds'] ?? [];

      // --- [INICIO] LÓGICA DE TRAMPA (RIGGED PACK) ---
      // Verificamos si hay un jugador programado para este usuario
      String? riggedPlayerId = (userSnap.data() as Map<String, dynamic>).containsKey('rigged_next_pack')
          ? (userSnap.data() as Map<String, dynamic>)['rigged_next_pack']
          : null;

      DocumentSnapshot? riggedDoc;
      if (riggedPlayerId != null) {
        riggedDoc = await db.collection('players').doc(riggedPlayerId).get();
      }
      // --- [FIN] LÓGICA DE TRAMPA ---

      // Pools de Jugadores
      var queryBase = await db.collection('players')
          .where('rating', isGreaterThanOrEqualTo: minBase)
          .where('rating', isLessThanOrEqualTo: maxBase)
          .limit(300).get();
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

        // PRIORIDAD 1: LA TRAMPA (Solo se aplica a la primera carta del pack)
        if (i == 0 && riggedDoc != null && riggedDoc.exists) {
          picked = riggedDoc;
          trampaUsada = true;
        }
        // PRIORIDAD 2: SUERTE O NORMAL
        else {
          bool triggerUpgrade = (upgradeChance > 0 && poolUpgrade.isNotEmpty) ? rnd.nextDouble() < upgradeChance : false;

          if (triggerUpgrade) {
            poolUpgrade.shuffle(); picked = poolUpgrade.first; poolUpgrade.removeAt(0);
          } else {
            if (poolBase.isEmpty) {
              if(poolUpgrade.isNotEmpty) { poolUpgrade.shuffle(); picked = poolUpgrade.first; poolUpgrade.removeAt(0); }
              else throw "Stock agotado.";
            } else {
              poolBase.shuffle(); picked = poolBase.first; poolBase.removeAt(0);
            }
          }
        }
        selectedDocs.add(picked);
        selectedIds.add(picked.id);
      }

      List<Map<String, dynamic>> finalData = selectedDocs.map((d) => d.data() as Map<String, dynamic>).toList();

      // TRANSACCIÓN
      await db.runTransaction((tx) async {
        DocumentSnapshot freshSeasonSnap = await tx.get(seasonRef);
        List freshTaken = freshSeasonSnap['takenPlayerIds'] ?? [];

        for (String id in selectedIds) {
          // Si es trampa, permitimos que pase aunque esté 'taken' (para poder regalar jugadores que ya salieron si es necesario, o corregir errores)
          // Si no es trampa, verificamos que esté libre.
          if (!trampaUsada && freshTaken.contains(id)) throw "Error de stock. Reintenta.";
        }

        // Actualizar Usuario
        Map<String, dynamic> userUpdates = {
          'budget': FieldValue.increment(-cost),
          'roster': FieldValue.arrayRemove(discardedIds)
        };

        // Si usamos la trampa, borramos el campo para que la próxima sea legal
        if (trampaUsada) {
          userUpdates['rigged_next_pack'] = FieldValue.delete();
        }

        tx.update(userRef, userUpdates);

        // Agregar nuevos jugadores
        DocumentSnapshot freshUserSnap = await tx.get(userRef);
        List currentRoster = List.from(freshUserSnap['roster'] ?? []);
        currentRoster.removeWhere((id) => discardedIds.contains(id));
        currentRoster.addAll(selectedIds);
        tx.update(userRef, {'roster': currentRoster});

        // Marcar como ocupados
        tx.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion(selectedIds)});
      });

      // Crear subastas para los descartes
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
    if (isOpening) {
      return const Scaffold(
          backgroundColor: Color(0xFF0D1B2A),
          body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.amber), SizedBox(height: 20), Text("Negociando...", style: TextStyle(color: Colors.white))]))
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(title: const Text("BOUTIQUE & SACRIFICIO"), backgroundColor: Colors.transparent, foregroundColor: Colors.white, centerTitle: true),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15), margin: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("PRESUPUESTO", style: TextStyle(color: Colors.white70)),
              Text("\$${(myBudget/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              children: [
                _buildPackCard(title: "PACK REFUERZO", desc: "3 Jugadores (80-84)\nSacrificio: 3 (+80)", cost: 120000000, colors: [Colors.blue[700]!, Colors.blue[300]!], onTap: () => _buyWithDiscardRule(120000000, 3, 80, 84, 0.10)),
                _buildPackCard(title: "PACK ESTRELLA", desc: "2 Jugadores (85-89)\nSacrificio: 2 (+80)", cost: 200000000, colors: [Colors.purple[800]!, Colors.purpleAccent], onTap: () => _buyWithDiscardRule(200000000, 2, 85, 89, 0.10)),
                _buildPackCard(title: "PACK LEYENDA", desc: "1 Jugador (+90)\nSacrificio: 1 (+80)", cost: 300000000, colors: [Colors.black, const Color(0xFFD4AF37)], onTap: () => _buyWithDiscardRule(300000000, 1, 90, 99, 0.0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard({required String title, required String desc, required int cost, required List<Color> colors, required VoidCallback onTap}) {
    return Container(
      height: 140, margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: colors.first.withOpacity(0.6), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: const Icon(Icons.flash_on, color: Colors.white, size: 30)),
        const SizedBox(width: 20),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12))])),
        Text("\$${(cost/1000000).toStringAsFixed(0)}M", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ])))),
    );
  }
}