import 'package:flutter/material.dart';
import '../services/news_service.dart';

class CustomNewsScreen extends StatefulWidget {
  final String seasonId;
  const CustomNewsScreen({super.key, required this.seasonId});

  @override
  State<CustomNewsScreen> createState() => _CustomNewsScreenState();
}

class _CustomNewsScreenState extends State<CustomNewsScreen> {
  final TextEditingController _topicCtrl = TextEditingController();
  bool isLoading = false;

  Future<void> _generate() async {
    if (_topicCtrl.text.isEmpty) return;
    setState(() => isLoading = true);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enviando a la redacción... (Esto toma unos minutos)")));

    // Llamada sin await para no bloquear, o con await si queremos confirmar
    await NewsService().createCustomNews(
      seasonId: widget.seasonId,
      topic: _topicCtrl.text,
    );

    if(mounted) {
      setState(() => isLoading = false);
      Navigator.pop(context); // Volver
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Noticia enviada a impresión! Aparecerá pronto."), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Redactar Noticia Oficial"), backgroundColor: const Color(0xFF0D1B2A)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Describe el tema de la noticia. La IA escribirá el artículo y generará la foto.", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(
              controller: _topicCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Ej: Se rumorea que el FC Barcelona está en bancarrota y tendrá que vender a sus estrellas...",
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : _generate,
                icon: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send),
                label: const Text("PUBLICAR NOTICIA"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800], foregroundColor: Colors.white),
              ),
            )
          ],
        ),
      ),
    );
  }
}