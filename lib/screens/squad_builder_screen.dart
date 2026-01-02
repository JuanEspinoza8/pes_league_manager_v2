import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:ui'; // Para efectos visuales

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
  // --- LÓGICA INTACTA ---
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

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
  Map<String, String?> lineup = {};

  List<DocumentSnapshot> myFullRoster = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _resetLineupSlots('4-3-3');
    _loadSquadData();
  }

  void _resetLineupSlots(String formationName) {
    var slots = formations[formationName]!.keys.toList();
    Map<String, String?> newLineup = {};
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

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Táctica Guardada"), backgroundColor: Color(0xFFD4AF37)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

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
                backgroundColor: const Color(0xFF1E293B), // Slate 800
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                title: const Text("OFERTA DE TRASPASO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _buildPlayerCircle(targetData, 50),
                        title: Text(targetData['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text("Media: ${targetData['rating']}", style: const TextStyle(color: Colors.white70)),
                      ),
                      const Divider(color: Colors.white24, height: 30),
                      TextField(
                        controller: moneyController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        decoration: InputDecoration(
                            labelText: "Oferta en Dinero",
                            prefixText: "\$ ",
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            labelStyle: const TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            prefixStyle: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 18)
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("O intercambiar por:", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),

                      if (loadingMyPlayers)
                        const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: const Color(0xFF0F172A),
                              hint: const Text("Seleccionar jugador...", style: TextStyle(color: Colors.white54)),
                              value: selectedSwapPlayer?['id'],
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFD4AF37)),
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
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Oferta enviada!"), backgroundColor: Colors.green));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                      child: const Text("ENVIAR OFERTA", style: TextStyle(fontWeight: FontWeight.bold))
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
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: Text(widget.isReadOnly ? "PIZARRA RIVAL" : "MI ESTRATEGIA", style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          if (!widget.isReadOnly)
            IconButton(icon: const Icon(Icons.save_rounded, color: goldColor), onPressed: _saveSquad, tooltip: "Guardar Táctica")
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: goldColor))
          : Column(
        children: [
          // HEADER FORMACIÓN (Selector Estilizado)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.grid_view_rounded, color: Colors.white54, size: 18),
                    SizedBox(width: 8),
                    Text("ESQUEMA TÁCTICO", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ],
                ),
                if (!widget.isReadOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: goldColor.withOpacity(0.3))
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: currentFormation,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: goldColor, fontWeight: FontWeight.bold, fontSize: 14),
                        icon: const Icon(Icons.arrow_drop_down, color: goldColor),
                        items: formations.keys.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              currentFormation = val;
                              _resetLineupSlots(val);
                            });
                          }
                        },
                      ),
                    ),
                  )
                else
                  Text(currentFormation, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
              ],
            ),
          ),

          if (widget.isReadOnly)
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [goldColor.withOpacity(0.8), goldColor])
                ),
                child: const Text("TOCA UN JUGADOR PARA OFERTAR", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.black, letterSpacing: 1))
            ),

          // --- CANCHA (PITCH) ---
          Expanded(
            flex: 3,
            child: LayoutBuilder(
                builder: (context, constraints) {
                  var slots = formations[currentFormation]!;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32), // Verde césped base
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5))
                        ],
                        image: const DecorationImage(
                            image: NetworkImage("https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/Soccer_Field_Transparant.svg/800px-Soccer_Field_Transparant.svg.png"),
                            fit: BoxFit.contain,
                            opacity: 0.8
                        ),
                        border: Border.all(color: Colors.white10, width: 4)
                    ),
                    child: Stack(
                      children: slots.keys.map((posKey) {
                        Offset relativePos = slots[posKey]!;
                        // Ajustamos ligeramente las posiciones para que centren bien en el contenedor
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

          // --- BANCA (GLASS PANEL) ---
          ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.white.withOpacity(0.05),
                child: Column(
                  children: [
                    Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        width: double.infinity,
                        color: Colors.black26,
                        child: const Text("BANQUILLO DE SUPLENTES", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5))
                    ),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
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
                                width: 70,
                                margin: const EdgeInsets.only(right: 8),
                                child: Column(
                                  children: [
                                    _buildPlayerCircle(data, 45),
                                    const SizedBox(height: 6),
                                    Text(data['name'], maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    Text(data['position'], style: const TextStyle(color: Colors.white54, fontSize: 9)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
          // Ficha de jugador (Círculo)
          Container(
            width: 55, height: 55,
            decoration: _getSlotDecoration(pData),
            child: (pData != null && pData['photoUrl'] != null && pData['photoUrl'] != "")
                ? ClipOval(child: Image.network(pData['photoUrl'], fit: BoxFit.cover))
                : Center(child: Text(pData != null ? "${pData['rating']}" : "", style: TextStyle(color: _getTextColorForRating(pData), fontWeight: FontWeight.w900, fontSize: 16))),
          ),

          // Etiqueta de Nombre
          if (pData != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.5),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)]
              ),
              child: Text(
                pData['name'].split(' ').last.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
          // Etiqueta de Posición vacía
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
              child: Text(posKey, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }

  void _showPlayerSelector(String posKey) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true, // Para mejor altura
      builder: (context) {
        var available = myFullRoster.where((doc) => !lineup.containsValue(doc.id)).toList();
        return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.8,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Center(child: Container(margin: const EdgeInsets.only(top: 10), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const Padding(padding: EdgeInsets.all(20), child: Text("SELECCIONAR JUGADOR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2))),
                  ListTile(
                    leading: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 16)),
                    title: const Text("QUITAR JUGADOR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    onTap: () {
                      setState(() => lineup[posKey] = null);
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: available.length,
                      itemBuilder: (context, index) {
                        var p = available[index].data() as Map<String, dynamic>;
                        return Container(
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
                          child: ListTile(
                            leading: _buildPlayerCircle(p, 45),
                            title: Text(p['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text("${p['position']} • Media: ${p['rating']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: const Icon(Icons.add_circle_outline, color: Color(0xFFD4AF37)),
                            onTap: () {
                              setState(() => lineup[posKey] = available[index].id);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  Widget _buildPlayerCircle(Map<String, dynamic> data, double size) {
    return Container(
      width: size, height: size,
      decoration: _getSlotDecoration(data),
      child: Center(child: Text(data['photoUrl'] == "" ? "${data['rating']}" : "", style: TextStyle(color: _getTextColorForRating(data), fontWeight: FontWeight.w900, fontSize: size * 0.4))),
    );
  }

  Color _getTextColorForRating(Map<String, dynamic>? player) {
    if (player == null) return Colors.white;
    int rating = player['rating'] ?? 75;
    if (rating >= 85) return Colors.black; // Gold & Black balls text should be black or dark
    return Colors.white;
  }

  BoxDecoration _getSlotDecoration(Map<String, dynamic>? player) {
    if (player == null) return BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: Colors.white12, width: 2, style: BorderStyle.solid));

    int rating = player['rating'] ?? 75;
    String tier = player['tier'] ?? '';

    // LEYENDA (Gradiente Místico)
    if (tier == 'LEYENDA') {
      return BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFDAA520)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 10)]
      );
    }
    // PRIME (Negro y Neón)
    if (tier == 'PRIME') {
      return BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(color: Colors.cyanAccent, width: 2),
          boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 8)]
      );
    }

    // Colores base estilo PES clásico
    Color bgColor;
    Color borderColor;

    if (rating >= 90) { // Black Ball
      bgColor = const Color(0xFF101010);
      borderColor = Colors.grey;
    } else if (rating >= 85) { // Gold Ball
      bgColor = const Color(0xFFD4AF37);
      borderColor = const Color(0xFFF7E7CE);
    } else if (rating >= 80) { // Silver Ball
      bgColor = const Color(0xFFC0C0C0);
      borderColor = Colors.white70;
    } else { // Bronze Ball
      bgColor = const Color(0xFFCD7F32);
      borderColor = const Color(0xFF8B4513);
    }

    return BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0,2))]
    );
  }
}