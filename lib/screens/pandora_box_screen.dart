import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'pack_reveal_screen.dart';

class PandoraBoxScreen extends StatefulWidget {
  final String seasonId;
  final String userId;
  final String boxName;
  final double successChance; // Ej: 0.15 o 0.30
  final int totalTaps; // Ej: 3 o 5
  final List<int> tierRatings; // Ej: [75, 80, 85, 90]
  final List<Color> boxColors; // Colores temáticos

  const PandoraBoxScreen({
    super.key,
    required this.seasonId,
    required this.userId,
    required this.boxName,
    required this.successChance,
    required this.totalTaps,
    required this.tierRatings,
    required this.boxColors,
  });

  @override
  State<PandoraBoxScreen> createState() => _PandoraBoxScreenState();
}

class _PandoraBoxScreenState extends State<PandoraBoxScreen> with SingleTickerProviderStateMixin {
  int _currentLevelIndex = 0;
  int _tapsUsed = 0;
  bool _isProcessing = false;
  String _statusMessage = "";

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _statusMessage = "Nivel Inicial: +${widget.tierRatings[0]} GRL";
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _performTap() async {
    if (_tapsUsed >= widget.totalTaps) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Forjando...";
    });

    // Animación de "golpe"
    _animController.repeat(reverse: true);
    await Future.delayed(const Duration(milliseconds: 1000));
    _animController.stop();
    _animController.reset();

    // Cálculo de probabilidad
    double roll = Random().nextDouble(); // 0.0 a 1.0
    bool success = roll < widget.successChance;

    setState(() {
      _tapsUsed++;
      _isProcessing = false;

      if (success) {
        // Aseguramos no pasarnos del array
        if (_currentLevelIndex < widget.tierRatings.length - 1) {
          _currentLevelIndex++;
          _statusMessage = "¡ÉXITO! Subió a +${widget.tierRatings[_currentLevelIndex]}";
        } else {
          _statusMessage = "¡YA ESTÁ AL MÁXIMO! (Éxito)";
        }
      } else {
        _statusMessage = "Falló. Se mantiene en +${widget.tierRatings[_currentLevelIndex]}";
      }
    });
  }

  Future<void> _openPack() async {
    setState(() => _isProcessing = true);

    int minR = widget.tierRatings[_currentLevelIndex];
    int maxR = 99;
    if (_currentLevelIndex < widget.tierRatings.length - 1) {
      maxR = widget.tierRatings[_currentLevelIndex + 1] - 1;
    }
    if (minR >= widget.tierRatings.last) maxR = 99;

    try {
      final db = FirebaseFirestore.instance;
      var query = await db.collection('players')
          .where('rating', isGreaterThanOrEqualTo: minR)
          .where('rating', isLessThanOrEqualTo: maxR)
          .limit(50)
          .get();

      var seasonDoc = await db.collection('seasons').doc(widget.seasonId).get();
      List takenIds = seasonDoc['takenPlayerIds'] ?? [];

      var available = query.docs.where((d) => !takenIds.contains(d.id)).toList();

      if (available.isEmpty) {
        var fallback = await db.collection('players')
            .where('rating', isGreaterThanOrEqualTo: minR)
            .limit(20)
            .get();
        available = fallback.docs.where((d) => !takenIds.contains(d.id)).toList();
      }

      if (available.isEmpty) throw "Sin stock disponible (+${minR}). Contacta al admin.";

      var picked = available[Random().nextInt(available.length)];

      await db.runTransaction((tx) async {
        var userRef = db.collection('seasons').doc(widget.seasonId).collection('participants').doc(widget.userId);
        var sRef = db.collection('seasons').doc(widget.seasonId);

        tx.update(userRef, {'roster': FieldValue.arrayUnion([picked.id])});
        tx.update(sRef, {'takenPlayerIds': FieldValue.arrayUnion([picked.id])});
      });

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PackRevealScreen(players: [picked.data()])));
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int tapsRemaining = widget.totalTaps - _tapsUsed;
    bool finished = tapsRemaining <= 0;
    int currentRating = widget.tierRatings[_currentLevelIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(title: Text(widget.boxName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)), backgroundColor: Colors.transparent, centerTitle: true, elevation: 0),
      body: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // INFO ESTADO
            Text(finished ? "PROCESO TERMINADO" : "INTENTOS RESTANTES: $tapsRemaining", style: const TextStyle(color: Colors.white54, letterSpacing: 2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("CALIDAD ACTUAL", style: TextStyle(color: widget.boxColors.last, fontSize: 16)),
            Text("+$currentRating GRL", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),

            const SizedBox(height: 10),
            Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),

            const SizedBox(height: 40),

            // EL CUBO
            GestureDetector(
              onTap: (!_isProcessing && !finished) ? _performTap : null,
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 - (_animController.value * 0.1),
                    child: Container(
                      width: 200, height: 200,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: widget.boxColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(color: widget.boxColors.first.withOpacity(0.6), blurRadius: 30 + (_animController.value * 50), spreadRadius: _animController.value * 10)
                          ],
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)
                      ),
                      child: Center(
                        child: _isProcessing
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(finished ? Icons.lock_open : Icons.touch_app, size: 60, color: Colors.white),
                            if (!finished)
                              Text("${(widget.successChance * 100).toInt()}% Prob.", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 60),

            // BOTÓN FINAL
            if (finished && !_isProcessing)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                onPressed: _openPack,
                icon: const Icon(Icons.auto_awesome),
                label: const Text("ABRIR RECOMPENSA"),
              )
            else if (!_isProcessing)
              const Text("Golpea el cubo para forjar tu destino.", style: TextStyle(color: Colors.white24))
          ],
        ),
      ),
    );
  }
}