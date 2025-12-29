import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mercado de Jugadores"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          )
        ],
      ),
      // StreamBuilder escucha la base de datos en tiempo real
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('players').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error al cargar datos"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text("No hay jugadores en la base de datos 'players'"),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              // Usamos los nombres de campos que definimos en el chat anterior
              final String name = data['name'] ?? 'Sin Nombre';
              final int rating = data['rating'] ?? 0;
              final String team = data['team'] ?? 'Libre';
              final String position = data['position'] ?? '?';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getColorByRating(rating),
                    child: Text(
                      rating.toString(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text("$position - $team"),
                  trailing: const Icon(Icons.add_circle_outline),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getColorByRating(int rating) {
    if (rating >= 90) return Colors.purple; // Prime/Leyenda
    if (rating >= 80) return Colors.amber[800]!; // Gold
    return Colors.grey; // Silver/Bronze
  }
}