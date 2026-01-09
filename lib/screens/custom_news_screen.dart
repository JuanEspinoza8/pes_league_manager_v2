import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/news_service.dart';
import '../services/notification_service.dart';

class CustomNewsScreen extends StatefulWidget {
  final String seasonId;
  const CustomNewsScreen({super.key, required this.seasonId});

  @override
  State<CustomNewsScreen> createState() => _CustomNewsScreenState();
}

class _CustomNewsScreenState extends State<CustomNewsScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  bool isPosting = false;
  Uint8List? _selectedImageBytes;

  // Función para seleccionar imagen de la galería
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      var bytes = await image.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
      });
    }
  }

  Future<void> _postNews() async {
    if (_titleCtrl.text.isEmpty || _bodyCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Completa título y cuerpo")));
      return;
    }

    setState(() => isPosting = true);

    try {
      if (_selectedImageBytes != null) {
        // OPCIÓN A: Subida Manual (El usuario eligió una foto)
        await NewsService().createManualNews(
          seasonId: widget.seasonId,
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          imageBytes: _selectedImageBytes!,
        );
      } else {
        // OPCIÓN B: Generación IA (No hay foto, la IA crea todo)
        String combinedTopic = "Titular: ${_titleCtrl.text.trim()}. Detalles: ${_bodyCtrl.text.trim()}";
        await NewsService().createCustomNews(
          seasonId: widget.seasonId,
          topic: combinedTopic,
        );
      }

      // Notificación Push Global
      await NotificationService.sendGlobalNotification(
          seasonId: widget.seasonId,
          title: "COMUNICADO OFICIAL",
          body: _titleCtrl.text.trim(),
          type: "INFO"
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Noticia publicada con éxito")));
      }
    } catch (e) {
      if (mounted) {
        setState(() => isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // --- ÁREA DE IMAGEN ---
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                    image: _selectedImageBytes != null
                        ? DecorationImage(image: MemoryImage(_selectedImageBytes!), fit: BoxFit.cover)
                        : null
                ),
                child: _selectedImageBytes == null
                    ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo, size: 40, color: Color(0xFFD4AF37)),
                    SizedBox(height: 10),
                    Text("Toca para subir imagen (Opcional)", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text("Si no subes foto, la IA generará una.", style: TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                )
                    : Stack(
                  children: [
                    Positioned(
                        right: 10, top: 10,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() => _selectedImageBytes = null),
                          ),
                        )
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // --- CAMPOS DE TEXTO ---
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "TITULAR",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.title, color: Colors.white24),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bodyCtrl,
              maxLines: 8,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "CUERPO DE LA NOTICIA",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 30),

            // --- BOTÓN DE ACCIÓN ---
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: isPosting ? null : _postNews,
                icon: const Icon(Icons.send),
                label: isPosting
                    ? const Text("PROCESANDO...")
                    : Text(_selectedImageBytes != null ? "SUBIR Y PUBLICAR" : "GENERAR CON IA"),
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