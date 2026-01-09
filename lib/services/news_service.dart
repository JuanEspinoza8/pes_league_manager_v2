import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../services/news_service.dart';
import '../services/notification_service.dart';
import 'package:http/http.dart' as http;

class NewsService {
  // ⚠️ TUS API KEYS
  static const String _geminiApiKey = 'APIKEY';
  static const String _pollinationsApiKey = 'APIKEY';

  final String _cloudName = 'APIKEY';
  final String _uploadPreset = 'APIKEY';
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _fallbackImage = "https://images.unsplash.com/photo-1522770179533-24471fcdba45?q=80&w=1080&auto=format&fit=crop";

  // --- NUEVA FUNCIÓN: NOTICIA MANUAL CON IMAGEN PROPIA ---
  Future<void> createManualNews({
    required String seasonId,
    required String title,
    required String body,
    required Uint8List imageBytes,
  }) async {
    try {
      // 1. Subir imagen a Cloudinary (Reutilizamos la función existente)
      String imageUrl = await _uploadToCloudinary(imageBytes);

      // 2. Guardar en Firestore directamente (Sin pasar por IA)
      await _db.collection('seasons').doc(seasonId).collection('news').add({
        'type': 'CUSTOM_MANUAL',
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
        'meta': {'author': 'ADMIN'}
      });
    } catch (e) {
      print("❌ Error Manual News: $e");
      rethrow;
    }
  }
  // -------------------------------------------------------

  // --- 1. NOTICIA DE PARTIDO ---
  Future<void> createMatchNews({
    required String seasonId,
    required String homeName,
    required String awayName,
    required String homeId,
    required String awayId,
    required int homeScore,
    required int awayScore,
    String? competition,
    bool isPenalties = false,
    String? penaltyScore,
    String? winnerName,
    String? matchDetails,
    bool isDerby = false,
    String? homeForm,
    String? awayForm,
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);

      List<String> imgVariants = [
        "ACTION_SHOT: Close up cinematic shot of [PLAYER_NAME] dribbling, intense focus, wearing the $winnerName's jersey..",
        "GOAL_KICK: Action shot of [PLAYER_NAME] striking the ball with power, wearing the $winnerName's jersey.",
        "CELEBRATION: [PLAYER_NAME] screaming and jumping in celebration, wearing the $winnerName's jersey.",
        "MOTM_TROPHY: [PLAYER_NAME] smiling holding the 'Man of the Match' trophy, wearing the $winnerName's jersey.",
        "CROWD_CRAZY: The fans of $winnerName going crazy in the stands with flares.",
        "MANAGER_REACTION: The manager of $winnerName clapping hands from the sideline.",
        "TEAM_HUDDLE: Players of $winnerName hugging in a group celebration."
      ];

      String selectedVariant = (winnerName != null)
          ? imgVariants[Random().nextInt(imgVariants.length)]
          : imgVariants[0];

      print("🎲 [NewsService] Variante sorteada: $selectedVariant");

      // --- LÓGICA DE APARIENCIA DEL DT ---
      String managerLook = "";
      if (selectedVariant.contains("MANAGER_REACTION") && winnerName != null) {
        try {
          String winnerId = (winnerName == homeName) ? homeId : awayId;
          if (!winnerId.startsWith("TBD") && !winnerId.startsWith("GANADOR")) {
            var doc = await _db.collection('seasons').doc(seasonId).collection('participants').doc(winnerId).get();
            if (doc.exists && doc.data() != null && doc.data()!.containsKey('managerDescription')) {
              managerLook = doc.data()!['managerDescription'];
              print("🤵 [NewsService] Apariencia DT encontrada: $managerLook");
            }
          }
        } catch (e) {
          print("⚠️ Error buscando avatar DT: $e");
        }
      }
      // -----------------------------------

      String context = "PARTIDO: $homeName $homeScore - $awayScore $awayName ($competition).";
      if (winnerName != null) context += " Ganador: $winnerName.";
      if (isDerby) context += " ES UN CLÁSICO.";

      if (matchDetails != null && matchDetails.isNotEmpty) {
        context += " ESTADÍSTICAS REALES: $matchDetails.";
      }

      if (homeForm != null) context += " Contexto Local: $homeForm.";
      if (awayForm != null) context += " Contexto Visita: $awayForm.";

      // PROMPT ORIGINAL COMPLETO RESTAURADO
      final prompt = Content.text('''
        Eres un redactor deportivo. INFO PARTIDO: $context
        
        ⛔ REGLAS TEXTO: NO inventes DTs reales (Xavi, Pep). Cíñete a los datos.
        
        📸 REGLAS IMAGEN:
        1. Escena obligatoria: "$selectedVariant".
        2. Si la escena es MANAGER_REACTION y tienes esta descripción: "$managerLook", ÚSALA para dibujar al DT. Si no hay descripción, haz uno genérico.
        3. Si es un jugador, reemplaza [PLAYER_NAME] por el goleador real.
        4. Si es un jugador famoso, la cara debe ser "accurate lookalike".
        
        JSON: {
          "title": "TITULAR (Max 6 palabras)",
          "body": "Resumen corto con emojis.",
          "image_prompt": "Cinematic photo. $selectedVariant. ${managerLook.isNotEmpty ? 'The manager looks like: $managerLook.' : ''} Realistic, 4k."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'home': homeName, 'away': awayName, 'score': "$homeScore-$awayScore"});
    } catch (e) {
      print("❌ Error Match News: $e");
    }
  }

  // --- 2. NOTICIA DE TRASPASO ---
  Future<void> createTransferNews({required String seasonId, required String playerName, required String fromTeam, required String toTeam, required int price}) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
      String priceStr = "\$${(price / 1000000).toStringAsFixed(1)}M";

      List<String> imgVariants = [
        "PRESS CONFERENCE: $playerName speaking at a microphone.",
        "JERSEY PRESENTATION: $playerName holding the new $toTeam jersey.",
        "MEDICAL TEST: $playerName doing a thumbs up with sensors.",
        "CONTRACT SIGNING: $playerName signing a paper."
      ];
      String selectedVariant = imgVariants[Random().nextInt(imgVariants.length)];

      // PROMPT ORIGINAL COMPLETO RESTAURADO
      final prompt = Content.text('''
        Fichaje: $playerName de $fromTeam a $toTeam por $priceStr.
        REGLAS TEXTO: NO inventes DTs reales (Xavi, Pep). Cíñete a los datos.
        JSON: {
          "title": "TITULAR FICHAJE",
          "body": "Análisis corto.",
          "image_prompt": "Realistic photo. $selectedVariant. Highly detailed face of $playerName, accurate likeness, 4k."
        }
      ''');
      await _processAndUpload(seasonId, model, prompt, {'type': 'TRANSFER'});
    } catch (e) {
      print("❌ Error Transfer News: $e");
    }
  }

  // --- 3. NOTICIA CUSTOM ---
  Future<void> createCustomNews({required String seasonId, required String topic}) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);

      // PROMPT ORIGINAL COMPLETO RESTAURADO
      final prompt = Content.text('''
        Redacta una noticia corta sobre: "$topic".
        
        INSTRUCCIONES DE IMAGEN:
        - Si mencionas una persona famosa, intenta que se parezca ("lookalike").
        - Estilo realista.
        
        JSON: {
          "title": "TITULAR", 
          "body": "Texto corto (2 frases).", 
          "image_prompt": "Realistic cinematic photo representing: $topic. Highly detailed, 4k." 
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'CUSTOM', 'topic': topic});
    } catch (e) {
      print("❌ Error Custom News: $e");
    }
  }

  // --- 4. COMPETICIÓN ---
  Future<void> createCompetitionNews({required String seasonId, required String teamName, required String eventType}) async {
    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
    String narrative = (eventType == 'DROP_TO_EUROPA') ? "El equipo $teamName cae de Champions a Europa League." : "El equipo $teamName cae de Europa League a Conference.";
    final prompt = Content.text('''
        Noticia: $narrative. JSON: { "title": "TITULAR DRAMA", "body": "Texto corto.", "image_prompt": "Sad players of $teamName walking off pitch, dramatic rain." }
      ''');
    await _processAndUpload(seasonId, model, prompt, {'type': 'COMPETITION'});
  }

  // --- 5. NOTICIA DE PATROCINIO ---
  Future<void> createSponsorshipNews({
    required String seasonId,
    required String teamName,
    required String brandName,
    required int amount
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
      String priceStr = "\$${(amount / 1000000).toStringAsFixed(2)}M";

      // PROMPT ORIGINAL COMPLETO RESTAURADO
      final prompt = Content.text('''
        Noticia deportiva: El club $teamName ha cumplido exitosamente los objetivos de su patrocinador $brandName y recibe un pago de $priceStr.
        
        INSTRUCCIONES:
        - Titular corto y financiero/exitoso.
        - Imagen realista, ambiente de negocios o celebración corporativa.
        
        JSON: {
          "title": "OBJETIVO CUMPLIDO",
          "body": "Breve resumen del éxito financiero para el club.",
          "image_prompt": "Realistic cinematic photo. A soccer manager shaking hands with a business executive in a modern office, or holding a check with $brandName logo. High detail, 4k."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'SPONSORSHIP'});
    } catch (e) {
      print("❌ Error Sponsor News: $e");
    }
  }

  Future<void> _processAndUpload(String seasonId, GenerativeModel model, Content prompt, Map<String, dynamic> meta) async {
    final response = await model.generateContent([prompt]);
    String cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
    if (cleanJson.contains('{')) cleanJson = cleanJson.substring(cleanJson.indexOf('{'), cleanJson.lastIndexOf('}') + 1);

    Map<String, dynamic> content = jsonDecode(cleanJson);
    String finalImageUrl = await _tryGenerateWithFallback(content['image_prompt']);

    await _db.collection('seasons').doc(seasonId).collection('news').add({
      'type': meta['type'] ?? 'NEWS',
      'title': content['title'],
      'body': content['body'],
      'imageUrl': finalImageUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': [],
      'meta': meta
    });
  }

  Future<String> _tryGenerateWithFallback(String prompt) async {
    // 1. INTENTO: NANOBANANA (Alta calidad)
    try {
      print("🎨 [IA] Plan A: Probando 'nanobanana'...");
      return await _generateAndUploadImage(prompt, model: 'nanobanana', resolution: 1024, timeoutSeconds: 80);
    } catch (e) {
      print("⚠️ nanobanana falló ($e). Pasando al Plan B...");

      // 2. INTENTO: KONTEXT
      try {
        print("🎨 [IA] Plan B: Probando 'kontext'...");
        return await _generateAndUploadImage(prompt, model: 'kontext', resolution: 1024, timeoutSeconds: 80);
      } catch (e2) {
        print("⚠️ kontext falló ($e2). Pasando al Plan C...");

        // 3. INTENTO: SEEDREAM
        try {
          print("🎨 [IA] Plan C: Probando 'seedream'...");
          return await _generateAndUploadImage(prompt, model: 'seedream', resolution: 1024, timeoutSeconds: 80);
        } catch (e3) {
          print("⚠️ seedream falló ($e3). Pasando al Plan D...");

          // 4. INTENTO: GPTIMAGE-LARGE
          try {
            print("🎨 [IA] Plan D: Probando 'gptimage-large'...");
            return await _generateAndUploadImage(prompt, model: 'gptimage-large', resolution: 1024, timeoutSeconds: 80);
          } catch (e4) {
            print("⚠️ gptimage-large falló ($e4). Pasando al Plan E...");

            // 5. INTENTO: GPTIMAGE (Estándar)
            try {
              print("🎨 [IA] Plan E: Probando 'gptimage'...");
              return await _generateAndUploadImage(prompt, model: 'gptimage', resolution: 1024, timeoutSeconds: 80);
            } catch (e5) {
              print("⚠️ gptimage falló ($e5). Pasando al Plan F (Turbo)...");

              // 6. INTENTO: TURBO (Rápido y baja resolución)
              try {
                print("🚀 [IA] Plan F: Último recurso con 'turbo'...");
                return await _generateAndUploadImage(prompt, model: 'turbo', resolution: 768, timeoutSeconds: 45);
              } catch (e6) {
                // FALLBACK FINAL: IMAGEN DE ESTADIO
                print("❌ ERROR CRÍTICO: Todos los modelos fallaron. Usando imagen genérica.");
                return _fallbackImage;
              }
            }
          }
        }
      }
    }
  }

  Future<String> _generateAndUploadImage(String prompt, {required String model, required int resolution, required int timeoutSeconds}) async {
    String encodedPrompt = Uri.encodeComponent(prompt);
    int seed = Random().nextInt(9999999);

    // URL SERVIDOR DIRECTO
    String pollUrl = "https://gen.pollinations.ai/image/$encodedPrompt?width=$resolution&height=$resolution&seed=$seed&model=$model&nologo=true";

    var imageResponse = await http.get(
      Uri.parse(pollUrl),
      headers: {
        'Authorization': 'Bearer $_pollinationsApiKey',
      },
    ).timeout(Duration(seconds: timeoutSeconds));

    if (imageResponse.statusCode == 200) {
      return await _uploadToCloudinary(imageResponse.bodyBytes);
    } else {
      throw "Pollinations Error ${imageResponse.statusCode}: ${imageResponse.body}";
    }
  }

  Future<String> _uploadToCloudinary(Uint8List imageBytes) async {
    var uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    var request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = _uploadPreset;
    request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'news.jpg'));
    var response = await request.send();
    if (response.statusCode == 200) {
      var jsonMap = jsonDecode(String.fromCharCodes(await response.stream.toBytes()));
      return jsonMap['secure_url'];
    } else {
      throw "Cloudinary Upload Error ${response.statusCode}";
    }
  }
}