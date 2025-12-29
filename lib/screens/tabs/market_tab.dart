import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../mid_season_shop.dart';
import '../squad_builder_screen.dart';

class MarketTab extends StatelessWidget {
  final String seasonId;
  final bool isMarketOpen;
  final String currentUserId;

  const MarketTab({super.key, required this.seasonId, required this.isMarketOpen, required this.currentUserId});

  // --- HELPER: Verificar si soy Admin (Para mostrar botón de liquidar) ---
  Future<bool> _isAdmin() async {
    var doc = await FirebaseFirestore.instance.collection('seasons').doc(seasonId).get();
    return doc.exists && doc.data()?['adminId'] == currentUserId;
  }

  // --- HELPER: Verificar si soy mitad inferior (Para poder ofertar) ---
  Future<bool> _amIEligibleForDiscardAuction() async {
    var pSnap = await FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').get();
    var docs = pSnap.docs;

    // Ordenar por puntos (mismo criterio que StandingsTab)
    docs.sort((a, b) {
      var sA = (a.data())['leagueStats'] ?? {};
      var sB = (b.data())['leagueStats'] ?? {};
      int ptsA = sA['pts']??0; int ptsB = sB['pts']??0;
      if (ptsA != ptsB) return ptsB.compareTo(ptsA);
      return (sB['dif']??0).compareTo(sA['dif']??0);
    });

    int myIndex = docs.indexWhere((d) => d.id == currentUserId);
    if (myIndex == -1) return false;

    int total = docs.length;
    int half = (total / 2).ceil();
    // Si myIndex >= half, estoy en la mitad de abajo
    return myIndex >= half;
  }

  // --- ACCIÓN: Ofertar por descarte ---
  Future<void> _bidOnDiscard(DocumentSnapshot auctionDoc, BuildContext context) async {
    bool eligible = await _amIEligibleForDiscardAuction();
    if (!eligible) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Solo la mitad inferior de la tabla puede ofertar aquí."), backgroundColor: Colors.red));
      return;
    }

    TextEditingController ctrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1B263B),
      title: const Text("OFERTAR POR DESCARTE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("El dinero se descontará si ganas al finalizar el tiempo.", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 15),
          TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: "Tu Oferta",
                  prefixText: "\$ ",
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))
              )
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancelar", style: TextStyle(color: Colors.white38))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              int bid = int.tryParse(ctrl.text) ?? 0;
              int currentHighest = auctionDoc['highestBid'] ?? 0;

              if (bid <= currentHighest) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tu oferta debe ser mayor a la actual."), backgroundColor: Colors.orange));
                return;
              }

              var myDoc = await FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(currentUserId).get();
              if ((myDoc['budget']??0) >= bid) {
                await auctionDoc.reference.update({
                  'highestBid': bid,
                  'highestBidderId': currentUserId
                });
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Oferta realizada con éxito!"), backgroundColor: Colors.green));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fondos insuficientes"), backgroundColor: Colors.red));
              }
            },
            child: const Text("CONFIRMAR OFERTA", style: TextStyle(color: Colors.white))
        )
      ],
    ));
  }

  // --- ACCIÓN ADMIN: Liquidar subastas vencidas ---
  Future<void> _resolveExpiredAuctions(BuildContext context) async {
    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(seasonId);

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Procesando subastas vencidas...")));

      var query = await seasonRef.collection('discard_auctions')
          .where('status', isEqualTo: 'ACTIVE')
          .get();

      var expiredDocs = query.docs.where((doc) {
        DateTime end = (doc['endTime'] as Timestamp).toDate();
        return DateTime.now().isAfter(end);
      }).toList();

      if (expiredDocs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay subastas pendientes de cierre.")));
        return;
      }

      int processed = 0;

      for (var doc in expiredDocs) {
        var data = doc.data();
        String? winnerId = data['highestBidderId'];
        int amount = data['highestBid'];
        String playerId = data['playerId'];

        await db.runTransaction((tx) async {
          if (winnerId != null && amount > 0) {
            // Hubo ganador: Cobrar y entregar
            DocumentReference winnerRef = seasonRef.collection('participants').doc(winnerId);
            DocumentSnapshot winnerSnap = await tx.get(winnerRef);

            if (winnerSnap.exists) {
              int currentBudget = winnerSnap['budget'] ?? 0;
              if (currentBudget >= amount) {
                tx.update(winnerRef, {
                  'budget': FieldValue.increment(-amount),
                  'roster': FieldValue.arrayUnion([playerId])
                });
                // Marcar jugador como tomado globalmente (ya estaba en 'takenIds' técnicamente, pero aseguramos)
                tx.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion([playerId])});
                tx.update(doc.reference, {'status': 'COMPLETED', 'winnerId': winnerId});
              } else {
                // Ganador sin fondos (Cancelar)
                tx.update(doc.reference, {'status': 'FAILED_NO_FUNDS'});
              }
            }
          } else {
            // Nadie pujó -> Expirada
            tx.update(doc.reference, {'status': 'EXPIRED_NO_BIDS'});
          }
        });
        processed++;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Se liquidaron $processed subastas."), backgroundColor: Colors.green));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AVISO DE MERCADO CERRADO
          if (!isMarketOpen)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              color: Colors.redAccent,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text("MERCADO CERRADO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // 1. TIENDA (BANNER)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: isMarketOpen ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => MidSeasonShop(seasonId: seasonId))) : null,
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Icon(Icons.storefront, color: Colors.white, size: 40),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("TIENDA & SACRIFICIO", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          Text(
                              isMarketOpen ? "Compra sobres descartando jugadores" : "Tienda cerrada",
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 20),
                      child: Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                    )
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),

          // 2. OPORTUNIDADES (DESCARTES)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("OPORTUNIDADES (Descartes)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('discard_auctions').where('status', isEqualTo: 'ACTIVE').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text("No hay jugadores descartados."));

              // Filtro visual: mostrar todas las activas (incluso vencidas, para que el admin las vea y liquide)
              var docs = snapshot.data!.docs;

              return SizedBox(
                height: 160,
                child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var doc = docs[index];
                      var data = doc.data() as Map<String, dynamic>;
                      DateTime end = (data['endTime'] as Timestamp).toDate();
                      bool isExpired = DateTime.now().isAfter(end);
                      Duration left = end.difference(DateTime.now());
                      String timeLeft = isExpired ? "FINALIZADA" : "${left.inHours}h ${left.inMinutes % 60}m";

                      return GestureDetector(
                        onTap: isExpired ? null : () => _bidOnDiscard(doc, context),
                        child: Container(
                          width: 130, margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: isExpired ? Colors.grey[200] : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isExpired ? Colors.grey : Colors.redAccent),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(timeLeft, style: TextStyle(color: isExpired ? Colors.grey : Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                              const SizedBox(height: 5),
                              CircleAvatar(backgroundColor: Colors.grey[300], radius: 25, child: Text("${data['rating']}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black))),
                              const SizedBox(height: 5),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(data['playerName'], textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              const Divider(height: 10),
                              Text("\$${(data['highestBid']/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                              if (!isExpired) const Text("Toca para pujar", style: TextStyle(fontSize: 8, color: Colors.grey))
                            ],
                          ),
                        ),
                      );
                    }
                ),
              );
            },
          ),

          // BOTÓN ADMIN (LIQUIDAR)
          FutureBuilder<bool>(
            future: _isAdmin(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.gavel, size: 18),
                      label: const Text("ADMIN: LIQUIDAR VENCIDAS"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                      onPressed: () => _resolveExpiredAuctions(context),
                    ),
                  ),
                );
              }
              return const SizedBox();
            },
          ),

          const SizedBox(height: 20),
          const Divider(thickness: 5, color: Colors.white),
          const SizedBox(height: 20),

          // 3. RIVALES
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text("RIVALES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor))),
          const SizedBox(height: 10),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: LinearProgressIndicator());
              return SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    String uid = snapshot.data!.docs[index].id;
                    if (uid == currentUserId) return const SizedBox();

                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SquadBuilderScreen(seasonId: seasonId, userId: uid, isReadOnly: true))),
                      child: Container(
                        width: 120, margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(backgroundColor: Colors.blue[900], child: Text(data['teamName'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                            const SizedBox(height: 8),
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(data['teamName'], textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            Text("\$${((data['budget']??0)/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 30),
          const Divider(thickness: 5, color: Colors.white),
          const SizedBox(height: 20),

          // 4. HISTORIAL
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text("ÚLTIMOS FICHAJES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.grey[800]))),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('transfers').where('status', isEqualTo: 'ACCEPTED').limit(10).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text("Sin movimientos recientes."));
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, index) => _TransferHistoryItem(transferDoc: snapshot.data!.docs[index], seasonId: seasonId),
              );
            },
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}

class _TransferHistoryItem extends StatelessWidget {
  final DocumentSnapshot transferDoc;
  final String seasonId;
  const _TransferHistoryItem({required this.transferDoc, required this.seasonId});
  @override
  Widget build(BuildContext context) {
    var data = transferDoc.data() as Map<String, dynamic>;
    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(data['fromUserId']).get(),
        FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(data['toUserId']).get(),
      ]),
      builder: (context, snapshot) {
        String buyerName = snapshot.hasData ? snapshot.data![0].get('teamName') : "...";
        String sellerName = snapshot.hasData ? snapshot.data![1].get('teamName') : "...";
        return ListTile(
          leading: const Icon(Icons.sync_alt, color: Colors.green),
          title: Text(data['targetPlayerName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text("$buyerName ➔ $sellerName", style: const TextStyle(fontSize: 12)),
          trailing: Text("\$${(data['offeredAmount']/1000000).toStringAsFixed(1)}M", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
        );
      },
    );
  }
}