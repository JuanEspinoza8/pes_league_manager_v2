import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsScreen extends StatelessWidget {
  final String seasonId;
  const NotificationsScreen({super.key, required this.seasonId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("PRENSA OFICIAL", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('seasons')
            .doc(seasonId)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.newspaper, size: 60, color: Colors.white10),
                  SizedBox(height: 10),
                  Text("Sin novedades por ahora", style: TextStyle(color: Colors.white24)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              String type = data['type'] ?? 'INFO';
              Timestamp? ts = data['createdAt'];
              String timeStr = "";
              if (ts != null) {
                timeStr = timeago.format(ts.toDate(), locale: 'en_short');
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E293B), // Tarjeta oscura V2
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5)]
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _getIconBgColor(type).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _getIconBgColor(type).withOpacity(0.3))
                        ),
                        child: Icon(_getIcon(type), color: _getIconBgColor(type), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    data['title'] ?? "Noticia",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  timeStr,
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              data['body'] ?? "",
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'MATCH': return Icons.sports_soccer;
      case 'TRANSFER': return Icons.swap_horiz;
      case 'AUCTION': return Icons.gavel;
      default: return Icons.info_outline;
    }
  }

  Color _getIconBgColor(String type) {
    switch (type) {
      case 'MATCH': return Colors.greenAccent;
      case 'TRANSFER': return Colors.amber;
      case 'AUCTION': return Colors.purpleAccent;
      default: return Colors.blueAccent;
    }
  }
}