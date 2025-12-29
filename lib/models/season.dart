import 'package:cloud_firestore/cloud_firestore.dart';

class Season {
  final String id;
  final String name;
  final String code; // Código de 6 letras para unirse
  final String adminId; // El que puede expulsar gente
  final String status; // 'WAITING', 'AUCTION', 'ACTIVE', 'FINISHED'
  final int initialBudget; // Dinero inicial (ej: 100M)
  final int maxPlayers;

  // Lista de IDs de usuarios que están dentro
  final List<String> participantIds;

  Season({
    required this.id,
    required this.name,
    required this.code,
    required this.adminId,
    required this.status,
    required this.initialBudget,
    required this.maxPlayers,
    required this.participantIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'adminId': adminId,
      'status': status,
      'initialBudget': initialBudget,
      'maxPlayers': maxPlayers,
      'participantIds': participantIds,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Season.fromMap(Map<String, dynamic> map, String id) {
    return Season(
      id: id,
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      adminId: map['adminId'] ?? '',
      status: map['status'] ?? 'WAITING',
      initialBudget: map['initialBudget'] ?? 100,
      maxPlayers: map['maxPlayers'] ?? 10,
      participantIds: List<String>.from(map['participantIds'] ?? []),
    );
  }
}