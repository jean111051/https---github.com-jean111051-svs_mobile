import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const SvsApp());
}

class SvsApp extends StatelessWidget {
  const SvsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue),
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: GoogleFonts.outfitTextTheme(),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSoft,
        selectedItemColor: AppColors.amber,
        unselectedItemColor: Color(0xFF93A6C7),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Verification System',
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.copyWith(
          labelSmall: GoogleFonts.jetBrainsMono(),
          labelMedium: GoogleFonts.jetBrainsMono(),
          labelLarge: GoogleFonts.jetBrainsMono(),
        ),
      ),
      home: const ReportPage(),
    );
  }
}

class AppColors {
  static const amber = Color(0xFFF4C95D);
  static const amberDark = Color(0xFFE7B449);
  static const amberDeep = Color(0xFFC08924);
  static const amberLight = Color(0xFFFFF3D6);
  static const amberBorder = Color(0xFFF8DC98);
  static const orange = Color(0xFFEA6A5A);
  static const orangeLight = Color(0xFFFFECE8);
  static const orangeBorder = Color(0xFFFFD1C9);
  static const red = Color(0xFFE33B3B);
  static const redLight = Color(0xFFFFE8E8);
  static const redBorder = Color(0xFFFFCACA);
  static const green = Color(0xFF2D6AE3);
  static const greenLight = Color(0xFFE3ECFF);
  static const greenBorder = Color(0xFFBFD4FF);
  static const blue = Color(0xFF1F4BB8);
  static const bg = Color(0xFFFFFFFF);
  static const bgSoft = Color(0xFF1F3560);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFD9E3F2);
  static const borderMid = Color(0xFFBFD0EA);
  static const text = Color(0xFF0E1A2B);
  static const text2 = Color(0xFF1F3560);
  static const muted = Color(0xFF5D6D86);
  static const muted2 = Color(0xFF7E8FA8);
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with WidgetsBindingObserver {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _panicCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  final _types = const [
    'Fire',
    'Flood',
    'Medical',
    'Accident',
    'Landslide',
    'Other',
  ];
  String? _selectedType;
  String? _selectedSeverity;

  String? _gps;
  int? _gpsAccuracy;
  bool _detectingGps = false;
  double? _mapLat;
  double? _mapLng;
  bool _showMap = false;

  final List<Uint8List> _photoPreviewBytes = [];
  final List<XFile> _photoFiles = [];

  bool _submitting = false;
  bool _panicSending = false;
  bool _panicDialogOpen = false;
  int _navIndex = 1;

  String? _panicNumber;
  String _baseUrl = 'https://svsmdrrmo.vercel.app';
  static const String _queuedReportsKey = 'queued_reports';

  static const String _baseUrlEnv = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );
  bool _baseUrlReady = false;

  final String _supabaseUrlEnv = dotenv.env['SUPABASE_URL'] ?? '';
  final String _supabaseAnonKeyEnv = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  final String _supabaseBucketEnv = dotenv.env['SUPABASE_BUCKET'] ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _initBaseUrl().then((_) => _trySendQueuedReports());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _barangayCtrl.dispose();
    _landmarkCtrl.dispose();
    _streetCtrl.dispose();
    _descCtrl.dispose();
    _panicCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySendQueuedReports();
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final panicNum = prefs.getString('panic_number');
    final baseUrl = prefs.getString('base_url');
    setState(() {
      _panicNumber = panicNum;
      _panicCtrl.text = _formatPhMobile(_panicNumber);
      if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        _baseUrl = baseUrl.trim();
      }
    });
  }

  String _normalizedBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (value.endsWith('/')) value = value.substring(0, value.length - 1);
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    return value;
  }

  String _normalizedSupabaseUrl(String input) {
    var value = input.trim();
    if (value.endsWith('/')) value = value.substring(0, value.length - 1);
    return value;
  }

  bool _hasSupabaseConfig() {
    return _supabaseUrlEnv.trim().isNotEmpty &&
        _supabaseAnonKeyEnv.trim().isNotEmpty &&
        _supabaseBucketEnv.trim().isNotEmpty;
  }

  String _effectiveBaseUrl() {
    var value = _normalizedBaseUrl(_baseUrl);
    if (!kIsWeb && Platform.isAndroid) {
      value = value
          .replaceAll('localhost', '10.0.2.2')
          .replaceAll('127.0.0.1', '10.0.2.2');
    }
    return value;
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }

  List<String> _candidateBaseUrls() {
    final candidates = <String>[];
    if (_baseUrlEnv.trim().isNotEmpty) {
      candidates.add(_normalizedBaseUrl(_baseUrlEnv));
    }
    if (_baseUrl.trim().isNotEmpty) {
      candidates.add(_normalizedBaseUrl(_baseUrl));
    }
    if (!kIsWeb && Platform.isAndroid) {
      candidates.add('http://10.0.2.2:3000');
    }
    candidates.add('http://localhost:3000');
    candidates.add('http://127.0.0.1:3000');
    return candidates.toSet().toList();
  }

  Future<bool> _probeBaseUrl(String baseUrl) async {
    final url = Uri.parse('$baseUrl/report');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 2));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initBaseUrl() async {
    final candidates = _candidateBaseUrls();
    for (final c in candidates) {
      final ok = await _probeBaseUrl(c);
      if (ok) {
        setState(() {
          _baseUrl = c;
          _baseUrlReady = true;
        });
        return;
      }
    }
    if (candidates.isNotEmpty) {
      setState(() {
        _baseUrl = candidates.first;
        _baseUrlReady = false;
      });
    }
  }

  Future<bool> _ensureBaseUrlReady({bool showError = false}) async {
    if (_baseUrlReady) return true;
    await _initBaseUrl();
    if (!_baseUrlReady && showError) {
      _toast(
        'Server not reachable. Set the correct server URL.',
        isError: true,
      );
    }
    return _baseUrlReady;
  }

  Future<void> _saveBaseUrl(String input) async {
    final normalized = _normalizedBaseUrl(input);
    if (normalized.isEmpty) {
      _toast('Server URL is required', isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', normalized);
    setState(() {
      _baseUrl = normalized;
      _baseUrlReady = false;
    });
    await _initBaseUrl();
    _toast(
      _baseUrlReady ? 'Server URL saved' : 'Server not reachable',
      isError: !_baseUrlReady,
    );
  }

  Future<void> _savePanicNumber() async {
    final normalized = _normalizePhMobile(_panicCtrl.text);
    if (normalized == null) {
      _toast('Invalid PH mobile number', isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('panic_number', normalized);
    setState(() {
      _panicNumber = normalized;
      _panicCtrl.text = _formatPhMobile(_panicNumber);
    });
    if (mounted) Navigator.pop(context);
    _toast('Panic number saved');
  }

  String? _normalizePhMobile(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('63') && digits.length == 12 && digits[2] == '9') {
      return '+$digits';
    }
    if (digits.startsWith('0') && digits.length == 11 && digits[1] == '9') {
      return '+63${digits.substring(1)}';
    }
    if (digits.startsWith('9') && digits.length == 10) {
      return '+63$digits';
    }
    return null;
  }

  String _formatPhMobile(String? intl) {
    final digits = (intl ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12 || !digits.startsWith('63')) return intl ?? '';
    final p1 = digits.substring(0, 2);
    final p2 = digits.substring(2, 5);
    final p3 = digits.substring(5, 8);
    final p4 = digits.substring(8);
    return '+$p1 $p2 $p3 $p4';
  }

  Future<Position?> _getBestPosition({required Duration timeout}) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: timeout,
        ),
      );
      return pos;
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _detectGps() async {
    setState(() => _detectingGps = true);
    try {
      final permission = await _ensureLocationPermission();
      if (!permission) return;

      final pos = await _getBestPosition(timeout: const Duration(seconds: 15));
      if (pos == null) {
        _toast('Could not detect location', isError: true);
        return;
      }
      final gps =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      setState(() {
        _gps = gps;
        _gpsAccuracy = pos.accuracy.round();
        _mapLat = pos.latitude;
        _mapLng = pos.longitude;
        _showMap = true;
      });
      await _autoFillLocation(pos.latitude, pos.longitude, overwrite: true);
      _toast('Location detected');
    } catch (_) {
      _toast('Could not detect location', isError: true);
    } finally {
      if (mounted) setState(() => _detectingGps = false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _toast('Location services are disabled', isError: true);
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _toast('Location permission denied', isError: true);
      return false;
    }
    return true;
  }

  Future<void> _autoFillLocation(
    double lat,
    double lng, {
    required bool overwrite,
  }) async {
    var filled = false;
    final canServer = await _ensureBaseUrlReady();
    if (canServer) {
      final url = Uri.parse(
        '${_effectiveBaseUrl()}/api/reverse-geocode?lat=$lat&lng=$lng',
      );
      try {
        final res = await http
            .get(url, headers: _apiHeaders())
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final barangay = (data['barangay'] ?? '').toString().trim();
          final landmark = (data['landmark'] ?? '').toString().trim();
          final street = (data['street'] ?? '').toString().trim();
          if (overwrite || _barangayCtrl.text.trim().isEmpty) {
            if (barangay.isNotEmpty) _barangayCtrl.text = barangay;
          }
          if (overwrite || _landmarkCtrl.text.trim().isEmpty) {
            if (landmark.isNotEmpty) _landmarkCtrl.text = "Near $landmark";
          }
          if (overwrite || _streetCtrl.text.trim().isEmpty) {
            if (street.isNotEmpty) _streetCtrl.text = street;
          }
          filled =
              barangay.isNotEmpty || landmark.isNotEmpty || street.isNotEmpty;
        }
      } catch (_) {}
    }

    if (!filled) {
      final osm = await _reverseGeocodeOsm(lat, lng);
      if (osm != null) {
        final barangay = osm.$1;
        final landmark = osm.$2;
        final street = osm.$3;
        if (overwrite || _barangayCtrl.text.trim().isEmpty) {
          if (barangay.isNotEmpty) _barangayCtrl.text = barangay;
        }
        if (overwrite || _landmarkCtrl.text.trim().isEmpty) {
          if (landmark.isNotEmpty) _landmarkCtrl.text = "Near $landmark";
        }
        if (overwrite || _streetCtrl.text.trim().isEmpty) {
          if (street.isNotEmpty) _streetCtrl.text = street;
        }
        filled =
            barangay.isNotEmpty || landmark.isNotEmpty || street.isNotEmpty;
      }
    }
    if (!filled) {
      final fallback =
          "Near ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
      final fallbackBarangay = 'Unknown Barangay';
      final fallbackStreet = 'Unknown Street';
      if (overwrite || _landmarkCtrl.text.trim().isEmpty) {
        _landmarkCtrl.text = fallback;
      }
      if (overwrite || _barangayCtrl.text.trim().isEmpty) {
        _barangayCtrl.text = fallbackBarangay;
      }
      if (overwrite || _streetCtrl.text.trim().isEmpty) {
        _streetCtrl.text = fallbackStreet;
      }
    }
  }

  Future<(String, String, String)?> _reverseGeocodeOsm(
    double lat,
    double lng,
  ) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': lat.toString(),
      'lon': lng.toString(),
      'zoom': '18',
      'addressdetails': '1',
    });
    try {
      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'smart_verification_system/1.0 (mobile)',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map<String, dynamic>?) ?? {};
      final road = (addr['road'] ?? addr['street'] ?? '').toString().trim();
      final house = (addr['house_number'] ?? addr['house_name'] ?? '')
          .toString()
          .trim();
      final neighbourhood =
          (addr['suburb'] ??
                  addr['neighbourhood'] ??
                  addr['quarter'] ??
                  addr['borough'] ??
                  addr['city_district'] ??
                  addr['village'] ??
                  addr['town'] ??
                  addr['city'] ??
                  '')
              .toString()
              .trim();
      final landmark =
          (addr['amenity'] ??
                  addr['building'] ??
                  addr['tourism'] ??
                  addr['shop'] ??
                  addr['historic'] ??
                  addr['attraction'] ??
                  '')
              .toString()
              .trim();
      final street = house.isNotEmpty && road.isNotEmpty
          ? '$house $road'
          : (road.isNotEmpty ? road : house);
      return (neighbourhood, landmark, street);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickSingleImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _toast('Image too large (max 10 MB)', isError: true);
      return;
    }

    setState(() {
      _photoFiles
        ..clear()
        ..add(file);
      _photoPreviewBytes
        ..clear()
        ..add(bytes);
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return;
    await _pickSingleImage(source);
  }

  void _removePhoto() {
    if (_photoFiles.isEmpty) return;
    setState(() {
      _photoFiles.clear();
      _photoPreviewBytes.clear();
    });
  }

  String _fileExtension(String path) {
    final lower = path.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == lower.length - 1) return '';
    return lower.substring(dotIndex + 1);
  }

  String _guessImageExt(String path) {
    final ext = _fileExtension(path);
    if (ext.isEmpty) return 'bin';
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'bmp':
      case 'tif':
      case 'tiff':
      case 'heic':
      case 'heif':
        return ext == 'jpeg' ? 'jpg' : ext;
      default:
        return ext;
    }
  }

  String _guessImageMime(String path) {
    final ext = _fileExtension(path);
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isValidPhotoUrl(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  List<String> _sanitizePhotoUrls(List<String> urls) {
    return urls.where(_isValidPhotoUrl).toList();
  }

  Future<List<String>> _uploadPhotosToSupabase(List<XFile> files) async {
    if (files.isEmpty) return [];
    if (!_hasSupabaseConfig()) {
      throw Exception('Supabase is not configured');
    }
    if (!_supabaseAnonKeyEnv.trim().startsWith('eyJ')) {
      final hint = _supabaseAnonKeyEnv.isEmpty
          ? '(empty)'
          : '${_supabaseAnonKeyEnv.substring(0, 8)}...';
      throw Exception(
        'Supabase anon key must be the legacy JWT (starts with "eyJ"). Current: $hint',
      );
    }
    final baseUrl = _normalizedSupabaseUrl(_supabaseUrlEnv);
    final bucket = _supabaseBucketEnv.trim();
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw Exception('Image too large (max 10 MB)');
      }
      final ext = _guessImageExt(file.path);
      final mime = _guessImageMime(file.path);
      final objectPath =
          'reports/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final uploadUrl = Uri.parse(
        '$baseUrl/storage/v1/object/$bucket/$objectPath',
      );
      final headers = <String, String>{
        'Authorization': 'Bearer $_supabaseAnonKeyEnv',
        'apikey': _supabaseAnonKeyEnv,
        'x-upsert': 'false',
      };
      if (mime != 'application/octet-stream') {
        headers['Content-Type'] = mime;
      }
      final res = await http.put(uploadUrl, headers: headers, body: bytes);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(
          'Supabase upload failed (${res.statusCode}): ${res.body}',
        );
      }
      final publicUrl = '$baseUrl/storage/v1/object/public/$bucket/$objectPath';
      urls.add(publicUrl);
    }
    return _sanitizePhotoUrls(urls);
  }

  Future<void> _submitReport() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _toast('Please complete required fields', isError: true);
      return;
    }
    if (_selectedType == null || _selectedSeverity == null) {
      _toast('Select emergency type and severity', isError: true);
      return;
    }

    final normalizedContact = _normalizePhMobile(_contactCtrl.text);
    if (normalizedContact == null) {
      _toast('Invalid PH mobile number', isError: true);
      return;
    }

    final liveGps = await _tryGetLiveGps();
    final gpsValue = liveGps ?? _gps;
    if (gpsValue == null) {
      _toast('Location required. Please detect GPS.', isError: true);
      return;
    }

    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'contact': normalizedContact,
      'emergencyType': _selectedType,
      'severity': _selectedSeverity,
      'barangay': _barangayCtrl.text.trim(),
      'landmark': _landmarkCtrl.text.trim(),
      'street': _streetCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'gps': gpsValue,
    };

    if (!await _ensureBaseUrlReady(showError: false)) {
      if (_photoFiles.isNotEmpty) {
        body['localPhotos'] = _photoFiles.map((e) => e.path).toList();
      }
      await _queueReport(body);
      _toast('No connection. Report saved and will retry automatically.');
      _resetForm();
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_photoFiles.isNotEmpty) {
        if (!_hasSupabaseConfig()) {
          _toast(
            'Supabase not configured. Set SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_BUCKET.',
            isError: true,
          );
          return;
        }
        try {
          final urls = _sanitizePhotoUrls(
            await _uploadPhotosToSupabase(_photoFiles),
          );
          if (urls.isEmpty) {
            throw Exception('No valid photo URLs after upload');
          }
          body['photo'] = urls.first;
          body['photos'] = urls;
        } catch (e) {
          body['localPhotos'] = _photoFiles.map((e) => e.path).toList();
          await _queueReport(body);
          _toast(
            'Photo upload failed (${_shortError(e)}). Report saved and will retry automatically.',
            isError: true,
          );
          _resetForm();
          return;
        }
      }
      final url = Uri.parse('${_effectiveBaseUrl()}/api/report');
      final res = await http
          .post(url, headers: _apiHeaders(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['success'] != true) {
        final err = data['error']?.toString() ?? 'Could not submit report';
        _toast(err, isError: true);
        return;
      }
      final reportId = data['id']?.toString() ?? 'RPT-0000';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.greenBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F172A),
                    blurRadius: 26,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.greenBorder),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.green,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Report submitted',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Report ID: $reportId',
                    style: Theme.of(
                      ctx,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      _resetForm();
    } on TimeoutException {
      await _queueReport(body);
      _toast('No connection. Report saved and will retry automatically.');
    } catch (e) {
      debugPrint('Submit report error: $e');
      await _queueReport(body);
      _toast('No connection. Report saved and will retry automatically.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _queueReport(Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queuedReportsKey) ?? <String>[];
    final entry = jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'body': body,
    });
    list.add(entry);
    await prefs.setStringList(_queuedReportsKey, list);
  }

  Future<void> _trySendQueuedReports() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queuedReportsKey) ?? <String>[];
    if (list.isEmpty) return;
    if (!await _ensureBaseUrlReady(showError: false)) return;

    final remaining = <String>[];
    var sent = 0;
    for (final item in list) {
      try {
        final data = jsonDecode(item) as Map<String, dynamic>;
        final body = (data['body'] as Map).cast<String, dynamic>();
        var storedItem = item;
        final localPhotos = (body['localPhotos'] as List?)?.cast<String>();
        if (localPhotos != null && localPhotos.isNotEmpty) {
          if (!_hasSupabaseConfig()) {
            remaining.add(item);
            continue;
          }
          try {
            final files = localPhotos.map((p) => XFile(p)).toList();
            final urls = _sanitizePhotoUrls(
              await _uploadPhotosToSupabase(files),
            );
            if (urls.isEmpty) {
              throw Exception('No valid photo URLs after upload');
            }
            body['photo'] = urls.first;
            body['photos'] = urls;
            body.remove('localPhotos');
            storedItem = jsonEncode({'ts': data['ts'], 'body': body});
          } catch (_) {
            remaining.add(item);
            continue;
          }
        }
        final url = Uri.parse('${_effectiveBaseUrl()}/api/report');
        final res = await http
            .post(url, headers: _apiHeaders(), body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        final ok = res.statusCode == 200 && parsed['success'] == true;
        if (ok) {
          sent += 1;
        } else {
          remaining.add(storedItem);
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(_queuedReportsKey, remaining);
    if (sent > 0 && mounted) {
      _toast('Sent $sent queued report${sent == 1 ? '' : 's'}.');
    }
  }

  Future<String?> _tryGetLiveGps() async {
    try {
      final permission = await _ensureLocationPermission();
      if (!permission) return null;
      final pos = await _getBestPosition(timeout: const Duration(seconds: 10));
      if (pos == null) return null;
      final gps =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      setState(() {
        _gps = gps;
        _gpsAccuracy = pos.accuracy.round();
        _mapLat = pos.latitude;
        _mapLng = pos.longitude;
        _showMap = true;
      });
      await _autoFillLocation(pos.latitude, pos.longitude, overwrite: true);
      return gps;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendPanic() async {
    if (_panicSending) return;
    if (_panicNumber == null) {
      _openPanicSetup();
      return;
    }
    if (!await _ensureBaseUrlReady(showError: true)) {
      return;
    }
    setState(() => _panicSending = true);
    _showPanicSendingDialog();
    try {
      final gpsValue = await _tryGetLiveGps();
      final payload = await _buildPanicPayload(gpsValue);
      final url = Uri.parse('${_effectiveBaseUrl()}/api/panic');
      final res = await http
          .post(url, headers: _apiHeaders(), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['success'] != true) {
        final err = data['error']?.toString() ?? 'Could not send SOS';
        _toast(err, isError: true);
        return;
      }
      final reportId = data['id']?.toString() ?? 'SOS-0000';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBFB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.redBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F172A),
                    blurRadius: 26,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.redLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.redBorder),
                    ),
                    child: const Icon(
                      Icons.campaign,
                      color: AppColors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'SOS sent',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'SOS ID: $reportId',
                    style: Theme.of(
                      ctx,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dispatchers have been alerted.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      ctx,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.text2),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } on TimeoutException {
      _toast('Network timeout. Check server URL.', isError: true);
    } catch (e) {
      debugPrint('Send panic error: $e');
      _toast('Network error: ${_shortError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _panicSending = false);
      _closePanicSendingDialog();
    }
  }

  Future<Map<String, dynamic>> _buildPanicPayload(String? gpsValue) async {
    String gps = gpsValue ?? _gps ?? 'unavailable';
    String barangay = '';
    String landmark = '';
    String street = '';

    final parsed = _parseGps(gps);
    if (parsed != null) {
      final lat = parsed.$1;
      final lng = parsed.$2;
      try {
        final url = Uri.parse(
          '${_effectiveBaseUrl()}/api/reverse-geocode?lat=$lat&lng=$lng',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          barangay = (data['barangay'] ?? '').toString().trim();
          landmark = (data['landmark'] ?? '').toString().trim();
          street = (data['street'] ?? '').toString().trim();
        }
      } catch (_) {}
    }

    return {
      'contact': _panicNumber,
      'gps': gps,
      'barangay': barangay,
      'landmark': landmark,
      'street': street,
    };
  }

  (double, double)? _parseGps(String gps) {
    final m = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(gps);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1) ?? '');
    final lng = double.tryParse(m.group(2) ?? '');
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat, lng);
  }

  void _openPanicSetup() {
    _panicCtrl.text = _formatPhMobile(_panicNumber);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.redLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.redBorder),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'One-time setup',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Set the number that will receive your SOS alert.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _panicCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Panic phone number',
                  hintText: '917 123 4567',
                  prefixText: '+63 ',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.orangeBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use a reachable number with SMS enabled.',
                        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _savePanicNumber,
                      child: const Text('Save number'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nameCtrl.clear();
    _contactCtrl.clear();
    _barangayCtrl.clear();
    _landmarkCtrl.clear();
    _streetCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _selectedType = null;
      _selectedSeverity = null;
      _gps = null;
      _gpsAccuracy = null;
      _mapLat = null;
      _mapLng = null;
      _showMap = false;
      _photoPreviewBytes.clear();
      _photoFiles.clear();
    });
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    final bg = isError ? AppColors.red : AppColors.green;
    final tone = isError ? AppColors.orangeLight : AppColors.greenLight;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: bg.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, String> _apiHeaders() {
    return const {'Content-Type': 'application/json', 'X-SVS-Client': 'mobile'};
  }

  void _showPanicSendingDialog() {
    if (!mounted || _panicDialogOpen) return;
    _panicDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBFB),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.orangeBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F172A),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.orangeBorder.withValues(
                              alpha: 0.6,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.red,
                          ),
                          backgroundColor: AppColors.orangeLight,
                        ),
                      ),
                      const Icon(Icons.near_me, color: AppColors.red, size: 34),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Sending SOS...',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: AppColors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Acquiring exact location and alerting dispatchers',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.text2,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _panicDialogOpen = false;
    });
  }

  void _closePanicSendingDialog() {
    if (!mounted || !_panicDialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFEAF2FF),
              Color(0xFFFFF7E6),
              Color(0xFFFFEEF0),
              AppColors.bg,
            ],
          ),
        ),
        child: SafeArea(child: CustomScrollView(slivers: _buildPageSlivers())),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  List<Widget> _buildPageSlivers() {
    switch (_navIndex) {
      case 0:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAboutPage()),
          SliverToBoxAdapter(child: _buildFooter(showContact: true)),
        ];
      case 1:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildPanicStrip()),
          SliverToBoxAdapter(child: _buildSosSteps()),
          SliverToBoxAdapter(child: _buildFooter(showContact: false)),
        ];
      case 2:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildForm()),
          SliverToBoxAdapter(child: _buildFooter(showContact: false)),
        ];
      case 3:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildFaqPage()),
          SliverToBoxAdapter(child: _buildFooter(showContact: false)),
        ];
      default:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildForm()),
          SliverToBoxAdapter(child: _buildFooter(showContact: true)),
        ];
    }
  }

  Widget _buildAboutPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAboutHero(),
          const SizedBox(height: 16),
          _buildAboutHighlights(),
          const SizedBox(height: 18),
          _buildDisasterGuide(),
        ],
      ),
    );
  }

  Widget _buildAboutHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final left = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.greenBorder),
                ),
                child: Text(
                  'The problem -> The solution',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'From clogged hotlines to clear,\nverified emergency reports.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Emergency lines used to drown in prank calls, vague landmarks, and '
                'dropped signals. SVS was built with responders to verify callers, '
                'pin locations automatically, and keep genuine emergencies moving fast.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: () => setState(() => _navIndex = 2),
                    child: const Text('File an Emergency Report'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _navIndex = 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blue,
                      side: const BorderSide(color: AppColors.blue, width: 1.4),
                    ),
                    child: const Text('Quick SOS options'),
                  ),
                ],
              ),
            ],
          );

          final right = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SITE OVERVIEW',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.muted2,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Everything in one place.',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                _aboutBullet(
                  'Learn the history of the emergency-reporting bottleneck.',
                ),
                _aboutBullet(
                  'See the solution: GPS-first SOS, verification, and offline queueing.',
                ),
                _aboutBullet(
                  'Trigger an SOS or file a verified report when seconds matter.',
                ),
              ],
            ),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 16),
                SizedBox(width: 320, child: right),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: 16),
              right,
            ],
          );
        },
      ),
    );
  }

  Widget _aboutMiniCard({
    required String number,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.greenLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.greenBorder),
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutHighlights() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final isWide = constraints.maxWidth >= 920;
        final isMid = constraints.maxWidth >= 640;
        final columns = isWide ? 4 : (isMid ? 2 : 1);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _aboutMiniCard(
                number: '01',
                title: 'Before SVS',
                body:
                    'Hotlines were flooded with prank calls, vague landmarks, and no GPS, slowing real dispatch work.',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _aboutMiniCard(
                number: '02',
                title: 'What had to change',
                body:
                    'We needed caller verification, automatic location capture, and a way to keep signals alive when networks drop.',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _aboutMiniCard(
                number: '03',
                title: 'Our solution',
                body:
                    'GPS-first SOS, identity checks, and offline queueing send clean, verified reports to dispatchers in seconds.',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _aboutMiniCard(
                number: '04',
                title: 'Results for teams',
                body:
                    'Faster triage, fewer false alarms, clearer routes, and better focus on life-saving responses.',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tagPill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bg),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
      ),
    );
  }

  Widget _pillBox(String label, String body, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            softWrap: true,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.text2,
                  height: 1.4,
                  fontSize: 11.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _disasterCard({
    required String title,
    required String tag,
    required List<Widget> details,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              final titleRow = Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.greenBorder),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.blue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                      maxLines: narrow ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!narrow) ...[
                    const SizedBox(width: 6),
                    _tagPill(tag, AppColors.amberLight, AppColors.amberDeep),
                  ],
                ],
              );

              if (!narrow) return titleRow;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleRow,
                  const SizedBox(height: 6),
                  _tagPill(tag, AppColors.amberLight, AppColors.amberDeep),
                ],
              );
            },
          ),
          children: details,
        ),
      ),
    );
  }

  Widget _buildDisasterGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Natural disasters: causes, effects, and what to do',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Quick reference for the most common hazards. Follow the before / during / after guidance and respect the do / do not reminders.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        _disasterCard(
          title: 'Typhoon / Cyclone',
          tag: 'Wind - Surge - Rain',
          details: [
            _pillBox(
              'Cause',
              'Low-pressure system over warm ocean driving severe winds and rain.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Effects',
              'Storm surge, flooding, power loss, flying debris.',
              AppColors.orangeLight,
              AppColors.orange,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Before',
              'Secure loose items, charge phones, prep go-bag, know evacuation routes.',
              AppColors.amberLight,
              AppColors.amberDeep,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'During',
              'Stay indoors away from windows; monitor official alerts; avoid floodwater.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'After',
              'Watch for downed lines, avoid standing water, document damage safely.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Do',
              'Evacuate when ordered; keep radio/phone for updates.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Don?t',
              'Drive through floodwater; go outside during the eye.',
              AppColors.redLight,
              AppColors.red,
            ),
          ],
        ),
        _disasterCard(
          title: 'Flood',
          tag: 'Water - Surge',
          details: [
            _pillBox(
              'Cause',
              'Heavy rain, storm surge, dam release, clogged drainage.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Effects',
              'Rapid water rise, contamination, electrocution risk, landslide triggers.',
              AppColors.orangeLight,
              AppColors.orange,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Before',
              'Move valuables up high, prep sandbags, plan high-ground paths.',
              AppColors.amberLight,
              AppColors.amberDeep,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'During',
              'Get to higher ground fast; turn off main power if safe.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'After',
              'Avoid wading; treat water as contaminated; use PPE for clean-up.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Do',
              'Follow LGU evacuation cues and text alerts.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Don?t',
              'Walk or drive through moving water; return home until cleared.',
              AppColors.redLight,
              AppColors.red,
            ),
          ],
        ),
        _disasterCard(
          title: 'Earthquake',
          tag: 'Shake - Aftershocks',
          details: [
            _pillBox(
              'Cause',
              'Sudden release of tectonic stress along faults.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Effects',
              'Ground shaking, structural collapse, liquefaction, aftershocks.',
              AppColors.orangeLight,
              AppColors.orange,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Before',
              'Bolt shelves, secure breakables, practice Drop-Cover-Hold drills.',
              AppColors.amberLight,
              AppColors.amberDeep,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'During',
              'Drop, Cover, Hold On; stay away from glass; move to open space.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'After',
              'Expect aftershocks; check gas leaks; avoid damaged structures.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Do',
              'Use stairs, not elevators, when exiting after shaking.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Don?t',
              'Run during shaking; stand under doorways or near windows.',
              AppColors.redLight,
              AppColors.red,
            ),
          ],
        ),
        _disasterCard(
          title: 'Fire / Urban Blaze',
          tag: 'Heat - Smoke',
          details: [
            _pillBox(
              'Cause',
              'Faulty wiring, open flames, cooking accidents, arson.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Effects',
              'Smoke inhalation, burns, structural failure, toxic fumes.',
              AppColors.orangeLight,
              AppColors.orange,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Before',
              'Check exits, keep extinguishers, avoid overloading outlets.',
              AppColors.amberLight,
              AppColors.amberDeep,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'During',
              'Stay low under smoke, feel doors for heat, evacuate and do not re-enter.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'After',
              'Call authorities, get medical check for smoke, do not switch power back on.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Do',
              'Stop, Drop, Roll if clothes ignite.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Don?t',
              'Use elevators; open hot doors; waste time gathering items.',
              AppColors.redLight,
              AppColors.red,
            ),
          ],
        ),
        _disasterCard(
          title: 'Landslide',
          tag: 'Slope - Soil',
          details: [
            _pillBox(
              'Cause',
              'Saturated slopes after heavy rain, earthquakes, or excavation.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Effects',
              'Rapid ground movement, buried roads/houses, blocked rivers.',
              AppColors.orangeLight,
              AppColors.orange,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Before',
              'Note cracks, leaning trees, recent slope cuts; prepare to relocate.',
              AppColors.amberLight,
              AppColors.amberDeep,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'During',
              'Evacuate uphill and away from the slide path; alert neighbors.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'After',
              'Avoid area until cleared; watch for secondary slides.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Do',
              'Heed slope warnings; keep go-bag ready in rainy season.',
              AppColors.greenLight,
              AppColors.blue,
            ),
            const SizedBox(height: 8),
            _pillBox(
              'Don?t',
              'Build or camp at the base of unstable slopes.',
              AppColors.redLight,
              AppColors.red,
            ),
          ],
        ),
      ],
    );
  }
  Widget _aboutBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppColors.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Frequently Asked Questions',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything you need to know about sending reports, staying verified, and keeping dispatchers focused on real emergencies.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _faqItem(
                  question: 'What counts as an emergency?',
                  answer:
                      'Immediate threats to life, health, or critical infrastructure: fire, trapped or injured people, severe flooding, collapsed structures, major road blockages, chemical spills.',
                  open: true,
                ),
                _faqDivider(),
                _faqItem(
                  question: 'How does SVS reduce prank calls?',
                  answer:
                      'Reports are verified through rate limiting, dispatcher review, and multi-channel checks to reduce false reports.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'Can I submit without GPS?',
                  answer:
                      'Yes. You can still enter barangay, landmark, and street details manually to send a report.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'What if I lose connection mid-report?',
                  answer:
                      'Your report is queued and retried once connectivity returns.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'Who can access the dashboard?',
                  answer:
                      'Authorized dispatchers and admins with secure login access only.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: () => setState(() => _navIndex = 2),
                child: const Text('Send a report'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _navIndex = 0),
                child: const Text('Learn about SVS'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _faqDivider() {
    return Divider(height: 20, color: AppColors.border.withValues(alpha: 0.7));
  }

  Widget _faqItem({
    required String question,
    required String answer,
    bool open = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: open,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        title: Text(
          question,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1F3560),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: AppColors.bgSoft,
          border: Border(
            top: BorderSide(color: AppColors.border.withValues(alpha: 0.25)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: (index) => setState(() => _navIndex = index),
          iconSize: 26,
          selectedFontSize: 13,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'About',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sos_rounded),
              label: 'SOS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_rounded),
              label: 'Report',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.quiz_rounded),
              label: 'FAQ',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/svs-logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SVS',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Smart Verification System',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPanicStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F0F172A),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.redBorder),
                ),
                child: Text(
                  'URGENT EMERGENCY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.red,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _panicSending ? null : _sendPanic,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFEF4444),
                        Color(0xFFDC2626),
                        Color(0xFFB91C1C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66DC2626),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _panicSending ? 'SENDING' : 'PANIC SOS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Tap to send instant SOS. Your location will be sent to dispatchers immediately.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _openPanicSetup,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.greenLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.greenBorder),
                        ),
                        child: const Icon(
                          Icons.phone,
                          size: 16,
                          color: AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _panicNumber == null
                              ? 'Set panic number'
                              : 'Sending as ${_formatPhMobile(_panicNumber)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.text2,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      Text(
                        'Change',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleSection(),
            const SizedBox(height: 16),
            _buildAlertStrip(),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              _buildSupabaseDebug(),
            ],
            const SizedBox(height: 16),
            _buildQuickGuide(),
            const SizedBox(height: 12),
            _buildCard(
              step: 'Step 01',
              title: 'Your Information',
              subtitle: 'Who is making this report?',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _textField(
                          controller: _nameCtrl,
                          label: 'Full Name',
                          hint: 'Juan dela Cruz',
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _textField(
                          controller: _contactCtrl,
                          label: 'Contact Number',
                          hint: '917 123 4567',
                          keyboardType: TextInputType.phone,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                          prefixText: '+63 ',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildCard(
              step: 'Step 02',
              title: 'Type of Emergency',
              subtitle: 'Select the category that best describes the incident',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  const runSpacing = 10.0;
                  const columns = 3;
                  final totalSpacing = spacing * (columns - 1);
                  final chipWidth =
                      (constraints.maxWidth - totalSpacing) / columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: runSpacing,
                    children: _types
                        .map(
                          (type) => SizedBox(
                            width: chipWidth,
                            child: _SelectChip(
                              label: type,
                              selected: _selectedType == type,
                              onTap: () => setState(() => _selectedType = type),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildCard(
              step: 'Step 03',
              title: 'Severity Level',
              subtitle: 'How serious is the situation right now?',
              child: Row(
                children: [
                  Expanded(
                    child: _SeverityButton(
                      label: 'Low',
                      color: AppColors.green,
                      selected: _selectedSeverity == 'Low',
                      onTap: () => setState(() => _selectedSeverity = 'Low'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SeverityButton(
                      label: 'Medium',
                      color: AppColors.amberDark,
                      selected: _selectedSeverity == 'Medium',
                      onTap: () => setState(() => _selectedSeverity = 'Medium'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SeverityButton(
                      label: 'High',
                      color: AppColors.red,
                      selected: _selectedSeverity == 'High',
                      onTap: () => setState(() => _selectedSeverity = 'High'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildCard(
              step: 'Step 04',
              title: 'Location',
              subtitle: 'Where is the emergency happening?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _detectingGps ? null : _detectGps,
                    icon: _detectingGps
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gps_fixed),
                    label: Text(
                      _gps == null
                          ? 'Auto-detect My Location (GPS)'
                          : 'Detected: $_gps (${_gpsAccuracy ?? 0}m)',
                    ),
                  ),
                  if (_gps != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detected location: $_gps',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.muted),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openMap(_gps!),
                          child: const Text('Open map'),
                        ),
                      ],
                    ),
                  ],
                  if (_showMap && _mapLat != null && _mapLng != null) ...[
                    const SizedBox(height: 12),
                    _buildLocationMap(_mapLat!, _mapLng!),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _textField(
                          controller: _barangayCtrl,
                          label: 'Barangay',
                          hint: 'Barangay Rizal',
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _textField(
                          controller: _landmarkCtrl,
                          label: 'Nearest Landmark',
                          hint: 'Near Municipal Hall',
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _streetCtrl,
                    label: 'Street / Additional Details',
                    hint: 'Street name or additional details',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildCard(
              step: 'Step 05',
              title: 'Incident Details',
              subtitle: 'Describe the situation and attach a photo if possible',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _textField(
                    controller: _descCtrl,
                    label: 'Description',
                    hint:
                        'Describe what is happening. Include number of people affected and hazards.',
                    maxLines: 4,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildPhotoPicker(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submitReport,
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amberDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              label: Text(
                _submitting ? 'Submitting...' : 'Submit Emergency Report',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationMap(double lat, double lng) {
    final target = LatLng(lat, lng);
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: target,
              initialZoom: 17,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.smart_verification_system',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: target,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.red,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xF2FFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Detected location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openMap(
                      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    ),
                    child: const Text('Open map'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xE6FFFFFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '© OpenStreetMap contributors',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.redLight,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.redBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 14,
                color: AppColors.red,
              ),
              const SizedBox(width: 6),
              Text(
                'SVS Emergency Report System',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.red,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Report an Emergency',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Your report will be received immediately by SVS dispatchers. Provide as much detail as possible for a faster response.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.text2, height: 1.5),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildAlertStrip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEFCE8), Color(0xFFFEF2F2)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orangeBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.orange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'For life-threatening emergencies, call 911 immediately. This form is for reporting incidents and requesting assistance through SVS.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.text2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sosStepCard({
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderMid),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.red,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.text2,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosSteps() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final isWide = constraints.maxWidth >= 900;
          final isMid = constraints.maxWidth >= 640;
          final columns = isWide ? 3 : (isMid ? 2 : 1);
          final cardWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: cardWidth,
                child: _sosStepCard(
                  title: '1. Tap Panic',
                  body:
                      'Sends your saved emergency contact plus your latest GPS fix.',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _sosStepCard(
                  title: '2. Stay on the line',
                  body:
                      'Dispatch will call back if GPS is weak. Keep your phone nearby.',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _sosStepCard(
                  title: '3. If offline',
                  body:
                      'Reports are queued and auto-retried when signal returns.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _guideItem({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.amberDeep,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickGuide() {
    return _buildCard(
      step: 'Quick Guide',
      title: 'Complete the report in order',
      subtitle:
          'Follow the five sections below. The most important details are your callback number, exact location, and a short description.',
      child: Column(
        children: [
          _guideItem(
            number: '01',
            title: 'Reporter details',
            subtitle: 'Name and contact number',
          ),
          _guideItem(
            number: '02',
            title: 'Emergency type',
            subtitle: 'Choose the closest match',
          ),
          _guideItem(
            number: '03',
            title: 'Severity',
            subtitle: 'Tell dispatch how urgent it is',
          ),
          _guideItem(
            number: '04',
            title: 'Location',
            subtitle: 'GPS, barangay, landmark, street',
          ),
          _guideItem(
            number: '05',
            title: 'Incident details',
            subtitle: 'Description and optional photo',
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderMid, width: 2),
        ),
        child: _photoFiles.isEmpty
            ? Column(
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 32,
                    color: AppColors.muted2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to add a photo',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'JPG or PNG up to 10 MB each',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_photoPreviewBytes.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _photoPreviewBytes.first,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tap to change photo',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted2),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _removePhoto,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _configStatusLine({
    required String label,
    required bool ok,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: ok ? AppColors.green : AppColors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupabaseDebug() {
    if (!kDebugMode) return const SizedBox.shrink();
    final url = _supabaseUrlEnv.trim();
    final anon = _supabaseAnonKeyEnv.trim();
    final bucket = _supabaseBucketEnv.trim();
    final anonLooksJwt = anon.startsWith('eyJ');
    final anonHint = anon.isEmpty ? '(empty)' : '${anon.substring(0, 8)}...';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supabase config (debug)',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _configStatusLine(
            label: 'URL',
            ok: url.isNotEmpty,
            value: url.isNotEmpty ? url : '(empty)',
          ),
          const SizedBox(height: 6),
          _configStatusLine(
            label: 'Anon key',
            ok: anonLooksJwt,
            value: anonLooksJwt ? anonHint : '$anonHint (not JWT)',
          ),
          const SizedBox(height: 6),
          _configStatusLine(
            label: 'Bucket',
            ok: bucket.isNotEmpty,
            value: bucket.isNotEmpty ? bucket : '(empty)',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter({required bool showContact}) {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.amberLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.amberBorder),
                ),
                child: const Icon(
                  Icons.local_fire_department,
                  color: AppColors.amberDeep,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Verification System',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Emergency Reporting',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.muted2),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Fast and reliable citizen incident reporting with real-time dispatcher visibility and location-aware alerts.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          if (showContact) ...[
            const SizedBox(height: 12),
            Text(
              'Contact Us',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Hotline: 911', style: Theme.of(context).textTheme.bodySmall),
            Text(
              'Office: +63 917 000 0000',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Email: support@svs.local',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Copyright $year SVS. All rights reserved.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String step,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.red,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? prefixText,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Future<void> _openMap(String gps) async {
    final parsed = _parseGps(gps);
    if (parsed == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps?q=${parsed.$1},${parsed.$2}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: selected ? AppColors.amberLight : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.amberBorder : AppColors.border,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? AppColors.amberDeep : AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityButton extends StatelessWidget {
  const _SeverityButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? color : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
