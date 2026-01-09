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
  static const String _geminiApiKey = 'AIzaSyBI3P_qDHSJiJXc4bVPD98w_Yn68PNnbKY';
  static const String _pollinationsApiKey = 'sk_gM2KUap37kMubFojqiAmb6PDTafWoJ8L';

  final String _cloudName = 'dwzo8abuy';
  final String _uploadPreset = 'pes_league';
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
      String imageUrl = await uploadToCloudinary(imageBytes);

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

  // --- 1. NOTICIA DE PARTIDO (MODO REALISTA Y ESTRICTO) ---
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

      // --- LÓGICA DE DT Y DATOS ---
      String? managerReferenceUrl;
      String managerDescription = "";
      String managerName = "Manager";

      // Identificar al equipo ganador (o local si es empate) para sacar su DT
      String targetTeamId = (winnerName != null && winnerName == awayName) ? awayId : homeId;

      if (!targetTeamId.startsWith("TBD") && !targetTeamId.startsWith("GANADOR")) {
        try {
          var doc = await _db.collection('seasons').doc(seasonId).collection('participants').doc(targetTeamId).get();
          if (doc.exists && doc.data() != null) {
            var data = doc.data()!;

            if (data.containsKey('managerName')) managerName = data['managerName'];
            if (data.containsKey('managerDescription')) managerDescription = data['managerDescription'];
            if (data.containsKey('managerPhotoUrl')) managerReferenceUrl = data['managerPhotoUrl'];

            print("🕵️ [NewsService] DT Info: $managerName | Desc: $managerDescription");
          }
        } catch (e) {
          print("⚠️ Error buscando avatar DT: $e");
        }
      }

      List<String> imgVariants = [
        "ACTION_SHOT: Close up cinematic shot of [PLAYER_NAME] sprinting with the ball, intense facial expression, sweat, stadium floodlights, highly detailed $winnerName kit, 8k.",
        "GOAL_KICK: Freeze-frame mid-air volley by [PLAYER_NAME], dramatic lighting, droplets of sweat and grass flying, photorealistic, wearing $winnerName jersey.",
        "CELEBRATION: [PLAYER_NAME] screaming in passion sliding on knees, veins visible, teammates running towards him, blurred crowd background, depth of field.",
        "MOTM_TROPHY: Post-match interview, [PLAYER_NAME] holding the 'Man of the Match' trophy, smiling, stadium lights reflecting, bokeh effect.",
      ];

      // Solo añadimos la variante de DT si tenemos datos concretos (descripción o foto)
      if (managerDescription.isNotEmpty || managerReferenceUrl != null) {
        imgVariants.add("MANAGER_REACTION: Sideline shot of manager $managerName shouting instructions, rain falling, dramatic rim lighting, intense focus.");
      } else {
        // Si no hay info del DT, añadimos variante de hinchada
        imgVariants.add("CROWD_CRAZY: Ultra-wide shot of $winnerName fans going crazy with flares and flags, atmospheric smoke.");
      }

      String selectedVariant = (winnerName != null)
          ? imgVariants[Random().nextInt(imgVariants.length)]
          : imgVariants[0];

      print("🎲 [NewsService] Variante sorteada: $selectedVariant");

      String context = "PARTIDO: $homeName $homeScore - $awayScore $awayName ($competition).";
      if (winnerName != null) context += " Ganador: $winnerName.";
      if (isDerby) context += " ES UN CLÁSICO.";
      if (matchDetails != null) context += " DETALLES: $matchDetails.";

      // --- CONSTRUCCIÓN DEL PROMPT ---
      String promptText = '''
        Actúa como periodista deportivo de élite (estilo Marca, ESPN).
        No menciones el nombre de ningun dt que no se mecione
        DATOS: $context
        
        🛑 INSTRUCCIONES ESTRICTAS DE IDENTIDAD PARA LA IMAGEN (image_prompt):
        
        1. JUGADORES:
           - Si mencionas un jugador, USA SU NOMBRE REAL en el prompt de imagen. 
           - Ejemplo: "Portrait of Lionel Messi..." (NO "Argentine player").
           
        
        2. ENTRENADOR (MANAGER):
           - Nombre: $managerName.
           - ${managerDescription.isNotEmpty ? "⚠️ OBLIGATORIO: Debes incluir EXACTAMENTE esta descripción física en el prompt: '$managerDescription'." : "Si no hay descripción, evita primeros planos del DT."}
        
        3. ESCENA:
           - Base: "$selectedVariant".
           - Estilo: "Photorealistic, 8k, Canon EOS R5, f/1.2, cinematic lighting, ray tracing".

        JSON RESPUESTA:
        {
          "title": "TITULAR IMPACTANTE (Max 6 palabras)",
          "body": "Resumen corto y pasional con emojis.",
          "image_prompt": "Prompt visual detallado en inglés siguiendo las reglas de identidad."
        }
      ''';

      final prompt = Content.text(promptText);

      await _processAndUpload(
          seasonId,
          model,
          prompt,
          {'home': homeName, 'away': awayName, 'score': "$homeScore-$awayScore"},
          referenceImageUrl: managerReferenceUrl
      );
    } catch (e) {
      print("❌ Error Match News: $e");
    }
  }

  // --- 2. NOTICIA DE TRASPASO (IDENTIDAD PURA) ---
  Future<void> createTransferNews({required String seasonId, required String playerName, required String fromTeam, required String toTeam, required int price}) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
      String priceStr = "\$${(price / 1000000).toStringAsFixed(1)}M";

      List<String> imgVariants = [
        "PRESS_CONFERENCE: $playerName holding the new $toTeam jersey, flashes going off, official press backdrop, corporate lighting.",
        "MEDICAL_TEST: $playerName running on a treadmill with sensors, shirtless, athletic physique, futuristic medical lab.",
        "CONTRACT_SIGNING: Close up of $playerName signing a paper with a golden pen, smiling, shaking hands with executive.",
        "AIRPORT_ARRIVAL: Paparazzi shot of $playerName arriving at airport, casual luxury clothes, surrounded by fans."
      ];
      String selectedVariant = imgVariants[Random().nextInt(imgVariants.length)];

      final prompt = Content.text('''
        Noticia de Fichaje: $playerName de $fromTeam a $toTeam por $priceStr.
        
        INSTRUCCIONES VISUALES (image_prompt):
        1. IDENTIDAD: Queremos ver a $playerName REAL.
        2. Prompt: "Photorealistic photo of famous soccer player $playerName. The face MUST be exactly $playerName. $selectedVariant. 8k resolution, cinematic."
        
        
        JSON: {
          "title": "TITULAR FICHAJE (Ej: ¡OFICIAL!)",
          "body": "Análisis corto estilo 'Fabrizio Romano'.",
          "image_prompt": "Prompt detallado en inglés..."
        }
      ''');
      await _processAndUpload(seasonId, model, prompt, {'type': 'TRANSFER'});
    } catch (e) {
      print("❌ Error Transfer News: $e");
    }
  }

  // --- 3. NOTICIA CUSTOM (CINEMÁTICA) ---
  Future<void> createCustomNews({required String seasonId, required String topic}) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);

      final prompt = Content.text('''
        Redacta una noticia corta sobre: "$topic".
        
        INSTRUCCIONES IMAGEN (image_prompt):
        - Describe una imagen que represente "$topic".
        - Estilo obligatorio: "Cinematic lighting, depth of field, 8k resolution, shot on 35mm lens, photorealistic".
        - Si mencionas un jugador famoso, pide su nombre real para fidelidad facial.
        
        JSON: {
          "title": "TITULAR", 
          "body": "Texto corto (2 frases).", 
          "image_prompt": "Prompt visual detallado..." 
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'CUSTOM', 'topic': topic});
    } catch (e) {
      print("❌ Error Custom News: $e");
    }
  }

  // --- 4. COMPETICIÓN (DRAMA) ---
  Future<void> createCompetitionNews({required String seasonId, required String teamName, required String eventType}) async {
    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
    String narrative = (eventType == 'DROP_TO_EUROPA') ? "El equipo $teamName cae de Champions a Europa League." : "El equipo $teamName cae de Europa League a Conference.";

    final prompt = Content.text('''
        Noticia de DRAMA DEPORTIVO: $narrative.
        
        IMAGEN (image_prompt):
        - "Sad players of $teamName walking off the pitch looking at the ground, rainy weather, dramatic moody lighting, bokeh effect on stadium lights, tragic atmosphere, high contrast".
        - No muestres caras felices.
        
        JSON: { "title": "TITULAR DRAMA", "body": "Texto corto.", "image_prompt": "Prompt visual..." }
      ''');
    await _processAndUpload(seasonId, model, prompt, {'type': 'COMPETITION'});
  }

  // --- 5. NOTICIA DE PATROCINIO (ESTILO NEGOCIOS) ---
  Future<void> createSponsorshipNews({
    required String seasonId,
    required String teamName,
    required String brandName,
    required int amount
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
      String priceStr = "\$${(amount / 1000000).toStringAsFixed(2)}M";

      final prompt = Content.text('''
        Noticia: El club $teamName ha cumplido exitosamente los objetivos de su patrocinador $brandName y recibe $priceStr.
        
        IMAGEN (image_prompt):
        - "A cinematic shot of a modern soccer jersey of $teamName featuring the logo of $brandName prominently, dramatic studio lighting".
        - O BIEN: "A luxurious boardroom meeting, shaking hands, glass walls, view of a stadium, cinematic corporate style".
        
        JSON: {
          "title": "TITULAR FINANCIERO",
          "body": "Breve resumen del éxito financiero.",
          "image_prompt": "Prompt visual..."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'SPONSORSHIP'});
    } catch (e) {
      print("❌ Error Sponsor News: $e");
    }
  }

  // --- PROCESAMIENTO Y SUBIDA (ROBUSTO) ---
  Future<void> _processAndUpload(String seasonId, GenerativeModel model, Content prompt, Map<String, dynamic> meta, {String? referenceImageUrl}) async {
    final response = await model.generateContent([prompt]);
    String rawText = response.text ?? "";

    // 1. Limpieza robusta de JSON (Markdown o texto plano)
    String cleanJson = rawText;
    if (cleanJson.contains('```json')) {
      cleanJson = cleanJson.split('```json')[1].split('```')[0];
    } else if (cleanJson.contains('```')) {
      cleanJson = cleanJson.split('```')[1].split('```')[0];
    }

    int start = cleanJson.indexOf('{');
    int end = cleanJson.lastIndexOf('}');
    if (start != -1 && end != -1) {
      cleanJson = cleanJson.substring(start, end + 1);
    }

    try {
      Map<String, dynamic> content = jsonDecode(cleanJson);

      // 2. Generar imagen con la URL de referencia si existe
      String finalImageUrl = await _tryGenerateWithFallback(
          content['image_prompt'],
          referenceImageUrl: referenceImageUrl
      );

      // 3. Guardar en Firestore
      await _db.collection('seasons').doc(seasonId).collection('news').add({
        'type': meta['type'] ?? 'NEWS',
        'title': content['title'],
        'body': content['body'],
        'imageUrl': finalImageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
        'meta': meta
      });
    } catch (e) {
      print("❌ Error procesando JSON o subiendo noticia: $e");
      print("Raw Gemini Response: $rawText");
    }
  }

  // --- ESTRATEGIA DE GENERACIÓN DE IMAGEN (CASCADA) ---
  Future<String> _tryGenerateWithFallback(String prompt, {String? referenceImageUrl}) async {
    // 1. INTENTO: NANOBANANA (Alta calidad + IMG2IMG)
    try {
      print("🎨 [IA] Plan A: Probando 'nanobanana'...");
      return await _generateAndUploadImage(prompt, model: 'nanobanana', resolution: 1024, timeoutSeconds: 80, referenceImageUrl: referenceImageUrl);
    } catch (e) {
      print("⚠️ nanobanana falló ($e). Pasando al Plan B...");

      // 2. INTENTO: KONTEXT (IMG2IMG)
      try {
        print("🎨 [IA] Plan B: Probando 'kontext'...");
        return await _generateAndUploadImage(prompt, model: 'kontext', resolution: 1024, timeoutSeconds: 80, referenceImageUrl: referenceImageUrl);
      } catch (e2) {
        print("⚠️ kontext falló ($e2). Pasando al Plan C...");

        // 3. INTENTO: SEEDREAM (IMG2IMG)
        try {
          print("🎨 [IA] Plan C: Probando 'seedream'...");
          return await _generateAndUploadImage(prompt, model: 'seedream', resolution: 1024, timeoutSeconds: 80, referenceImageUrl: referenceImageUrl);
        } catch (e3) {
          print("⚠️ seedream falló ($e3). Pasando al Plan D...");

          // 4. INTENTO: GPTIMAGE-LARGE (IMG2IMG)
          try {
            print("🎨 [IA] Plan D: Probando 'gptimage-large'...");
            return await _generateAndUploadImage(prompt, model: 'gptimage-large', resolution: 1024, timeoutSeconds: 80, referenceImageUrl: referenceImageUrl);
          } catch (e4) {
            print("⚠️ gptimage-large falló ($e4). Pasando al Plan E...");

            // 5. INTENTO: GPTIMAGE (Estándar + IMG2IMG)
            try {
              print("🎨 [IA] Plan E: Probando 'gptimage'...");
              return await _generateAndUploadImage(prompt, model: 'gptimage', resolution: 1024, timeoutSeconds: 80, referenceImageUrl: referenceImageUrl);
            } catch (e5) {
              print("⚠️ gptimage falló ($e5). Pasando al Plan F (Turbo)...");

              // 6. INTENTO: TURBO (NO SOPORTA IMG2IMG -> Pasamos null en la referencia)
              try {
                print("🚀 [IA] Plan F: Último recurso con 'turbo'...");
                return await _generateAndUploadImage(prompt, model: 'turbo', resolution: 768, timeoutSeconds: 45, referenceImageUrl: null); // NULL AQUÍ EXPLICITAMENTE
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

  Future<String> _generateAndUploadImage(String prompt, {required String model, required int resolution, required int timeoutSeconds, String? referenceImageUrl}) async {
    String encodedPrompt = Uri.encodeComponent(prompt);
    int seed = Random().nextInt(9999999);

    // URL SERVIDOR DIRECTO
    String pollUrl = "https://gen.pollinations.ai/image/$encodedPrompt?width=$resolution&height=$resolution&seed=$seed&model=$model&nologo=true";

    // --- MAGIA IMG2IMG ---
    // Si tenemos URL de referencia y el modelo NO es turbo, la adjuntamos
    if (referenceImageUrl != null && model != 'turbo') {
      pollUrl += "&image=${Uri.encodeComponent(referenceImageUrl)}";
    }
    // ---------------------

    var imageResponse = await http.get(
      Uri.parse(pollUrl),
      headers: {
        'Authorization': 'Bearer $_pollinationsApiKey',
      },
    ).timeout(Duration(seconds: timeoutSeconds));

    if (imageResponse.statusCode == 200) {
      return await uploadToCloudinary(imageResponse.bodyBytes);
    } else {
      throw "Pollinations Error ${imageResponse.statusCode}: ${imageResponse.body}";
    }
  }

  Future<String> uploadToCloudinary(Uint8List imageBytes) async {
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