import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SquadBuilderScreen extends StatefulWidget {
  final String seasonId;
  final String userId;
  final bool isReadOnly; // Si es true, es modo "Ver Rival"

  const SquadBuilderScreen({
    super.key,
    required this.seasonId,
    required this.userId,
    this.isReadOnly = false,
  });

  @override
  State<SquadBuilderScreen> createState() => _SquadBuilderScreenState();
}

class _SquadBuilderScreenState extends State<SquadBuilderScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // --- FORMACIONES ---
  final Map<String, Map<String, Offset>> formations = {
    '4-3-3': {
      'GK': const Offset(0.50, 0.88),
      'LB': const Offset(0.15, 0.70), 'CB1': const Offset(0.38, 0.75), 'CB2': const Offset(0.62, 0.75), 'RB': const Offset(0.85, 0.70),
      'CM1': const Offset(0.50, 0.55), 'CM2': const Offset(0.30, 0.45), 'CM3': const Offset(0.70, 0.45),
      'LW': const Offset(0.15, 0.20), 'ST': const Offset(0.50, 0.12), 'RW': const Offset(0.85, 0.20),
    },
    '4-4-2': {
      'GK': const Offset(0.50, 0.88),
      'LB': const Offset(0.15, 0.70), 'CB1': const Offset(0.38, 0.75), 'CB2': const Offset(0.62, 0.75), 'RB': const Offset(0.85, 0.70),
      'LM': const Offset(0.15, 0.45), 'CM1': const Offset(0.38, 0.50), 'CM2': const Offset(0.62, 0.50), 'RM': const Offset(0.85, 0.45),
      'ST1': const Offset(0.35, 0.15), 'ST2': const Offset(0.65, 0.15),
    },
    '4-2-3-1': {
      'GK': const Offset(0.50, 0.88),
      'LB': const Offset(0.15, 0.70), 'CB1': const Offset(0.38, 0.75), 'CB2': const Offset(0.62, 0.75), 'RB': const Offset(0.85, 0.70),
      'DMF1': const Offset(0.35, 0.60), 'DMF2': const Offset(0.65, 0.60),
      'LMF': const Offset(0.15, 0.35), 'AMF': const Offset(0.50, 0.35), 'RMF': const Offset(0.85, 0.35),
      'ST': const Offset(0.50, 0.12),
    },
    '3-5-2': {
      'GK': const Offset(0.50, 0.88),
      'CB1': const Offset(0.25, 0.75), 'CB2': const Offset(0.50, 0.78), 'CB3': const Offset(0.75, 0.75),
      'DMF1': const Offset(0.40, 0.60), 'DMF2': const Offset(0.60, 0.60),
      'LMF': const Offset(0.10, 0.40), 'AMF': const Offset(0.50, 0.35), 'RMF': const Offset(0.90, 0.40),
      'ST1': const Offset(0.35, 0.15), 'ST2': const Offset(0.65, 0.15),
    },
    '5-3-2': {
      'GK': const Offset(0.50, 0.88),
      'LB': const Offset(0.10, 0.65), 'CB1': const Offset(0.30, 0.75), 'CB2': const Offset(0.50, 0.78), 'CB3': const Offset(0.70, 0.75), 'RB': const Offset(0.90, 0.65),
      'CM1': const Offset(0.35, 0.50), 'CM2': const Offset(0.50, 0.55), 'CM3': const Offset(0.65, 0.50),
      'ST1': const Offset(0.35, 0.15), 'ST2': const Offset(0.65, 0.15),
    },
  };

  String currentFormation = '4-3-3';
  Map<String, String?> lineup = {}; // { 'GK': 'player_id', ... }

  List<DocumentSnapshot> myFullRoster = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    // Inicializar lineup vacío
    _resetLineupSlots('4-3-3');
    _loadSquadData();
  }

  void _resetLineupSlots(String formationName) {
    var slots = formations[formationName]!.keys.toList();
    Map<String, String?> newLineup = {};
    // Mantener jugadores si la posición existe en la nueva formación
    for (var slot in slots) {
      newLineup[slot] = lineup[slot];
    }
    lineup = newLineup;
  }

  Future<void> _loadSquadData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(widget.userId)
          .get();

      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;

      if (data['selectedFormation'] != null) {
        currentFormation = data['selectedFormation'];
      }

      if (data['lineup'] != null) {
        Map<String, dynamic> savedLineup = data['lineup'];
        lineup = savedLineup.map((key, value) => MapEntry(key, value?.toString()));
        _resetLineupSlots(currentFormation);
      }

      List<dynamic> rosterIds = data['roster'] ?? [];
      if (rosterIds.isNotEmpty) {
        List<DocumentSnapshot> allDocs = [];
        List<String> stringIds = rosterIds.map((e) => e.toString()).toList();

        for (var i = 0; i < stringIds.length; i += 10) {
          var chunk = stringIds.sublist(i, (i + 10) < stringIds.length ? (i + 10) : stringIds.length);
          var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: chunk).get();
          allDocs.addAll(q.docs);
        }

        if(mounted) {
          setState(() {
            myFullRoster = allDocs;
            myFullRoster.sort((a, b) => (b['rating']??0).compareTo(a['rating']??0));
            isLoading = false;
          });
        }
      } else {
        if(mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      print("Error cargando squad: $e");
      if(mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveSquad() async {
    if (widget.isReadOnly) return;
    try {
      await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(widget.userId)
          .update({
        'lineup': lineup,
        'selectedFormation': currentFormation
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Táctica Guardada")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- LÓGICA DE OFERTAS ---
  Future<void> _checkMarketAndShowOffer(String targetPlayerId, Map<String, dynamic> targetData) async {
    DocumentSnapshot seasonDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();
    bool isMarketOpen = seasonDoc['marketOpen'] ?? true;

    if (!isMarketOpen) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("El mercado está CERRADO por el administrador."),
        backgroundColor: Colors.red,
      ));
      return;
    }
    _showMakeOfferDialog(targetPlayerId, targetData);
  }

  void _showMakeOfferDialog(String targetPlayerId, Map<String, dynamic> targetData) {
    TextEditingController moneyController = TextEditingController();
    Map<String, String>? selectedSwapPlayer;
    List<DocumentSnapshot> myOwnPlayers = [];
    bool loadingMyPlayers = true;

    showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              if (loadingMyPlayers) {
                _fetchAllMyPlayers().then((players) {
                  setDialogState(() {
                    myOwnPlayers = players;
                    loadingMyPlayers = false;
                  });
                });
              }

              return AlertDialog(
                backgroundColor: const Color(0xFF1B263B), // Fondo oscuro
                title: const Text("OFERTA DE TRASPASO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: _buildPlayerCircle(targetData, 45),
                        title: Text(targetData['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text("Media: ${targetData['rating']}", style: const TextStyle(color: Colors.white70)),
                      ),
                      const Divider(color: Colors.white24),
                      TextField(
                        controller: moneyController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                            labelText: "Oferta en Dinero",
                            prefixText: "\$ ",
                            filled: true,
                            fillColor: Colors.black26,
                            labelStyle: const TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("O intercambiar por:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 5),

                      if (loadingMyPlayers)
                        const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.white))
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1B263B),
                              hint: const Text("Seleccionar jugador...", style: TextStyle(color: Colors.white54)),
                              value: selectedSwapPlayer?['id'],
                              onChanged: (val) {
                                if (val != null) {
                                  var pDoc = myOwnPlayers.firstWhere((doc) => doc.id == val);
                                  setDialogState(() {
                                    selectedSwapPlayer = {
                                      'id': val,
                                      'name': pDoc['name']
                                    };
                                  });
                                }
                              },
                              items: myOwnPlayers.map((doc) {
                                var d = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem(
                                  value: doc.id,
                                  child: Text("${d['name']} (${d['rating']})", style: const TextStyle(color: Colors.white)),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
                  ElevatedButton(
                      onPressed: () async {
                        int offerAmount = int.tryParse(moneyController.text) ?? 0;
                        if (offerAmount == 0 && selectedSwapPlayer == null) {
                          return;
                        }

                        await FirebaseFirestore.instance
                            .collection('seasons').doc(widget.seasonId)
                            .collection('transfers').add({
                          'fromUserId': currentUserId,
                          'toUserId': widget.userId,
                          'targetPlayerId': targetPlayerId,
                          'targetPlayerName': targetData['name'],
                          'swapPlayerId': selectedSwapPlayer?['id'],
                          'swapPlayerName': selectedSwapPlayer?['name'],
                          'offeredAmount': offerAmount,
                          'status': 'PENDING',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Oferta enviada!")));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text("ENVIAR OFERTA", style: TextStyle(color: Colors.white))
                  )
                ],
              );
            },
          );
        }
    );
  }

  Future<List<DocumentSnapshot>> _fetchAllMyPlayers() async {
    var myDoc = await FirebaseFirestore.instance
        .collection('seasons').doc(widget.seasonId)
        .collection('participants').doc(currentUserId)
        .get();

    List rosterIds = myDoc.data()?['roster'] ?? [];
    if (rosterIds.isEmpty) return [];

    List<String> stringIds = rosterIds.map((e) => e.toString()).toList();
    List<DocumentSnapshot> allDocs = [];

    for (var i = 0; i < stringIds.length; i += 10) {
      var chunk = stringIds.sublist(i, (i + 10) < stringIds.length ? (i + 10) : stringIds.length);
      var q = await FirebaseFirestore.instance.collection('players').where(FieldPath.documentId, whereIn: chunk).get();
      allDocs.addAll(q.docs);
    }
    allDocs.sort((a,b) => (b['rating']??0).compareTo(a['rating']??0));
    return allDocs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "PIZARRA RIVAL" : "MI TÁCTICA", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: const Color(0xFF0D1B2A), // Azul Noche
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (!widget.isReadOnly)
            IconButton(icon: const Icon(Icons.save), onPressed: _saveSquad)
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // HEADER FORMACIÓN
          Container(
            color: const Color(0xFF1B263B),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("ESQUEMA TÁCTICO", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                if (!widget.isReadOnly)
                  DropdownButton<String>(
                    value: currentFormation,
                    dropdownColor: const Color(0xFF1B263B),
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                    underline: Container(),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.amber),
                    items: formations.keys.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          currentFormation = val;
                          _resetLineupSlots(val);
                        });
                      }
                    },
                  )
                else
                  Text(currentFormation, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
              ],
            ),
          ),

          if (widget.isReadOnly)
            Container(
                color: Colors.amber,
                width: double.infinity,
                padding: const EdgeInsets.all(5),
                child: const Text("TOCA UN JUGADOR PARA OFERTAR", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))
            ),

          // --- CANCHA (PITCH) ---
          Expanded(
            flex: 3,
            child: LayoutBuilder(
                builder: (context, constraints) {
                  var slots = formations[currentFormation]!;

                  return Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32),
                        image: DecorationImage(
                            image: NetworkImage("https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Soccer_Field_Transparant.svg/800px-Soccer_Field_Transparant.svg.png"),
                            fit: BoxFit.contain,
                            opacity: 0.6 // Un poco más visible
                        )
                    ),
                    child: Stack(
                      children: slots.keys.map((posKey) {
                        Offset relativePos = slots[posKey]!;
                        return Positioned(
                          left: relativePos.dx * constraints.maxWidth - 27.5,
                          top: relativePos.dy * constraints.maxHeight - 27.5,
                          child: _buildSlot(posKey, constraints),
                        );
                      }).toList(),
                    ),
                  );
                }
            ),
          ),

          // --- BANCA ---
          Container(
              color: const Color(0xFF0D1B2A),
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              child: const Text("BANQUILLO", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: const Color(0xFF101010), // Fondo negro suave
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: myFullRoster.length,
                itemBuilder: (context, index) {
                  final player = myFullRoster[index];
                  bool isUsed = lineup.containsValue(player.id);

                  if (isUsed && !widget.isReadOnly) return const SizedBox();

                  final data = player.data() as Map<String, dynamic>;
                  return GestureDetector(
                    onTap: () {
                      if (widget.isReadOnly) {
                        _checkMarketAndShowOffer(player.id, data);
                        return;
                      }
                    },
                    child: Opacity(
                      opacity: isUsed ? 0.3 : 1.0,
                      child: Container(
                        width: 70, margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            _buildPlayerCircle(data, 50),
                            const SizedBox(height: 4),
                            Text(data['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10)),
                            Text(data['position'], style: const TextStyle(color: Colors.grey, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSlot(String posKey, BoxConstraints constraints) {
    String? playerId = lineup[posKey];
    DocumentSnapshot? playerDoc;
    Map<String, dynamic>? pData;

    if (playerId != null) {
      try {
        playerDoc = myFullRoster.firstWhere((d) => d.id == playerId);
        pData = playerDoc.data() as Map<String, dynamic>;
      } catch (e) { }
    }

    return GestureDetector(
      onTap: () {
        if (widget.isReadOnly) {
          if (playerId != null && pData != null) _checkMarketAndShowOffer(playerId, pData);
          return;
        }
        _showPlayerSelector(posKey);
      },
      child: Column(
        children: [
          // Ficha de jugador
          Container(
            width: 55, height: 55,
            decoration: _getSlotDecoration(pData),
            child: (pData != null && pData['photoUrl'] != null && pData['photoUrl'] != "")
                ? ClipOval(child: Image.network(pData['photoUrl'], fit: BoxFit.cover))
                : Center(child: Text(pData != null ? "${pData['rating']}" : "", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
          ),

          // Etiqueta de Nombre
          if (pData != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24, width: 0.5)),
              child: Text(
                pData['name'].split(' ').last.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
          // Etiqueta de Posición vacía
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
              child: Text(posKey, style: const TextStyle(color: Colors.white, fontSize: 8)),
            )
        ],
      ),
    );
  }

  void _showPlayerSelector(String posKey) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A), // Fondo oscuro
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        var available = myFullRoster.where((doc) => !lineup.containsValue(doc.id)).toList();
        return Column(
          children: [
            const Padding(padding: EdgeInsets.all(15), child: Text("SELECCIONAR JUGADOR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1))),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.close, color: Colors.white)),
              title: const Text("Quitar Jugador", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                setState(() => lineup[posKey] = null);
                Navigator.pop(context);
              },
            ),
            Expanded(
              child: ListView.builder(
                itemCount: available.length,
                itemBuilder: (context, index) {
                  var p = available[index].data() as Map<String, dynamic>;
                  return ListTile(
                    leading: _buildPlayerCircle(p, 40),
                    title: Text(p['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("${p['position']} - Media: ${p['rating']}", style: const TextStyle(color: Colors.grey)),
                    onTap: () {
                      setState(() => lineup[posKey] = available[index].id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayerCircle(Map<String, dynamic> data, double size) {
    return Container(
      width: size, height: size,
      decoration: _getSlotDecoration(data),
      child: Center(child: Text(data['photoUrl'] == "" ? "${data['rating']}" : "", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
    );
  }

  BoxDecoration _getSlotDecoration(Map<String, dynamic>? player) {
    if (player == null) return BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: Colors.white24, style: BorderStyle.solid));

    int rating = player['rating'] ?? 75;
    String tier = player['tier'] ?? '';

    // Bordes más elaborados
    if (tier == 'LEYENDA') {
      return BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Colors.red, Colors.purple, Colors.orange], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.5), blurRadius: 10)]
      );
    }
    if (tier == 'PRIME') {
      return BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(color: Colors.cyanAccent, width: 2),
          boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.3), blurRadius: 8)]
      );
    }

    Color c = rating >= 90 ? Colors.black : (rating >= 85 ? const Color(0xFFD4AF37) : (rating >= 80 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32))); // Oro, Plata, Bronce
    Color borderC = rating >= 85 ? Colors.amberAccent : Colors.white54;

    return BoxDecoration(shape: BoxShape.circle, color: c, border: Border.all(color: borderC, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0,2))]);
  }
}