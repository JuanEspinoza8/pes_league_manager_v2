import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Asegurate de tener intl o formatea la fecha simple

class NewsTab extends StatelessWidget {
  final String seasonId;
  const NewsTab({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('seasons')
            .doc(seasonId)
            .collection('news')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.newspaper, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  const Text("El diario está vacío...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              return _NewsCard(doc: doc);
            },
          );
        },
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final DocumentSnapshot doc;
  const _NewsCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    List likes = data['likes'] ?? [];
    bool isLiked = likes.contains(currentUserId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Logo del Diario o Liga)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.sports_soccer, size: 20, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("PES LEAGUE NEWS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(_formatDate(data['timestamp']), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                const Icon(Icons.more_horiz),
              ],
            ),
          ),

          // Imagen (Cuadrada 1:1 o 4:5)
          GestureDetector(
            onDoubleTap: () => _toggleLike(doc.reference, currentUserId, likes),
            child: AspectRatio(
              aspectRatio: 4 / 4,
              child: Image.network(
                data['imageUrl'] ?? '',
                fit: BoxFit.cover,
                loadingBuilder: (c, child, progress) {
                  if (progress == null) return child;
                  return Container(color: Colors.grey[200], child: const Center(child: CircularProgressIndicator()));
                },
                errorBuilder: (c, e, s) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleLike(doc.reference, currentUserId, likes),
                  child: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.black, size: 28),
                ),
                const SizedBox(width: 15),
                const Icon(Icons.mode_comment_outlined, size: 26),
                const SizedBox(width: 15),
                const Icon(Icons.send_outlined, size: 26),
              ],
            ),
          ),

          // Likes Count
          if (likes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text("${likes.length} Me gusta", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),

          // Caption (Título y Cuerpo)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  TextSpan(text: "${data['title']} ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  TextSpan(text: "\n${data['body']}", style: const TextStyle(fontSize: 14, height: 1.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleLike(DocumentReference ref, String uid, List currentLikes) {
    if (currentLikes.contains(uid)) {
      ref.update({'likes': FieldValue.arrayRemove([uid])});
    } else {
      ref.update({'likes': FieldValue.arrayUnion([uid])});
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Hace un momento";
    if (timestamp is Timestamp) {
      DateTime date = timestamp.toDate();
      Duration diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return "Hace ${diff.inMinutes} min";
      if (diff.inHours < 24) return "Hace ${diff.inHours} h";
      return "${date.day}/${date.month}";
    }
    return "";
  }
}