import 'package:flutter/material.dart';

class PackRevealScreen extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  const PackRevealScreen({super.key, required this.players});

  @override
  State<PackRevealScreen> createState() => _PackRevealScreenState();
}

class _PackRevealScreenState extends State<PackRevealScreen> {
  // --- LÓGICA INTACTA ---
  int currentCardIndex = 0;
  bool isCardRevealed = false;
  late List<Map<String, dynamic>> sortedPlayers;

  @override
  void initState() {
    super.initState();
    sortedPlayers = List.from(widget.players);
    sortedPlayers.sort((a, b) => (a['rating'] ?? 0).compareTo(b['rating'] ?? 0));
  }

  void _handleCardTap() {
    if (!isCardRevealed) {
      setState(() => isCardRevealed = true);
    } else {
      if (currentCardIndex < sortedPlayers.length) {
        setState(() {
          currentCardIndex++;
          isCardRevealed = false;
        });
      }
    }
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    bool finishedAll = currentCardIndex >= sortedPlayers.length;
    const goldColor = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("REVELANDO...", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 14)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment.center, radius: 1.2, colors: [Color(0xFF1E293B), Color(0xFF0B1120)])
        ),
        child: Column(
          children: [
            if (!finishedAll) ...[
              const SizedBox(height: 30),

              // INDICADOR DE PROGRESO
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("CARTA ${currentCardIndex + 1}", style: TextStyle(color: goldColor, fontWeight: FontWeight.bold)),
                  Text(" / ${sortedPlayers.length}", style: const TextStyle(color: Colors.white38)),
                ],
              ),

              const Spacer(),

              // LA CARTA (ANIMADA)
              GestureDetector(
                onTap: _handleCardTap,
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    transitionBuilder: (w, a) => RotationTransition(turns: Tween(begin: 0.5, end: 1.0).animate(a), child: w),
                    child: isCardRevealed
                        ? _buildFrontCard(sortedPlayers[currentCardIndex])
                        : _buildBackCard(sortedPlayers[currentCardIndex])
                ),
              ),

              const Spacer(),

              AnimatedOpacity(
                opacity: isCardRevealed ? 1.0 : 0.6,
                duration: const Duration(seconds: 1),
                child: Text(
                    isCardRevealed ? "TOCA PARA SIGUIENTE" : "TOCA PARA REVELAR",
                    style: const TextStyle(color: Colors.white24, letterSpacing: 3, fontSize: 10, fontWeight: FontWeight.bold)
                ),
              ),
              const SizedBox(height: 50),

            ] else ...[
              // --- PANTALLA FINAL ---
              const Spacer(),
              Icon(Icons.auto_awesome, size: 80, color: goldColor),
              const SizedBox(height: 30),
              const Text("TRANSFERENCIA COMPLETADA", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 50, vertical: 10),
                child: Text("Los jugadores están listos para ser alineados.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5)),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 200,
                height: 55,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D1B2A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text("CONTINUAR", style: TextStyle(fontWeight: FontWeight.bold))
                ),
              ),
              const Spacer(),
            ]
          ],
        ),
      ),
    );
  }

  // --- REUTILIZAMOS EL MISMO ESTILO PREMIUM ---

  BoxDecoration _getCardDecoration(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();

    if (tier == 'LEYENDA') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700), width: 2),
          gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF880E4F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.5), blurRadius: 20)]
      );
    }
    if (tier == 'PRIME') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.cyanAccent, width: 2),
          color: Colors.black,
          boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 15)]
      );
    }

    Color bgColor;
    Color borderColor;

    if (rating >= 90) {
      bgColor = const Color(0xFF101010); borderColor = Colors.white38;
    } else if (rating >= 85) {
      bgColor = const Color(0xFFD4AF37); borderColor = const Color(0xFFFFE082);
    } else if (rating >= 80) {
      bgColor = const Color(0xFFB0BEC5); borderColor = Colors.white70;
    } else {
      bgColor = const Color(0xFF8D6E63); borderColor = const Color(0xFFD7CCC8);
    }

    return BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor, width: 3), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)]);
  }

  Color _getTextColor(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();
    if (tier == 'LEYENDA' || tier == 'PRIME' || rating >= 90) return Colors.white;
    return Colors.black;
  }

  Widget _buildBackCard(Map<String, dynamic> p) {
    return Container(
      key: const ValueKey(1), width: 280, height: 420,
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12, width: 4), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)]),
      child: Center(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10)), child: const Icon(Icons.sports_soccer, size: 60, color: Colors.white10))),
    );
  }

  Widget _buildFrontCard(Map<String, dynamic> p) {
    Color txtColor = _getTextColor(p);
    return Container(
      key: const ValueKey(2), width: 280, height: 420,
      decoration: _getCardDecoration(p),
      child: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.1, child: Icon(Icons.shield, size: 200, color: txtColor))),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${p['rating']}", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: txtColor)),
                Text(p['position'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: txtColor)),
                const Spacer(),
                Center(child: Text(p['name'].toString().toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 24, color: txtColor, fontWeight: FontWeight.w900, letterSpacing: 1))),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}