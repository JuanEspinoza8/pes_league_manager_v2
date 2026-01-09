import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// Importamos esto para formatear fechas relativas si es necesario,
// o usamos la lógica simple que ya tenías.

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
              // Pasamos seasonId a la tarjeta
              return _NewsCard(doc: doc, seasonId: seasonId);
            },
          );
        },
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final String seasonId; // Necesario para buscar datos del usuario al comentar

  const _NewsCard({required this.doc, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    List likes = data['likes'] ?? [];
    bool isLiked = likes.contains(currentUserId);
    int commentCount = data['commentCount'] ?? 0; // Leemos el contador si existe

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
                // Botón de Comentarios
                GestureDetector(
                  onTap: () => _showCommentsModal(context),
                  child: const Icon(Icons.mode_comment_outlined, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.send_outlined, size: 26, color: Colors.white),
              ],
            ),
          ),

          // Likes Count & Comment Count
          if (likes.isNotEmpty || commentCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (likes.isNotEmpty) Text("${likes.length} Me gusta", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                  if (likes.isNotEmpty && commentCount > 0) const SizedBox(width: 10),
                  if (commentCount > 0) GestureDetector(
                    onTap: () => _showCommentsModal(context),
                    child: Text(
                      "$commentCount comentarios",
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  )
                ],
              ),
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

  void _showCommentsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Para que suba con el teclado
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CommentsSheet(newsRef: doc.reference, seasonId: seasonId),
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

// --- WIDGET PARA LA HOJA DE COMENTARIOS ---
class _CommentsSheet extends StatefulWidget {
  final DocumentReference newsRef;
  final String seasonId;

  const _CommentsSheet({required this.newsRef, required this.seasonId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    // Calculamos la altura para dejar ver el teclado
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7, // Ocupa el 70% de la pantalla
        child: Column(
          children: [
            // Barra superior del modal
            Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10))
              ),
              child: const Center(child: Text("Comentarios", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ),

            // Lista de comentarios
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: widget.newsRef.collection('comments').orderBy('timestamp', descending: false).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                  if (snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("Sé el primero en comentar.", style: TextStyle(color: Colors.white38)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var c = snapshot.data!.docs[index];
                      var data = c.data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white10,
                              child: Text((data['userName'] ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['userName'] ?? "Usuario", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(data['text'] ?? "", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                ],
                              ),
                            ),
                            Text(_miniDate(data['timestamp']), style: const TextStyle(color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Input de texto
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  border: Border(top: BorderSide(color: Colors.white10))
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Escribe un comentario...",
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFD4AF37), strokeWidth: 2))
                        : const Icon(Icons.send, color: Color(0xFFD4AF37)),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _sendComment() async {
    String text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      // 1. Buscamos el nombre del equipo/usuario
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('seasons').doc(widget.seasonId)
          .collection('participants').doc(uid).get();

      String userName = "Usuario";
      if (userDoc.exists) {
        var data = userDoc.data() as Map<String, dynamic>;
        userName = data['teamName'] ?? data['name'] ?? "Usuario";
      }

      // 2. Guardamos el comentario en una transacción para actualizar el contador a la vez
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Referencia a nueva doc de comentario
        DocumentReference newCommentRef = widget.newsRef.collection('comments').doc();

        // Escribimos el comentario
        transaction.set(newCommentRef, {
          'userId': uid,
          'userName': userName,
          'text': text,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Incrementamos el contador en la noticia
        transaction.update(widget.newsRef, {
          'commentCount': FieldValue.increment(1)
        });
      });

      _commentCtrl.clear();
      // Cerramos el teclado
      FocusScope.of(context).unfocus();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isSending = false);
    }
  }

  String _miniDate(dynamic timestamp) {
    if (timestamp == null) return "Ahora";
    if (timestamp is Timestamp) {
      DateTime d = timestamp.toDate();
      return "${d.hour}:${d.minute.toString().padLeft(2, '0')}";
    }
    return "";
  }
}