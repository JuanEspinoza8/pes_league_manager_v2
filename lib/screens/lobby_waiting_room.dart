import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'auction_room.dart';
import 'pack_opener.dart';
import 'my_team_screen.dart';
import 'league_dashboard_screen.dart';
import '../services/season_generator_service.dart';
import '../utils/debug_tools.dart';

class LobbyWaitingRoom extends StatefulWidget {
  final String seasonId;
  const LobbyWaitingRoom({super.key, required this.seasonId});

  @override
  State<LobbyWaitingRoom> createState() => _LobbyWaitingRoomState();
}

class _LobbyWaitingRoomState extends State<LobbyWaitingRoom> {
  // --- LÓGICA INTACTA ---
  bool isGenerating = false;

  void _showSupercopaSelectionAndStart(BuildContext context) {
    List<String> selectedIds = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text("🏆 Supercopa: Elige 4", style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('seasons')
                      .doc(widget.seasonId)
                      .collection('participants')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var docs = snapshot.data!.docs;

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var data = docs[index].data() as Map<String, dynamic>;
                        String id = docs[index].id;
                        String name = data['teamName'] ?? 'Sin Nombre';
                        bool isSelected = selectedIds.contains(id);

                        return CheckboxListTile(
                          title: Text(name, style: const TextStyle(color: Colors.white70)),
                          value: isSelected,
                          activeColor: const Color(0xFFD4AF37),
                          checkColor: Colors.black,
                          side: const BorderSide(color: Colors.white24),
                          onChanged: (bool? val) {
                            setStateDialog(() {
                              if (val == true) {
                                if (selectedIds.length < 4) selectedIds.add(id);
                              } else {
                                selectedIds.remove(id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                Text("Seleccionados: ${selectedIds.length}/4", style: TextStyle(color: selectedIds.length == 4 ? Colors.greenAccent : Colors.redAccent)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: selectedIds.length == 4
                      ? () {
                    Navigator.pop(context);
                    _handleStartSeason(selectedIds);
                  }
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                  child: const Text("CONFIRMAR E INICIAR", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleStartSeason(List<String> supercopaIds) async {
    setState(() => isGenerating = true);
    try {
      await SeasonGeneratorService().startSeason(widget.seasonId, supercopaIds);
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if(mounted) setState(() => isGenerating = false);
    }
  }

  void _showDebugMenu() {
    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0F172A),
        builder: (c) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("HERRAMIENTAS ADMIN", style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.smart_toy, color: Colors.white),
                  title: const Text("Rellenar con Bots", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(c);
                    await DebugTools().fillLeagueWithBots(widget.seasonId, 10);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bots añadidos.")));
                  },
                ),
              ],
            ),
          );
        }
    );
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final goldColor = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("VESTUARIO", style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
          if (!snapshot.data!.exists) return const Center(child: Text("Temporada no encontrada", style: TextStyle(color: Colors.white)));

          final seasonData = snapshot.data!.data() as Map<String, dynamic>;
          final Map<String, dynamic> config = seasonData['config'] ?? {};
          final String acquisitionMode = config['acquisitionMode'] ?? 'AUCTION';
          final int maxPlayers = config['maxPlayers'] ?? 10;
          final String code = seasonData['code'];
          final String status = seasonData['status'];
          final String adminId = seasonData['adminId'];
          final List<dynamic> participants = seasonData['participantIds'] ?? [];
          final bool isAdmin = currentUserId == adminId;

          // REDIRECCIÓN SI YA EMPEZÓ
          if (status == 'ACTIVE') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, size: 100, color: goldColor),
                  const SizedBox(height: 30),
                  const Text("¡LA LIGA HA COMENZADO!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                        backgroundColor: goldColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 10,
                        shadowColor: goldColor.withOpacity(0.5)
                    ),
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LeagueDashboardScreen(seasonId: widget.seasonId))),
                    child: const Text("IR AL CAMPO DE JUEGO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  )
                ],
              ),
            );
          }

          return Column(
            children: [
              // --- HEADER TIPO TICKET ---
              Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.1), blurRadius: 20, offset: const Offset(0,10))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // Fondo degradado
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF172554)])
                        ),
                        child: Column(
                          children: [
                            Text("CÓDIGO DE ACCESO", style: TextStyle(color: Colors.blue[100], fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado")));
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withOpacity(0.1))
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(code, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 8)),
                                    const SizedBox(width: 15),
                                    const Icon(Icons.copy, color: Colors.white70, size: 24),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _TagBadgeV2(text: status == 'WAITING' ? 'EN ESPERA' : 'DRAFT ACTIVO', color: status == 'WAITING' ? Colors.orange : Colors.greenAccent),
                                const SizedBox(width: 10),
                                _TagBadgeV2(text: acquisitionMode == 'AUCTION' ? 'SUBASTA' : 'SOBRES', color: Colors.purpleAccent),
                              ],
                            )
                          ],
                        ),
                      ),
                      // Decoración de círculos
                      Positioned(top: -20, left: -20, child: CircleAvatar(backgroundColor: Colors.white.withOpacity(0.05), radius: 40)),
                      Positioned(bottom: -20, right: -20, child: CircleAvatar(backgroundColor: Colors.white.withOpacity(0.05), radius: 40)),
                    ],
                  ),
                ),
              ),

              // --- CONTADOR Y LISTA ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("DTs EN LÍNEA", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                      child: Text("${participants.length} / $maxPlayers", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
                  builder: (context, participantsSnap) {
                    if (!participantsSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white10));

                    var docs = participantsSnap.data!.docs;
                    bool iHaveTeam = false;
                    try {
                      var myDoc = docs.firstWhere((d) => d.id == currentUserId);
                      List roster = myDoc['roster'] ?? [];
                      iHaveTeam = roster.isNotEmpty;
                    } catch (_) {}

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              var data = docs[index].data() as Map<String, dynamic>;
                              bool isFull = (data['roster'] ?? []).length >= 22;
                              bool isMe = data['uid'] == currentUserId;
                              bool isBot = data['role'] == 'BOT';
                              bool isAdminUser = data['uid'] == adminId;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                    color: isMe ? goldColor.withOpacity(0.1) : const Color(0xFF1E293B), // Fondo distinto si soy yo
                                    borderRadius: BorderRadius.circular(12),
                                    border: isMe ? Border.all(color: goldColor.withOpacity(0.5)) : Border.all(color: Colors.transparent)
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isBot ? Colors.grey[800] : (isAdminUser ? goldColor : Colors.blueAccent),
                                    child: Icon(
                                        isBot ? Icons.smart_toy : (isAdminUser ? Icons.star : Icons.person),
                                        color: isBot ? Colors.white54 : (isAdminUser ? Colors.black : Colors.white),
                                        size: 18
                                    ),
                                  ),
                                  title: Text(
                                      data['teamName'],
                                      style: TextStyle(
                                          color: isMe ? goldColor : Colors.white,
                                          fontWeight: isMe ? FontWeight.w900 : FontWeight.normal
                                      )
                                  ),
                                  trailing: isFull
                                      ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20)
                                      : const Icon(Icons.hourglass_empty, color: Colors.white24, size: 20),
                                ),
                              );
                            },
                          ),
                        ),

                        // --- ÁREA DE ACCIONES (GLASS PANEL) ---
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  border: const Border(top: BorderSide(color: Colors.white12))
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 1. ESTADO: ESPERA
                                  if (status == 'WAITING') ...[
                                    if (isAdmin)
                                      SizedBox(
                                        width: double.infinity,
                                        height: 55,
                                        child: ElevatedButton(
                                          onPressed: () => FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({'status': 'DRAFT_PHASE'}),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: goldColor,
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              elevation: 5
                                          ),
                                          child: const Text("INICIAR FASE DE DRAFT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                        ),
                                      )
                                    else
                                      Column(
                                        children: const [
                                          CircularProgressIndicator(color: Colors.white24),
                                          SizedBox(height: 15),
                                          Text("El administrador iniciará el draft pronto...", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                                        ],
                                      ),

                                    if (isAdmin) ...[
                                      const SizedBox(height: 10),
                                      TextButton.icon(
                                          onPressed: _showDebugMenu,
                                          icon: const Icon(Icons.settings, color: Colors.white24),
                                          label: const Text("Opciones de Admin", style: TextStyle(color: Colors.white24))
                                      )
                                    ]
                                  ],

                                  // 2. ESTADO: DRAFT
                                  if (status == 'DRAFT_PHASE' || status == 'AUCTION') ...[
                                    if (acquisitionMode == 'AUCTION')
                                      SizedBox(
                                        width: double.infinity,
                                        child: _ActionButtonV2(
                                            text: "ENTRAR A LA SUBASTA",
                                            icon: Icons.gavel_rounded,
                                            color: goldColor,
                                            textColor: Colors.black,
                                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionRoom(seasonId: widget.seasonId, isAdmin: isAdmin)))
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        width: double.infinity,
                                        child: _ActionButtonV2(
                                            text: iHaveTeam ? "SOBRE ABIERTO" : "ABRIR SOBRE INICIAL",
                                            icon: iHaveTeam ? Icons.check_circle_outline : Icons.flash_on,
                                            color: iHaveTeam ? Colors.white10 : Colors.purpleAccent,
                                            textColor: iHaveTeam ? Colors.white38 : Colors.white,
                                            onTap: iHaveTeam ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackOpener(seasonId: widget.seasonId)))
                                        ),
                                      ),

                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: currentUserId))),
                                        icon: const Icon(Icons.shield_outlined),
                                        label: const Text("VER PLANTILLA", style: TextStyle(fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 18),
                                            side: const BorderSide(color: Colors.white24),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                        ),
                                      ),
                                    ),

                                    if (isAdmin) ...[
                                      const SizedBox(height: 20),
                                      const Divider(color: Colors.white10),
                                      isGenerating
                                          ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: Colors.greenAccent))
                                          : SizedBox(
                                        width: double.infinity,
                                        child: TextButton.icon(
                                          icon: const Icon(Icons.play_circle_fill, color: Colors.greenAccent),
                                          label: const Text("FINALIZAR DRAFT E INICIAR LIGA", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                          onPressed: () => _showSupercopaSelectionAndStart(context),
                                        ),
                                      )
                                    ]
                                  ]
                                ],
                              ),
                            ),
                          ),
                        )
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Widgets Auxiliares Re-estilizados
class _TagBadgeV2 extends StatelessWidget {
  final String text;
  final Color color;
  const _TagBadgeV2({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3))
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}

class _ActionButtonV2 extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  const _ActionButtonV2({required this.text, required this.icon, required this.color, required this.textColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: Colors.white10,
        disabledForegroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: onTap == null ? 0 : 8,
        shadowColor: color.withOpacity(0.4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}