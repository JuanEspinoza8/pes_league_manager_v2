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
    // Si es admin, mostramos 2 pestañas: Mis Contratos y Solicitudes Globales
    _tabController = TabController(length: widget.isAdmin ? 2 : 1, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text("PATROCINADORES"),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        bottom: widget.isAdmin ? TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white54,
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
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text("No tienes ofertas ni contratos activos. \n¡Gana partidos para atraer marcas!", textAlign: TextAlign.center));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            String id = docs[index].id;
            String status = data['status'];

            Color statusColor = Colors.grey;
            if (status == 'OFFER') statusColor = Colors.blue;
            if (status == 'ACTIVE') statusColor = Colors.green;
            if (status == 'PENDING_REVIEW') statusColor = Colors.orange;
            if (status == 'COMPLETED') statusColor = Colors.black;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(data['brandIcon'] ?? '💰', style: const TextStyle(fontSize: 30)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['brandName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Text("Tier ${data['tier']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        )
                      ],
                    ),
                    const Divider(),
                    Text(data['description'], style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    Text("Recompensa: \$${(data['reward'] / 1000000).toStringAsFixed(2)}M",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                    const SizedBox(height: 15),

                    // --- ACCIONES DE USUARIO ---
                    if (status == 'OFFER')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _service.rejectOffer(widget.seasonId, widget.userId, id),
                            child: const Text("Rechazar", style: TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _service.acceptOffer(widget.seasonId, widget.userId, id),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: const Text("ACEPTAR"),
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
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text("¡OBJETIVO CUMPLIDO! (Revisar)"),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D1B2A), foregroundColor: Colors.white),
                            ),
                          ),
                          // BOTÓN DE ARREPENTIMIENTO (ABANDONAR)
                          TextButton.icon(
                            onPressed: () => _showAbandonDialog(id),
                            icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                            label: const Text("Abandonar contrato (Liberar cupo)", style: TextStyle(color: Colors.red, fontSize: 12)),
                          )
                        ],
                      ),

                    if (status == 'PENDING_REVIEW')
                      const Center(child: Text("Esperando verificación del administrador...", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),

                    if (status == 'COMPLETED')
                      const Center(child: Text("Pagado y finalizado.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
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
          title: const Text("¿Abandonar Patrocinio?"),
          content: const Text("Perderás este contrato y el progreso actual. Se liberará el espacio para recibir nuevas ofertas si tienes suerte en próximos partidos."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _service.abandonContract(widget.seasonId, widget.userId, contractId);
              },
              child: const Text("ABANDONAR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        )
    );
  }

  // --- PESTAÑA 2: ADMIN PANEL ---
  Widget _buildAdminRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      // Traemos todos los participantes y luego buscamos sus sponsorships pendientes
      stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getAllPendingRequests(snapshot.data!.docs),
          builder: (context, pendingSnap) {
            if (!pendingSnap.hasData) return const Center(child: CircularProgressIndicator());
            var requests = pendingSnap.data!;

            if (requests.isEmpty) return const Center(child: Text("No hay solicitudes pendientes."));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                var req = requests[index];
                return Card(
                  color: Colors.amber.shade50,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified_user, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(child: Text("Usuario: ${req['userName']}", style: const TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text("${req['brandIcon']} ${req['brandName']} - \$${(req['reward']/1000000).toStringAsFixed(2)}M"),
                        const SizedBox(height: 5),
                        Text("Objetivo: ${req['description']}", style: const TextStyle(fontStyle: FontStyle.italic)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                await _service.denyClaim(widget.seasonId, req['userId'], req['docId']);
                                if(mounted) setState(() {}); // Recargar UI
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              child: const Text("RECHAZAR"),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                await _service.approveAndPay(
                                    widget.seasonId,
                                    req['userId'],
                                    req['docId'],
                                    req['reward'],
                                    req['userName'],
                                    req['brandName']
                                );
                                if(mounted) setState(() {}); // Recargar UI
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text("PAGAR"),
                            ),
                          ],
                        )
                      ],
                    ),
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
      // Nota: Esto hace N lecturas, optimizable en el futuro con Collection Groups si la app escala mucho.
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