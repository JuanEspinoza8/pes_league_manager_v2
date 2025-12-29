import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'tabs/matches_tab.dart';
import 'tabs/standings_tab.dart';
import 'tabs/stats_tab.dart';
import 'tabs/market_tab.dart';
import 'squad_builder_screen.dart';
import 'transfers_screen.dart';
import 'notifications_screen.dart';
import 'my_team_screen.dart';
import 'available_players_screen.dart';
import '../services/season_generator_service.dart';
import '../services/champions_progression_service.dart';
import '../services/standings_service.dart';
import '../services/stats_service.dart';
import '../utils/debug_tools.dart';

class LeagueDashboardScreen extends StatefulWidget {
  final String seasonId;
  const LeagueDashboardScreen({super.key, required this.seasonId});

  @override
  State<LeagueDashboardScreen> createState() => _LeagueDashboardScreenState();
}

class _LeagueDashboardScreenState extends State<LeagueDashboardScreen> {
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

  // --- MENÚ DE HERRAMIENTAS (ADMIN Y CUENTA) ---
  void _showDebugMenu() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0D1B2A), builder: (c) {
      return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView( // Scroll por si hay muchas opciones
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // SECCIÓN 1: MI CUENTA (Para todos)
                const Text("MI CUENTA", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                const Divider(color: Colors.white24),
                _adminTile(Icons.vpn_key, "Cambiar Contraseña", Colors.white, () {
                  Navigator.pop(c);
                  _showChangePasswordDialog();
                }),
                const SizedBox(height: 20),

                // SECCIÓN 2: HERRAMIENTAS ADMIN (Solo si es Admin)
                if (isAdmin) ...[
                  const Text("HERRAMIENTAS ADMIN", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                  const Divider(color: Colors.white24),

                  // 1. Simulación y Estructura
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

                  // 2. Mantenimiento
                  _adminTile(Icons.refresh, "Recalcular Tablas y Stats", Colors.cyanAccent, () async {
                    Navigator.pop(c);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sincronizando toda la liga...")));
                    await StandingsService().recalculateLeagueStandings(widget.seasonId);
                    await StandingsService().recalculateChampionsStandings(widget.seasonId);
                    await StatsService().recalculateTeamStats(widget.seasonId);
                    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Sincronización completada!"), backgroundColor: Colors.green));
                  }),

                  // 3. Gestión de Jugadores
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

  // --- NUEVO: DIÁLOGO CAMBIO DE CONTRASEÑA ---
  void _showChangePasswordDialog() {
    final TextEditingController passCtrl = TextEditingController();

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Cambiar Contraseña"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Esto cambiará la clave actual y cerrará el acceso al dueño anterior.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 15),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                      labelText: "Nueva Contraseña",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock)
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
              ElevatedButton(
                  onPressed: () async {
                    if (passCtrl.text.trim().length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mínimo 6 caracteres"), backgroundColor: Colors.red));
                      return;
                    }
                    try {
                      await FirebaseAuth.instance.currentUser?.updatePassword(passCtrl.text.trim());
                      if(mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Contraseña actualizada con éxito!"), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e. Intenta cerrar sesión y volver a entrar."), backgroundColor: Colors.red));
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
      title: const Text("Simular Jornada"),
      content: TextField(controller: roundCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Número de Ronda", border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancelar")),
        ElevatedButton(onPressed: () async {
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
              title: const Text("Asignar Jugador a Dedo"),
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
                        hint: const Text("Selecciona el Equipo Destino"),
                        value: selectedUserId,
                        items: items,
                        onChanged: (val) => setStateDialog(() => selectedUserId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: playerController,
                    decoration: const InputDecoration(labelText: "ID del Jugador (ej: messi)", border: OutlineInputBorder()),
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
                  child: const Text("ENVIAR REGALO"),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _showRigPackDialog() {
    String? selectedUserId;
    String? selectedPlayerId;
    String selectedPlayerName = "Ninguno seleccionado";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1B263B),
              title: const Text("🎰 PROGRAMAR DESTINO", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Elige a la víctima y busca el jugador.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 15),

                  // 1. VÍCTIMA
                  const Text("VÍCTIMA:", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      var items = snapshot.data!.docs.map((doc) {
                        return DropdownMenuItem(value: doc.id, child: Text(doc['teamName'], style: const TextStyle(color: Colors.black)));
                      }).toList();

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          hint: const Text("Selecciona Usuario"),
                          value: selectedUserId,
                          items: items,
                          onChanged: (val) => setStateDialog(() => selectedUserId = val),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 2. BUSCADOR VISUAL
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
      backgroundColor: const Color(0xFF0D1B2A),
      builder: (context) {
        return Padding(padding: EdgeInsets.only(top: 40, bottom: MediaQuery.of(context).viewInsets.bottom), child: const _PlayerSearchWidget());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String budgetStr = "\$${(myBudget / 1000000).toStringAsFixed(1)}M";

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(myTeamName.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text(budgetStr, style: const TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.w500)),
            ],
          ),
          backgroundColor: const Color(0xFF0D1B2A),
          elevation: 0,
          foregroundColor: Colors.white,

          actions: [
            // BOTÓN MERCADO (Solo Admin)
            if (isAdmin) IconButton(icon: Icon(isMarketOpen ? Icons.lock_open : Icons.lock, color: isMarketOpen ? Colors.greenAccent : Colors.redAccent), onPressed: _toggleMarket, tooltip: "Abrir/Cerrar Mercado"),

            // BOTÓN HERRAMIENTAS (Visible para TODOS ahora, dentro filtra qué mostrar)
            IconButton(icon: const Icon(Icons.settings, color: Colors.white54), onPressed: _showDebugMenu, tooltip: "Ajustes y Admin"),

            IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(seasonId: widget.seasonId)))),
            IconButton(icon: const Icon(Icons.compare_arrows), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransfersScreen(seasonId: widget.seasonId)))),

            Padding(
              padding: const EdgeInsets.only(right: 10, left: 5),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyTeamScreen(seasonId: widget.seasonId, userId: currentUserId))),
                child: const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.shield, color: Color(0xFF0D1B2A), size: 20)),
              ),
            )
          ],

          bottom: const TabBar(
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.amber,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              tabs: [
                Tab(icon: Icon(Icons.calendar_month), text: "FIXTURE"),
                Tab(icon: Icon(Icons.format_list_numbered), text: "TABLA"),
                Tab(icon: Icon(Icons.bar_chart), text: "STATS"),
                Tab(icon: Icon(Icons.storefront), text: "MERCADO"),
              ]
          ),
        ),

        body: Container(
          color: const Color(0xFFF0F2F5),
          child: TabBarView(
            children: [
              MatchesTab(seasonId: widget.seasonId, isAdmin: isAdmin),
              StandingsTab(seasonId: widget.seasonId),
              StatsTab(seasonId: widget.seasonId),
              MarketTab(seasonId: widget.seasonId, isMarketOpen: isMarketOpen, currentUserId: currentUserId),
            ],
          ),
        ),
      ),
    );
  }
}

// --- WIDGET DE BÚSQUEDA DE JUGADORES ---
class _PlayerSearchWidget extends StatefulWidget {
  const _PlayerSearchWidget();

  @override
  State<_PlayerSearchWidget> createState() => _PlayerSearchWidgetState();
}

class _PlayerSearchWidgetState extends State<_PlayerSearchWidget> {
  List<DocumentSnapshot> allPlayers = [];
  List<DocumentSnapshot> filtered = [];
  bool loading = true;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Carga ligera: solo los primeros 500 para no saturar si hay muchos
    var q = await FirebaseFirestore.instance.collection('players').orderBy('rating', descending: true).limit(500).get();
    if(mounted) {
      setState(() {
        allPlayers = q.docs;
        filtered = q.docs;
        loading = false;
      });
    }
  }

  void _filter(String text) {
    setState(() {
      if (text.isEmpty) {
        filtered = allPlayers;
      } else {
        filtered = allPlayers.where((d) => d['name'].toString().toLowerCase().contains(text.toLowerCase())).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Escribe nombre (ej: Messi)...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.amber),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: _filter,
          ),
        ),
        SizedBox(
          height: 400,
          child: loading
              ? const Center(child: CircularProgressIndicator(color: Colors.amber))
              : ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              var data = filtered[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[800],
                  child: Text("${data['rating']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                title: Text(data['name'], style: const TextStyle(color: Colors.white)),
                subtitle: Text("${data['position']} • ${data['team']}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context, {
                    'id': filtered[index].id,
                    'name': data['name'],
                    'rating': data['rating']
                  });
                },
              );
            },
          ),
        )
      ],
    );
  }
}