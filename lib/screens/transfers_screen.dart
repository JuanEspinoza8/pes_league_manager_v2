import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class TransfersScreen extends StatefulWidget {
  final String seasonId;
  const TransfersScreen({super.key, required this.seasonId});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
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
      // Obtenemos nombres para la notificación antes de la transacción
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

        // Intercambio de dinero
        transaction.update(buyerRef, {'budget': buyerBudget - amount});
        transaction.update(sellerRef, {'budget': sellerBudget + amount});

        // Intercambio de jugadores (Principal)
        sellerRoster.remove(targetPlayerId);
        buyerRoster.add(targetPlayerId);

        // Intercambio de jugadores (Swap)
        if (swapPlayerId != null) {
          if (!buyerRoster.contains(swapPlayerId)) throw "El comprador ya no tiene al jugador de cambio";
          buyerRoster.remove(swapPlayerId);
          sellerRoster.add(swapPlayerId);
        }

        transaction.update(buyerRef, {'roster': buyerRoster});
        transaction.update(sellerRef, {'roster': sellerRoster});
        transaction.update(offerDoc.reference, {'status': 'ACCEPTED'});
      });

      // --- NOTIFICACIÓN DETALLADA ---
      String amountStr = amount > 0 ? "por \$${(amount/1000000).toStringAsFixed(1)}M" : "gratis";
      String swapStr = swapPlayerId != null ? " + ${data['swapPlayerName']}" : "";

      await NotificationService.sendGlobalNotification(
          seasonId: widget.seasonId,
          title: "MERCADO",
          body: "$buyerName fichó a $playerName de $sellerName $amountStr$swapStr",
          type: "TRANSFER"
      );

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Traspaso completado!"), backgroundColor: Colors.green));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<String> _getTeamName(String userId) async {
    var doc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(userId).get();
    return doc.data()?['teamName'] ?? 'Equipo';
  }

  Future<void> _rejectOffer(String transferId) async {
    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('transfers').doc(transferId).update({'status': 'REJECTED'});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5), // Fondo gris suave
        appBar: AppBar(
          title: const Text("BUZÓN DE FICHAJES", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          backgroundColor: const Color(0xFF0D1B2A),
          foregroundColor: Colors.white,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [Tab(text: "RECIBIDAS"), Tab(text: "ENVIADAS")],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(isReceived: true),
            _buildList(isReceived: false),
          ],
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return _buildEmptyState();

        var docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
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
          Icon(Icons.move_to_inbox, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text("No hay movimientos aquí", style: TextStyle(color: Colors.grey[500], fontSize: 18)),
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
      case 'ACCEPTED':
        statusColor = Colors.green;
        statusText = "ACEPTADA";
        statusIcon = Icons.check_circle;
        break;
      case 'REJECTED':
        statusColor = Colors.red;
        statusText = "RECHAZADA";
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusText = "PENDIENTE";
        statusIcon = Icons.hourglass_top;
    }

    String moneyText = data['offeredAmount'] > 0 ? "\$${(data['offeredAmount']/1000000).toStringAsFixed(1)}M" : "";
    String swapName = data['swapPlayerName'] ?? "Ninguno";
    bool hasSwap = data['swapPlayerId'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // HEADER CON ESTADO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 5),
                      Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                if (moneyText.isNotEmpty)
                  Text(moneyText, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            const Divider(height: 20),

            // CONTENIDO DE LA OFERTA
            Row(
              children: [
                // JUGADOR OBJETIVO
                Expanded(child: _PlayerColumn("SOLICITADO", data['targetPlayerName'], Icons.person)),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.swap_horiz, color: Colors.grey),
                ),

                // A CAMBIO DE
                Expanded(child: _PlayerColumn("A CAMBIO", hasSwap ? swapName : "Solo Dinero", hasSwap ? Icons.person_outline : Icons.monetization_on_outlined)),
              ],
            ),

            // BOTONES (Solo si está pendiente y la recibí yo)
            if (isPending && isReceived) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      child: const Text("RECHAZAR"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      child: const Text("ACEPTAR"),
                    ),
                  ),
                ],
              )
            ],

            // INFORMACIÓN DE QUIÉN (Si la envié yo, dice a quién se la envié)
            if (!isReceived) ...[
              const SizedBox(height: 10),
              const Divider(height: 10),
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('seasons').doc(seasonId).collection('participants').doc(data['toUserId']).get(),
                builder: (c, s) => Text("Enviada a: ${s.data?['teamName'] ?? '...'}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
              )
            ]
          ],
        ),
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  final String label;
  final String name;
  final IconData icon;
  const _PlayerColumn(this.label, this.name, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 5),
        Icon(icon, color: const Color(0xFF0D1B2A), size: 28),
        const SizedBox(height: 5),
        Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}