import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _alertNotificationChannel =
    AndroidNotificationChannel(
      'svs_alerts',
      'SVS Alerts',
      description: 'Emergency alerts sent by the SVS admin dashboard.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
bool _localNotificationsReady = false;

Future<void> _bootstrapNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotifications.initialize(settings: initSettings);
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(_alertNotificationChannel);
  await androidPlugin?.requestNotificationsPermission();
  _localNotificationsReady = true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await _bootstrapNotifications();
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
        backgroundColor: AppColors.navBg,
        selectedItemColor: AppColors.navSelected,
        unselectedItemColor: AppColors.navUnselected,
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
  static const navBg = Color(0xFFFFFFFF);
  static const navSelected = Color(0xFF1F4BB8);
  static const navUnselected = Color(0xFF7E8FA8);
  static const bg = Color(0xFFF5F7FF);
  static const bgSoft = Color(0xFF1F3560);
  static const surface = Color(0xFFF4F8FF);
  static const border = Color(0xFFD9E3F2);
  static const borderMid = Color(0xFFBFD0EA);
  static const text = Color(0xFF0E1A2B);
  static const text2 = Color(0xFF1F3560);
  static const muted = Color(0xFF5D6D86);
  static const muted2 = Color(0xFF7E8FA8);
}

class AdminAlert {
  const AdminAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.disasterType,
    required this.severity,
    required this.active,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String disasterType;
  final String severity;
  final bool active;
  final DateTime? createdAt;

  factory AdminAlert.fromJson(Map<String, dynamic> json) {
    return AdminAlert(
      id: (json['id'] ?? json['source_id'] ?? '').toString(),
      title: (json['title'] ?? 'Emergency alert').toString().trim(),
      message: (json['message'] ?? '').toString().trim(),
      disasterType: (json['disasterType'] ?? json['disaster_type'] ?? 'General')
          .toString()
          .trim(),
      severity: (json['severity'] ?? 'high').toString().trim().toLowerCase(),
      active: (json['active'] ?? json['is_active']) != false,
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['created_at'] ?? '').toString(),
      ),
    );
  }
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with WidgetsBindingObserver {
  static const bool _showReporterDebugPanels = false;

  final MapController _mapController = MapController();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _panicCtrl = TextEditingController();
  final _faqFeedbackCtrl = TextEditingController();

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
  double _mapZoom = 16;
  bool _mapSatellite = false;

  final List<Uint8List> _photoPreviewBytes = [];
  final List<XFile> _photoFiles = [];

  bool _submitting = false;
  bool _panicSending = false;
  bool _panicDialogOpen = false;
  bool _checkingAlerts = false;
  bool _alertDialogOpen = false;
  int _navIndex = 2;

  String? _panicNumber;
  String _baseUrl = 'https://svsmdrrmo.vercel.app';
  static const String _queuedReportsKey = 'queued_reports';
  static const String _lastSeenAlertIdKey = 'last_seen_alert_id';
  static const Duration _alertPollInterval = Duration(seconds: 5);

  static const String _baseUrlEnv = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );
  final String _baseUrlDotenv = dotenv.env['BASE_URL'] ?? '';
  bool _baseUrlReady = false;

  final String _supabaseUrlEnv = dotenv.env['SUPABASE_URL'] ?? '';
  final String _supabaseAnonKeyEnv = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  final String _supabaseBucketEnv = dotenv.env['SUPABASE_BUCKET'] ?? '';
  final String _supabaseAlertsTableEnv =
      dotenv.env['SUPABASE_ALERTS_TABLE'] ?? 'admin_alerts';
  Timer? _alertPollingTimer;
  String? _lastSeenAlertId;
  AdminAlert? _activeAlert;
  String _alertDebugStatus = 'idle';
  String _alertDebugSource = '-';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadPrefs();
    await _initBaseUrl();
    _trySendQueuedReports();
    await _primeAdminAlerts();
    _startAlertPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertPollingTimer?.cancel();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _barangayCtrl.dispose();
    _landmarkCtrl.dispose();
    _streetCtrl.dispose();
    _descCtrl.dispose();
    _panicCtrl.dispose();
    _faqFeedbackCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySendQueuedReports();
      unawaited(_primeAdminAlerts());
      _startAlertPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _alertPollingTimer?.cancel();
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final panicNum = prefs.getString('panic_number');
    final baseUrl = prefs.getString('base_url');
    final lastSeenAlertId = prefs.getString(_lastSeenAlertIdKey);
    setState(() {
      _panicNumber = panicNum;
      _panicCtrl.text = _formatPhMobile(_panicNumber);
      _lastSeenAlertId = lastSeenAlertId;
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
    if (_baseUrlDotenv.trim().isNotEmpty) {
      candidates.add(_normalizedBaseUrl(_baseUrlDotenv));
    }
    if (_baseUrlEnv.trim().isNotEmpty) {
      candidates.add(_normalizedBaseUrl(_baseUrlEnv));
    }
    if (!kIsWeb && Platform.isAndroid) {
      candidates.add('http://10.0.2.2:3000');
    }
    candidates.add('http://localhost:3000');
    candidates.add('http://127.0.0.1:3000');
    if (_baseUrl.trim().isNotEmpty) {
      candidates.add(_normalizedBaseUrl(_baseUrl));
    }
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

  Future<void> _showAdminAlertNotification(AdminAlert alert) async {
    if (!_localNotificationsReady) return;
    final body = alert.message.isEmpty
        ? '${alert.disasterType} - ${alert.severity.toUpperCase()}'
        : alert.message;
    await _localNotifications.show(
      id: alert.id.hashCode,
      title: alert.title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _alertNotificationChannel.id,
          _alertNotificationChannel.name,
          channelDescription: _alertNotificationChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: jsonEncode({
        'id': alert.id,
        'title': alert.title,
        'message': alert.message,
        'disasterType': alert.disasterType,
        'severity': alert.severity,
      }),
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

  void _startAlertPolling() {
    _alertPollingTimer?.cancel();
    unawaited(_checkForAdminAlerts());
    _alertPollingTimer = Timer.periodic(_alertPollInterval, (_) {
      _checkForAdminAlerts();
    });
  }

  Future<void> _saveLastSeenAlertId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenAlertIdKey, id);
    _lastSeenAlertId = id;
  }

  Future<void> _primeAdminAlerts() async {
    await _checkForAdminAlerts(notifyOnNew: false);
  }

  Future<void> _consumeAdminAlert(
    AdminAlert alert, {
    required bool notifyOnNew,
  }) async {
    if (alert.id.isEmpty || !alert.active) {
      if (mounted && _activeAlert != null) {
        setState(() => _activeAlert = null);
      }
      return;
    }

    final isNewAlert = alert.id != _lastSeenAlertId;
    if (mounted) {
      setState(() => _activeAlert = alert);
    }

    if (isNewAlert) {
      await _saveLastSeenAlertId(alert.id);
      if (notifyOnNew) {
        await _showAdminAlertNotification(alert);
        await _presentAdminAlert(alert);
      }
    }
  }

  Future<void> _checkForAdminAlerts({bool notifyOnNew = true}) async {
    if (_checkingAlerts) return;

    _checkingAlerts = true;
    try {
      AdminAlert? alert;
      var source = 'supabase';
      alert = await _fetchLatestAlertFromSupabase();
      if (alert == null && await _ensureBaseUrlReady(showError: false)) {
        source = 'server';
        alert = await _fetchLatestAlertFromServer();
      }

      if (alert == null) {
        if (mounted && _activeAlert != null) {
          setState(() => _activeAlert = null);
        }
        if (mounted) {
          setState(() {
            _alertDebugStatus = 'no active alert found';
            _alertDebugSource = source;
          });
        }
        return;
      }
      if (mounted) {
        final resolvedAlert = alert;
        setState(() {
          _alertDebugStatus =
              'alert ${resolvedAlert.id} ${notifyOnNew ? "checked" : "primed"}';
          _alertDebugSource = source;
        });
      }
      await _consumeAdminAlert(alert, notifyOnNew: notifyOnNew);
    } catch (e) {
      debugPrint('[alerts] poll failed: $e');
      if (mounted) {
        setState(() {
          _alertDebugStatus = 'error: ${_shortError(e)}';
        });
      }
    } finally {
      _checkingAlerts = false;
    }
  }

  Future<AdminAlert?> _fetchLatestAlertFromServer() async {
    final url = Uri.parse('${_effectiveBaseUrl()}/api/alerts/latest');
    final res = await http
        .get(url, headers: _apiHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint('[alerts] server status=${res.statusCode} body=${res.body}');
      return null;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['success'] != true) return null;

    final alertJson = data['alert'];
    if (alertJson is! Map) return null;
    return AdminAlert.fromJson(alertJson.cast<String, dynamic>());
  }

  Future<AdminAlert?> _fetchLatestAlertFromSupabase() async {
    if (_supabaseUrlEnv.trim().isEmpty || _supabaseAnonKeyEnv.trim().isEmpty) {
      return null;
    }
    final table = _supabaseAlertsTableEnv.trim().isEmpty
        ? 'admin_alerts'
        : _supabaseAlertsTableEnv.trim();
    final baseUrl = _normalizedSupabaseUrl(_supabaseUrlEnv);
    final url = Uri.parse(
      '$baseUrl/rest/v1/${Uri.encodeComponent(table)}'
      '?select=source_id,title,message,disaster_type,severity,active,sent_by,created_at'
      '&active=eq.true'
      '&order=created_at.desc'
      '&limit=1',
    );
    final res = await http
        .get(
          url,
          headers: {
            'Authorization': 'Bearer $_supabaseAnonKeyEnv',
            'apikey': _supabaseAnonKeyEnv,
          },
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint('[alerts] supabase status=${res.statusCode} body=${res.body}');
      return null;
    }
    final data = jsonDecode(res.body);
    if (data is! List || data.isEmpty || data.first is! Map) return null;
    return AdminAlert.fromJson((data.first as Map).cast<String, dynamic>());
  }

  Future<void> _triggerTestAlert() async {
    const alert = AdminAlert(
      id: 'debug-local-test',
      title: 'Debug Alert Test',
      message: 'Local notifications are working on this device.',
      disasterType: 'System',
      severity: 'high',
      active: true,
    );
    await _showAdminAlertNotification(alert);
    if (mounted) {
      setState(() {
        _alertDebugStatus = 'local notification test fired';
        _alertDebugSource = 'device';
      });
      _toast('Local notification test fired');
    }
  }

  Widget _buildAlertDebugPanel() {
    if (!kDebugMode || !_showReporterDebugPanels) {
      return const SizedBox.shrink();
    }
    final ok = !_alertDebugStatus.startsWith('error');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? AppColors.greenLight : AppColors.redLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok ? AppColors.greenBorder : AppColors.redBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alert debug',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Status: $_alertDebugStatus',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.text2),
          ),
          const SizedBox(height: 4),
          Text(
            'Source: $_alertDebugSource',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.text2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    unawaited(_checkForAdminAlerts());
                    _toast('Checking alerts now');
                  },
                  child: const Text('Check Alerts'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _triggerTestAlert,
                  child: const Text('Test Notification'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _presentAdminAlert(AdminAlert alert) async {
    if (!mounted || _alertDialogOpen) return;
    _alertDialogOpen = true;
    unawaited(_triggerAlertFeedback());
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final severityColor = _alertSeverityColor(alert.severity);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBFB),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.redBorder, width: 1.4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330F172A),
                    blurRadius: 28,
                    offset: Offset(0, 14),
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
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.redLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.redBorder),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.red,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.title,
                              style: Theme.of(ctx).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${alert.disasterType} - ${alert.severity.toUpperCase()}',
                              style: Theme.of(ctx).textTheme.labelSmall
                                  ?.copyWith(
                                    color: severityColor,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    alert.message,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.text2,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.orangeBorder),
                    ),
                    child: Text(
                      'Prepare now and follow official MDRRMO or LGU instructions.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.text2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('I Understand'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _alertDialogOpen = false;
    }
  }

  Future<void> _triggerAlertFeedback() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    for (var i = 0; i < 3; i++) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  Color _alertSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return AppColors.red;
      case 'medium':
        return AppColors.amberDeep;
      case 'low':
        return AppColors.blue;
      case 'high':
      default:
        return AppColors.orange;
    }
  }

  Widget _buildAdminAlertBanner() {
    final alert = _activeAlert;
    if (alert == null || !alert.active) return const SizedBox.shrink();

    final severityColor = _alertSeverityColor(alert.severity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InkWell(
        onTap: () => _presentAdminAlert(alert),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF4E8), Color(0xFFFFECEC)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.orangeBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.redBorder),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: AppColors.red,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Disaster Alert',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: severityColor,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
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
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF2F6FF),
                    Color(0xFFFFF7EF),
                    Color(0xFFFFFFFF),
                  ],
                  stops: [0.0, 0.82, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -150,
            right: -170,
            child: IgnorePointer(
              child: Container(
                width: 520,
                height: 360,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.95,
                    colors: [Color(0x293B82F6), Color(0x003B82F6)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -110,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 280,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.95,
                    colors: [Color(0x1FEF4444), Color(0x00EF4444)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(child: CustomScrollView(slivers: _buildPageSlivers())),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  List<Widget> _buildPageSlivers() {
    switch (_navIndex) {
      case 0:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAdminAlertBanner()),
          SliverToBoxAdapter(child: _buildAboutPage()),
          SliverToBoxAdapter(child: _buildFooter()),
        ];
      case 1:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAdminAlertBanner()),
          SliverToBoxAdapter(child: _buildPanicStrip()),
          SliverToBoxAdapter(child: _buildSosSteps()),
          SliverToBoxAdapter(child: _buildFooter()),
        ];
      case 2:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAdminAlertBanner()),
          SliverToBoxAdapter(child: _buildForm()),
          SliverToBoxAdapter(child: _buildFooter()),
        ];
      case 3:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAdminAlertBanner()),
          SliverToBoxAdapter(child: _buildFaqPage()),
          SliverToBoxAdapter(child: _buildFooter()),
        ];
      default:
        return [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildAdminAlertBanner()),
          SliverToBoxAdapter(child: _buildForm()),
          SliverToBoxAdapter(child: _buildFooter()),
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
          const SizedBox(height: 20),
          _buildEmergencyGuideSection(),
          const SizedBox(height: 20),
          _buildHotlineSection(),
          const SizedBox(height: 20),
          _buildAboutFooterCallout(),
        ],
      ),
    );
  }

  Widget _buildAboutHero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xD1FFFFFF), Color(0xE6EEF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E5FF), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x190F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
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
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.borderMid),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  'The problem -> The solution',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'From clogged hotlines to clear, verified emergency reports.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  color: const Color(0xFF0C1A36),
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Emergency lines used to drown in prank calls, vague landmarks, and '
                'dropped signals. SVS was built with responders to verify callers, '
                'pin locations automatically, and keep genuine emergencies moving fast.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF1F2937),
                  height: 1.75,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => setState(() => _navIndex = 2),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('File an Emergency Report'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _navIndex = 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blue,
                      side: const BorderSide(
                        color: AppColors.borderMid,
                        width: 1.5,
                      ),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Quick SOS options'),
                  ),
                ],
              ),
            ],
          );

          final right = Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF4F7FF), Color(0xFFEEF3FF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBDCFE), width: 1.6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SITE OVERVIEW',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.blue,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Everything in one place.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1A36),
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
            children: [left, const SizedBox(height: 16), right],
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Color(0xFFEEF4FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBED6FA), width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x401D4ED8),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF14213D),
              height: 1.6,
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

  Widget _buildHotlineSection() {
    final hotlines = <Map<String, String>>[
      {
        'label': 'Mayor\'s Office',
        'phone': '(075) 632 1757',
        'dial': '0756321757',
        'image': 'assets/public/images/logo1.png',
      },
      {
        'label': 'Bureau of Fire Protection (BFP)',
        'phone': '(075) 636 4321\n0943 424 2810\n0917 186 6611',
        'dial': '0756364321',
        'image': 'assets/public/images/logo2.png',
      },
      {
        'label': 'Philippine National Police (PNP)',
        'phone': '(075) 632 1754\n0998 598 5117',
        'dial': '0756321754',
        'image': 'assets/public/images/logo3.png',
      },
      {
        'label': 'Pangasinan Electric Coop (PANELCO III)',
        'phone': '0915 448 1608\n0942 700 9417',
        'dial': '09154481608',
        'image': 'assets/public/images/logo4.png',
      },
      {
        'label': 'Mawadi-PrimeWater',
        'phone': '0949 300 3375',
        'dial': '09493003375',
        'image': 'assets/public/images/logo5.png',
      },
      {
        'label': 'MDRRMO',
        'phone': '(075) 600 2564\n0969 223 6912',
        'dial': '0756002564',
        'image': 'assets/public/images/logo6.png',
      },
      {
        'label': 'Rural Health Unit (RHU)',
        'phone': '(075) 632 1874\n0912 679 8036',
        'dial': '0756321874',
        'image': 'assets/public/images/logo7.png',
      },
      {
        'label': 'Mapandan Community Hospital',
        'phone': '(075) 632 0491',
        'dial': '0756320491',
        'image': 'assets/public/images/logo8.png',
      },
      {
        'label': 'Ambulance',
        'phone': '0910 131 1110',
        'dial': '09101311110',
        'image': 'assets/public/images/logo9.png',
      },
      {
        'label': 'MSWD',
        'phone': '(075) 632 1751',
        'dial': '0756321751',
        'image': 'assets/public/images/logo10.png',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emergency Hotlines',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1A36),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = constraints.maxWidth >= 940
                ? 4
                : constraints.maxWidth >= 680
                ? 3
                : constraints.maxWidth >= 440
                ? 2
                : 1;
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: hotlines
                  .map(
                    (item) => SizedBox(
                      width: cardWidth,
                      child: _buildHotlineCard(
                        label: item['label']!,
                        phone: item['phone']!,
                        dialNumber: item['dial']!,
                        imagePath: item['image']!,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmergencyGuideSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emergency Guide',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1A36),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Open each emergency type to review the cause, effects, and what to do before, during, and after the incident.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF1F2937),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        _buildEmergencyGuideCard(
          title: 'Typhoon / Cyclone',
          subtitle: 'Wind, heavy rain, and storm surge',
          cause:
              'Low-pressure systems over warm seas can intensify into strong winds and prolonged heavy rain.',
          effects:
              'Flooding, flying debris, power interruptions, storm surge, and blocked roads.',
          before:
              'Charge devices, prepare a go-bag, secure loose items, and know your evacuation route.',
          during:
              'Stay indoors away from windows, monitor official alerts, and avoid floodwater.',
          after:
              'Watch for downed lines, unstable structures, and standing water before returning outside.',
        ),
        _buildEmergencyGuideCard(
          title: 'Flood',
          subtitle: 'Rapid water rise and contamination risk',
          cause:
              'Heavy rainfall, storm surge, overflowing rivers, and clogged drainage systems.',
          effects:
              'Strong currents, contaminated water, isolation, electrocution hazards, and damaged homes.',
          before:
              'Move essentials to higher places, prepare food and water, and identify safe higher ground.',
          during:
              'Evacuate early, cut power if safe, and never walk or drive through moving water.',
          after:
              'Use protective gear, avoid contaminated water, and return only when authorities say it is safe.',
        ),
        _buildEmergencyGuideCard(
          title: 'Earthquake',
          subtitle: 'Sudden ground shaking and aftershocks',
          cause:
              'Tectonic plates release built-up stress along faults beneath the ground.',
          effects:
              'Structural damage, falling debris, aftershocks, landslides, and utility disruptions.',
          before:
              'Secure heavy furniture, identify safe spots, and practice Drop, Cover, and Hold On.',
          during:
              'Drop, Cover, and Hold On. Stay away from glass and do not run during active shaking.',
          after:
              'Expect aftershocks, check injuries, avoid damaged buildings, and watch for gas or electrical leaks.',
        ),
        _buildEmergencyGuideCard(
          title: 'Fire / Urban Blaze',
          subtitle: 'Fast-moving heat, smoke, and toxic fumes',
          cause:
              'Faulty wiring, open flames, cooking accidents, overloaded outlets, or arson.',
          effects:
              'Burns, smoke inhalation, building damage, toxic air, and limited escape routes.',
          before:
              'Check exits, keep extinguishers ready, and avoid unsafe electrical setups.',
          during:
              'Stay low below smoke, feel doors for heat, evacuate quickly, and never re-enter the structure.',
          after:
              'Seek medical care for smoke exposure, avoid weakened areas, and wait for official clearance.',
        ),
        _buildEmergencyGuideCard(
          title: 'Landslide',
          subtitle: 'Slope failure after rain or shaking',
          cause:
              'Saturated soil, steep slopes, earthquakes, and excavation can destabilize the ground.',
          effects:
              'Buried homes, blocked roads, damaged utilities, and secondary slope failures.',
          before:
              'Watch for ground cracks, leaning trees, or unusual slope movement and prepare to evacuate early.',
          during:
              'Move away from the slide path immediately and warn nearby people if possible.',
          after:
              'Stay out of the area, watch for more movement, and wait for authorities to inspect the slope.',
        ),
      ],
    );
  }

  Widget _buildEmergencyGuideCard({
    required String title,
    required String subtitle,
    required String cause,
    required String effects,
    required String before,
    required String during,
    required String after,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Color(0xFFEEF4FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBED6FA), width: 1.4),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.amberDeep,
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.blue,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
          children: [
            _buildEmergencyGuideInfo('Cause', cause),
            const SizedBox(height: 8),
            _buildEmergencyGuideInfo('Effects', effects),
            const SizedBox(height: 8),
            _buildEmergencyGuideInfo('Before', before),
            const SizedBox(height: 8),
            _buildEmergencyGuideInfo('During', during),
            const SizedBox(height: 8),
            _buildEmergencyGuideInfo('After', after),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyGuideInfo(String label, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.red,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
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

  Widget _buildHotlineCard({
    required String label,
    required String phone,
    required String dialNumber,
    required String imagePath,
  }) {
    final phoneNumbers = phone
        .split('\n')
        .map((number) => number.trim())
        .where((number) => number.isNotEmpty)
        .toList();
    final hasMultipleNumbers = phoneNumbers.length > 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleHotlineTap(
          label: label,
          phoneNumbers: phoneNumbers,
          fallbackDialNumber: dialNumber,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF8FBFF), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC8D7F3), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  imagePath,
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                    if (hasMultipleNumbers) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Tap to choose a number',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.call_outlined, color: AppColors.blue, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleHotlineTap({
    required String label,
    required List<String> phoneNumbers,
    required String fallbackDialNumber,
  }) async {
    if (phoneNumbers.length <= 1) {
      await _callHotline(
        phoneNumbers.isEmpty ? fallbackDialNumber : phoneNumbers.first,
      );
      return;
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFBFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderMid,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a number to open in your phone app.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                ...phoneNumbers.map(
                  (number) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(number),
                        borderRadius: BorderRadius.circular(10),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.greenLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.greenBorder,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.call_outlined,
                                  color: AppColors.blue,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  number,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      await _callHotline(selected);
    }
  }

  Future<void> _callHotline(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (opened) return;
    } catch (_) {}

    try {
      final opened = await launchUrl(uri);
      if (opened) return;
    } catch (_) {}

    if (mounted) {
      _toast('Could not open phone app for $phone', isError: true);
    }
  }

  Widget _buildAboutFooterCallout() {
    return Container(
      alignment: Alignment.center,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
          children: const [
            TextSpan(text: 'Need immediate help? Go to the '),
            TextSpan(
              text: 'SOS page',
              style: TextStyle(color: AppColors.blue),
            ),
            TextSpan(text: ' or file a '),
            TextSpan(
              text: 'report',
              style: TextStyle(color: AppColors.blue),
            ),
            TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }

  Widget _aboutBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                color: const Color(0xFF1F2937),
                height: 1.6,
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
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0C1A36),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Everything you need to know about sending reports, staying verified, and keeping dispatchers focused on real emergencies.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF1E293B),
              height: 1.75,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFaqChip('Verified callers'),
              _buildFaqChip('GPS-first'),
              _buildFaqChip('Offline ready'),
              _buildFaqChip('Dispatcher-first UX'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF7FAFF), Color(0xFFEEF3FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD3E2FF), width: 1.6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x240F172A),
                  blurRadius: 20,
                  offset: Offset(0, 10),
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
                      'We use attestation, phone validation, rate limits, dispatcher review, and pattern checks on repeat offenders. Photos and GPS improve verification.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'Can I submit without GPS?',
                  answer:
                      'Yes. Fill in barangay, landmark, and street. If GPS later appears, we append it to help dispatch find you faster.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'What if I lose connection mid-report?',
                  answer:
                      'Your submission is stored in the offline queue and automatically re-sent when connectivity returns. You can also call the hotline.',
                ),
                _faqDivider(),
                _faqItem(
                  question: 'Who can access the dashboard?',
                  answer:
                      'Only authenticated dispatchers and admins with role-based access. Login attempts are rate-limited and monitored.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildFaqFeedbackCard(),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: () => setState(() => _navIndex = 2),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Send a report'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _navIndex = 0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  side: const BorderSide(color: AppColors.borderMid),
                  backgroundColor: Colors.white,
                ),
                child: const Text('Learn about SVS'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFaqChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE7FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.blue,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFaqFeedbackCard() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F0),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'We value your feedback',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB23B3B),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Let us know how we can improve your experience or if you have any suggestions. Your input helps us serve you better.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6A5A3A),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Your Feedback',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4A3A1A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _faqFeedbackCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Share your thoughts here...',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0CDBD)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFFE0CDBD),
                      width: 1.7,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.red,
                      width: 1.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final text = _faqFeedbackCtrl.text.trim();
                  if (text.isEmpty) {
                    _toast('Please enter feedback first', isError: true);
                    return;
                  }
                  _faqFeedbackCtrl.clear();
                  _toast('Thanks for your feedback');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB23B3B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Submit Feedback'),
              ),
            ],
          ),
        ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE7FF), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            alignment: Alignment.center,
            child: const Text(
              '?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          title: Text(
            question,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F1D3A),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                answer,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF1F2937),
                  height: 1.7,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BottomNavigationBar(
              currentIndex: _navIndex,
              onTap: (index) => setState(() => _navIndex = index),
              iconSize: 24,
              selectedFontSize: 13,
              unselectedFontSize: 12,
              elevation: 0,
              backgroundColor: Colors.transparent,
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
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/svs-logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SVS',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Smart Verification System',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Verified emergency reporting and SOS.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanicStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF8FBFF), Color(0xFFFFF8EF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x160F172A),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                  color: const Color(0xF7FFFFFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.8),
                  ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTitleSection(),
                const SizedBox(height: 16),
                _buildAlertStrip(),
                if (kDebugMode && _showReporterDebugPanels) ...[
                  const SizedBox(height: 12),
                  _buildAlertDebugPanel(),
                ],
                if (kDebugMode && _showReporterDebugPanels) ...[
                  const SizedBox(height: 12),
                  _buildSupabaseDebug(),
                ],
                const SizedBox(height: 18),
                _buildCard(
                  step: 'Step 01',
                  title: 'Reporter details',
                  subtitle:
                      'Who is making this report and how can dispatch call back?',
                  icon: Icons.badge_outlined,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 620;
                      return wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _textField(
                                    controller: _nameCtrl,
                                    label: 'Full name',
                                    hint: 'Juan dela Cruz',
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _textField(
                                    controller: _contactCtrl,
                                    label: 'Contact number',
                                    hint: '917 123 4567',
                                    keyboardType: TextInputType.phone,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'Required'
                                        : null,
                                    prefixText: '+63 ',
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _textField(
                                  controller: _nameCtrl,
                                  label: 'Full name',
                                  hint: 'Juan dela Cruz',
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                _textField(
                                  controller: _contactCtrl,
                                  label: 'Contact number',
                                  hint: '917 123 4567',
                                  keyboardType: TextInputType.phone,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
                                  prefixText: '+63 ',
                                ),
                              ],
                            );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  step: 'Step 02',
                  title: 'Emergency type',
                  subtitle: 'Choose the closest category for the incident.',
                  icon: Icons.emergency_outlined,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 680 ? 3 : 2;
                      const spacing = 12.0;
                      final width =
                          (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: _types.map((type) {
                          final meta = _emergencyTypeMeta(type);
                          return SizedBox(
                            width: width,
                            child: _SelectChip(
                              label: type,
                              subtitle: meta.$1,
                              icon: meta.$2,
                              selected: _selectedType == type,
                              onTap: () => setState(() => _selectedType = type),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  step: 'Step 03',
                  title: 'Severity level',
                  subtitle:
                      'Tell responders how urgent the situation is right now.',
                  icon: Icons.priority_high_rounded,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;
                      return wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _SeverityButton(
                                    label: 'Low',
                                    subtitle: 'Needs attention',
                                    icon: Icons.shield_outlined,
                                    color: AppColors.green,
                                    selected: _selectedSeverity == 'Low',
                                    onTap: () => setState(
                                      () => _selectedSeverity = 'Low',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SeverityButton(
                                    label: 'Medium',
                                    subtitle: 'Response needed',
                                    icon: Icons.report_problem_outlined,
                                    color: AppColors.amberDark,
                                    selected: _selectedSeverity == 'Medium',
                                    onTap: () => setState(
                                      () => _selectedSeverity = 'Medium',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SeverityButton(
                                    label: 'High',
                                    subtitle: 'Immediate danger',
                                    icon: Icons.warning_amber_rounded,
                                    color: AppColors.red,
                                    selected: _selectedSeverity == 'High',
                                    onTap: () => setState(
                                      () => _selectedSeverity = 'High',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SeverityButton(
                                  label: 'Low',
                                  subtitle: 'Needs attention',
                                  icon: Icons.shield_outlined,
                                  color: AppColors.green,
                                  selected: _selectedSeverity == 'Low',
                                  onTap: () =>
                                      setState(() => _selectedSeverity = 'Low'),
                                ),
                                const SizedBox(height: 12),
                                _SeverityButton(
                                  label: 'Medium',
                                  subtitle: 'Response needed',
                                  icon: Icons.report_problem_outlined,
                                  color: AppColors.amberDark,
                                  selected: _selectedSeverity == 'Medium',
                                  onTap: () => setState(
                                    () => _selectedSeverity = 'Medium',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _SeverityButton(
                                  label: 'High',
                                  subtitle: 'Immediate danger',
                                  icon: Icons.warning_amber_rounded,
                                  color: AppColors.red,
                                  selected: _selectedSeverity == 'High',
                                  onTap: () => setState(
                                    () => _selectedSeverity = 'High',
                                  ),
                                ),
                              ],
                            );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  step: 'Step 04',
                  title: 'Location',
                  subtitle:
                      'Share the exact place so responders can reach you faster.',
                  icon: Icons.location_on_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: _detectingGps ? null : _detectGps,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE9F2FF),
                          foregroundColor: AppColors.blue,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.borderMid),
                          ),
                        ),
                        icon: _detectingGps
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.gps_fixed_rounded),
                        label: Text(
                          _gps == null
                              ? 'Detect my location'
                              : 'Detected: $_gps (+/-${_gpsAccuracy ?? 0}m)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_showMap && _mapLat != null && _mapLng != null)
                        _buildLocationMap(_mapLat!, _mapLng!)
                      else
                        _buildMapPlaceholder(),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 620;
                          return wide
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: _textField(
                                        controller: _barangayCtrl,
                                        label: 'Barangay',
                                        hint: 'Barangay Rizal',
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _textField(
                                        controller: _landmarkCtrl,
                                        label: 'Nearest landmark',
                                        hint: 'Near Municipal Hall',
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _textField(
                                      controller: _barangayCtrl,
                                      label: 'Barangay',
                                      hint: 'Barangay Rizal',
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                    const SizedBox(height: 14),
                                    _textField(
                                      controller: _landmarkCtrl,
                                      label: 'Nearest landmark',
                                      hint: 'Near Municipal Hall',
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 14),
                      _textField(
                        controller: _streetCtrl,
                        label: 'Street / additional details',
                        hint: 'Street name, purok, or access notes',
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildCard(
                  step: 'Step 05',
                  title: 'Incident details',
                  subtitle:
                      'Describe what is happening and attach a photo if possible.',
                  icon: Icons.description_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _textField(
                        controller: _descCtrl,
                        label: 'Description',
                        hint:
                            'Describe what is happening, how many people are affected, and visible hazards.',
                        maxLines: 5,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _buildPhotoPicker(),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submitReport,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  label: Text(
                    _submitting
                        ? 'Submitting emergency report...'
                        : 'Submit emergency report',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationMap(double lat, double lng) {
    final target = LatLng(lat, lng);
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: target,
              initialZoom: _mapZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
              onMapEvent: (event) {
                final nextZoom = event.camera.zoom;
                if (mounted && (nextZoom - _mapZoom).abs() > 0.01) {
                  setState(() => _mapZoom = nextZoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _mapSatellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xF4FFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppColors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Detected location',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.text,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
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
          Positioned(
            left: 12,
            bottom: 12,
            child: Row(
              children: [
                _mapControlButton(
                  icon: _mapSatellite
                      ? Icons.map_outlined
                      : Icons.satellite_alt_outlined,
                  label: _mapSatellite ? 'Map' : 'Satellite',
                  onTap: () => setState(() => _mapSatellite = !_mapSatellite),
                ),
                const SizedBox(width: 8),
                _mapControlButton(
                  icon: Icons.remove,
                  label: 'Out',
                  onTap: () {
                    final nextZoom = (_mapZoom - 1).clamp(5.0, 18.0).toDouble();
                    _mapController.move(target, nextZoom);
                    setState(() => _mapZoom = nextZoom);
                  },
                ),
                const SizedBox(width: 8),
                _mapControlButton(
                  icon: Icons.add,
                  label: 'In',
                  onTap: () {
                    final nextZoom = (_mapZoom + 1).clamp(5.0, 18.0).toDouble();
                    _mapController.move(target, nextZoom);
                    setState(() => _mapZoom = nextZoom);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF4FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.text2),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF2FF), Color(0xFFFFF7E6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderMid),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: AppColors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Map preview will appear here',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Use GPS detection to pin the incident and automatically help fill the location fields.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.text2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.border.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                height: 1.05,
                letterSpacing: -1.2,
              ),
              children: const [
                TextSpan(text: 'Report an '),
                TextSpan(
                  text: 'Emergency',
                  style: TextStyle(color: AppColors.red),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your report will be received immediately by SVS dispatchers. Provide as much detail as possible for a faster response.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.text2, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildAlertStrip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFAF1),
        borderRadius: BorderRadius.circular(12),
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

  Widget _sosStepCard({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMid),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 12,
            offset: Offset(0, 6),
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

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderMid, width: 2),
        ),
        child: _photoFiles.isEmpty
            ? Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 28,
                      color: AppColors.muted2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to add a photo',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
    if (!kDebugMode || !_showReporterDebugPanels) {
      return const SizedBox.shrink();
    }
    final url = _supabaseUrlEnv.trim();
    final anon = _supabaseAnonKeyEnv.trim();
    final bucket = _supabaseBucketEnv.trim();
    final serverUrl = _effectiveBaseUrl();
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
            label: 'Server',
            ok: _baseUrlReady,
            value: serverUrl,
          ),
          const SizedBox(height: 6),
          _configStatusLine(
            label: 'Alerts',
            ok: !_alertDebugStatus.startsWith('error'),
            value: '$_alertDebugStatus via $_alertDebugSource',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unawaited(_checkForAdminAlerts()),
                  child: const Text('Check alerts now'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _triggerTestAlert,
                  child: const Text('Test notification'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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

  Widget _buildFooter() {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.borderMid.withValues(alpha: 0.8)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copyright $year SVS. All rights reserved.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard({
    required String step,
    required String title,
    required String subtitle,
    required Widget child,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xEFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.65),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(icon, color: AppColors.blue, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.red,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.text2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            filled: true,
            fillColor: const Color(0xFFFBFCFF),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines > 1 ? 16 : 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.border.withValues(alpha: 0.9),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.amberDark,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.red, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  (String, IconData) _emergencyTypeMeta(String type) {
    switch (type) {
      case 'Fire':
        return ('Smoke or active flames', Icons.local_fire_department_outlined);
      case 'Flood':
        return ('Rising water or overflow', Icons.water_damage_outlined);
      case 'Medical':
        return ('Injury or health emergency', Icons.medical_services_outlined);
      case 'Accident':
        return ('Vehicle or road incident', Icons.car_crash_outlined);
      case 'Landslide':
        return ('Road collapse or debris', Icons.landscape_outlined);
      default:
        return ('Unlisted incident type', Icons.more_horiz_rounded);
    }
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
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        constraints: const BoxConstraints(minHeight: 110),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFFAEE) : const Color(0xFFFBFCFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.amberBorder : AppColors.border,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF8E4) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.amberBorder : AppColors.border,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? AppColors.amberDeep : AppColors.muted,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? AppColors.amberDeep : AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.muted2,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeverityButton extends StatelessWidget {
  const _SeverityButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : const Color(0xFFFBFCFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.35)
                      : AppColors.border,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? color : AppColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? color : AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
