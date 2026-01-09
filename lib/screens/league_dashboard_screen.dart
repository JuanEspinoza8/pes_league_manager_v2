import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'tabs/matches_tab.dart';
import 'tabs/standings_tab.dart';
import 'tabs/stats_tab.dart';
import 'tabs/market_tab.dart';
import 'tabs/news_tab.dart';
import 'squad_builder_screen.dart';
import 'transfers_screen.dart';
import 'notifications_screen.dart';
import 'my_team_screen.dart';
import 'available_players_screen.dart';
import 'rivalry_manager_screen.dart';
import 'custom_news_screen.dart';
import '../services/season_generator_service.dart';
import '../services/champions_progression_service.dart';
import '../services/standings_service.dart';
import '../services/stats_service.dart';
import '../utils/debug_tools.dart';
import 'custom_news_screen.dart';

class LeagueDashboardScreen extends StatefulWidget {
  final String seasonId;
  const LeagueDashboardScreen({super.key, required this.seasonId});

  @override
  State<LeagueDashboardScreen> createState() => _LeagueDashboardScreenState();
}

class _LeagueDashboardScreenState extends State<LeagueDashboardScreen> {
  // --- LÓGICA INTACTA ---
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  bool isAdmin = false;
  bool isMarketOpen = true;
  String myTeamName = "Cargando...";
  int myBudget = 0;

  @override
  void initState() {
    super.initState();
    _checkAdminAndMarket();
    _loadMyTeamInfo();
  }

  void _checkAdminAndMarket() {
    FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots().listen((doc) {
      if (!doc.exists) return;
      var data = doc.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          isAdmin = (data['adminId'] == currentUserId);
          isMarketOpen = data['marketOpen'] ?? true;
        });
      }
    });
  }

  void _loadMyTeamInfo() {
    FirebaseFirestore.instance
        .collection('seasons').doc(widget.seasonId)
        .collection('participants').doc(currentUserId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      var data = doc.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          myTeamName = data['teamName'] ?? "Mi Equipo";
          myBudget = data['budget'] ?? 0;
        });
      }
    });
  }

  Future<void> _toggleMarket() async {
    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({'marketOpen': !isMarketOpen});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!isMarketOpen ? "Mercado ABIERTO" : "Mercado CERRADO"), backgroundColor: !isMarketOpen ? Colors.green : Colors.red));
  }

  void _showManagerAppearanceList() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Editar Apariencia de DTs", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  var data = docs[i].data() as Map<String, dynamic>;
                  String teamName = data['teamName'];
                  String desc = data['managerDescription'] ?? "No definida";

                  return ListTile(
                    title: Text(teamName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.edit, color: Colors.blue),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditManagerDescriptionDialog(docs[i].id, teamName, desc == "No definida" ? "" : desc);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar"))],
      ),
    );
  }

  void _showEditManagerDescriptionDialog(String userId, String teamName, String currentDesc) {
    TextEditingController _ctrl = TextEditingController(text: currentDesc);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text("DT de $teamName", style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Describe físicamente a tu amigo para que la IA lo dibuje.", style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  hintText: "Ej: Rubio, gafas de sol, traje negro...",
                  hintStyle: TextStyle(color: Colors.white30),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.black26
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('seasons').doc(widget.seasonId)
                  .collection('participants').doc(userId)
                  .update({'managerDescription': _ctrl.text.trim()});

              if(mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Apariencia de $teamName guardada")));
                _showManagerAppearanceList();
              }
            },
            child: const Text("GUARDAR"),
          )
        ],
      ),
    );
  }

  void _showDebugMenu() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F172A), builder: (c) {
      return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("MI CUENTA", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                const Divider(color: Colors.white24),
                _adminTile(Icons.vpn_key, "Cambiar Contraseña", Colors.white, () {
                  Navigator.pop(c);
                  _showChangePasswordDialog();
                }),
                const SizedBox(height: 20),

                if (isAdmin) ...[
                  const Text("HERRAMIENTAS ADMIN", style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 14)),
                  const Divider(color: Colors.white24),

                  _adminTile(Icons.fast_forward, "Simular Fecha", Colors.greenAccent, () { Navigator.pop(c); _showSimulationDialog(); }),
                  _adminTile(Icons.emoji_events, "Forzar Llaves Copa", Colors.orangeAccent, () async {
                    Navigator.pop(c);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generando Copa...")));
                    await SeasonGeneratorService().fillCupBracketFromStandings(widget.seasonId);
                  }),
                  _adminTile(Icons.star, "Forzar Playoffs UCL", Colors.purpleAccent, () async {
                    Navigator.pop(c);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verificando grupos...")));
                    await ChampionsProgressionService().checkGroupStageEnd(widget.seasonId);
                  }),
                  _adminTile(Icons.flash_on, "GESTIONAR CLÁSICOS", Colors.redAccent, () {
                    Navigator.pop(c);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RivalryManagerScreen(seasonId: widget.seasonId)));
                  }),
                  _adminTile(Icons.face, "EDITAR APARIENCIAS DT", Colors.cyanAccent, () {
                    Navigator.pop(c);
                    _showManagerAppearanceList();
                  }),
                  _adminTile(Icons.newspaper, "REDACTAR NOTICIA OFICIAL", Colors.blueAccent, () {
                    Navigator.pop(c);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomNewsScreen(seasonId: widget.seasonId)));
                  }),
                  _adminTile(Icons.refresh, "Recalcular Tablas y Stats", Colors.grey, () async {
                    Navigator.pop(c);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sincronizando toda la liga...")));
                    await StandingsService().recalculateLeagueStandings(widget.seasonId);
                    await StandingsService().recalculateChampionsStandings(widget.seasonId);
                    await StatsService().recalculateTeamStats(widget.seasonId);
                    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Sincronización completada!"), backgroundColor: Colors.green));
                  }),
                  _adminTile(Icons.card_giftcard, "REGALAR JUGADOR (Directo)", Colors.pinkAccent, () {
                    Navigator.pop(c);
                    _showGiftPlayerDialog();
                  }),
                  _adminTile(Icons.casino, "PROGRAMAR SOBRE (Trampa)", Colors.redAccent, () {
                    Navigator.pop(c);
                    _showRigPackDialog();
                  }),
                  _adminTile(Icons.list_alt, "VER JUGADORES LIBRES", Colors.tealAccent, () {
                    Navigator.pop(c);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AvailablePlayersScreen(seasonId: widget.seasonId)));
                  }),
                ]
              ],
            ),
          )
      );
    });
  }

  Widget _adminTile(IconData icon, String text, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  void _showChangePasswordDialog() {
    final TextEditingController passCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text("Cambiar Contraseña", style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Esto cambiará la clave actual.", style: TextStyle(fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 15),
                TextField(
                  controller: passCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: "Nueva Contraseña",
                      labelStyle: TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      prefixIcon: Icon(Icons.lock, color: Colors.white54)
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                  onPressed: () async {
                    if (passCtrl.text.trim().length < 6) return;
                    try {
                      await FirebaseAuth.instance.currentUser?.updatePassword(passCtrl.text.trim());
                      if(mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Contraseña actualizada!"), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text("CONFIRMAR")
              )
            ],
          );
        }
    );
  }

  void _showSimulationDialog() {
    final TextEditingController roundCtrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text("Simular Jornada", style: TextStyle(color: Colors.white)),
      content: TextField(
          controller: roundCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              labelText: "Número de Ronda",
              labelStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))
          )
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancelar")),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              int r = int.tryParse(roundCtrl.text) ?? 0;
              Navigator.pop(c);
              if (r > 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Simulando...")));
                await DebugTools().simulateRound(widget.seasonId, r);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Simulación completada!")));
              }
            }, child: const Text("Simular"))
      ],
    ));
  }

  void _showGiftPlayerDialog() {

    final TextEditingController playerController = TextEditingController();
    String? selectedUserId;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text("Regalar Jugador", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      var items = snapshot.data!.docs.map((doc) {
                        return DropdownMenuItem(value: doc.id, child: Text(doc['teamName'], overflow: TextOverflow.ellipsis));
                      }).toList();

                      return DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white),
                        hint: const Text("Selecciona Equipo", style: TextStyle(color: Colors.white54)),
                        value: selectedUserId,
                        items: items,
                        onChanged: (val) => setStateDialog(() => selectedUserId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: playerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: "ID del Jugador", labelStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedUserId == null || playerController.text.isEmpty) return;
                    String playerId = playerController.text.trim();
                    final db = FirebaseFirestore.instance;
                    final seasonRef = db.collection('seasons').doc(widget.seasonId);
                    try {
                      await db.runTransaction((transaction) async {
                        transaction.update(seasonRef.collection('participants').doc(selectedUserId), {'roster': FieldValue.arrayUnion([playerId])});
                        transaction.update(seasonRef, {'takenPlayerIds': FieldValue.arrayUnion([playerId])});
                      });
                      if(mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Regalo enviado!"), backgroundColor: Colors.green)); }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text("ENVIAR"),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _showRigPackDialog() {
    // (Similar actualización de colores al diálogo anterior si se desea, omitido por brevedad para enfocar en el Dashboard principal)
    // ... Lógica Original ...
    // Solo actualizo el background del AlertDialog a 0xFF1E293B y textos a blanco.
    String? selectedUserId;
    String? selectedPlayerId;
    String selectedPlayerName = "Ninguno seleccionado";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text("🎰 PROGRAMAR DESTINO", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Elige a la víctima y busca el jugador.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 15),
                  const Text("VÍCTIMA:", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      var items = snapshot.data!.docs.map((doc) {
                        return DropdownMenuItem(value: doc.id, child: Text(doc['teamName'], style: const TextStyle(color: Colors.white)));
                      }).toList();

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(5)),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          dropdownColor: const Color(0xFF0F172A),
                          hint: const Text("Selecciona Usuario", style: TextStyle(color: Colors.white54)),
                          value: selectedUserId,
                          items: items,
                          onChanged: (val) => setStateDialog(() => selectedUserId = val),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text("CARTA A ENTREGAR:", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: () async {
                      var result = await _openPlayerPicker(context);
                      if (result != null) {
                        setStateDialog(() {
                          selectedPlayerId = result['id'];
                          selectedPlayerName = "${result['name']} (${result['rating']})";
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: selectedPlayerId != null ? Colors.green : Colors.white24)),
                      child: Row(
                        children: [
                          Icon(selectedPlayerId != null ? Icons.check_circle : Icons.search, color: selectedPlayerId != null ? Colors.green : Colors.white),
                          const SizedBox(width: 10),
                          Expanded(child: Text(selectedPlayerName, style: TextStyle(color: Colors.white, fontWeight: selectedPlayerId != null ? FontWeight.bold : FontWeight.normal))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () async {
                    if (selectedUserId == null || selectedPlayerId == null) return;
                    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(selectedUserId).update({'rigged_next_pack': selectedPlayerId});
                    if(mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("¡Trampa lista para $selectedPlayerName!"), backgroundColor: Colors.green)); }
                  },
                  child: const Text("ACTIVAR TRAMPA"),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _openPlayerPicker(BuildContext context) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1120),
      builder: (context) {
        return Padding(padding: EdgeInsets.only(top: 40, bottom: MediaQuery.of(context).viewInsets.bottom), child: const _PlayerSearchWidget());
      },
    );
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    String budgetStr = "\$${(myBudget / 1000000).toStringAsFixed(1)}M";
    final goldColor = const Color(0xFFD4AF37);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1120),
        appBar: AppBar(
          toolbarHeight: 80, // Más alto para mejor layout
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(myTeamName.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.withOpacity(0.5))
                ),
                child: Text(budgetStr, style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          elevation: 0,
          shadowColor: Colors.black,

          actions: [
            // Iconos de acción más limpios
            if (isAdmin)
              IconButton(icon: Icon(isMarketOpen ? Icons.lock_open : Icons.lock, color: isMarketOpen ? Colors.greenAccent : Colors.redAccent), onPressed: _toggleMarket),
            IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white54), onPressed: _showDebugMenu),
            IconButton(icon: const Icon(Icons.notifications_none_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(seasonId: widget.seasonId)))),
            IconButton(icon: const Icon(Icons.compare_arrows_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransfersScreen(seasonId: widget.seasonId)))),

            Padding(
              padding: const EdgeInsets.only(right: 16, left: 8),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: currentUserId))),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: goldColor, width: 2)),
                  child: const CircleAvatar(backgroundColor: Color(0xFF0D1B2A), radius: 16, child: Icon(Icons.shield, color: Colors.white, size: 18)),
                ),
              ),
            )
          ],

          bottom: TabBar(
              isScrollable: true,
              labelColor: goldColor,
              unselectedLabelColor: Colors.white38,
              indicatorColor: goldColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
              tabs: const [
                Tab(text: "NOTICIAS"), // Eliminamos iconos para un look más limpio y editorial
                Tab(text: "FIXTURE"),
                Tab(text: "TABLA"),
                Tab(text: "STATS"),
                Tab(text: "MERCADO"),
              ]
          ),
        ),

        body: TabBarView(
          children: [
            NewsTab(seasonId: widget.seasonId),
            MatchesTab(seasonId: widget.seasonId, isAdmin: isAdmin),
            StandingsTab(seasonId: widget.seasonId),
            StatsTab(seasonId: widget.seasonId),
            MarketTab(seasonId: widget.seasonId, isMarketOpen: isMarketOpen, currentUserId: currentUserId),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET DE BÚSQUEDA REDISEÑADO ---
class _PlayerSearchWidget extends StatefulWidget {
  const _PlayerSearchWidget();
  @override State<_PlayerSearchWidget> createState() => _PlayerSearchWidgetState();
}

class _PlayerSearchWidgetState extends State<_PlayerSearchWidget> {
  // Lógica intacta
  List<DocumentSnapshot> allPlayers = [];
  List<DocumentSnapshot> filtered = [];
  bool loading = true;
  final TextEditingController _ctrl = TextEditingController();

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    var q = await FirebaseFirestore.instance.collection('players').orderBy('rating', descending: true).limit(500).get();
    if(mounted) { setState(() { allPlayers = q.docs; filtered = q.docs; loading = false; }); }
  }

  void _filter(String text) {
    setState(() {
      if (text.isEmpty) { filtered = allPlayers; }
      else { filtered = allPlayers.where((d) => d['name'].toString().toLowerCase().contains(text.toLowerCase())).toList(); }
    });
  }

  @override Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
          padding: const EdgeInsets.all(20.0),
          child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                  hintText: "Buscar jugador...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(20)
              ),
              onChanged: _filter
          )
      ),
      SizedBox(
          height: 400,
          child: loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                var data = filtered[index].data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10)
                  ),
                  child: ListTile(
                      leading: Container(
                          width: 40, height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24)
                          ),
                          child: Text("${data['rating']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))
                      ),
                      title: Text(data['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text("${data['position']} • ${data['team']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () { Navigator.pop(context, {'id': filtered[index].id, 'name': data['name'], 'rating': data['rating']}); }
                  ),
                );
              }
          )
      )
    ]);
  }
}