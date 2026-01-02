import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/news_service.dart';

class TransfersScreen extends StatefulWidget {
  final String seasonId;
  const TransfersScreen({super.key, required this.seasonId});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  // --- LÓGICA INTACTA ---
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  Future<void> _acceptOffer(DocumentSnapshot offerDoc) async {
    final data = offerDoc.data() as Map<String, dynamic>;
    final String buyerId = data['fromUserId'];
    final String sellerId = data['toUserId'];
    final String targetPlayerId = data['targetPlayerId'];
    final String? swapPlayerId = data['swapPlayerId'];
    final int amount = data['offeredAmount'] ?? 0;

    final db = FirebaseFirestore.instance;
    final seasonRef = db.collection('seasons').doc(widget.seasonId);

    try {
      String buyerName = await _getTeamName(buyerId);
      String sellerName = await _getTeamName(sellerId);
      String playerName = data['targetPlayerName'];

      await db.runTransaction((transaction) async {
        DocumentReference buyerRef = seasonRef.collection('participants').doc(buyerId);
        DocumentReference sellerRef = seasonRef.collection('participants').doc(sellerId);

        DocumentSnapshot buyerSnap = await transaction.get(buyerRef);
        DocumentSnapshot sellerSnap = await transaction.get(sellerRef);

        int buyerBudget = buyerSnap['budget'] ?? 0;
        int sellerBudget = sellerSnap['budget'] ?? 0;
        List buyerRoster = List.from(buyerSnap['roster'] ?? []);
        List sellerRoster = List.from(sellerSnap['roster'] ?? []);

        if (buyerBudget < amount) throw "El comprador no tiene fondos suficientes";
        if (!sellerRoster.contains(targetPlayerId)) throw "Ya no tienes a este jugador";

        transaction.update(buyerRef, {'budget': buyerBudget - amount});
        transaction.update(sellerRef, {'budget': sellerBudget + amount});

        sellerRoster.remove(targetPlayerId);
        buyerRoster.add(targetPlayerId);

        if (swapPlayerId != null) {
          if (!buyerRoster.contains(swapPlayerId)) throw "El comprador ya no tiene al jugador de cambio";
          buyerRoster.remove(swapPlayerId);
          sellerRoster.add(swapPlayerId);
        }

        transaction.update(buyerRef, {'roster': buyerRoster});
        transaction.update(sellerRef, {'roster': sellerRoster});
        transaction.update(offerDoc.reference, {'status': 'ACCEPTED'});
      });

      try {
        NewsService().createTransferNews(
          seasonId: widget.seasonId,
          playerName: playerName,
          fromTeam: sellerName,
          toTeam: buyerName,
          price: amount,
        );
      } catch (newsError) {
        print("⚠️ Error generando noticia de traspaso (no crítico): $newsError");
      }

      String amountStr = amount > 0 ? "por \$${(amount/1000000).toStringAsFixed(1)}M" : "gratis";
      String swapStr = swapPlayerId != null ? " + ${data['swapPlayerName']}" : "";

      await NotificationService.sendGlobalNotification(
          seasonId: widget.seasonId,
          title: "MERCADO",
          body: "$buyerName fichó a $playerName de $sellerName $amountStr$swapStr",
          type: "TRANSFER"
      );

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Traspaso completado!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<String> _getTeamName(String userId) async {
    var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(userId).get();
    return doc.data()?['teamName'] ?? 'Equipo';
  }

  Future<void> _rejectOffer(String transferId) async {
    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('transfers').doc(transferId).update({'status': 'REJECTED'});
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1120),
        appBar: AppBar(
          title: const Text("BUZÓN DE FICHAJES", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18)),
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: goldColor,
            labelColor: goldColor,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
            indicatorWeight: 3,
            tabs: const [Tab(text: "RECIBIDAS"), Tab(text: "ENVIADAS")],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F172A), Color(0xFF0B1120)])
          ),
          child: TabBarView(
            children: [
              _buildList(isReceived: true),
              _buildList(isReceived: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList({required bool isReceived}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('transfers')
          .where(isReceived ? 'toUserId' : 'fromUserId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        if (snapshot.data!.docs.isEmpty) return _buildEmptyState();

        var docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var doc = docs[index];
            var data = doc.data() as Map<String, dynamic>;
            return _TransferCard(
              data: data,
              isReceived: isReceived,
              onAccept: () => _acceptOffer(doc),
              onReject: () => _rejectOffer(doc.id),
              seasonId: widget.seasonId,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 20),
          Text("No hay movimientos recientes", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isReceived;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final String seasonId;

  const _TransferCard({required this.data, required this.isReceived, required this.onAccept, required this.onReject, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    bool isPending = data['status'] == 'PENDING';
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (data['status']) {
      case 'ACCEPTED': statusColor = Colors.greenAccent; statusText = "ACEPTADA"; statusIcon = Icons.check_circle_outline; break;
      case 'REJECTED': statusColor = Colors.redAccent; statusText = "RECHAZADA"; statusIcon = Icons.cancel_outlined; break;
      default: statusColor = Colors.amberAccent; statusText = "PENDIENTE"; statusIcon = Icons.hourglass_empty;
    }

    String moneyText = data['offeredAmount'] > 0 ? "\$${(data['offeredAmount']/1000000).toStringAsFixed(1)}M" : "";
    String swapName = data['swapPlayerName'] ?? "Ninguno";
    bool hasSwap = data['swapPlayerId'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B), // Slate 800
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        children: [
          // Header Estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [Icon(statusIcon, size: 16, color: statusColor), const SizedBox(width: 8), Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1))]),
                if (moneyText.isNotEmpty) Text(moneyText, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _PlayerColumn("SOLICITADO", data['targetPlayerName'], Icons.person)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Icon(Icons.compare_arrows, color: Colors.white.withOpacity(0.3), size: 30)),
                    Expanded(child: _PlayerColumn("A CAMBIO", hasSwap ? swapName : "Solo Dinero", hasSwap ? Icons.person_outline : Icons.monetization_on_outlined)),
                  ],
                ),
                if (isPending && isReceived) ...[
                  const SizedBox(height: 25),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: onReject,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                            ),
                            child: const Text("RECHAZAR", style: TextStyle(fontWeight: FontWeight.bold))
                        )
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                        child: ElevatedButton(
                            onPressed: onAccept,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 5
                            ),
                            child: const Text("ACEPTAR", style: TextStyle(fontWeight: FontWeight.bold))
                        )
                    ),
                  ])
                ],
                if (!isReceived) ...[
                  const SizedBox(height: 15),
                  Divider(color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 5),
                  FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(data['toUserId']).get(),
                      builder: (c, s) => Text("Enviada a: ${s.data?['teamName'] ?? '...'}", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontStyle: FontStyle.italic))
                  )
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  final String label; final String name; final IconData icon;
  const _PlayerColumn(this.label, this.name, this.icon);
  @override Widget build(BuildContext context) {
    return Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), letterSpacing: 1)),
          const SizedBox(height: 10),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white10)
              ),
              child: Icon(icon, color: Colors.white, size: 24)
          ),
          const SizedBox(height: 10),
          Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis)
        ]
    );
  }
}