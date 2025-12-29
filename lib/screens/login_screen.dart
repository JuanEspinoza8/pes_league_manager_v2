import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../data_uploader.dart'; // <--- Importante para que funcione la carga

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              const Color(0xFF1B263B),
              const Color(0xFF000000),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO
                const Icon(Icons.sports_soccer, size: 80, color: Colors.white),
                const SizedBox(height: 10),
                const Text(
                  "PES LEAGUE",
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                ),
                const Text(
                  "MANAGER",
                  style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 5.0),
                ),
                const SizedBox(height: 40),

                // FORMULARIO
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  color: Colors.white.withOpacity(0.95),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          isLogin ? "Bienvenido DT" : "Crear Club",
                          style: TextStyle(color: colorScheme.primary, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email_outlined)),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          decoration: const InputDecoration(labelText: "Contraseña", prefixIcon: Icon(Icons.lock_outline)),
                          obscureText: true,
                        ),
                        const SizedBox(height: 10),
                        if (errorMessage != null)
                          Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : handleSubmit,
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: Colors.white, elevation: 2),
                            child: isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(isLogin ? "INICIAR TEMPORADA" : "REGISTRAR CLUB"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => setState(() { isLogin = !isLogin; errorMessage = null; }),
                          child: Text(isLogin ? "¿Nuevo aquí? Crea tu cuenta" : "Ya tengo cuenta", style: TextStyle(color: colorScheme.primary)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // --- BOTÓN DE CARGA DE JUGADORES (RESTAURADO) ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subiendo jugadores a la base de datos...")));
                      try {
                        await uploadPlayersToFirestore(); // Llama a tu función en data_uploader.dart
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Jugadores cargados exitosamente!"), backgroundColor: Colors.green));
                      } catch (e) {
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                      }
                    },
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("ADMIN: CARGAR JUGADORES"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.8), // Rojo para destacar
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}