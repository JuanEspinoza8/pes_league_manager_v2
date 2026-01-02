import 'dart:ui'; // Necesario para el efecto de desenfoque (Blur)
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../data_uploader.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- LÓGICA INTACTA ---
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLogin = true;
  String? errorMessage;
  bool isLoading = false;

  Future<void> handleSubmit() async {
    setState(() => isLoading = true);
    try {
      if (isLogin) {
        await AuthService().signIn(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        await AuthService().signUp(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      // Extendemos el body detrás de la barra de estado para inmersión total
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. FONDO DE GRADIENTE "CHAMPIONS NIGHT"
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF020617), // Negro azulado
                  Color(0xFF172554), // Azul profundo
                  Color(0xFF0F172A), // Slate Dark
                ],
              ),
            ),
          ),

          // 2. PATRÓN DECORATIVO (Opcional: Círculos difuminados para ambiente)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E40AF).withOpacity(0.3),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // 3. CONTENIDO PRINCIPAL
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // LOGO & BRANDING EVOLUCIONADO
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: const Icon(Icons.sports_soccer, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "PES LEAGUE",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        shadows: [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 4)]
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "MANAGER",
                        style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w300, letterSpacing: 6.0),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(4)),
                        child: const Text("V2", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                      )
                    ],
                  ),
                  const SizedBox(height: 50),

                  // TARJETA DE LOGIN CON EFECTO GLASSMORPHISM
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(32.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05), // Transparencia sutil
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLogin ? "Iniciar Sesión" : "Crear Club",
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isLogin ? "Bienvenido de nuevo, mister." : "Comienza tu legado hoy.",
                              style: const TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                            const SizedBox(height: 30),

                            // INPUTS
                            TextField(
                              controller: emailController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: "Email",
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: passwordController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: "Contraseña",
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                            ),

                            const SizedBox(height: 16),

                            // ERROR MESSAGE
                            if (errorMessage != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withOpacity(0.3))
                                ),
                                child: Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                              ),

                            const SizedBox(height: 24),

                            // BOTÓN PRINCIPAL
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD4AF37), // Dorado
                                  foregroundColor: Colors.black,
                                  shadowColor: const Color(0xFFD4AF37).withOpacity(0.5),
                                  elevation: 8,
                                ),
                                child: isLoading
                                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                    : Text(isLogin ? "ENTRAR AL CAMPO" : "FUNDAR CLUB"),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // SWITCH LOGIN/REGISTER
                            Center(
                              child: TextButton(
                                onPressed: () => setState(() { isLogin = !isLogin; errorMessage = null; }),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white70),
                                    children: [
                                      TextSpan(text: isLogin ? "¿Nuevo DT? " : "¿Ya tienes club? "),
                                      TextSpan(
                                        text: isLogin ? "Ficha aquí" : "Inicia sesión",
                                        style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // BOTÓN ADMIN (Más discreto pero accesible)
                  TextButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subiendo jugadores a la base de datos..."), backgroundColor: Color(0xFF0F172A)));
                      try {
                        await uploadPlayersToFirestore();
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Jugadores cargados exitosamente!"), backgroundColor: Colors.green));
                      } catch (e) {
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                      }
                    },
                    icon: Icon(Icons.cloud_upload, size: 16, color: Colors.white.withOpacity(0.3)),
                    label: Text("ADMIN PANEL: RESTAURAR DB", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}