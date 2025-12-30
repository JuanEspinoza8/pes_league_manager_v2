import 'dart:convert';
import 'dart:math'; // Para el random
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class NewsService {
  static const String _apiKey = 'oculto';
  final String _cloudName = 'oculto';
  final String _uploadPreset = 'oculto';
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _fallbackImage = "https://images.unsplash.com/photo-1522770179533-24471fcdba45?q=80&w=1080&auto=format&fit=crop";

  // --- 1. NOTICIA DE PARTIDO (CON CONTEXTO Y VARIANTES) ---
  Future<void> createMatchNews({
    required String seasonId,
    required String homeName,
    required String awayName,
    required int homeScore,
    required int awayScore,
    String? competition,
    bool isPenalties = false,
    String? penaltyScore,
    String? winnerName,
    String? matchDetails,
    bool isDerby = false,
    // NUEVOS PARAMETROS DE CONTEXTO
    String? homeForm, // Ej: "Viene de perder 3 seguidos"
    String? awayForm,
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

      // 1. Elegir Variante de Imagen Aleatoria
      List<String> imgVariants = [
        "ACTION: Action shot of the match, intense duel between players.",
        "CELEBRATION: A player from $winnerName screaming and jumping in celebration after a goal.",
        "MOTM: The star player of $winnerName holding the 'Man of the Match' trophy in a post-match interview.",
        "CROWD: The fans of $winnerName going crazy in the stands with flares."
      ];
      String selectedVariant = (winnerName != null)
          ? imgVariants[Random().nextInt(imgVariants.length)]
          : imgVariants[0]; // Si es empate, usamos acción

      String context = "PARTIDO: $homeName $homeScore - $awayScore $awayName ($competition).";
      if (winnerName != null) context += " Ganador: $winnerName.";
      if (isDerby) context += " ES UN CLÁSICO.";
      if (matchDetails != null) context += " Detalles: $matchDetails.";

      // Agregamos el historial al contexto
      if (homeForm != null) context += " Contexto Local ($homeName): $homeForm.";
      if (awayForm != null) context += " Contexto Visita ($awayName): $awayForm.";

      final prompt = Content.text('''
        Actúa como un periodista deportivo. Escribe una noticia sobre: $context.
        
        INSTRUCCIONES:
        1. Considera el "Contexto" (si un equipo venía perdiendo mucho y ganó, es una "resurrección". Si venía ganando y perdió, es un "golpe").
        2. La imagen debe corresponder a este estilo: "$selectedVariant".
        
        JSON:
        {
          "title": "TITULAR IMPACTANTE (Max 6 palabras)",
          "body": "Resumen narrativo. Usa emojis.",
          "image_prompt": "Cinematic photo based on this style: $selectedVariant. Realistic, 4k, soccer atmosphere."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {
        'home': homeName, 'away': awayName, 'score': "$homeScore-$awayScore"
      });

    } catch (e) {
      print("❌ Error Match News: $e");
    }
  }

  // --- 2. NOTICIA DE TRASPASO (CON VARIANTES) ---
  Future<void> createTransferNews({
    required String seasonId,
    required String playerName,
    required String fromTeam,
    required String toTeam,
    required int price,
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
      String priceStr = "\$${(price / 1000000).toStringAsFixed(1)}M";

      // Variantes de Traspaso
      List<String> imgVariants = [
        "PRESS: $playerName sitting at a press conference microphone, flashes going off.",
        "SHIRT: $playerName smiling and holding the new $toTeam jersey up for the cameras.",
        "GOODBYE: $playerName waving goodbye to the fans of $fromTeam with a nostalgic look.",
        "MEDICAL: $playerName doing a thumbs up during medical tests with sensors."
      ];
      String selectedVariant = imgVariants[Random().nextInt(imgVariants.length)];

      final prompt = Content.text('''
        Noticia de fichaje: $playerName pasa de $fromTeam a $toTeam por $priceStr.
        Estilo de imagen deseado: $selectedVariant.
        
        JSON:
        {
          "title": "TITULAR FICHAJE (Max 5 palabras)",
          "body": "Análisis del fichaje. ¿Es caro? ¿Es traición? Usa emojis.",
          "image_prompt": "Realistic photo: $selectedVariant. Cinematic lighting, 4k."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'TRANSFER'});
    } catch (e) {
      print("❌ Error Transfer News: $e");
    }
  }

  // --- 3. NOTICIA CUSTOM (ADMIN) ---
  Future<void> createCustomNews({
    required String seasonId,
    required String topic, // Lo que escriba el admin
  }) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

      final prompt = Content.text('''
        Escribe una noticia oficial o rumor sobre este tema: "$topic".
        
        JSON:
        {
          "title": "TITULAR ATRACTIVO (Max 6 palabras)",
          "body": "Desarrollo de la noticia en 2 o 3 frases. Usa emojis.",
          "image_prompt": "A realistic photo representing: $topic. Cinematic, 4k."
        }
      ''');

      await _processAndUpload(seasonId, model, prompt, {'type': 'CUSTOM', 'topic': topic});
    } catch (e) {
      print("❌ Error Custom News: $e");
    }
  }

  // ... (createCompetitionNews se mantiene igual) ...
  Future<void> createCompetitionNews({required String seasonId, required String teamName, required String eventType}) async {
    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
    String narrative = (eventType == 'DROP_TO_EUROPA')
        ? "El equipo $teamName cae de Champions a Europa League."
        : "El equipo $teamName cae de Europa League a Conference.";

    final prompt = Content.text('''
        Noticia dramática: $narrative.
        JSON: { "title": "TITULAR DRAMA", "body": "Texto corto.", "image_prompt": "Sad players of $teamName walking, rain, dramatic." }
      ''');
    await _processAndUpload(seasonId, model, prompt, {'type': 'COMPETITION'});
  }

  // --- HELPERS (CON ESTRATEGIA DE REINTENTO) ---
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
    try {
      print("🎨 [IA] Plan A: FLUX (Alta Calidad)...");
      return await _generateAndUploadImage(prompt, model: 'flux', resolution: 1024, timeoutMinutes: 5);
    } catch (e) {
      try {
        print("⚠️ [IA] Plan B: TURBO (Rápido)...");
        return await _generateAndUploadImage(prompt, model: 'turbo', resolution: 768, timeoutMinutes: 2);
      } catch (e2) {
        print("⚠️ [IA] Fallo total. Usando Estadio.");
        return _fallbackImage;
      }
    }
  }

  Future<String> _generateAndUploadImage(String prompt, {required String model, required int resolution, required int timeoutMinutes}) async {
    String encodedPrompt = Uri.encodeComponent(prompt);
    int seed = DateTime.now().millisecondsSinceEpoch;
    String pollUrl = "https://image.pollinations.ai/prompt/$encodedPrompt?width=$resolution&height=$resolution&seed=$seed&model=$model&nologo=true";
    var imageResponse = await http.get(Uri.parse(pollUrl)).timeout(Duration(minutes: timeoutMinutes));

    if (imageResponse.statusCode == 200) {
      return await _uploadToCloudinary(imageResponse.bodyBytes);
    } else {
      throw "Pollinations Error ${imageResponse.statusCode}";
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
      throw "Cloudinary Error";
    }
  }
}