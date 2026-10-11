import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const Color _anaRenk = Color(0xFFD32F2F);
const Color _ikinciRenk = Color(0xFFFF5252);
const LinearGradient _anaGradient = LinearGradient(
  colors: [_anaRenk, _ikinciRenk],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ---------------------------------------------------------------------------
// Tarif modeli ve metin ayrıştırıcı
// ---------------------------------------------------------------------------

class Tarif {
  String baslik = '';
  final List<String> malzemeler = [];
  final List<String> adimlar = [];
  String tavsiye = '';
}

String _temizMetin(String s) {
  return s
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^[#\s]+'), '')
      .trim();
}

String _baslikTemizle(String s) {
  return s
      .replaceAll(RegExp(r'[\*#\[\]]'), '')
      .replaceAll('🍽', '')
      .replaceAll('\uFE0F', '')
      .trim();
}

/// Yapay zekanın ürettiği metni bölümlere ayırır.
/// Beklenen format bulunamazsa null döner (düz metin gösterilir).
Tarif? tarifiAyristir(String metin) {
  final t = Tarif();
  String bolum = 'baslik';
  final tavsiye = StringBuffer();

  for (final ham in metin.split('\n')) {
    final s = ham.trim();
    if (s.isEmpty) continue;

    final c = s.replaceAll(RegExp(r'[\*#\s]'), '');
    if (c.startsWith('🍽')) {
      t.baslik = _baslikTemizle(s);
      bolum = 'baslik';
      continue;
    }
    if (c.startsWith('🛒')) {
      bolum = 'malzeme';
      continue;
    }
    if (c.startsWith('👨') || c.startsWith('🍳')) {
      bolum = 'yapilis';
      continue;
    }
    if (c.startsWith('💡')) {
      bolum = 'tavsiye';
      continue;
    }

    switch (bolum) {
      case 'baslik':
        if (t.baslik.isEmpty) t.baslik = _baslikTemizle(s);
        break;
      case 'malzeme':
        final m = _temizMetin(s.replaceFirst(RegExp(r'^[\s•\-\*·▪●]+'), ''));
        if (m.isNotEmpty) t.malzemeler.add(m);
        break;
      case 'yapilis':
        final a = _temizMetin(s.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), ''));
        if (a.isNotEmpty) t.adimlar.add(a);
        break;
      case 'tavsiye':
        if (tavsiye.isNotEmpty) tavsiye.write(' ');
        tavsiye.write(_temizMetin(s));
        break;
    }
  }

  t.tavsiye = tavsiye.toString();
  if (t.malzemeler.isEmpty && t.adimlar.isEmpty) return null;
  return t;
}

// ---------------------------------------------------------------------------
// Uygulama
// ---------------------------------------------------------------------------

class YemekTarifiApp extends StatelessWidget {
  const YemekTarifiApp({super.key});

  ThemeData _tema(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: _anaRenk, brightness: b);
    return ThemeData(useMaterial3: true, colorScheme: cs);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akıllı Tarif Asistanı',
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SplashEkrani(),
    );
  }
}

// ---------------------------------------------------------------------------
// Açılış (splash) ekranı
// ---------------------------------------------------------------------------

class SplashEkrani extends StatefulWidget {
  const SplashEkrani({super.key});

  @override
  State<SplashEkrani> createState() => _SplashEkraniState();
}

class _SplashEkraniState extends State<SplashEkrani> with SingleTickerProviderStateMixin {
  late final AnimationController _kontrol;
  late final Animation<double> _logoOlcek;
  late final Animation<double> _logoSolma;
  late final Animation<double> _baslikSolma;
  late final Animation<double> _imzaSolma;
  late final Animation<Offset> _imzaKayma;
  Timer? _zamanlayici;
  bool _gecildi = false;

  @override
  void initState() {
    super.initState();
    _kontrol = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();

    _logoOlcek = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _kontrol,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _logoSolma = CurvedAnimation(
      parent: _kontrol,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _baslikSolma = CurvedAnimation(
      parent: _kontrol,
      curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
    );
    _imzaSolma = CurvedAnimation(
      parent: _kontrol,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );
    _imzaKayma = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(_imzaSolma);

    _zamanlayici = Timer(const Duration(milliseconds: 3400), _devamEt);
  }

  void _devamEt() {
    if (_gecildi || !mounted) return;
    _gecildi = true;
    _zamanlayici?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const AnaEkran(),
        transitionsBuilder: (_, animasyon, __, child) =>
            FadeTransition(opacity: animasyon, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _kontrol.dispose();
    super.dispose();
  }

  Widget _halka(double boyut, double opaklik) {
    return Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: opaklik),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _devamEt,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.15,
              colors: [Color(0xFFC62828), Color(0xFF5A0C12), Color(0xFF1A0507)],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Positioned(top: -90, right: -70, child: _halka(260, 0.07)),
              Positioned(bottom: -120, left: -80, child: _halka(320, 0.05)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _logoOlcek,
                      child: FadeTransition(
                        opacity: _logoSolma,
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                              ),
                              BoxShadow(
                                color: _ikinciRenk.withValues(alpha: 0.5),
                                blurRadius: 60,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 54,
                            color: _anaRenk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _baslikSolma,
                      child: Column(
                        children: [
                          const Text(
                            'Akıllı Tarif Asistanı',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: 48,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: FadeTransition(
                  opacity: _imzaSolma,
                  child: SlideTransition(
                    position: _imzaKayma,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DESIGNED BY',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [Colors.white, Color(0xFFFFCDD2)],
                          ).createShader(rect),
                          child: const Text(
                            'KemOku',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
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

  String _tarifSonucu = '';
  Tarif? _tarif;
  String _hata = '';
  bool _yukleniyor = false;
  int _mesajIndex = 0;
  Timer? _zamanlayici;
  final Set<int> _isaretli = {};

  static const List<String> _yuklemeMesajlari = [
    'Video indiriliyor...',
    'Yapay zeka videoyu izliyor...',
    'Malzemeler çıkarılıyor...',
    'Tarif yazılıyor...',
    'Son rötuşlar yapılıyor...',
  ];

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _linkController.dispose();
    _sifreController.dispose();
    super.dispose();
  }

  Future<void> _yapistir() async {
    final veri = await Clipboard.getData(Clipboard.kTextPlain);
    final metin = veri?.text;
    if (metin != null && metin.trim().isNotEmpty) {
      _linkController.text = metin.trim();
    }
  }

  Future<void> _kopyala() async {
    await Clipboard.setData(ClipboardData(text: _tarifSonucu));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tarif panoya kopyalandı'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> tarifiGetir() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      setState(() => _hata = 'Lütfen önce bir video linki yapıştır.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _yukleniyor = true;
      _tarifSonucu = '';
      _tarif = null;
      _hata = '';
      _isaretli.clear();
      _mesajIndex = 0;
    });

    _zamanlayici?.cancel();
    _zamanlayici = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      setState(() {
        _mesajIndex = (_mesajIndex + 1) % _yuklemeMesajlari.length;
      });
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
        final metin = (data['tarif'] ?? '').toString();
        if (metin.trim().isEmpty) {
          setState(() => _hata = 'Tarif boş döndü, tekrar dene.');
        } else {
          setState(() {
            _tarifSonucu = metin;
            _tarif = tarifiAyristir(metin);
          });
        }
      } else {
        String detay = response.body;
        try {
          final hata = jsonDecode(utf8.decode(response.bodyBytes));
          detay = (hata['detail'] ?? detay).toString();
        } catch (_) {}
        setState(() {
          _hata = response.statusCode == 401
              ? '🔒 $detay'
              : 'Hata (${response.statusCode}): $detay';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = 'Sunucuya ulaşılamadı. Sunucu uyuyor olabilir, '
            'bir dakika bekleyip tekrar dene.\n\nDetay: $e';
      });
    } finally {
      _zamanlayici?.cancel();
      if (mounted) {
        setState(() => _yukleniyor = false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  BoxDecoration _kartDekor(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final koyu = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: koyu
                ? const [Color(0xFF2E1416), Color(0xFF141010)]
                : const [Color(0xFFFFEBEE), Color(0xFFFFFBFB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
                children: [
                  _ustBolum(cs),
                  const SizedBox(height: 28),
                  _girisKarti(cs),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _sonucAlani(cs),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ustBolum(ColorScheme cs) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: _anaGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _anaRenk.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'Akıllı Tarif Asistanı',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'TikTok veya YouTube videosunu yapıştır,\ntarifi saniyeler içinde çıkaralım.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _alan({
    required TextEditingController controller,
    required String ipucu,
    required IconData ikon,
    required ColorScheme cs,
    bool gizli = false,
    Widget? sonEk,
  }) {
    return TextField(
      controller: controller,
      obscureText: gizli,
      onSubmitted: gizli
          ? (_) {
              if (!_yukleniyor) tarifiGetir();
            }
          : null,
      decoration: InputDecoration(
        hintText: ipucu,
        prefixIcon: Icon(ikon, color: _anaRenk),
        suffixIcon: sonEk,
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _anaRenk, width: 1.5),
        ),
      ),
    );
  }

  Widget _girisKarti(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _kartDekor(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _alan(
            controller: _linkController,
            ipucu: 'Video linkini yapıştır...',
            ikon: Icons.link_rounded,
            cs: cs,
            sonEk: IconButton(
              tooltip: 'Panodan yapıştır',
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: _yapistir,
            ),
          ),
          const SizedBox(height: 12),
          _alan(
            controller: _sifreController,
            ipucu: 'Erişim şifresi (varsa)',
            ikon: Icons.lock_outline_rounded,
            cs: cs,
            gizli: true,
          ),
          const SizedBox(height: 18),
          _anaButon(),
        ],
      ),
    );
  }

  Widget _anaButon() {
    final aktif = !_yukleniyor;
    return Opacity(
      opacity: aktif ? 1 : 0.7,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: _anaGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _anaRenk.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: aktif ? tarifiGetir : null,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _yukleniyor
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    _yukleniyor ? 'Hazırlanıyor...' : 'Tarifi Getir',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sonucAlani(ColorScheme cs) {
    if (_yukleniyor) return _yuklemeKarti(cs);
    if (_hata.isNotEmpty) return _hataKarti(cs);
    if (_tarif != null) return _tarifGorunumu(cs, _tarif!);
    if (_tarifSonucu.isNotEmpty) return _duzMetinKarti(cs);
    return _bosDurum(cs);
  }

  Widget _bosDurum(ColorScheme cs) {
    return Padding(
      key: const ValueKey('bos'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _anaRenk.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.ramen_dining_rounded, size: 42, color: _anaRenk),
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz bir tarif yok',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'Bir yemek videosunun linkini yukarıya yapıştır.',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _yuklemeKarti(ColorScheme cs) {
    return Container(
      key: const ValueKey('yukleme'),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: _kartDekor(cs),
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(color: _anaRenk, strokeWidth: 4),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _yuklemeMesajlari[_mesajIndex],
              key: ValueKey(_mesajIndex),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bu işlem bir iki dakika sürebilir.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _hataKarti(ColorScheme cs) {
    return Container(
      key: const ValueKey('hata'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              _hata,
              style: TextStyle(fontSize: 15, height: 1.5, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _duzMetinKarti(ColorScheme cs) {
    return Container(
      key: const ValueKey('duz'),
      padding: const EdgeInsets.all(20),
      decoration: _kartDekor(cs),
      child: SelectableText(
        _tarifSonucu,
        style: TextStyle(fontSize: 16, height: 1.6, color: cs.onSurface),
      ),
    );
  }

  Widget _tarifGorunumu(ColorScheme cs, Tarif t) {
    return Column(
      key: const ValueKey('tarif'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _baslikBandi(t),
        const SizedBox(height: 16),
        if (t.malzemeler.isNotEmpty) ...[
          _bolumKarti(
            cs,
            Icons.shopping_basket_rounded,
            'Malzemeler',
            Column(
              children: [
                for (var i = 0; i < t.malzemeler.length; i++)
                  _malzemeSatiri(cs, i, t.malzemeler[i]),
              ],
            ),
            sag: '${t.malzemeler.length} adet',
          ),
          const SizedBox(height: 16),
        ],
        if (t.adimlar.isNotEmpty) ...[
          _bolumKarti(
            cs,
            Icons.soup_kitchen_rounded,
            'Yapılışı',
            Column(
              children: [
                for (var i = 0; i < t.adimlar.length; i++)
                  _adimSatiri(cs, i + 1, t.adimlar[i]),
              ],
            ),
            sag: '${t.adimlar.length} adım',
          ),
          const SizedBox(height: 16),
        ],
        if (t.tavsiye.isNotEmpty) _tavsiyeKarti(cs, t.tavsiye),
      ],
    );
  }

  Widget _baslikBandi(Tarif t) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: _anaGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _anaRenk.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TARİFİN HAZIR',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.baslik.isEmpty ? 'Lezzetli bir tarif' : t.baslik,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Tarifi kopyala',
            onPressed: _kopyala,
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bolumKarti(
    ColorScheme cs,
    IconData ikon,
    String baslik,
    Widget icerik, {
    String? sag,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _kartDekor(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _anaRenk.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(ikon, color: _anaRenk, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  baslik,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (sag != null)
                Text(sag, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 14),
          icerik,
        ],
      ),
    );
  }

  Widget _malzemeSatiri(ColorScheme cs, int index, String metin) {
    final isaret = _isaretli.contains(index);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          if (!_isaretli.remove(index)) _isaretli.add(index);
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isaret ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isaret ? _anaRenk : cs.outline,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                metin,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  decoration: isaret ? TextDecoration.lineThrough : null,
                  color: isaret ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adimSatiri(ColorScheme cs, int numara, String metin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(gradient: _anaGradient, shape: BoxShape.circle),
            child: Text(
              '$numara',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SelectableText(
                metin,
                style: TextStyle(fontSize: 16, height: 1.55, color: cs.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tavsiyeKarti(ColorScheme cs, String metin) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_rounded, color: _anaRenk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Şefin Tavsiyesi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  metin,
                  style: TextStyle(fontSize: 15, height: 1.5, color: cs.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}