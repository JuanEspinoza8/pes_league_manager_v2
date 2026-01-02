import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:ui'; // Para efectos de Blur
import '../services/auth_service.dart';
import 'lobby_waiting_room.dart';
import 'create_season_screen.dart';

class LobbySelectionScreen extends StatefulWidget {
  const LobbySelectionScreen({super.key});

  @override
  State<LobbySelectionScreen> createState() => _LobbySelectionScreenState();
}

class _LobbySelectionScreenState extends State<LobbySelectionScreen> {
  // --- LÓGICA ORIGINAL INTACTA ---
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
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    // Definimos colores locales para consistencia
    final glassColor = const Color(0xFF1E293B).withOpacity(0.4);
    final goldColor = const Color(0xFFD4AF37);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("HUB DE LIGAS"),
        backgroundColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: Colors.white),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.5))
            ),
            child: IconButton(
              icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
              onPressed: () => AuthService().signOut(),
              tooltip: "Cerrar Sesión",
            ),
          )
        ],
      ),
      // Fondo Global V2
      backgroundColor: const Color(0xFF0B1120),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [Color(0xFF1E293B), Color(0xFF0B1120)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER TEXT ---
                const Text(
                  "TUS CAMPAÑAS",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                Text(
                  "Gestiona tu legado",
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                ),
                const SizedBox(height: 20),

                // --- LISTA DE LIGAS ---
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('seasons')
                      .where('participantIds', arrayContains: currentUserId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: goldColor));
                    var docs = snapshot.data!.docs;

                    if (docs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                            color: glassColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.05))
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.sports_soccer_outlined, size: 60, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 15),
                            Text("Sin contratos activos", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16)),
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

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isActive
                                ? [BoxShadow(color: goldColor.withOpacity(0.15), blurRadius: 20, offset: const Offset(0,4))]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isActive ? goldColor.withOpacity(0.1) : glassColor,
                                  border: Border.all(
                                      color: isActive ? goldColor.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                                      width: 1
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF0B1120),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isActive ? goldColor : Colors.white10)
                                    ),
                                    child: Icon(
                                        Icons.emoji_events_outlined,
                                        color: isActive ? goldColor : Colors.white54
                                    ),
                                  ),
                                  title: Text(
                                    data['name'] ?? "Liga Sin Nombre",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isActive ? 'EN JUEGO' : 'PRE-TEMPORADA',
                                            style: TextStyle(
                                                color: isActive ? Colors.greenAccent : Colors.grey,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: CircleAvatar(
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    child: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
                                  ),
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyWaitingRoom(seasonId: docs[index].id)));
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 40),
                Divider(color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 20),

                // --- ACCIONES RÁPIDAS (CREAR / UNIRSE) ---
                const Text(
                  "NUEVA AVENTURA",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 20),

                // Botón Crear (Dorado Premium)
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSeasonScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [const Color(0xFFC0A062), goldColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: goldColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
                          child: const Icon(Icons.add, color: Colors.black87, size: 24),
                        ),
                        const SizedBox(width: 20),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("CREAR NUEVA TEMPORADA", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                              SizedBox(height: 4),
                              Text("Eres el Presidente. Define las reglas.", style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Tarjeta Unirse (Dark Glass)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.qr_code_scanner, color: goldColor),
                              const SizedBox(width: 10),
                              const Text("Unirse con Código", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _joinCodeController,
                                  textCapitalization: TextCapitalization.characters,
                                  style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: "ABC-123",
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), letterSpacing: 4),
                                    fillColor: const Color(0xFF0B1120),
                                    filled: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: isLoading ? null : _joinSeason,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: isLoading
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                    : const Icon(Icons.arrow_forward_rounded, color: Colors.black),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}