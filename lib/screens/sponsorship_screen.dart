import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/sponsorship_service.dart';

class SponsorshipScreen extends StatefulWidget {
  final String seasonId;
  final String userId;
  final bool isAdmin;

  const SponsorshipScreen({
    super.key,
    required this.seasonId,
    required this.userId,
    required this.isAdmin
  });

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SponsorshipService _service = SponsorshipService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.isAdmin ? 2 : 1, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("PATROCINADORES", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: widget.isAdmin ? TabBar(
          controller: _tabController,
          indicatorColor: goldColor,
          labelColor: goldColor,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: "MIS CONTRATOS"),
            Tab(text: "SOLICITUDES (ADMIN)"),
          ],
        ) : null,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyContractsTab(),
          if (widget.isAdmin) _buildAdminRequestsTab(),
        ],
      ),
    );
  }

  // --- PESTAÑA 1: MIS CONTRATOS ---
  Widget _buildMyContractsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(widget.userId)
          .collection('sponsorships')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        var docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.handshake_outlined, size: 60, color: Colors.white10),
                  SizedBox(height: 10),
                  Text("Sin contratos activos.\n¡Gana partidos para atraer marcas!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white24)),
                ],
              )
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            String id = docs[index].id;
            String status = data['status'];

            Color statusColor = Colors.grey;
            if (status == 'OFFER') statusColor = Colors.blueAccent;
            if (status == 'ACTIVE') statusColor = Colors.greenAccent;
            if (status == 'PENDING_REVIEW') statusColor = Colors.orangeAccent;
            if (status == 'COMPLETED') statusColor = Colors.white24;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: status == 'ACTIVE' ? Colors.green.withOpacity(0.3) : Colors.white10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0,4))]
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                          child: Text(data['brandIcon'] ?? '💰', style: const TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['brandName'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                              Text("Nivel ${data['tier']}", style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                        )
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(data['description'], style: const TextStyle(fontSize: 14, color: Colors.white70)),
                    const SizedBox(height: 10),
                    Text("Recompensa: \$${(data['reward'] / 1000000).toStringAsFixed(2)}M",
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.greenAccent, fontSize: 18)),
                    const SizedBox(height: 15),

                    // --- ACCIONES DE USUARIO ---
                    if (status == 'OFFER')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _service.rejectOffer(widget.seasonId, widget.userId, id),
                            child: const Text("RECHAZAR", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _service.acceptOffer(widget.seasonId, widget.userId, id),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: const Text("FIRMAR CONTRATO", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),

                    if (status == 'ACTIVE')
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _service.requestVerification(widget.seasonId, widget.userId, id),
                              icon: const Icon(Icons.check_circle_outline, color: Colors.black),
                              label: const Text("SOLICITAR PAGO", style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _showAbandonDialog(id),
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text("Romper contrato (Liberar espacio)", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                            ),
                          )
                        ],
                      ),

                    if (status == 'PENDING_REVIEW')
                      const Center(child: Text("En revisión por la directiva...", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white30, fontSize: 12))),

                    if (status == 'COMPLETED')
                      const Center(child: Text("Contrato finalizado y pagado.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white24, fontSize: 12))),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- DIÁLOGO PARA ABANDONAR ---
  void _showAbandonDialog(String contractId) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("¿Romper Patrocinio?", style: TextStyle(color: Colors.white)),
          content: const Text("Perderás este contrato y el progreso actual. Se liberará el espacio para recibir nuevas ofertas si tienes suerte en próximos partidos.", style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _service.abandonContract(widget.seasonId, widget.userId, contractId);
              },
              child: const Text("ROMPER CONTRATO", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        )
    );
  }

  // --- PESTAÑA 2: ADMIN PANEL ---
  Widget _buildAdminRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getAllPendingRequests(snapshot.data!.docs),
          builder: (context, pendingSnap) {
            if (!pendingSnap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
            var requests = pendingSnap.data!;

            if (requests.isEmpty) return const Center(child: Text("No hay solicitudes pendientes.", style: TextStyle(color: Colors.white24)));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                var req = requests[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user, color: Colors.orangeAccent),
                          const SizedBox(width: 8),
                          Expanded(child: Text("Usuario: ${req['userName']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text("${req['brandIcon']} ${req['brandName']} - \$${(req['reward']/1000000).toStringAsFixed(2)}M", style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 5),
                      Text("Objetivo: ${req['description']}", style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white38)),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await _service.denyClaim(widget.seasonId, req['userId'], req['docId']);
                                if(mounted) setState(() {});
                              },
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                              child: const Text("RECHAZAR"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await _service.approveAndPay(
                                    widget.seasonId,
                                    req['userId'],
                                    req['docId'],
                                    req['reward'],
                                    req['userName'],
                                    req['brandName']
                                );
                                if(mounted) setState(() {});
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text("APROBAR PAGO"),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getAllPendingRequests(List<QueryDocumentSnapshot> participants) async {
    List<Map<String, dynamic>> allRequests = [];

    for (var userDoc in participants) {
      var spSnap = await userDoc.reference.collection('sponsorships')
          .where('status', isEqualTo: 'PENDING_REVIEW')
          .get();

      for (var doc in spSnap.docs) {
        var d = doc.data();
        allRequests.add({
          'userId': userDoc.id,
          'userName': userDoc['teamName'],
          'docId': doc.id,
          'brandName': d['brandName'],
          'brandIcon': d['brandIcon'],
          'description': d['description'],
          'reward': d['reward'],
        });
      }
    }
    return allRequests;
  }
}