import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'news_service.dart';

class SponsorshipService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<Map<String, dynamic>> BRANDS = [
    {'name': 'Churreria La Araña', 'tier': 1, 'multiplier': 0.7, 'icon': '🏪'},
    {'name': 'Mateo Maderas', 'tier': 1, 'multiplier': 1.0, 'icon': '🐴🪵'},
    {'name': 'El Buen Gusto', 'tier': 2, 'multiplier': 1.3, 'icon': '🏪'},
    {'name': 'Claudia Montanaro', 'tier': 2, 'multiplier': 1.5, 'icon': '💁‍♀️️'},
    {'name': 'Carrefour', 'tier': 2, 'multiplier': 2.0, 'icon': '🥖'},
    {'name': 'Spotify', 'tier': 3, 'multiplier': 2.5, 'icon': '🎵'},
    {'name': 'Presidente Chiki Oso', 'tier': 3, 'multiplier': 3.0, 'icon': '⚽'},
  ];

  // CAMBIO 1: Los objetivos ahora tienen un precio base según su dificultad.
  static const List<Map<String, dynamic>> OBJECTIVES = [
    {
      "description": "Ganar los próximos 2 partidos de Liga.",
      "basePayment": 80000000 // Difícil, paga bien base
    },
    {
      "description": "Marcar 5 goles en total en los próximos 3 partidos.",
      "basePayment": 10000000 // Medio
    },
    {
      "description": "Mantener la valla invicta en 2 de los próximos 4 partidos.",
      "basePayment": 18000000 // Difícil para equipos chicos
    },
    {
      "description": "Alinear a los 3 jugadores de menos media en el próximo partido contra un equipo +1000 ELO y ganar.",
      "basePayment": 25000000 // Muy Arriesgado, paga mucho
    },
    {
      "description": "No recibir tarjetas rojas en los próximos 5 partidos.",
      "basePayment": 10000000 // Fácil, paga poco
    },
    {
      "description": "Ganar el próximo partido por una diferencia de 3 goles o más.",
      "basePayment": 25000000 // Muy Difícil
    },
    {
      "description": "Jugar el proximo partido con un 5-4-1 y ganar",
      "basePayment": 30000000 // Muy Difícil
    },
    {
      "description": "Obetene una posesion superior al 60% en tu proximo partido",
      "basePayment": 8000000 // Muy Difícil
    },
    {
      "description": "Obetene una posesion menor al 40% en tu proximo partido",
      "basePayment": 8000000 // Muy Difícil
    },
    {
      "description": "Logra 10 tiros al arco (no afuera) en el proximo partido",
      "basePayment": 10000000 // Muy Difícil
    },
    {
      "description": "Alcanza 150 pases en el proximo partido",
      "basePayment": 12000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga 3 goles en un solo partido",
      "basePayment": 20000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga 4 goles en un solo partido",
      "basePayment": 35000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga 5 goles en un solo partido",
      "basePayment": 50000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga 3 goles de cabeza en 2 partidos",
      "basePayment": 15000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga un gol de chinela (bien hecho, no volea ni tijera)",
      "basePayment": 20000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga un gol de tiro libre cercano",
      "basePayment": 10000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga un gol de tiro libre lejano",
      "basePayment": 15000000 // Muy Difícil
    },
    {
      "description": "Logra que un jugador haga un gol olimpico",
      "basePayment": 70000000 // Muy Difícil
    },
  ];

  // 1. GENERAR OFERTA (Lógica Modificada)
  Future<void> tryGenerateSponsorshipOffer(String seasonId, String userId, String teamName) async {
    // A. PASO 1: Verificar si ya tiene un contrato ACEPTADO
    var activeContracts = await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships')
        .where('status', whereIn: ['ACTIVE', 'PENDING_REVIEW'])
        .get();

    if (activeContracts.docs.isNotEmpty) {
      return;
    }

    // B. PASO 2: Probabilidad
    final random = Random();
    if (random.nextDouble() > 0.30) return;

    // C. PASO 3: Limpiar ofertas viejas
    var pendingOffers = await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships')
        .where('status', isEqualTo: 'OFFER')
        .get();

    for (var doc in pendingOffers.docs) {
      await doc.reference.delete();
    }

    // D. PASO 4: Crear la nueva oferta con Lógica Dinámica

    // Seleccionamos Marca y Objetivo
    var brand = BRANDS[random.nextInt(BRANDS.length)];
    var objectiveData = OBJECTIVES[random.nextInt(OBJECTIVES.length)];

    // CAMBIO 2: Cálculo del dinero
    // Obtenemos el pago base del objetivo específico
    int objectiveBaseReward = objectiveData['basePayment'] as int;

    // Obtenemos el multiplicador de la marca (Ej: Nike paga x3.8, Local Store x1.0)
    double brandMultiplier = brand['multiplier'] as double;

    // Factor de negociación aleatoria (entre 0.9 y 1.1 para pequeña variación)
    double randomVariation = 0.9 + random.nextDouble() * 0.2;

    // FÓRMULA FINAL: (Base del Objetivo * Multiplicador Marca * Variación)
    int finalReward = (objectiveBaseReward * brandMultiplier * randomVariation).round();

    // Redondear a decenas de miles para que se vea "limpio" (ej: 1.240.000)
    finalReward = (finalReward ~/ 10000) * 10000;

    await _db.collection('seasons').doc(seasonId)
        .collection('participants').doc(userId)
        .collection('sponsorships').add({
      'brandName': brand['name'],
      'brandIcon': brand['icon'],
      'tier': brand['tier'],
      'description': objectiveData['description'], // Tomamos la descripción del mapa
      'reward': finalReward,
      'status': 'OFFER',
      'createdAt': FieldValue.serverTimestamp(),
    });

    print("✅ Nueva oferta generada para $teamName: ${brand['name']} - \$${finalReward}");
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