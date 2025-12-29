import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'lobby_waiting_room.dart';

class CreateSeasonScreen extends StatefulWidget {
  const CreateSeasonScreen({super.key});

  @override
  State<CreateSeasonScreen> createState() => _CreateSeasonScreenState();
}

class _CreateSeasonScreenState extends State<CreateSeasonScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  int _maxPlayers = 10;
  String _acquisitionMode = 'AUCTION';
  bool _hasLeague = true;
  bool _hasCup = true;
  bool _hasChampions = true;
  bool _isLoading = false;

  String _generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _createSeason() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser!;
    final db = FirebaseFirestore.instance;
    final String code = _generateRoomCode();

    try {
      DocumentReference seasonRef = await db.collection('seasons').add({
        'name': _nameController.text.trim(),
        'code': code,
        'adminId': user.uid,
        'status': 'WAITING',
        'createdAt': FieldValue.serverTimestamp(),
        'takenPlayerIds': [],
        'participantIds': [user.uid],
        'config': {
          'maxPlayers': _maxPlayers,
          'acquisitionMode': _acquisitionMode,
          'competitions': {'league': _hasLeague, 'cup': _hasCup, 'champions': _hasChampions},
          'initialBudget': _acquisitionMode == 'AUCTION' ? 100000000 : 0,
        }
      });

      await seasonRef.collection('participants').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'teamName': "Equipo de ${user.email!.split('@')[0]}",
        'budget': _acquisitionMode == 'AUCTION' ? 100000000 : 0,
        'roster': [],
        'points_league': 0,
        'role': 'ADMIN',
      });

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LobbyWaitingRoom(seasonId: seasonRef.id)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Fondo Oscuro Premium
      appBar: AppBar(
        title: const Text("CREAR TORNEO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TARJETA NOMBRE ---
              _buildSectionTitle("IDENTIDAD"),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: "Nombre de la Temporada",
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.emoji_events, color: Colors.amber),
                  ),
                  validator: (v) => v!.isEmpty ? "Escribe un nombre" : null,
                ),
              ),

              const SizedBox(height: 25),

              // --- TARJETA PARTICIPANTES ---
              _buildSectionTitle("CAPACIDAD"),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Participantes", style: TextStyle(color: Colors.white, fontSize: 16)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(15)),
                          child: Text("$_maxPlayers", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.blueAccent,
                        thumbColor: Colors.white,
                        overlayColor: Colors.blueAccent.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _maxPlayers.toDouble(),
                        min: 2,
                        max: 20,
                        divisions: 18,
                        onChanged: (val) => setState(() => _maxPlayers = val.toInt()),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // --- TARJETA FORMATO (DRAFT) ---
              _buildSectionTitle("FORMATO DE INICIO"),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    _buildRadioTile(
                        title: "Modo Subasta",
                        subtitle: "Presupuesto de 100M. Puja en vivo.",
                        value: 'AUCTION',
                        icon: Icons.gavel,
                        color: Colors.amber
                    ),
                    const Divider(color: Colors.white10),
                    _buildRadioTile(
                        title: "Modo Sobres",
                        subtitle: "Equipo aleatorio equilibrado.",
                        value: 'PACKS',
                        icon: Icons.card_giftcard,
                        color: Colors.purple
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // --- TARJETA COMPETICIONES ---
              _buildSectionTitle("COMPETICIONES"),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    _buildSwitchTile("Liga", "Todos contra todos", _hasLeague, (v) => setState(() => _hasLeague = v), Icons.format_list_numbered, Colors.blue),
                    const Divider(color: Colors.white10),
                    _buildSwitchTile("Copa", "Eliminación directa (Playoffs)", _hasCup, (v) => setState(() => _hasCup = v), Icons.emoji_events, Colors.orange),
                    const Divider(color: Colors.white10),
                    _buildSwitchTile("Champions", "Fase de Grupos + Eliminatorias", _hasChampions, (v) => setState(() => _hasChampions = v), Icons.star, Colors.indigoAccent),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // --- BOTÓN CREAR ---
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createSeason,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D1B2A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Color(0xFF0D1B2A))
                      : const Text("LANZAR TEMPORADA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
        color: const Color(0xFF1B263B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]
    );
  }

  Widget _buildRadioTile({required String title, required String subtitle, required String value, required IconData icon, required Color color}) {
    bool selected = _acquisitionMode == value;
    return RadioListTile(
      activeColor: color,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      title: Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white38, fontSize: 12)),
      secondary: Icon(icon, color: selected ? color : Colors.grey),
      value: value,
      groupValue: _acquisitionMode,
      onChanged: (v) => setState(() => _acquisitionMode = v.toString()),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged, IconData icon, Color color) {
    return SwitchListTile(
      activeColor: color,
      inactiveThumbColor: Colors.grey,
      inactiveTrackColor: Colors.black26,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}