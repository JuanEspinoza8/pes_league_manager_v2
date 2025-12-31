import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiStatsService {
  // ¡RECUERDA PONER TU API KEY REAL AQUÍ!
  static const String _apiKey = 'CLAVE';

  Future<Map<String, dynamic>?> extractStatsFromImage(Uint8List imageBytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',

        apiKey: _apiKey,
      );

      final prompt = TextPart("""
        Analiza esta imagen de estadísticas de post-partido de PES/eFootball/FIFA.
        Identifica los valores numéricos para el equipo LOCAL (Izquierda) y VISITANTE (Derecha).
        
        Extrae estos datos en JSON (usa 0 si no encuentras el dato):
        {
          "home": {
            "goals": int,
            "possession": int (solo el número),
            "shots": int (tiros totales),
            "shotsOnTarget": int (tiros al arco),
            "passes": int (pases totales),
            "passesCompleted": int (pases completados),
            "fouls": int (faltas),
            "offsides": int (fuera de juego),
            "interceptions": int (intercepciones o quites)
          },
          "away": {
            "goals": int,
            "possession": int,
            "shots": int,
            "shotsOnTarget": int,
            "passes": int,
            "passesCompleted": int,
            "fouls": int,
            "offsides": int,
            "interceptions": int
          }
        }
        Responde SOLO con el JSON.
      """);

      final imagePart = DataPart('image/jpeg', imageBytes);
      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      String? text = response.text;
      if (text == null) return null;

      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(text);
    } catch (e) {
      print("Error Gemini: $e");
      return null;
    }
  }
}