import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para controlar colores de la barra de estado
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/lobby_selection_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // DISEÑO V2: Barra de estado inmersiva
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // PALETA V2: Colores más profundos y dorados más elegantes
    const primaryColor = Color(0xFF0F172A); // Azul noche profundo (Slate 900)
    const secondaryColor = Color(0xFFD4AF37); // Dorado metálico
    const accentColor = Color(0xFF38BDF8); // Azul eléctrico para detalles modernos

    return MaterialApp(
      title: 'PES League Manager V2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // Cambiamos a Dark Mode nativo para dar sensación premium
        primaryColor: primaryColor,
        scaffoldBackgroundColor: const Color(0xFF0B1120), // Fondo casi negro

        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: secondaryColor,
          tertiary: accentColor,
          brightness: Brightness.dark,
          surface: const Color(0xFF1E293B), // Color de superficie para tarjetas
        ),

        // Títulos y textos
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0, color: Colors.white),
          displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.white),
          bodyLarge: TextStyle(fontSize: 16, color: Colors.white70),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent, // AppBar flotante/transparente
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Colors.white
          ),
          iconTheme: IconThemeData(color: secondaryColor), // Íconos dorados
        ),

        // Tarjetas más modernas
        cardTheme: CardThemeData(
          elevation: 8,
          shadowColor: const Color(0xFF000000).withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: const Color(0xFF1E293B), // Slate 800
        ),

        // Botones con estilo "Sport"
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: secondaryColor, // Botones dorados por defecto
            foregroundColor: Colors.black, // Texto negro sobre dorado para contraste
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            elevation: 4,
            shadowColor: secondaryColor.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0),
          ),
        ),

        // Inputs modernos y oscuros
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F172A), // Input oscuro
          labelStyle: const TextStyle(color: Colors.white54),
          prefixIconColor: secondaryColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: secondaryColor, width: 2)),
        ),
      ),

      // --- NAVEGACIÓN AUTOMÁTICA (Lógica intacta) ---
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: secondaryColor)));
          }

          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text("Error de autenticación", style: TextStyle(color: Colors.red))));
          }

          if (snapshot.hasData) {
            return const LobbySelectionScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}