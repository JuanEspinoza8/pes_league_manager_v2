import 'dart:async';
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
      if (mounted) setState(() => _timeLeft = 0);
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

      // AUTO-RESOLVER CUANDO EL TIEMPO LLEGA A 0 (SOLO ADMIN)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("DRAFT TÁCTICO"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.red),
              onPressed: () => _auctionService.drawNextPlayer(widget.seasonId),
              tooltip: "Forzar siguiente jugador",
            )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('auction').doc('status').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) {
            return Center(
              child: widget.isAdmin
                  ? ElevatedButton(onPressed: () => _auctionService.initializeAuction(widget.seasonId), child: const Text("INICIAR DRAFT"))
                  : const Text("Esperando al administrador...", style: TextStyle(color: Colors.white)),
            );
          }

          var auctionData = snapshot.data!.data() as Map<String, dynamic>;

          bool isActive = auctionData['active'] ?? false;
          if (!isActive) return const Center(child: Text("SUBASTA FINALIZADA", style: TextStyle(color: Colors.white, fontSize: 30)));

          // --- PANTALLA DE PAUSA / RESULTADO ---
          String state = auctionData['state'] ?? 'BIDDING';
          if (state == 'PAUSED') {
            return _buildPauseScreen(auctionData);
          }

          // --- PANTALLA DE PUJA (BIDDING) ---
          _syncTimer(auctionData['timerEnd']);

          return Column(
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
          );
        },
      ),
    );
  }

  // --- NUEVA PANTALLA DE PAUSA ---
  Widget _buildPauseScreen(Map auctionData) {
    String result = auctionData['lastResult'] ?? "Ronda finalizada";

    return Center(
      child: Container(
        margin: const EdgeInsets.all(30),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 30)]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 60, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              result,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            if (widget.isAdmin)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _auctionService.continueAuction(widget.seasonId),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text("SIGUIENTE JUGADOR ➡️", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              )
            else
              const Text("Esperando al administrador...", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic))
          ],
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
      color: Colors.amber.withOpacity(0.1),
      child: Column(
        children: [
          Text(
            "FASE ${phaseIdx + 1}: ${phaseName.toUpperCase()}",
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          if (data['skipsConsecutive'] != null && data['skipsConsecutive'] > 0)
            Text("⚠ Skips consecutivos: ${data['skipsConsecutive']}/3", style: const TextStyle(color: Colors.redAccent, fontSize: 12))
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

    return Column(
      children: [
        Text(
          "$_timeLeft",
          style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w900,
              color: _timeLeft <= 10 ? Colors.red : Colors.white,
              shadows: [Shadow(color: _timeLeft <= 10 ? Colors.red : Colors.blue, blurRadius: 20)]
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.grey.shade900, Colors.black]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getRatingColor(rating), width: 2),
              boxShadow: [BoxShadow(color: _getRatingColor(rating).withOpacity(0.4), blurRadius: 20)]
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$rating", style: TextStyle(color: _getRatingColor(rating), fontSize: 28, fontWeight: FontWeight.w900)),
                  Text(pos, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const Icon(Icons.person, size: 100, color: Colors.white),
              Text(name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              const Text("OFERTA ACTUAL", style: TextStyle(color: Colors.grey, fontSize: 10)),
              Text("\$${(currentBid/1000000).toStringAsFixed(1)}M", style: const TextStyle(color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.bold)),
              if (bidderName != null)
                Text("Ganando: $bidderName", style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              if (bidderName == null)
                const Text("Sin ofertas", style: TextStyle(color: Colors.white30)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserControls(Map auctionData) {
    return StreamBuilder<DocumentSnapshot>(
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

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("TU PRESUPUESTO", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                      Text("\$${(myBudget/1000000).toStringAsFixed(1)}M", style: TextStyle(color: myBudget < 40000000 ? Colors.red : Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("TUS ${currentPosNeeded}", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                      Text(completed ? "✅ LISTO" : "$iHave / $maxNeeded", style: TextStyle(color: completed ? Colors.green : Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 15),

              if (completed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text("Ya completaste esta posición.", style: TextStyle(color: Colors.green))),
                )
              else if (myBudget < (auctionData['currentBid'] + 5000000))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text("Sin fondos suficientes.", style: TextStyle(color: Colors.red))),
                )
              else
                Row(
                  children: [
                    _bidBtn("+5M", 5000000, Colors.blue, auctionData['currentBid'], myName),
                    const SizedBox(width: 10),
                    _bidBtn("+10M", 10000000, Colors.purple, auctionData['currentBid'], myName),
                    const SizedBox(width: 10),
                    _bidBtn("+30M", 30000000, Colors.orange, auctionData['currentBid'], myName),
                  ],
                ),

              const SizedBox(height: 10),
              if (!completed)
                const Text("Si el tiempo acaba y no eres el mayor postor, pasas.", style: TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }

  Widget _bidBtn(String label, int amount, Color color, int currentBid, String myName) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _placeBid(currentBid, amount, myName),
        style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Color _getRatingColor(int r) {
    if (r >= 85) return Colors.black;
    if (r >= 80) return const Color(0xFFD4AF37);
    if (r >= 75) return const Color(0xFFC0C0C0);
    return const Color(0xFFCD7F32);
  }
}