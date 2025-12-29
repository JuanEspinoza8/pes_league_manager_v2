import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para controlar colores de la barra de estado
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/lobby_selection_screen.dart'; // <--- CORRECCIÓN: Importamos la pantalla correcta
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);


  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Fondo transparente
    statusBarIconBrightness: Brightness.light, // Íconos claros (blancos)
    statusBarBrightness: Brightness.dark, // Para iOS
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PES League Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: const Color(0xFF0D1B2A),
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D1B2A),
          primary: const Color(0xFF0D1B2A),
          secondary: const Color(0xFFC0A062),
          tertiary: const Color(0xFFE63946),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1B2A),
          foregroundColor: Colors.white, // Texto del AppBar blanco
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          iconTheme: IconThemeData(color: Colors.white), // Iconos del AppBar blancos
        ),

        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D1B2A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.grey, width: 0.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0D1B2A), width: 2)),
        ),
      ),

      // --- NAVEGACIÓN AUTOMÁTICA ---
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text("Error de autenticación")));
          }

          if (snapshot.hasData) {
            // CORRECCIÓN: Ahora vamos al Lobby, no a la lista de jugadores
            return const LobbySelectionScreen();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}