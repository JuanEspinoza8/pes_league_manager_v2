import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'lobby_waiting_room.dart';
import 'create_season_screen.dart';

class LobbySelectionScreen extends StatefulWidget {
  const LobbySelectionScreen({super.key});

  @override
  State<LobbySelectionScreen> createState() => _LobbySelectionScreenState();
}

class _LobbySelectionScreenState extends State<LobbySelectionScreen> {
  final TextEditingController _joinCodeController = TextEditingController();
  bool isLoading = false;
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  Future<void> _joinSeason() async {
    String code = _joinCodeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("El código debe tener 6 caracteres")));
      return;
    }

    setState(() => isLoading = true);
    final db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser!;

    final querySnapshot = await db.collection('seasons').where('code', isEqualTo: code).limit(1).get();

    if (querySnapshot.docs.isEmpty) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Temporada no encontrada")));
      return;
    }

    final seasonDoc = querySnapshot.docs.first;
    List<dynamic> participants = seasonDoc['participantIds'] ?? [];

    if (!participants.contains(user.uid)) {
      await db.collection('seasons').doc(seasonDoc.id).update({
        'participantIds': FieldValue.arrayUnion([user.uid])
      });
      await db.collection('seasons').doc(seasonDoc.id).collection('participants').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'teamName': "Equipo de ${user.email!.split('@')[0]}",
        'budget': 100000000,
        'roster': [],
        'points_league': 0,
        'role': 'MEMBER',
      });
    }

    setState(() => isLoading = false);
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyWaitingRoom(seasonId: seasonDoc.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar simplificado con fondo oscuro
      appBar: AppBar(
        title: const Text("HUB DE LIGAS"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () => AuthService().signOut(),
            tooltip: "Cerrar Sesión",
          )
        ],
      ),
      // Fondo oscuro global
      backgroundColor: const Color(0xFF0D1B2A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SECCIÓN: HEADER ---
            const Text(
              "Tus Temporadas",
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 5),
            const Text(
              "Continúa tu carrera o inicia una nueva",
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // --- LISTA DE LIGAS ---
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('seasons')
                  .where('participantIds', arrayContains: currentUserId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
                var docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white10)
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.sports_soccer, size: 50, color: Colors.white24),
                        SizedBox(height: 10),
                        Text("No tienes ligas activas", style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    bool isActive = data['status'] == 'ACTIVE';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      color: const Color(0xFF1B263B), // Tarjeta oscura
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isActive ? Colors.amber : Colors.transparent, width: 1) // Borde dorado si activa
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.emoji_events, color: isActive ? Colors.amber : Colors.grey),
                        ),
                        title: Text(
                          data['name'] ?? "Liga Sin Nombre",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(
                          "Estado: ${isActive ? 'EN JUEGO' : 'EN LOBBY'}",
                          style: TextStyle(color: isActive ? Colors.greenAccent : Colors.grey, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyWaitingRoom(seasonId: docs[index].id)));
                        },
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 30),
            const Divider(color: Colors.white10),
            const SizedBox(height: 20),

            // --- ACCIONES RÁPIDAS (CREAR / UNIRSE) ---
            const Text(
              "Nueva Aventura",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // Botón Crear
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSeasonScreen())),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFC0A062), Color(0xFFE0C080)]), // Dorado
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
                ),
                child: Row(
                  children: const [
                    Icon(Icons.add_circle, color: Colors.black87, size: 30),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CREAR NUEVA TEMPORADA", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 16)),
                          Text("Sé el administrador y configura las reglas", style: TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.black54),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // Tarjeta Unirse
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.qr_code, color: Colors.black87),
                      SizedBox(width: 10),
                      Text("Unirse a una sala", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _joinCodeController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: "CÓDIGO DE SALA",
                            hintText: "EJ: ABC123",
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: isLoading ? null : _joinSeason,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.arrow_forward, color: Colors.white),
                      )
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}