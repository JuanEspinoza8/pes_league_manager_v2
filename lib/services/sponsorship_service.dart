import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'news_service.dart';

class SponsorshipService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<Map<String, dynamic>> BRANDS = [
    {'name': 'Local Store', 'tier': 1, 'multiplier': 1.0, 'icon': '🏪'},
    {'name': 'Generic Sport', 'tier': 1, 'multiplier': 1.2, 'icon': '👟'},
    {'name': 'Puma', 'tier': 2, 'multiplier': 2.0, 'icon': '🐆'},
    {'name': 'Adidas', 'tier': 3, 'multiplier': 3.5, 'icon': '🕉️'},
    {'name': 'Nike', 'tier': 3, 'multiplier': 3.8, 'icon': '✔️'},
    {'name': 'Emirates', 'tier': 3, 'multiplier': 4.0, 'icon': '✈️'},
  ];

  static const List<String> OBJECTIVES = [
    "Ganar los próximos 2 partidos de Liga.",
    "Marcar 5 goles en total en los próximos 3 partidos.",
    "Mantener la valla invicta en 2 de los próximos 4 partidos.",
    "Alinear a 3 jugadores de menos de 75 de media en el próximo partido y ganar.",
    "No recibir tarjetas rojas en los próximos 5 partidos.",
    "Ganar el próximo partido por una diferencia de 3 goles o más.",
  ];

  // 1. GENERAR OFERTA (Lógica Modificada)
  Future<void> tryGenerateSponsorshipOffer(String seasonId, String userId, String teamName) async {
    // A. PASO 1: Verificar si ya tiene un contrato ACEPTADO (Activo o en revisión)
    // Si ya aceptó uno, NO le deben llegar más ofertas hasta que lo termine o abandone.
    var activeContracts = await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships')
        .where('status', whereIn: ['ACTIVE', 'PENDING_REVIEW'])
        .get();

    if (activeContracts.docs.isNotEmpty) {
      // Ya tiene trabajo, no molestamos.
      return;
    }

    // B. PASO 2: Tirar los dados de la suerte
    final random = Random();
    // 30% de probabilidad de recibir oferta al ganar
    if (random.nextDouble() > 0.30) return;

    // --- ¡NUEVA OFERTA EN CAMINO! ---

    // C. PASO 3: Limpiar ofertas viejas NO aceptadas
    // Si llegamos aquí, es porque salió una nueva. Si el usuario tenía una oferta "vísta" pendiente ('OFFER'),
    // la borramos para reemplazarla por esta nueva (el tren pasa una sola vez).
    var pendingOffers = await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships')
        .where('status', isEqualTo: 'OFFER')
        .get();

    for (var doc in pendingOffers.docs) {
      await doc.reference.delete();
    }

    // D. PASO 4: Crear la nueva oferta
    var brand = BRANDS[random.nextInt(BRANDS.length)];
    String objective = OBJECTIVES[random.nextInt(OBJECTIVES.length)];

    int baseReward = 1000000; // 1M base
    double variation = 0.8 + random.nextDouble() * 0.4; // 0.8 a 1.2
    int finalReward = (baseReward * (brand['multiplier'] as double) * variation).round();

    // Redondear a decenas de miles para que se vea bonito
    finalReward = (finalReward ~/ 10000) * 10000;

    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').add({
      'brandName': brand['name'],
      'brandIcon': brand['icon'],
      'tier': brand['tier'],
      'description': objective,
      'reward': finalReward,
      'status': 'OFFER', // Llega como oferta
      'createdAt': FieldValue.serverTimestamp(),
    });

    print("✅ Nueva oferta generada para $teamName: ${brand['name']} (Reemplazando anteriores si había)");
  }

  // 2. ACEPTAR OFERTA
  Future<void> acceptOffer(String seasonId, String userId, String contractId) async {
    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').doc(contractId).update({
      'status': 'ACTIVE',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  // 3. RECHAZAR / DESCARTAR OFERTA
  Future<void> rejectOffer(String seasonId, String userId, String contractId) async {
    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').doc(contractId).delete();
  }

  // 4. ABANDONAR CONTRATO
  Future<void> abandonContract(String seasonId, String userId, String contractId) async {
    await rejectOffer(seasonId, userId, contractId);
  }

  // 5. SOLICITAR VERIFICACIÓN
  Future<void> requestVerification(String seasonId, String userId, String contractId) async {
    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').doc(contractId).update({
      'status': 'PENDING_REVIEW',
    });
  }

  // 6. ADMIN: APROBAR Y PAGAR
  Future<void> approveAndPay(String seasonId, String userId, String contractId, int amount, String teamName, String brandName) async {
    WriteBatch batch = _db.batch();

    var contractRef = _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').doc(contractId);

    var userRef = _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId);

    // Marcar como completado
    batch.update(contractRef, {'status': 'COMPLETED', 'completedAt': FieldValue.serverTimestamp()});

    // Depositar dinero
    batch.update(userRef, {'budget': FieldValue.increment(amount)});

    await batch.commit();

    // Generar Noticia
    NewsService().createSponsorshipNews(
        seasonId: seasonId,
        teamName: teamName,
        brandName: brandName,
        amount: amount
    );
  }

  // 7. ADMIN: RECHAZAR
  Future<void> denyClaim(String seasonId, String userId, String contractId) async {
    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').doc(contractId).update({
      'status': 'ACTIVE', // Lo devolvemos a activo para que siga intentando
    });
  }
}