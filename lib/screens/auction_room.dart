import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuctionRoom extends StatefulWidget {
  final String seasonId;
  final bool isAdmin;
  const AuctionRoom({super.key, required this.seasonId, required this.isAdmin});

  @override
  State<AuctionRoom> createState() => _AuctionRoomState();
}

class _AuctionRoomState extends State<AuctionRoom> {
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  DocumentSnapshot? currentPlayer;
  Timer? _timer;
  int _timeLeft = 30;
  bool _isAuctionActive = false;

  @override
  void initState() {
    super.initState();
    _listenToAuction();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _listenToAuction() {
    FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      var data = snapshot.data() as Map<String, dynamic>;
      var auctionData = data['currentAuction'];

      if (auctionData != null) {
        setState(() {
          _isAuctionActive = true;
          _timeLeft = auctionData['endTime'].toDate().difference(DateTime.now()).inSeconds;
        });
        if (currentPlayer == null || currentPlayer!.id != auctionData['playerId']) {
          _loadPlayer(auctionData['playerId']);
        }
        _startLocalTimer();
      } else {
        setState(() {
          _isAuctionActive = false;
          currentPlayer = null;
          _timer?.cancel();
        });
      }
    });
  }

  Future<void> _loadPlayer(String playerId) async {
    var doc = await FirebaseFirestore.instance.collection('players').doc(playerId).get();
    setState(() => currentPlayer = doc);
  }

  void _startLocalTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _placeBid(int currentBid, int increment) async {
    int newBid = currentBid + increment;

    // Obtener mi presupuesto
    var myDoc = await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(currentUserId).get();
    int myBudget = myDoc.data()?['budget'] ?? 0;

    if (myBudget < newBid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fondos insuficientes!"), backgroundColor: Colors.red));
      return;
    }

    DateTime newEndTime = DateTime.now().add(const Duration(seconds: 15)); // Anti-sniper

    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({
      'currentAuction.currentBid': newBid,
      'currentAuction.highestBidder': currentUserId,
      'currentAuction.endTime': newEndTime, // Reset tiempo si puja al final
    });
  }

  Future<void> _startNewAuction() async {
    // Admin saca jugador random
    var players = await FirebaseFirestore.instance.collection('players').where('rating', isGreaterThan: 80).limit(50).get();
    var randomDoc = players.docs.toList()..shuffle();
    var player = randomDoc.first;

    await FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).update({
      'currentAuction': {
        'playerId': player.id,
        'currentBid': 1000000, // 1M base
        'highestBidder': null,
        'endTime': DateTime.now().add(const Duration(seconds: 30))
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Fondo oscuro
      appBar: AppBar(
        title: const Text("SALA DE SUBASTAS"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          var auction = data['currentAuction'];

          if (auction == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gavel, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text("ESPERANDO SUBASTA...", style: TextStyle(color: Colors.white, fontSize: 18)),
                  if (widget.isAdmin)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ElevatedButton(onPressed: _startNewAuction, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), child: const Text("SACAR JUGADOR AL AZAR")),
                    )
                ],
              ),
            );
          }

          int currentBid = auction['currentBid'];
          String? bidderId = auction['highestBidder'];

          return Column(
            children: [
              // --- CRONÓMETRO ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: _timeLeft < 10 ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
                child: Center(
                  child: Text(
                    "$_timeLeft s",
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: _timeLeft < 10 ? Colors.redAccent : Colors.lightBlueAccent,
                        shadows: [Shadow(blurRadius: 10, color: (_timeLeft < 10 ? Colors.red : Colors.blue))]
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- TARJETA DE JUGADOR ---
              if (currentPlayer != null)
                Center(child: _buildPlayerCard(currentPlayer!.data() as Map<String, dynamic>)),

              const SizedBox(height: 20),

              // --- PUJA ACTUAL ---
              Text("PUJA ACTUAL", style: TextStyle(color: Colors.grey[400], letterSpacing: 2)),
              Text(
                "\$${(currentBid / 1000000).toStringAsFixed(1)}M",
                style: const TextStyle(color: Colors.amber, fontSize: 36, fontWeight: FontWeight.bold),
              ),
              if (bidderId != null)
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('seasons').doc(widget.seasonId).collection('participants').doc(bidderId).get(),
                  builder: (c, s) => Text("Ganando: ${s.data?['teamName'] ?? '...'}", style: const TextStyle(color: Colors.white70)),
                )
              else
                const Text("Sin ofertas", style: TextStyle(color: Colors.white30)),

              const Spacer(),

              // --- BOTONES DE PUJA ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))
                ),
                child: Row(
                  children: [
                    _bidButton(currentBid, 100000, "+100K", Colors.blue),
                    const SizedBox(width: 10),
                    _bidButton(currentBid, 1000000, "+1M", Colors.green),
                    const SizedBox(width: 10),
                    _bidButton(currentBid, 5000000, "+5M", Colors.purple),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _bidButton(int currentBid, int amount, String label, Color color) {
    return Expanded(
      child: ElevatedButton(
        onPressed: _timeLeft > 0 ? () => _placeBid(currentBid, amount) : null,
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> p) {
    int rating = p['rating'] ?? 75;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.amber[100]!, Colors.amber[600]!]),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [const BoxShadow(color: Colors.amber, blurRadius: 15, spreadRadius: 1)],
          border: Border.all(color: Colors.white, width: 2)
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("$rating", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              Text(p['position'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          const Icon(Icons.person, size: 80),
          const SizedBox(height: 10),
          Text(p['name'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(p['team'], style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}