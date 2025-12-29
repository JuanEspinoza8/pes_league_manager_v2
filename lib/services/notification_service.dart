import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  // Enviar una notificación global a la temporada
  static Future<void> sendGlobalNotification({
    required String seasonId,
    required String title,
    required String body,
    String type = 'INFO', // INFO, MATCH, TRANSFER
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('seasons').doc(seasonId)
          .collection('notifications')
          .add({
        'title': title,
        'body': body,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': [], // Lista de usuarios que ya la leyeron (para el puntito rojo)
      });
    } catch (e) {
      print("Error enviando notificación: $e");
    }
  }
}