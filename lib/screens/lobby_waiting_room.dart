import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool isGenerating = false;

  // --- NUEVA LÓGICA DE INICIO: SELECCIÓN DE SUPERCOPA ---
  void _showSupercopaSelectionAndStart(BuildContext context) {
    List<String> selectedIds = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("🏆 Supercopa: Elige 4"),
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
                          title: Text(name),
                          value: isSelected,
                          activeColor: Colors.amber,
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
                Text("Seleccionados: ${selectedIds.length}/4", style: TextStyle(color: selectedIds.length == 4 ? Colors.green : Colors.red)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR"),
                ),
                ElevatedButton(
                  onPressed: selectedIds.length == 4
                      ? () {
                    Navigator.pop(context); // Cerrar diálogo
                    _handleStartSeason(selectedIds); // Iniciar con los seleccionados
                  }
                      : null, // Deshabilitado si no son 4
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D1B2A), foregroundColor: Colors.white),
                  child: const Text("CONFIRMAR E INICIAR"),
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
      // Pasamos los IDs seleccionados al generador
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
        backgroundColor: const Color(0xFF0D1B2A),
        builder: (c) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("HERRAMIENTAS ADMIN", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
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

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Fondo oscuro
      appBar: AppBar(
        title: const Text("VESTUARIO", style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
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
                  const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
                  const SizedBox(height: 20),
                  const Text("¡LA LIGA HA COMENZADO!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black
                    ),
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LeagueDashboardScreen(seasonId: widget.seasonId))),
                    child: const Text("IR AL CAMPO DE JUEGO", style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          }

          return Column(
            children: [
              // --- HEADER CÓDIGO ---
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue[900]!, Colors.blue[800]!]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0,5))],
                    border: Border.all(color: Colors.white10)
                ),
                child: Column(
                  children: [
                    Text("CÓDIGO DE ACCESO", style: TextStyle(color: Colors.blue[100], fontSize: 12, letterSpacing: 1.5)),
                    const SizedBox(height: 5),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado al portapapeles")));
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(code, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 8)),
                          const SizedBox(width: 10),
                          const Icon(Icons.copy, color: Colors.white54, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TagBadge(text: status == 'WAITING' ? 'EN ESPERA' : 'DRAFT ACTIVO', color: status == 'WAITING' ? Colors.orange : Colors.green),
                        const SizedBox(width: 10),
                        _TagBadge(text: acquisitionMode == 'AUCTION' ? 'SUBASTA' : 'SOBRES', color: Colors.purple),
                      ],
                    )
                  ],
                ),
              ),

              // --- LISTA DE PARTICIPANTES ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("DTs CONECTADOS", style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("${participants.length} / $maxPlayers", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
                  builder: (context, participantsSnap) {
                    if (!participantsSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white10));

                    var docs = participantsSnap.data!.docs;

                    // BUSCAR MI USUARIO PARA VERIFICAR SI YA TENGO EQUIPO
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
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                    color: isMe ? Colors.white.withOpacity(0.1) : Colors.black26,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isMe ? Border.all(color: Colors.amber.withOpacity(0.3)) : null
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isBot ? Colors.grey[700] : (isAdminUser ? Colors.amber : Colors.blue),
                                    child: Icon(isBot ? Icons.smart_toy : (isAdminUser ? Icons.star : Icons.person), color: Colors.white, size: 20),
                                  ),
                                  title: Text(data['teamName'], style: TextStyle(color: Colors.white, fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
                                  trailing: isFull
                                      ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                                      : const Icon(Icons.timelapse, color: Colors.grey),
                                ),
                              );
                            },
                          ),
                        ),

                        // --- ÁREA DE ACCIONES (PANEL INFERIOR BLANCO) ---
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(30))
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. SI ESTÁ EN ESPERA (Solo Admin inicia)
                              if (status == 'WAITING') ...[
                                if (isAdmin)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: () => FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({'status': 'DRAFT_PHASE'}),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D1B2A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                      child: const Text("INICIAR FASE DE DRAFT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  )
                                else
                                  const Text("Esperando que el administrador inicie el draft...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),

                                if (isAdmin) ...[
                                  const SizedBox(height: 10),
                                  TextButton.icon(onPressed: _showDebugMenu, icon: const Icon(Icons.settings), label: const Text("Opciones de Admin"))
                                ]
                              ],

                              // 2. FASE DE DRAFT (Acciones de usuario)
                              if (status == 'DRAFT_PHASE' || status == 'AUCTION') ...[
                                if (acquisitionMode == 'AUCTION')
                                // --- CORRECCIÓN: SOLO BOTÓN DE SUBASTA ---
                                  SizedBox(
                                    width: double.infinity,
                                    child: _ActionButton(
                                        text: "ENTRAR A LA SUBASTA",
                                        icon: Icons.gavel,
                                        color: Colors.amber[800]!,
                                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionRoom(seasonId: widget.seasonId, isAdmin: isAdmin)))
                                    ),
                                  )
                                else
                                // Modo Sobres (Mantenemos igual)
                                  SizedBox(
                                    width: double.infinity,
                                    child: _ActionButton(
                                        text: iHaveTeam ? "SOBRE YA ABIERTO" : "ABRIR SOBRE INICIAL",
                                        icon: iHaveTeam ? Icons.check : Icons.flash_on,
                                        color: iHaveTeam ? Colors.grey : Colors.blue[800]!,
                                        onTap: iHaveTeam ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackOpener(seasonId: widget.seasonId)))
                                    ),
                                  ),

                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: currentUserId))),
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), side: const BorderSide(color: Color(0xFF0D1B2A))),
                                    child: const Text("VER MI PLANTILLA", style: TextStyle(color: Color(0xFF0D1B2A), fontWeight: FontWeight.bold)),
                                  ),
                                ),

                                // 3. ADMIN: INICIAR LIGA
                                if (isAdmin) ...[
                                  const SizedBox(height: 15),
                                  const Divider(),
                                  isGenerating
                                      ? const CircularProgressIndicator()
                                      : SizedBox(
                                    width: double.infinity,
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                                      label: const Text("FINALIZAR DRAFT E INICIAR LIGA", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      onPressed: () => _showSupercopaSelectionAndStart(context),
                                    ),
                                  )
                                ]
                              ]
                            ],
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

class _TagBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _TagBadge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton({required this.text, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: Colors.grey[300],
        disabledForegroundColor: Colors.grey[600],
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: onTap == null ? 0 : 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}