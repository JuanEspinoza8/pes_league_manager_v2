import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AvailablePlayersScreen extends StatefulWidget {
  final String seasonId;
  const AvailablePlayersScreen({super.key, required this.seasonId});

  @override
  State<AvailablePlayersScreen> createState() => _AvailablePlayersScreenState();
}

class _AvailablePlayersScreenState extends State<AvailablePlayersScreen> {
  List<DocumentSnapshot> _availablePlayers = [];
  List<DocumentSnapshot> _filteredPlayers = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAvailablePlayers();
  }

  Future<void> _loadAvailablePlayers() async {
    try {
      final db = FirebaseFirestore.instance;

      // 1. Obtener lista de IDs ocupados en la temporada
      DocumentSnapshot seasonDoc = await db.collection('seasons').doc(widget.seasonId).get();
      List<dynamic> takenIdsDynamic = seasonDoc['takenPlayerIds'] ?? [];
      Set<String> takenIds = takenIdsDynamic.map((e) => e.toString()).toSet();

      // 2. Obtener TODOS los jugadores de la base de datos
      // (Como son ~300-600, es seguro traerlos todos de una vez)
      QuerySnapshot playersSnap = await db.collection('players').get();

      // 3. Filtrar: Quedarse solo con los que NO están en takenIds
      List<DocumentSnapshot> free = [];
      for (var doc in playersSnap.docs) {
        if (!takenIds.contains(doc.id)) {
          free.add(doc);
        }
      }

      // 4. Ordenar por Media (Rating) descendente
      free.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));

      if (mounted) {
        setState(() {
          _availablePlayers = free;
          _filteredPlayers = free;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _filterPlayers(String query) {
    if (query.isEmpty) {
      setState(() => _filteredPlayers = _availablePlayers);
    } else {
      setState(() {
        _filteredPlayers = _availablePlayers.where((doc) {
          String name = doc['name'].toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("JUGADORES LIBRES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_isLoading)
              Text("${_availablePlayers.length} disponibles", style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
          ],
        ),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // BARRA DE BÚSQUEDA
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filterPlayers,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Buscar jugador...",
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),

          // LISTA
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                : _filteredPlayers.isEmpty
                ? const Center(child: Text("No se encontraron jugadores.", style: TextStyle(color: Colors.white54)))
                : ListView.builder(
              itemCount: _filteredPlayers.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (context, index) {
                var data = _filteredPlayers[index].data() as Map<String, dynamic>;
                String id = _filteredPlayers[index].id; // ID para copiar

                return Card(
                  color: Colors.white.withOpacity(0.05),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getRatingColor(data['rating']),
                      child: Text("${data['rating']}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(data['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("${data['position']} • ${data['team']}", style: const TextStyle(color: Colors.white54)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, color: Colors.amber),
                      tooltip: "Copiar ID para Trampa",
                      onPressed: () {
                        // Copiar ID al portapapeles (útil para la trampa del sobre)
                        // Requiere: import 'package:flutter/services.dart';
                        // Pero para simplificar, mostramos snackbar
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("ID: $id"),
                          action: SnackBarAction(label: "CERRAR", onPressed: (){}),
                          duration: const Duration(seconds: 4),
                        ));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getRatingColor(int? rating) {
    if (rating == null) return Colors.grey;
    if (rating >= 90) return Colors.cyanAccent;
    if (rating >= 85) return Colors.purpleAccent;
    if (rating >= 80) return Colors.amber;
    if (rating >= 75) return Colors.greenAccent;
    return Colors.white;
  }
}