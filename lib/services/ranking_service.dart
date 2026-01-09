import 'dart:math';

class RankingService {
  // Constante K: Determina qué tan drásticos son los cambios. 32 es estándar en FIFA.
  static const int kFactor = 32;

  /// Calcula el nuevo Ranking ELO y el cambio de puntos
  /// [currentRating]: Ranking actual del equipo (ej: 1000)
  /// [opponentRating]: Ranking del rival
  /// [actualScore]: 1.0 (Ganó), 0.5 (Empató), 0.0 (Perdió)
  static Map<String, int> calculateNewRanking(int currentRating, int opponentRating, double actualScore) {
    // 1. Calcular la probabilidad esperada de ganar
    // Fórmula: E = 1 / (1 + 10 ^ ((R_opp - R_me) / 400))
    double expectedScore = 1 / (1 + pow(10, (opponentRating - currentRating) / 400));

    // 2. Calcular el cambio de puntos
    // Fórmula: P = K * (ResultadoReal - ResultadoEsperado)
    int ratingChange = (kFactor * (actualScore - expectedScore)).round();

    // 3. Retornar nuevo ranking y la diferencia
    return {
      'newRating': currentRating + ratingChange,
      'change': ratingChange
    };
  }

  /// Calcula el premio monetario basado en el desempeño
  /// [baseReward]: Premio base por jugar (ej: 2M)
  /// [winBonus]: Premio base por ganar (ej: 8M)
  /// [ratingChange]: Puntos de ranking ganados (si es negativo, es 0)
  static int calculateBudgetReward(bool isWinner, bool isDraw, int ratingChange) {
    // --- NUEVA CONFIGURACIÓN EXTREMA ---

    // BASE MÁS BAJA: Para que los "partidos fáciles" paguen poco (cerca de 5M)
    int base = isWinner
        ? 4500000  // 4.5M por ganar
        : (isDraw ? 2500000 : 1000000); // 2.5M empate, 1M derrota

    // BONUS MUY ALTO: 500k por punto.
    // Como una hazaña da ~31 puntos -> 31 * 500k = 15.5M extra.
    // 4.5M (Base) + 15.5M (Bonus) = 20M Total.
    int rankingBonus = max(0, ratingChange) * 500000;

    return base + rankingBonus;
  }
}