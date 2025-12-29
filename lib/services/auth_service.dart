import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Obtener usuario actual
  User? get currentUser => _auth.currentUser;

  // Stream para detectar cambios de estado (Login/Logout)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Iniciar Sesión
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Registrarse
  Future<void> signUp({required String email, required String password}) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  // Cerrar Sesión
  Future<void> signOut() async {
    await _auth.signOut();
  }
}