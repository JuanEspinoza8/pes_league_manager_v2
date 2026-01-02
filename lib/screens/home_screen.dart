import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("SCOUTING GLOBAL"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 20),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white70),
            onPressed: () {}, // Placeholder visual
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => AuthService().signOut(),
          )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('players').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error de conexión", style: TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.person_search, size: 60, color: Colors.white24),
                  SizedBox(height: 10),
                  Text("Base de datos vacía", style: TextStyle(color: Colors.white24)),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // 2 columnas para aspecto de cartas
              childAspectRatio: 0.85,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final String name = data['name'] ?? 'Desconocido';
              final int rating = data['rating'] ?? 0;
              final String team = data['team'] ?? 'Agente Libre';
              final String position = data['position'] ?? 'N/A';

              return Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0,4))]
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rating Badge
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _getColorByRating(rating), width: 2),
                      ),
                      child: Text(
                        rating.toString(),
                        style: TextStyle(color: _getColorByRating(rating), fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      position,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8)
                      ),
                      child: Text(
                        team,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getColorByRating(int rating) {
    if (rating >= 90) return Colors.purpleAccent; // Iconic
    if (rating >= 85) return Colors.black; // Black Ball
    if (rating >= 80) return const Color(0xFFD4AF37); // Gold
    if (rating >= 75) return Colors.grey; // Silver
    return Colors.brown[300]!; // Bronze
  }
}