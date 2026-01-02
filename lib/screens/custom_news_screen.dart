import 'package:flutter/material.dart';
import '../services/news_service.dart';
import '../services/notification_service.dart';

class CustomNewsScreen extends StatefulWidget {
  final String seasonId;
  const CustomNewsScreen({super.key, required this.seasonId});

  @override
  State<CustomNewsScreen> createState() => _CustomNewsScreenState();
}

class _CustomNewsScreenState extends State<CustomNewsScreen> {
  // --- LÓGICA INTACTA ---
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  bool isPosting = false;

  Future<void> _postNews() async {
    if (_titleCtrl.text.isEmpty || _bodyCtrl.text.isEmpty) return;
    setState(() => isPosting = true);

    // CORRECCIÓN: Concatenamos título y cuerpo para enviarlo como 'topic' al servicio de IA
    // El servicio NewsService espera un 'topic' para generar la noticia.
    String combinedTopic = "Titular: ${_titleCtrl.text.trim()}. Detalles: ${_bodyCtrl.text.trim()}";

    await NewsService().createCustomNews(
      seasonId: widget.seasonId,
      topic: combinedTopic,
    );

    // Enviamos notificación push con el texto manual para que llegue rápido
    await NotificationService.sendGlobalNotification(
        seasonId: widget.seasonId,
        title: "COMUNICADO OFICIAL",
        body: _titleCtrl.text.trim(),
        type: "INFO"
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Noticia enviada a redacción (IA)")));
    }
  }
  // --- FIN LÓGICA ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        title: const Text("REDACTAR NOTICIA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "TITULAR",
                labelStyle: const TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.title, color: Colors.white24),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bodyCtrl,
              maxLines: 10,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "CUERPO DE LA NOTICIA",
                labelStyle: const TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: isPosting ? null : _postNews,
                icon: const Icon(Icons.send),
                label: isPosting
                    ? const Text("PROCESANDO...")
                    : const Text("PUBLICAR COMUNICADO"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}