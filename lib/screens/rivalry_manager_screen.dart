import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RivalryManagerScreen extends StatefulWidget {
  final String seasonId;
  const RivalryManagerScreen({super.key, required this.seasonId});

  @override
  State<RivalryManagerScreen> createState() => _RivalryManagerScreenState();
}

class _RivalryManagerScreenState extends State<RivalryManagerScreen> {
  // --- LÓGICA INTACTA ---
  List<DocumentSnapshot> participants = [];
  List<String> rivalries = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    var pSnap = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').get();
    var sSnap = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).get();

    if (mounted) {
      setState(() {
        participants = pSnap.docs;
        rivalries = List<String>.from(sSnap.data()?['rivalries'] ?? []);
        isLoading = false;
      });
    }
  }

  Future<void> _toggleRivalry(String p1Id, String p2Id) async {
    String key1 = "${p1Id}_$p2Id";
    String key2 = "${p2Id}_$p1Id";
    bool exists = rivalries.contains(key1) || rivalries.contains(key2);

    List<String> newRivalries = List.from(rivalries);
    if (exists) {
      newRivalries.remove(key1);
      newRivalries.remove(key2);
    } else {
      newRivalries.add(key1);
    }

    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({'rivalries': newRivalries});
    setState(() => rivalries = newRivalries);
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("GESTIÓN DE CLÁSICOS", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: participants.length,
        itemBuilder: (context, i) {
          var p1 = participants[i];
          // Solo mostramos combinaciones únicas (triángulo superior de la matriz)
          var opponents = participants.sublist(i + 1);

          if (opponents.isEmpty) return const SizedBox();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text("RIVALES DE ${p1['teamName'].toString().toUpperCase()}", style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              ...opponents.map((p2) {
                String key1 = "${p1.id}_${p2.id}";
                String key2 = "${p2.id}_${p1.id}";
                bool isRival = rivalries.contains(key1) || rivalries.contains(key2);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isRival ? Colors.redAccent.withOpacity(0.5) : Colors.white10),
                  ),
                  child: SwitchListTile(
                    activeColor: Colors.redAccent,
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.black26,
                    title: Row(
                      children: [
                        Text(p1['teamName'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text("VS", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.w900, fontSize: 10)),
                        ),
                        Text(p2['teamName'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                    subtitle: isRival
                        ? const Text("🔥 CLÁSICO ACTIVO", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10))
                        : const Text("Partido normal", style: TextStyle(color: Colors.white30, fontSize: 10)),
                    value: isRival,
                    onChanged: (val) => _toggleRivalry(p1.id, p2.id),
                  ),
                );
              }).toList()
            ],
          );
        },
      ),
    );
  }
}