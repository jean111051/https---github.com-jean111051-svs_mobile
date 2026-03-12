import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  static const amber = Color(0xFFFACC15);
  static const amberDark = Color(0xFFEAB308);
  static const amberDeep = Color(0xFFCA8A04);
  static const amberLight = Color(0xFFFEFCE8);
  static const amberBorder = Color(0xFFFDE047);
  static const orange = Color(0xFFDC2626);
  static const orangeLight = Color(0xFFFEF2F2);
  static const orangeBorder = Color(0xFFFCA5A5);
  static const red = Color(0xFFDC2626);
  static const redLight = Color(0xFFFEF2F2);
  static const redBorder = Color(0xFFFCA5A5);
  static const green = Color(0xFF2563EB);
  static const greenLight = Color(0xFFDBEAFE);
  static const greenBorder = Color(0xFF93C5FD);
  static const blue = Color(0xFF1D4ED8);
  static const bg = Color(0xFFE8F1FF);
  static const surface = Color(0xFFF4F8FF);
  static const border = Color(0xFFBFD6F5);
  static const borderMid = Color(0xFF97BDE9);
  static const text = Color(0xFF0F172A);
  static const text2 = Color(0xFF1E3A8A);
  static const muted = Color(0xFF334155);
  static const muted2 = Color(0xFF64748B);
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
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

  String? _photoDataUrl;
  XFile? _photoFile;

  bool _submitting = false;
  bool _panicSending = false;
  bool _panicDialogOpen = false;

  String? _panicNumber;
  String _baseUrl = 'http://10.0.2.2:3000';

  static const String _baseUrlEnv = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );
  bool _baseUrlReady = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _initBaseUrl();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _barangayCtrl.dispose();
    _landmarkCtrl.dispose();
    _streetCtrl.dispose();
    _descCtrl.dispose();
    _panicCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final panicNum = prefs.getString('panic_number');
    setState(() {
      _panicNumber = panicNum;
      _panicCtrl.text = _formatPhMobile(_panicNumber);
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

  Future<bool> _ensureBaseUrlReady() async {
    if (_baseUrlReady) return true;
    await _initBaseUrl();
    return _baseUrlReady;
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
      await _autoFillLocation(pos.latitude, pos.longitude, overwrite: false);
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
        }
      } catch (_) {}
    }
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

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
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
    final lower = file.path.toLowerCase();
    final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() {
      _photoFile = file;
      _photoDataUrl = dataUrl;
    });
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
    if (!await _ensureBaseUrlReady()) {
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

    setState(() => _submitting = true);
    try {
      final url = Uri.parse('${_effectiveBaseUrl()}/api/report');
      final body = {
        'name': _nameCtrl.text.trim(),
        'contact': normalizedContact,
        'emergencyType': _selectedType,
        'severity': _selectedSeverity,
        'barangay': _barangayCtrl.text.trim(),
        'landmark': _landmarkCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'gps': gpsValue,
        'photo': _photoDataUrl,
      };
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
      _toast('Network timeout. Check server URL.', isError: true);
    } catch (e) {
      debugPrint('Submit report error: $e');
      _toast('Network error: ${_shortError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      await _autoFillLocation(pos.latitude, pos.longitude, overwrite: false);
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
    if (!await _ensureBaseUrlReady()) {
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
      builder: (ctx) => AlertDialog(
        title: const Text('One-time setup'),
        content: TextField(
          controller: _panicCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Panic phone number',
            hintText: '+63 917 123 4567',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _savePanicNumber, child: const Text('Save')),
        ],
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
      _photoDataUrl = null;
      _photoFile = null;
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
        return WillPopScope(
          onWillPop: () async => false,
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
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildPanicStrip()),
              SliverToBoxAdapter(child: _buildForm()),
              SliverToBoxAdapter(child: _buildFooter()),
            ],
          ),
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
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: const Icon(Icons.shield, color: AppColors.amberDeep),
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
          _StatusPill(
            label: 'Online',
            color: AppColors.green,
            background: AppColors.greenLight,
            border: AppColors.greenBorder,
          ),
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
            children: [
              Text(
                'Urgent Emergency',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.red,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
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
              Text(
                'Tap to send instant SOS. Your location will be sent to dispatchers immediately.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.text2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openPanicSetup,
                icon: const Icon(Icons.phone, size: 16),
                label: Text(
                  _panicNumber == null
                      ? 'Set panic number'
                      : 'Sending as ${_formatPhMobile(_panicNumber)} (tap to change)',
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
            const SizedBox(height: 16),
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
                          hint: '+63 917 123 4567',
                          keyboardType: TextInputType.phone,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
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
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _types
                    .map(
                      (type) => _SelectChip(
                        label: type,
                        selected: _selectedType == type,
                        onTap: () => setState(() => _selectedType = type),
                      ),
                    )
                    .toList(),
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
          GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 17),
            markers: {
              Marker(markerId: const MarkerId('detected'), position: target),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: (_) {},
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

  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderMid, width: 2),
        ),
        child: _photoFile == null
            ? Column(
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 32,
                    color: AppColors.muted2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to upload a photo',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'JPG or PNG up to 10 MB',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.muted2),
                  ),
                ],
              )
            : Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode((_photoDataUrl ?? '').split(',').last),
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Photo attached',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.green),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.amberLight : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.amberBorder : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected ? AppColors.amberDeep : AppColors.muted,
            fontWeight: FontWeight.w700,
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
