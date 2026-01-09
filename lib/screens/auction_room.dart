import 'dart:async';
import 'dart:ui'; // Para ImageFilter
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auction_service.dart';

class AuctionRoom extends StatefulWidget {
  final String seasonId;
  final bool isAdmin;
  const AuctionRoom({super.key, required this.seasonId, required this.isAdmin});

  @override
  State<AuctionRoom> createState() => _AuctionRoomState();
}

class _AuctionRoomState extends State<AuctionRoom> {
  // --- LÓGICA ---
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final AuctionService _auctionService = AuctionService();

  int _timeLeft = 0;
  Timer? _timer;
  bool _isResolving = false;
  DateTime? _lastKnownEndTime;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer(Timestamp? firestoreTime) {
    if (firestoreTime == null) {
      _timer?.cancel();
      // --- CORRECCIÓN 1: Evita el error "setState called during build" ---
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _timeLeft != 0) {
          setState(() => _timeLeft = 0);
        }
      });
      return;
    }
    DateTime targetTime = firestoreTime.toDate();
    if (_lastKnownEndTime == null || targetTime != _lastKnownEndTime) {
      _lastKnownEndTime = targetTime;
      _startLocalTimer(targetTime);
    }
  }

  void _startLocalTimer(DateTime targetTime) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) { timer.cancel(); return; }
      int seconds = targetTime.difference(DateTime.now()).inSeconds;
      if (seconds < 0) seconds = 0;
      if (seconds != _timeLeft) setState(() => _timeLeft = seconds);

      if (seconds == 0 && widget.isAdmin && !_isResolving) {
        timer.cancel();
        _triggerResolution();
      }
    });
  }

  Future<void> _triggerResolution() async {
    if (_isResolving) return;
    _isResolving = true;
    await Future.delayed(const Duration(seconds: 1));
    try {
      await _auctionService.resolveAuction(widget.seasonId);
    } catch (e) {
      print("Error resolviendo: $e");
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _placeBid(int currentBid, int increment, String myName) async {
    try {
      await _auctionService.placeBid(widget.seasonId, currentUserId, myName, currentBid + increment);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("SALA DE SUBASTAS", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        actions: [
          if (widget.isAdmin) ...[
            // BOTÓN DE MIGRACIÓN (EJECUTAR UNA VEZ PARA ARREGLAR LA BD)
            IconButton(
              icon: const Icon(Icons.build, color: Colors.amberAccent),
              tooltip: "🛠️ Migrar DB (Fix /)",
              onPressed: () async {
                await _auctionService.migrateLegacyKeys(widget.seasonId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Base de datos migrada (Barras eliminadas)"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            // BOTÓN DE FORZAR JUGADOR
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.redAccent),
              onPressed: () => _auctionService.drawNextPlayer(widget.seasonId),
              tooltip: "Forzar siguiente jugador",
            ),
          ]
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2, colors: [Color(0xFF1E293B), Color(0xFF0B1120)])
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('auction').doc('status').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
            if (!snapshot.data!.exists) {
              return Center(
                child: widget.isAdmin
                    ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                    onPressed: () => _auctionService.initializeAuction(widget.seasonId),
                    child: const Text("INICIAR DRAFT", style: TextStyle(fontWeight: FontWeight.bold))
                )
                    : const Text("Esperando al administrador...", style: TextStyle(color: Colors.white54)),
              );
            }

            var auctionData = snapshot.data!.data() as Map<String, dynamic>;

            bool isActive = auctionData['active'] ?? false;
            if (!isActive) return const Center(child: Text("SUBASTA FINALIZADA", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)));

            String state = auctionData['state'] ?? 'BIDDING';
            if (state == 'PAUSED') {
              return _buildPauseScreen(auctionData);
            }

            _syncTimer(auctionData['timerEnd']);

            // --- CORRECCIÓN 2: Solución al Overflow (Pantalla Amarilla) ---
            return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            _buildPhaseHeader(auctionData),
                            const Spacer(),
                            if (auctionData['currentPlayer'] != null)
                              _buildPlayerCard(auctionData['currentPlayer'], auctionData),
                            if (auctionData['currentPlayer'] == null)
                              const Text("Sorteando jugador...", style: TextStyle(color: Colors.white54)),
                            const Spacer(),
                            _buildUserControls(auctionData),
                          ],
                        ),
                      ),
                    ),
                  );
                }
            );
          },
        ),
      ),
    );
  }

  Widget _buildPauseScreen(Map auctionData) {
    String result = auctionData['lastResult'] ?? "Ronda finalizada";

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            margin: const EdgeInsets.all(30),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1),
                boxShadow: [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.2), blurRadius: 30)]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events, size: 60, color: Color(0xFFD4AF37)),
                const SizedBox(height: 20),
                Text(
                  result,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold, height: 1.5),
                ),
                const SizedBox(height: 40),
                if (widget.isAdmin)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () => _auctionService.continueAuction(widget.seasonId),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Text("SIGUIENTE JUGADOR ➡️", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  )
                else
                  const Column(
                    children: [
                      CircularProgressIndicator(color: Colors.white24),
                      SizedBox(height: 20),
                      Text("Esperando al administrador...", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                    ],
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseHeader(Map data) {
    String phaseName = data['phaseName'] ?? "Iniciando...";
    int phaseIdx = data['phaseIndex'] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
      ),
      child: Column(
        children: [
          Text(
            "FASE ${phaseIdx + 1}: ${phaseName.toUpperCase()}",
            style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          if (data['skipsConsecutive'] != null && data['skipsConsecutive'] > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("⚠ Skips consecutivos: ${data['skipsConsecutive']}/3", style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Map player, Map auctionData) {
    int rating = player['rating'] ?? 0;
    String name = player['name'] ?? "Desconocido";
    String pos = player['position'] ?? "";
    int currentBid = auctionData['currentBid'] ?? 0;
    String? bidderName = auctionData['highestBidderName'];
    Color cardColor = _getRatingColor(rating);

    return Column(
      children: [
        // TEMPORIZADOR
        Container(
          width: 100, height: 100,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _timeLeft <= 5 ? Colors.redAccent : Colors.white10, width: 4),
              boxShadow: _timeLeft <= 5 ? [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 20)] : []
          ),
          child: Text(
            "$_timeLeft",
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: _timeLeft <= 5 ? Colors.redAccent : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 30),

        // TARJETA DE JUGADOR
        Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cardColor, width: 1.5),
              boxShadow: [BoxShadow(color: cardColor.withOpacity(0.3), blurRadius: 25, spreadRadius: -5)]
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$rating", style: TextStyle(color: cardColor, fontSize: 32, fontWeight: FontWeight.w900)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(4)),
                    child: Text(pos, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Icon(Icons.person, size: 80, color: Colors.white.withOpacity(0.8)),
              const SizedBox(height: 10),
              Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),

              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),

              const Text("OFERTA ACTUAL", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("\$${(currentBid/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.w900)),

              const SizedBox(height: 5),
              if (bidderName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFD4AF37).withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text("👑 $bidderName", style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold)),
                )
              else
                const Text("---", style: TextStyle(color: Colors.white30)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserControls(Map auctionData) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              border: const Border(top: BorderSide(color: Colors.white12))
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUserId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              var userData = snapshot.data!.data() as Map<String, dynamic>;

              int myBudget = userData['budget'] ?? 0;
              Map myStatus = userData['auctionStatus'] ?? {};
              String myName = userData['teamName'] ?? "Yo";

              int phaseIndex = auctionData['phaseIndex'];
              if (phaseIndex >= AuctionService.PHASES.length) return const SizedBox();

              var phaseConfig = AuctionService.PHASES[phaseIndex];
              String currentPosNeeded = phaseConfig['position'];
              int maxNeeded = phaseConfig['count'];
              int iHave = myStatus[currentPosNeeded] ?? 0;
              bool completed = iHave >= maxNeeded;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("TU PRESUPUESTO", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                          Text("\$${(myBudget/1000000).toStringAsFixed(1)}M", style: TextStyle(color: myBudget < 40000000 ? Colors.redAccent : Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("NECESITAS: $currentPosNeeded", style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                          Text(completed ? "✅ COMPLETO" : "$iHave / $maxNeeded", style: TextStyle(color: completed ? Colors.green : Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  if (completed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                      child: const Center(child: Text("Ya cubriste esta posición.", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                    )
                  else if (myBudget < (auctionData['currentBid'] + 5000000))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.3))),
                      child: const Center(child: Text("Fondos insuficientes para superar.", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                    )
                  else
                    Row(
                      children: [
                        _bidBtn("+5M", 5000000, Colors.blueAccent, auctionData['currentBid'], myName),
                        const SizedBox(width: 10),
                        _bidBtn("+10M", 10000000, Colors.deepPurpleAccent, auctionData['currentBid'], myName),
                        const SizedBox(width: 10),
                        _bidBtn("+30M", 30000000, Colors.orangeAccent, auctionData['currentBid'], myName),
                      ],
                    ),

                  const SizedBox(height: 10),
                  if (!completed)
                    const Text("Si el tiempo acaba y no vas ganando, pasas.", style: TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _bidBtn(String label, int amount, Color color, int currentBid, String myName) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _placeBid(currentBid, amount, myName),
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 5,
            shadowColor: color.withOpacity(0.5)
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
    );
  }

  Color _getRatingColor(int r) {
    if (r >= 90) return Colors.black;
    if (r >= 85) return const Color(0xFFD4AF37); // Se usará para borde oscuro en contexto claro, aquí invertimos lógica en UI
    if (r >= 80) return const Color(0xFF9C8029);
    if (r >= 75) return Colors.grey;
    return const Color(0xFFCD7F32);
  }
}