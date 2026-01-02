import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NewsTab extends StatelessWidget {
  final String seasonId;
  const NewsTab({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1120), // Fondo Negro Profundo
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('seasons')
            .doc(seasonId)
            .collection('news')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.newspaper, size: 60, color: Colors.white10),
                  SizedBox(height: 10),
                  Text("El diario está vacío...", style: TextStyle(color: Colors.white24)),
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
      margin: const EdgeInsets.only(bottom: 20),
      color: const Color(0xFF1E293B), // Slate 800 (Card BG)
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD4AF37), width: 1)),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black,
                    child: Icon(Icons.sports_soccer, size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("PES LEAGUE NEWS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white, letterSpacing: 0.5)),
                    Text(_formatDate(data['timestamp']), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                const Icon(Icons.more_horiz, color: Colors.white54),
              ],
            ),
          ),

          // Imagen
          GestureDetector(
            onDoubleTap: () => _toggleLike(doc.reference, currentUserId, likes),
            child: AspectRatio(
              aspectRatio: 1, // 1:1 Cuadrado
              child: Image.network(
                data['imageUrl'] ?? '',
                fit: BoxFit.cover,
                loadingBuilder: (c, child, progress) {
                  if (progress == null) return child;
                  return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
                },
                errorBuilder: (c, e, s) => Container(color: Colors.black12, child: const Icon(Icons.broken_image, color: Colors.white24)),
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleLike(doc.reference, currentUserId, likes),
                  child: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.redAccent : Colors.white, size: 28),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.mode_comment_outlined, size: 26, color: Colors.white),
                const SizedBox(width: 20),
                const Icon(Icons.send_outlined, size: 26, color: Colors.white),
              ],
            ),
          ),

          // Likes Count
          if (likes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text("${likes.length} Me gusta", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),

          // Caption
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white),
                children: [
                  TextSpan(text: "${data['title']} ", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  TextSpan(text: "\n${data['body']}", style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- LÓGICA INTACTA ---
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