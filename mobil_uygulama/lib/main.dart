import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const YemekTarifiApp());
}

/// Backend adresi (otomatik seçilir):
/// - Yayındaki sitede: sitenin kendi adresi (backend aynı sunucuda)
/// - Yerelde "flutter run -d chrome": http://127.0.0.1:8000
/// - Android emülatör: http://10.0.2.2:8000
/// - Windows / diğer: http://127.0.0.1:8000
String get apiTabanAdresi {
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://127.0.0.1:8000';
    }
    return Uri.base.origin;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

class YemekTarifiApp extends StatelessWidget {
  const YemekTarifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akıllı Tarif Asistanı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const AnaEkran(),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _sifreController = TextEditingController();
  String _tarifSonucu = "";
  bool _yukleniyor = false;

  @override
  void dispose() {
    _linkController.dispose();
    _sifreController.dispose();
    super.dispose();
  }

  Future<void> tarifiGetir() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;

    setState(() {
      _yukleniyor = true;
      _tarifSonucu = "";
    });

    try {
      final response = await http
          .post(
            Uri.parse('$apiTabanAdresi/tarif-getir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'link': link,
              'sifre': _sifreController.text.trim(),
            }),
          )
          .timeout(const Duration(minutes: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _tarifSonucu = (data['tarif'] ?? "Tarif boş döndü.").toString();
        });
      } else {
        String detay = response.body;
        try {
          final hata = jsonDecode(utf8.decode(response.bodyBytes));
          detay = (hata['detail'] ?? detay).toString();
        } catch (_) {}
        setState(() {
          _tarifSonucu = response.statusCode == 401
              ? "🔒 $detay"
              : "Hata (${response.statusCode}):\n$detay";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tarifSonucu =
            "Bağlantı Hatası: Sunucuya ulaşılamadı.\n"
            "Sunucu uyuyor olabilir, bir dakika bekleyip tekrar dene.\n\n"
            "Detay: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double ekranGenisligi = MediaQuery.of(context).size.width;
    final double icerikGenisligi = ekranGenisligi > 800 ? 700 : ekranGenisligi * 0.9;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Akıllı Tarif Asistanı', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SizedBox(
          width: icerikGenisligi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              Card(
                elevation: 4,
                shadowColor: Colors.deepOrange.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _linkController,
                        decoration: InputDecoration(
                          hintText: 'TikTok veya YouTube linkini yapıştırın...',
                          prefixIcon: const Icon(Icons.link, color: Colors.deepOrange),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _sifreController,
                        obscureText: true,
                        onSubmitted: (_) => _yukleniyor ? null : tarifiGetir(),
                        decoration: InputDecoration(
                          hintText: 'Erişim şifresi (varsa)',
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.deepOrange),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _yukleniyor ? null : tarifiGetir,
                          icon: _yukleniyor
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.restaurant_menu),
                          label: Text(
                            _yukleniyor ? 'Yapay Zeka Videoyu İzliyor...' : 'Tarifi Getir',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _yukleniyor
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.deepOrange),
                            SizedBox(height: 16),
                            Text(
                              "Mutfağa giriliyor...\nLütfen bekleyin.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : _tarifSonucu.isEmpty
                        ? const Center(
                            child: Text(
                              "🍽️\nHenüz bir tarif aratmadınız.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 18),
                            ),
                          )
                        : Card(
                            elevation: 2,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  _tarifSonucu,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.6,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}