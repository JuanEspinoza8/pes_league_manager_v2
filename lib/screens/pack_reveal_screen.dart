import 'package:flutter/material.dart';

class PackRevealScreen extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  const PackRevealScreen({super.key, required this.players});

  @override
  State<PackRevealScreen> createState() => _PackRevealScreenState();
}

class _PackRevealScreenState extends State<PackRevealScreen> {
  int currentCardIndex = 0;
  bool isCardRevealed = false;

  // Ordenamos de menor a mayor media para dejar lo mejor al final (Suspenso)
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

  @override
  Widget build(BuildContext context) {
    bool finishedAll = currentCardIndex >= sortedPlayers.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Fondo Oscuro
      appBar: AppBar(
        title: const Text("REVELANDO PACK", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // Bloquear volver atrás durante la apertura
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)]
            )
        ),
        child: Column(
          children: [
            if (!finishedAll) ...[
              const SizedBox(height: 30),

              // INDICADOR DE PROGRESO
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                child: Text(
                    "CARTA ${currentCardIndex + 1} DE ${sortedPlayers.length}",
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1)
                ),
              ),

              const Spacer(),

              // LA CARTA (ANIMADA)
              GestureDetector(
                onTap: _handleCardTap,
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
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
                    isCardRevealed ? "Toca para siguiente" : "Toca para revelar",
                    style: const TextStyle(color: Colors.white38, letterSpacing: 2, fontSize: 12)
                ),
              ),
              const SizedBox(height: 40),

            ] else ...[
              // --- PANTALLA FINAL ---
              const Spacer(),
              const Icon(Icons.star, size: 80, color: Colors.amber),
              const SizedBox(height: 20),
              const Text("¡FICHAJES COMPLETADOS!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                child: Text(
                    "Los jugadores han sido enviados a tu club. Ve a 'Mi Equipo' para alinearlos.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D1B2A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
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

  // --- ESTILOS DE CARTA (Reutilizados para consistencia) ---

  BoxDecoration _getCardDecoration(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();

    if (tier == 'LEYENDA') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white, width: 2),
          gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF880E4F), Color(0xFF4A148C), Color(0xFFFFD700)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.6), blurRadius: 20)]
      );
    }
    if (tier == 'PRIME') {
      return BoxDecoration(
          borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent, width: 2),
          gradient: const LinearGradient(colors: [Color(0xFFCFD8DC), Color(0xFF546E7A), Color(0xFF263238)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.4), blurRadius: 15)]
      );
    }

    Color bgColor;
    Color borderColor;

    if (rating >= 90) { // Bola Negra
      bgColor = const Color(0xFF101010);
      borderColor = Colors.white54;
    } else if (rating >= 85) { // Oro Brillante
      bgColor = const Color(0xFFFFD700);
      borderColor = Colors.orange;
    } else if (rating >= 80) { // Oro Opaco
      bgColor = const Color(0xFFC5A000);
      borderColor = Colors.brown;
    } else { // Silver
      bgColor = const Color(0xFF9E9E9E);
      borderColor = Colors.blueGrey;
    }

    return BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor, width: 4), boxShadow: [BoxShadow(color: bgColor.withOpacity(0.5), blurRadius: 10)]);
  }

  Color _getTextColor(Map<String, dynamic> player) {
    int rating = player['rating'] ?? 75;
    String tier = (player['tier'] ?? '').toString().toUpperCase();
    if (tier == 'LEYENDA' || tier == 'PRIME' || rating >= 90) return Colors.white;
    return Colors.black;
  }

  Widget _buildBackCard(Map<String, dynamic> p) {
    return Container(
      key: const ValueKey(1), width: 300, height: 450,
      decoration: _getCardDecoration(p).copyWith(gradient: null, color: const Color(0xFF0D1B2A)),
      child: Container(
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 5),
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF1B263B), Color(0xFF000000)], begin: Alignment.topRight, end: Alignment.bottomLeft)
        ),
        child: const Center(child: Icon(Icons.star, size: 80, color: Colors.white24)),
      ),
    );
  }

  Widget _buildFrontCard(Map<String, dynamic> p) {
    Color txtColor = _getTextColor(p);
    return Container(
      key: const ValueKey(2), width: 300, height: 450,
      decoration: _getCardDecoration(p),
      child: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.1, child: Icon(Icons.shield, size: 200, color: txtColor))),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Row(children: [const SizedBox(width: 20), Column(children: [Text("${p['rating']}", style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: txtColor)), Text(p['position'], style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: txtColor))])]),
              const Spacer(),
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), color: Colors.black54, child: Text(p['name'].toString().toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }
}