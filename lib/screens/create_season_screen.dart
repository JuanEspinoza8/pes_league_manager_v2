import 'dart:math';
import 'dart:ui'; // Necesario para el Blur
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
  // --- LÓGICA INTACTA ---
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
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("CREAR TORNEO", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617)], // Slate 900 -> Black
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 40), // Top padding por AppBar
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- SECCIÓN IDENTIDAD ---
                _buildSectionTitle("IDENTIDAD DE LA LIGA"),
                _GlassCard(
                  child: TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: "NOMBRE DEL TORNEO",
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: goldColor, width: 1)),
                      prefixIcon: const Icon(Icons.emoji_events_outlined, color: goldColor),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    ),
                    validator: (v) => v!.isEmpty ? "El nombre es obligatorio" : null,
                  ),
                ),

                const SizedBox(height: 30),

                // --- SECCIÓN CAPACIDAD ---
                _buildSectionTitle("PARTICIPANTES"),
                _GlassCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("DTs Humanos", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                                color: goldColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: goldColor.withOpacity(0.5))
                            ),
                            child: Text("$_maxPlayers", style: const TextStyle(color: goldColor, fontWeight: FontWeight.w900, fontSize: 16)),
                          )
                        ],
                      ),
                      const SizedBox(height: 20),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: goldColor,
                          inactiveTrackColor: Colors.white10,
                          thumbColor: Colors.white,
                          overlayColor: goldColor.withOpacity(0.2),
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        ),
                        child: Slider(
                          value: _maxPlayers.toDouble(),
                          min: 2,
                          max: 20,
                          divisions: 18,
                          onChanged: (val) => setState(() => _maxPlayers = val.toInt()),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text("Define el tamaño de la sala. Puedes rellenar con bots después.", style: TextStyle(color: Colors.white30, fontSize: 11), textAlign: TextAlign.center),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // --- SECCIÓN FORMATO ---
                _buildSectionTitle("MECÁNICA DE FICHAJES"),
                _GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _buildRadioTile(
                          title: "SUBASTA EN VIVO",
                          subtitle: "Presupuesto de 100M. Puja estratégica en tiempo real.",
                          value: 'AUCTION',
                          icon: Icons.gavel_rounded,
                          color: goldColor
                      ),
                      Divider(color: Colors.white.withOpacity(0.05), height: 1),
                      _buildRadioTile(
                          title: "APERTURA DE SOBRES",
                          subtitle: "Suerte y azar. Equipos equilibrados por el destino.",
                          value: 'PACKS',
                          icon: Icons.flash_on_rounded,
                          color: Colors.purpleAccent
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // --- SECCIÓN COMPETICIONES ---
                _buildSectionTitle("TORNEOS ACTIVOS"),
                _GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _buildSwitchTile("LIGA", "Formato todos contra todos (Ida/Vuelta)", _hasLeague, (v) => setState(() => _hasLeague = v), Icons.table_chart_rounded, Colors.blueAccent),
                      Divider(color: Colors.white.withOpacity(0.05), height: 1),
                      _buildSwitchTile("COPA", "Eliminación directa (Playoffs)", _hasCup, (v) => setState(() => _hasCup = v), Icons.emoji_events_rounded, Colors.orangeAccent),
                      Divider(color: Colors.white.withOpacity(0.05), height: 1),
                      _buildSwitchTile("CHAMPIONS", "Grupos + Eliminatorias (Top Teams)", _hasChampions, (v) => setState(() => _hasChampions = v), Icons.star_rounded, Colors.indigoAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                // --- BOTÓN CREAR ---
                Container(
                  decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: goldColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 5))]
                  ),
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createSeason,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                        : const Text("INICIAR TEMPORADA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)
      ),
    );
  }

  Widget _buildRadioTile({required String title, required String subtitle, required String value, required IconData icon, required Color color}) {
    bool selected = _acquisitionMode == value;
    return RadioListTile(
      activeColor: color,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      title: Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(subtitle, style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: selected ? color.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: selected ? color : Colors.white24),
      ),
      value: value,
      groupValue: _acquisitionMode,
      onChanged: (v) => setState(() => _acquisitionMode = v.toString()),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged, IconData icon, Color color) {
    return SwitchListTile(
      activeColor: color,
      inactiveThumbColor: Colors.grey[800],
      inactiveTrackColor: Colors.black26,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ),
      secondary: Icon(icon, color: value ? color : Colors.white24, size: 24),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(24)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}