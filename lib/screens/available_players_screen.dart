import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AvailablePlayersScreen extends StatefulWidget {
  final String seasonId;
  const AvailablePlayersScreen({super.key, required this.seasonId});

  @override
  State<AvailablePlayersScreen> createState() => _AvailablePlayersScreenState();
}

class _AvailablePlayersScreenState extends State<AvailablePlayersScreen> {
  // --- LÓGICA INTACTA ---
  List<DocumentSnapshot> _availablePlayers = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  List<DocumentSnapshot> _filteredPlayers = [];

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    try {
      final seasonDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();
      List takenIds = seasonDoc.data()?['takenPlayerIds'] ?? [];

      // Traemos los mejores 500 para no saturar, ordenados por rating
      final query = await FirebaseFirestore.instance.collection('players').orderBy('rating', descending: true).limit(500).get();

      if (mounted) {
        setState(() {
          // Filtramos localmente los que no estén en 'takenIds'
          _availablePlayers = query.docs.where((doc) => !takenIds.contains(doc.id)).toList();
          _filteredPlayers = _availablePlayers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if(mounted) setState(() => _isLoading = false);
      print("Error cargando libres: $e");
    }
  }

  void _filter(String text) {
    setState(() {
      if (text.isEmpty) {
        _filteredPlayers = _availablePlayers;
      } else {
        _filteredPlayers = _availablePlayers.where((d) => d['name'].toString().toLowerCase().contains(text.toLowerCase())).toList();
      }
    });
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("AGENTES LIBRES", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // BARRA DE BÚSQUEDA
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Buscar por nombre...",
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              onChanged: _filter,
            ),
          ),

          // LISTA
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                : _filteredPlayers.isEmpty
                ? const Center(child: Text("No se encontraron jugadores.", style: TextStyle(color: Colors.white24)))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredPlayers.length,
              itemBuilder: (context, index) {
                var data = _filteredPlayers[index].data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05))
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 45, height: 45,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                          border: Border.all(color: _getRatingColor(data['rating']), width: 2)
                      ),
                      child: Text("${data['rating']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    title: Text(data['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text("${data['position']} • ${data['team']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white24),
                      onPressed: () {
                        // Copiar ID para admin
                        final pid = _filteredPlayers[index].id;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("ID copiado: $pid")));
                        // Aquí podrías implementar copy to clipboard real
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

  Color _getRatingColor(int? r) {
    int rating = r ?? 0;
    if (rating >= 85) return const Color(0xFFD4AF37); // Gold
    if (rating >= 80) return Colors.grey; // Silver
    return const Color(0xFFCD7F32); // Bronze
  }
}