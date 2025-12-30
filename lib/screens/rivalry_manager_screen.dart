import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RivalryManagerScreen extends StatefulWidget {
  final String seasonId;
  const RivalryManagerScreen({super.key, required this.seasonId});

  @override
  State<RivalryManagerScreen> createState() => _RivalryManagerScreenState();
}

class _RivalryManagerScreenState extends State<RivalryManagerScreen> {
  String? teamA;
  String? teamB;

  Future<void> _addRivalry() async {
    if (teamA == null || teamB == null || teamA == teamB) return;

    // Guardamos la rivalidad como un string combinado para fácil búsqueda
    // Ej: "idTeamA_idTeamB" y también "idTeamB_idTeamA" para búsqueda bidireccional
    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({
      'rivalries': FieldValue.arrayUnion(["${teamA}_$teamB", "${teamB}_$teamA"])
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Clásico Creado!")));
    setState(() { teamA = null; teamB = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gestor de Clásicos"), backgroundColor: const Color(0xFF0D1B2A)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Selecciona dos equipos para declarar un CLÁSICO o DERBI.", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),

            // SELECTORES
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                var items = snapshot.data!.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['teamName']))).toList();

                return Column(
                  children: [
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text("Equipo Local"),
                      value: teamA,
                      items: items,
                      onChanged: (v) => setState(() => teamA = v),
                    ),
                    const Icon(Icons.flash_on, color: Colors.red, size: 40),
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text("Equipo Rival"),
                      value: teamB,
                      items: items,
                      onChanged: (v) => setState(() => teamB = v),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 30),
            ElevatedButton(
                onPressed: _addRivalry,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text("CREAR RIVALIDAD")
            ),

            const Divider(height: 40),
            const Text("Rivales Actuales:", style: TextStyle(fontWeight: FontWeight.bold)),

            // LISTA DE RIVALES EXISTENTES
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  List rivalries = (snapshot.data!.data() as Map)['rivalries'] ?? [];
                  // Filtramos para no mostrar duplicados (A_B y B_A)
                  var unique = rivalries.where((r) => r.toString().compareTo(r.toString().split('_')[1] + "_" + r.toString().split('_')[0]) > 0).toList();

                  return ListView.builder(
                    itemCount: unique.length,
                    itemBuilder: (ctx, i) {
                      var parts = unique[i].toString().split('_');
                      return FutureBuilder<List<DocumentSnapshot>>(
                        future: Future.wait([
                          FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(parts[0]).get(),
                          FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(parts[1]).get(),
                        ]),
                        builder: (c, s) {
                          if (!s.hasData) return const SizedBox();
                          return ListTile(
                            title: Text("${s.data![0]['teamName']} vs ${s.data![1]['teamName']}"),
                            leading: const Icon(Icons.security),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({
                                  'rivalries': FieldValue.arrayRemove([unique[i], "${parts[1]}_${parts[0]}"])
                                });
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}