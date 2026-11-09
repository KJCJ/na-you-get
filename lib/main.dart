import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
// show LatLng only: latlong2 also exports a Path class that clashes with
// Flutter's dart:ui Path used by the chart painters.
import 'package:latlong2/latlong.dart' show LatLng;
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'core/theme.dart';
import 'core/widgets/management_hub.dart';

const String baseUrl = 'https://random.taila91e03.ts.net';

// Vocabulary note: the UI calls these users "Job Workers". The database and
// API keep the historical name `is_runner` / `driver_id` / `/deliveries`.
// One person, two names: Worker in the UI, runner in the backend.

DateTime? _lastApiErrorAt;

/// Shows a red snackbar when a network call fails. Throttled so a screen that
/// fires several requests at once does not stack identical messages.
void showNetworkError(BuildContext context, String action) {
  final now = DateTime.now();
  if (_lastApiErrorAt != null &&
      now.difference(_lastApiErrorAt!).inSeconds < 20) {
    return;
  }
  _lastApiErrorAt = now;
  debugPrint('Network error while fetching ' + action);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(
          'Could not reach the server. Check your connection.'),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 3),
    ),
  );
}
const String apiKey = '3269e65be9a1970f8dc3874d4da06407e19e12d63427e75213bff1785acabfd295';
const String appVersion = '1.0.0';
const String apkDownloadUrl = 'https://github.com/KJCJ/na-you-get/releases/latest/download/NaYouGet.apk';

// ==========================================
// IMAGE UPLOAD HELPER
// ==========================================
Future<String?> pickAndUploadImage(BuildContext context) async {
  final picker = ImagePicker();
  try {
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
    request.headers['x-api-key'] = apiKey;
    final bytes = await picked.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'upload.jpg'));

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(body);
      return data['url']?.toString();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed. Try again.')),
        );
      }
      return null;
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot pick image: $e')),
      );
    }
    return null;
  }
}

/// The signed-in user's PLATFORM KYC status: approved | submitted |
/// rejected | none. An employer-held ID does not count.
Future<String> platformKycStatus() async {
  try {
    final user = await UserSession.load();
    final res = await http.get(
      Uri.parse('$baseUrl/kyc/mine'),
      headers: {
        'x-api-key': apiKey,
        'Authorization': 'Bearer ${user?['token'] ?? ''}',
      },
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final list = jsonDecode(res.body) as List;
      for (final r in list) {
        final m = Map<String, dynamic>.from(r as Map);
        if (m['company_id'] == null) {
          return (m['status'] ?? 'none').toString();
        }
      }
      return 'none';
    }
  } catch (_) {}
  return 'none';
}

/// Only an APPROVED platform ID unlocks applications.
Future<bool> hasPlatformKyc() async {
  return (await platformKycStatus()) == 'approved';
}

/// The "Identity Verification (Required)" panel used by every application form.
/// Loads the KYC state itself, so dialogs open instantly and the panel fills
/// in a moment later instead of the whole dialog waiting on the network.
class KycGate extends StatefulWidget {
  final void Function(bool)? onChanged;
  const KycGate({super.key, this.onChanged});

  @override
  State<KycGate> createState() => _KycGateState();
}

class _KycGateState extends State<KycGate> {
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final s = await platformKycStatus();
    if (!mounted) return;
    setState(() => _status = s);
    widget.onChanged?.call(s == 'approved');
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const KycUploadScreen()));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
    });
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null || _busy) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Checking identity verification...',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return kycRequirementBlock(context, _status!, _upload);
  }
}

Widget kycRequirementBlock(
    BuildContext context, String status, Future<void> Function() onUpload) {
  final approved = status == 'approved';
  final underReview = status == 'submitted';
  final ok = approved;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: approved
          ? kNyqGreen.withValues(alpha: 0.08)
          : (underReview ? Colors.grey.shade100 : Colors.orange.shade50),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: approved
              ? kNyqGreen
              : (underReview
                  ? Colors.grey.shade400
                  : Colors.orange.shade300)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
                approved
                    ? Icons.verified
                    : (underReview
                        ? Icons.hourglass_top
                        : Icons.badge_outlined),
                size: 16,
                color: approved
                    ? kNyqGreen
                    : (underReview
                        ? Colors.grey.shade700
                        : Colors.orange.shade900)),
            const SizedBox(width: 6),
            const Text('Identity Verification (Required)',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          approved
              ? 'ID verified'
              : (underReview
                  ? 'Under review - NYG is checking your ID.'
                  : 'Upload your ID before we can review your application.'),
          style: TextStyle(
              fontSize: 11,
              color: approved
                  ? kNyqGreen
                  : (underReview
                      ? Colors.grey.shade700
                      : Colors.orange.shade900)),
        ),
        if (!ok) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kNyqAccent,
                side: BorderSide(color: kNyqAccent.withValues(alpha: 0.5)),
              ),
              icon: const Icon(Icons.badge_outlined, size: 16),
              label: const Text('Upload ID Now'),
              onPressed: underReview ? null : () => onUpload(),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Uploads an ID/selfie photo to the private KYC store.
/// Gallery on web, camera on Android. Returns the opaque image id.
Future<String?> uploadKycImage(BuildContext context) async {
  final picker = ImagePicker();
  try {
    final source = kIsWeb ? ImageSource.gallery : ImageSource.camera;
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final user = await UserSession.load();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/kyc/upload'));
    request.headers['x-api-key'] = apiKey;
    request.headers['Authorization'] = 'Bearer ${user?['token'] ?? ''}';
    final bytes = await picked.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: 'id.jpg'));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(body)['image_id']?.toString();
    }
    if (context.mounted) {
      String msg = 'Upload failed. Try again.';
      try {
        msg = (jsonDecode(body)['detail'] ?? msg).toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
    }
    return null;
  } catch (e) {
    if (context.mounted) {
      showNetworkError(context, 'your ID photo');
    }
    return null;
  }
}

const List<String> kChatEmojis = [
  '😀', '😂', '🙂', '😍', '😎', '🤔', '😢', '😡',
  '👍', '👎', '🙏', '👏', '💪', '👋', '🤝', '✌️',
  '❤️', '🔥', '✨', '🎉', '💯', '⚡', '🌹', '🥰',
  '😅', '😇', '🤗', '😴', '🙌', '👌', '🤙', '🫶',
  '🛒', '💰', '💵', '📦', '🚚', '🏪', '📱', '⏰',
  '✅', '❌', '❓', '❗', '🙋', '🤷', '😬', '🫡',
];

String normalisePhone(String raw) {
  return raw.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
}

List<String> productPhotos(Map<String, dynamic> product) {
  // Returns list of image URLs, falls back to [image_url] if image_urls absent
  final urlsRaw = product['image_urls'];

  // Case 1 - backend returns a real List
  if (urlsRaw is List && urlsRaw.isNotEmpty) {
    final list = urlsRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    if (list.isNotEmpty) return list;
  }

  // Case 2 - backend returns a JSON string
  if (urlsRaw is String && urlsRaw.isNotEmpty) {
    try {
      final parsed = jsonDecode(urlsRaw);
      if (parsed is List) {
        final list = parsed.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
  }
  final single = product['image_url'];
  if (single is String && single.isNotEmpty) return [single];
  return [];
}

Future<void> showMultiPhotoPicker(
  BuildContext context,
  List<String> currentPhotos,
  void Function(List<String>) onChanged,
) async {
  final updated = List<String>.from(currentPhotos);

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Photos (up to 4)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(4, (index) {
                    final hasImage = index < updated.length;
                    return Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: hasImage
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      updated[index],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setDialogState(() => updated.removeAt(index));
                                    },
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : IconButton(
                              icon: const Icon(Icons.add_a_photo, color: Colors.grey),
                              onPressed: () async {
                                final url = await pickAndUploadImage(context);
                                if (url != null) {
                                  setDialogState(() => updated.add(url));
                                }
                              },
                            ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                const Text(
                  'First photo is the main image.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onChanged(updated);
                Navigator.pop(ctx);
              },
              child: const Text('Save Photos'),
            ),
          ],
        );
      },
    ),
  );
}

void handleSessionExpired(BuildContext context) async {
  await UserSession.clear();
  await ShopSession.clear();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthScreen()),
    (route) => false,
  );
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Your session expired. Please sign in again.')),
  );
}

// Shows the right message for a failed authenticated call. Renders the
// backend's own detail when it sends one, so guards such as "you have active
// orders" actually reach the user instead of a generic failure.
bool showApiError(
  BuildContext context,
  int statusCode,
  String body, {
  String fallback = 'Could not complete action.',
}) {
  if (statusCode == 401) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Session expired. Please sign out and back in.')),
    );
    return true;
  }
  if (statusCode >= 500) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server error. Please try again.')),
    );
    return true;
  }
  String message = fallback;
  try {
    final data = jsonDecode(body);
    final detail = data['detail'];
    if (detail != null) message = detail.toString();
  } catch (_) {}
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  return true;
}

// ==========================================
// MAIN APP
// ==========================================
void main() {
  runApp(const NaYouGetApp());
}

class NaYouGetApp extends StatelessWidget {
  const NaYouGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Na You Get (NYG)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kNyqSand,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNyqAccent,
          primary: kNyqAccent,
          secondary: kNyqOchre,
          tertiary: kNyqBlueDeep,
          surface: kNyqSand,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
              fontWeight: FontWeight.w800,
              color: kNyqInk,
              letterSpacing: -0.5),
          titleLarge: TextStyle(
              fontWeight: FontWeight.w700,
              color: kNyqInk,
              letterSpacing: -0.2),
          titleMedium:
              TextStyle(fontWeight: FontWeight.w600, color: kNyqInk),
          bodyMedium: TextStyle(
              height: 1.5, fontWeight: FontWeight.w400, color: kNyqInk),
          bodySmall: TextStyle(height: 1.4, color: Color(0xFF6B615A)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kNyqSand,
          surfaceTintColor: kNyqSand,
          foregroundColor: kNyqInk,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: Color(0x0F5A3A28),
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: kNyqInk,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: kNyqInk),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kNyqSand,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          height: 68,
          indicatorColor: kNyqGreen.withAlpha(38),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return IconThemeData(
                size: 24,
                color: on ? kNyqGreen : const Color(0xFF9A9088));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? kNyqGreen : const Color(0xFF9A9088),
            );
          }),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return on ? kNyqGreen : Colors.grey.shade400;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            final on = states.contains(WidgetState.selected);
            return on ? kNyqGreen.withAlpha(90) : Colors.grey.shade300;
          }),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE8E0D5),
          thickness: 1,
          space: 1,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ==========================================
// USER SESSION
// ==========================================
class UserSession {
  static const _idKey = 'user_id';
  static const _nameKey = 'user_name';
  static const _phoneKey = 'user_phone';
  static const _roleKey = 'user_role';
  static const _tokenKey = 'user_token';
  static const _photoKey = 'user_photo';
  static const _isSellerKey = 'user_is_seller';
  static const _isRunnerKey = 'user_is_runner';

  static Future<void> save(Map<String, dynamic> user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, user['id']);
    await prefs.setString(_nameKey, user['name']);
    await prefs.setString(_phoneKey, user['phone_number']);
    await prefs.setString(_roleKey, user['role'] ?? 'customer');
    if (user['is_seller'] != null) {
      await prefs.setBool(_isSellerKey, user['is_seller'] == 1 || user['is_seller'] == true);
    }
    if (user['is_runner'] != null) {
      await prefs.setBool(_isRunnerKey, user['is_runner'] == 1 || user['is_runner'] == true);
    }
    if (user['is_admin'] != null) {
      await prefs.setBool('user_is_admin', user['is_admin'] == 1 || user['is_admin'] == true);
    }
    if (user['is_company_manager'] != null) {
      await prefs.setBool('user_is_company_manager',
          user['is_company_manager'] == 1 || user['is_company_manager'] == true);
    }
    if (user['vehicle_type'] != null) {
      await prefs.setString('user_vehicle_type', user['vehicle_type']);
    }
    if (user['is_online'] != null) {
      await prefs.setBool('user_is_online', user['is_online'] == 1 || user['is_online'] == true);
    }
    if (user['photo_url'] != null) {
      await prefs.setString(_photoKey, user['photo_url']);
    }
    if (user['must_change_password'] != null) {
      await prefs.setBool('user_must_change_password',
          user['must_change_password'] == 1 ||
              user['must_change_password'] == true);
    }
    await prefs.setString(_tokenKey, token);
  }

  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_idKey);
    final token = prefs.getString(_tokenKey);
    if (id == null || token == null) return null;
    return {
      'id': id,
      'name': prefs.getString(_nameKey) ?? '',
      'phone_number': prefs.getString(_phoneKey) ?? '',
      'role': prefs.getString(_roleKey) ?? 'customer',
      'is_seller': prefs.getBool(_isSellerKey) ?? false,
      'is_runner': prefs.getBool(_isRunnerKey) ?? false,
      'is_admin': prefs.getBool('user_is_admin') ?? false,
      'is_company_manager':
          prefs.getBool('user_is_company_manager') ?? false,
      'vehicle_type': prefs.getString('user_vehicle_type'),
      'is_online': prefs.getBool('user_is_online') ?? false,
      'photo_url': prefs.getString(_photoKey),
      'must_change_password':
          prefs.getBool('user_must_change_password') ?? false,
      'token': token,
    };
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_photoKey);
    await prefs.remove(_isSellerKey);
    await prefs.remove(_isRunnerKey);
    await prefs.remove('user_is_admin');
    await prefs.remove('user_is_company_manager');
    await prefs.remove('user_vehicle_type');
    await prefs.remove('user_is_online');
  }

  static Future<String?> becomeSeller() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/become-seller'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) {
        await clear();
        return 'SESSION_EXPIRED';
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await prefs.setBool(_isSellerKey, true);
        return null;
      }
      return 'Could not enable selling';
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> becomeRunner() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/become-runner'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) {
        await clear();
        return 'SESSION_EXPIRED';
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await prefs.setBool(_isRunnerKey, true);
        return null;
      }
      return 'Could not enable running';
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> revokeSeller() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/revoke-seller'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) {
        await clear();
        return 'SESSION_EXPIRED';
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await prefs.setBool(_isSellerKey, false);
        return null;
      }
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not disable selling';
      } catch (_) {
        return 'Could not disable selling';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> revokeRunner() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/revoke-runner'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) {
        await clear();
        return 'SESSION_EXPIRED';
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await prefs.setBool(_isRunnerKey, false);
        return null;
      }
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not disable running';
      } catch (_) {
        return 'Could not disable running';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<bool> update(Map<String, dynamic> updates) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return false;

    try {
      final res = await http.put(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final user = data['user'];
        await prefs.setString('user_name', user['name']);
        await prefs.setString('user_phone', user['phone_number']);
        if (user['is_seller'] != null) {
          await prefs.setBool(_isSellerKey, user['is_seller'] == 1 || user['is_seller'] == true);
        }
        if (user['is_runner'] != null) {
          await prefs.setBool(_isRunnerKey, user['is_runner'] == 1 || user['is_runner'] == true);
        }
        if (user['is_admin'] != null) {
          await prefs.setBool('user_is_admin', user['is_admin'] == 1 || user['is_admin'] == true);
        }
        if (user['vehicle_type'] != null) {
          await prefs.setString('user_vehicle_type', user['vehicle_type']);
        }
        if (user['is_online'] != null) {
          await prefs.setBool('user_is_online',
              user['is_online'] == 1 || user['is_online'] == true);
        }
        if (user['photo_url'] != null) {
          await prefs.setString('user_photo', user['photo_url']);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('user_is_admin') ?? false;
  }

  static Future<List<dynamic>> getMyInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/invoices/mine'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body) as List;
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> getAllInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/invoices'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body) as List;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getInvoiceDetail(int invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/invoices/$invoiceId'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<String?> generateInvoice(String sellerPhone) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/invoices/generate'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'seller_phone': sellerPhone}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not generate invoice';
      } catch (_) {
        return 'Could not generate invoice';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> markInvoiceSellerPaid(int invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/invoices/$invoiceId/seller-paid'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not confirm';
      } catch (_) {
        return 'Could not confirm';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> markInvoiceNygReceived(int invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/invoices/$invoiceId/nyg-received'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not confirm';
      } catch (_) {
        return 'Could not confirm';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<Map<String, dynamic>?> getAdminEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/earnings'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> changePassword(String currentPassword, String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'You are not signed in';

    try {
      final res = await http.put(
        Uri.parse('$baseUrl/auth/me/password'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null; // null = success
      }
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not change password';
      } catch (_) {
        return 'Could not change password';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';

    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 401) {
        await clear();
        return 'SESSION_EXPIRED';
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await clear();
        return null;
      }
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not delete account';
      } catch (_) {
        return 'Could not delete account';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> updateProduct(int productId, Map<String, dynamic> updates) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/products/$productId'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not update product';
      } catch (_) {
        return 'Could not update product';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<Map<String, dynamic>?> getOrderStatus(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/orders/$orderId/status'),
        headers: {
          'x-api-key': apiKey,
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getFullOrderStatus(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/orders/$orderId/full-status'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // Three steps in the 10-step UI have no /flow/ route on the backend and
  // are served only by /confirm/*. Both write the same order columns that
  // /full-status reads, so those three are routed through /confirm/.
  static const Map<String, String> _flowFallbackToConfirm = {
    'seller-handed': 'seller-handed',
    'runner-picked-up': 'runner-picked-up',
    'runner-delivered': 'runner-delivered',
  };

  static Future<String?> confirmFlowStep(int orderId, String step) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    final fallback = _flowFallbackToConfirm[step];
    final path = fallback != null
        ? '$baseUrl/orders/$orderId/confirm/$fallback'
        : '$baseUrl/orders/$orderId/flow/$step';
    try {
      final res = await http.put(
        Uri.parse(path),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not confirm';
      } catch (_) {
        return 'Could not confirm';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }

  static Future<String?> confirmOrderStep(int orderId, String step) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return 'Not signed in';
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/orders/$orderId/confirm/$step'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return 'SESSION_EXPIRED';
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      try {
        final data = jsonDecode(res.body);
        return data['detail']?.toString() ?? 'Could not confirm';
      } catch (_) {
        return 'Could not confirm';
      }
    } catch (_) {
      return 'Cannot reach server';
    }
  }
}

// ==========================================
// SHOP SESSION
// ==========================================
class ShopSession {
  static const _idKey = 'merchant_id';
  static const _nameKey = 'shop_name';
  static const _ownerKey = 'owner_name';
  static const _phoneKey = 'phone_number';
  static const _cityKey = 'city';
  static const _categoryKey = 'category';
  static const _logoKey = 'logo_url';
  static const _themeKey = 'theme_colour';
  static const _bgKey = 'background_colour';

  static Future<void> save(Map<String, dynamic> merchant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, merchant['id']);
    await prefs.setString(_nameKey, merchant['shop_name']);
    await prefs.setString(_ownerKey, merchant['owner_name']);
    await prefs.setString(_phoneKey, merchant['phone_number']);
    await prefs.setString(_cityKey, merchant['city'] ?? 'Freetown');
    await prefs.setString(_categoryKey, merchant['category'] ?? 'Other');
    if (merchant['logo_url'] != null) {
      await prefs.setString(_logoKey, merchant['logo_url']);
    }
    if (merchant['theme_colour'] != null) {
      await prefs.setString(_themeKey, merchant['theme_colour']);
    }
    if (merchant['background_colour'] != null) {
      await prefs.setString(_bgKey, merchant['background_colour']);
    }
  }

  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_idKey);
    if (id == null) return null;
    return {
      'id': id,
      'shop_name': prefs.getString(_nameKey) ?? 'My Shop',
      'owner_name': prefs.getString(_ownerKey) ?? '',
      'phone_number': prefs.getString(_phoneKey) ?? '',
      'city': prefs.getString(_cityKey) ?? 'Freetown',
      'category': prefs.getString(_categoryKey) ?? 'Other',
      'logo_url': prefs.getString(_logoKey),
      'theme_colour': prefs.getString(_themeKey),
      'background_colour': prefs.getString(_bgKey),
    };
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_ownerKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_cityKey);
    await prefs.remove(_categoryKey);
    await prefs.remove(_logoKey);
  }
}

// ==========================================
// MESSAGE SESSION
// ==========================================
class MessageSession {
  /// Set when the last call was rejected with 401, so callers can tell an
  /// expired session apart from a genuinely empty inbox.
  static bool lastCallWasUnauthorized = false;

  static Future<List<dynamic>> getInbox() async {
    lastCallWasUnauthorized = false;
    final user = await UserSession.load();
    if (user == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/messages/inbox'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 401) {
        lastCallWasUnauthorized = true;
        return [];
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      return jsonDecode(res.body) as List;
    } catch (_) {
      return [];
    }
  }

  static Future<List<dynamic>> getConversation(int otherUserId) async {
    lastCallWasUnauthorized = false;
    final user = await UserSession.load();
    if (user == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/messages/conversation/$otherUserId'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 401) {
        lastCallWasUnauthorized = true;
        return [];
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final data = jsonDecode(res.body);
      return data['messages'] as List;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> send(int recipientId, String text,
      {int? shopId, int? orderId, int? replyToMessageId}) async {
    lastCallWasUnauthorized = false;
    final user = await UserSession.load();
    if (user == null) return false;
    try {
      // Map<String, dynamic> so the optional int values below can be added.
      final Map<String, dynamic> body = {'recipient_id': recipientId, 'text': text};
      if (shopId != null) body['shop_id'] = shopId;
      if (orderId != null) body['order_id'] = orderId;
      if (replyToMessageId != null) {
        body['reply_to_message_id'] = replyToMessageId;
      }
      final res = await http.post(
        Uri.parse('$baseUrl/messages/'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 401) {
        lastCallWasUnauthorized = true;
        return false;
      }
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markRead(int otherUserId) async {
    lastCallWasUnauthorized = false;
    final user = await UserSession.load();
    if (user == null) return;
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/messages/conversation/$otherUserId/read'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 401) {
        lastCallWasUnauthorized = true;
      }
    } catch (_) {}
  }
}

// ==========================================
// AUTH SCREEN
// ==========================================
class AuthScreen extends StatefulWidget {
  final String? suggestedRole;
  const AuthScreen({super.key, this.suggestedRole});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _phoneController = TextEditingController(text: '+232');
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _showRecoveryDialog() async {
    bool byPhone = true;
    final inputCtl = TextEditingController();
    bool busy = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            final value = inputCtl.text.trim();
            if (value.isEmpty) {
              setDialogState(() => error = byPhone
                  ? 'Enter your phone number.'
                  : 'Enter your full name.');
              return;
            }
            setDialogState(() {
              busy = true;
              error = null;
            });
            try {
              final res = await http
                  .post(
                    Uri.parse('$baseUrl/support/recovery'),
                    headers: {
                      'Content-Type': 'application/json',
                      'x-api-key': apiKey,
                    },
                    body: jsonEncode({
                      'request_type': byPhone ? 'password' : 'phone',
                      'detail': value,
                    }),
                  )
                  .timeout(const Duration(seconds: 12));
              if (res.statusCode >= 200 && res.statusCode < 300) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Your request has been sent to the Admin. We will contact you shortly.'),
                      backgroundColor: kNyqGreen,
                    ),
                  );
                }
                return;
              }
              final data = jsonDecode(res.body);
              setDialogState(() {
                busy = false;
                error =
                    (data['detail'] ?? 'Could not send request.').toString();
              });
            } catch (_) {
              setDialogState(() {
                busy = false;
                error = 'Network error. Please try again.';
              });
            }
          }

          return AlertDialog(
            title: const Text('Account Recovery'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    byPhone
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: kNyqAccent,
                  ),
                  title: const Text('I know my phone number'),
                  onTap: () => setDialogState(() {
                    byPhone = true;
                    inputCtl.clear();
                    error = null;
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    !byPhone
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: kNyqAccent,
                  ),
                  title: const Text('I forgot my phone number'),
                  onTap: () => setDialogState(() {
                    byPhone = false;
                    inputCtl.clear();
                    error = null;
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: inputCtl,
                  keyboardType:
                      byPhone ? TextInputType.phone : TextInputType.name,
                  decoration: InputDecoration(
                    labelText: byPhone ? 'Phone Number' : 'Full Name',
                    hintText:
                        byPhone ? '+232 78 839002' : 'e.g. Mohamed Kamara',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send Request'),
              ),
            ],
          );
        },
      ),
    );
    inputCtl.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.suggestedRole != null) {
      _isLogin = false;
    }
  }

  Future<void> _submit() async {
    final normalisedPhone = normalisePhone(_phoneController.text);
    if (normalisedPhone.length < 8) {
      setState(() => _error = 'Please enter a valid phone number');
      return;
    }
    if (!_isLogin && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final url = _isLogin ? '$baseUrl/auth/login' : '$baseUrl/auth/signup';
    final body = _isLogin
        ? {
            'phone_number': normalisedPhone,
            'password': _passwordController.text,
          }
        : {
            'phone_number': normalisedPhone,
            'name': _nameController.text.trim(),
            'password': _passwordController.text,
            'role': 'customer',
          };

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        await UserSession.save(data['user'], data['token']);
        if (mounted) TextInput.finishAutofillContext();
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _error = data['detail']?.toString() ?? 'Something went wrong';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Cannot reach server. Check your connection.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Sign In' : 'Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
            children: [
              Image.asset('assets/logo.png', height: 80),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone Number (+232...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Your Full Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: [
                  _isLogin
                      ? AutofillHints.password
                      : AutofillHints.newPassword,
                ],
                decoration: const InputDecoration(
                  labelText: 'Password (min 6 characters)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isLogin ? 'Sign In' : 'Create Account',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _error = null;
                  });
                },
                child: Text(_isLogin
                    ? 'New here? Create an account'
                    : 'Already have an account? Sign in'),
              ),
              TextButton.icon(
                onPressed: _showRecoveryDialog,
                icon: const Icon(Icons.help_outline, size: 16),
                label: const Text('Forgot password or phone number?'),
              ),
            ],
          )
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ACCOUNT SHEET + ACCOUNT BUTTON (shared by all tabs)
// ==========================================
bool isSeller(Map<String, dynamic>? u) {
  if (u == null) return false;
  final v = u['is_seller'];
  return v == true || v == 1 || v?.toString() == '1';
}

bool isRunner(Map<String, dynamic>? u) {
  if (u == null) return false;
  final v = u['is_runner'];
  return v == true || v == 1 || v?.toString() == '1';
}

Color parseThemeColour(String? hex, {Color fallback = const Color(0xFFE8F5E9)}) {
  if (hex == null) return fallback;
  var h = hex.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return fallback;
  return Color(v);
}

const Map<String, String> kShopPalette = {
  '#000000': 'Black',
  '#FFFFFF': 'White',
  '#1B5E20': 'NYG Green',
  '#03A9F4': 'Blue',
  '#F44336': 'Red',
  '#FF9800': 'Orange',
  '#9C27B0': 'Purple',
  '#F5F5F5': 'Light Grey',
};

const int kAdminUserId = 4;

Future<void> sendApplication(String subject, List<String> lines) async {
  final buffer = StringBuffer('[' + subject + ']')..writeln();
  buffer.writeln('--------------------');
  for (final l in lines) {
    buffer.writeln('- ' + l);
  }
  buffer.writeln('--------------------');
  buffer.write('Sent from the NYG app');
  await MessageSession.send(kAdminUserId, buffer.toString());
}

Future<void> showSellerApplicationDialog(
    BuildContext context, Map<String, dynamic> user,
    {VoidCallback? onDone}) async {
  final business = TextEditingController();
  final city = TextEditingController(text: 'Freetown');

  final phone = TextEditingController(
      text: (user['phone_number'] ?? '').toString());
  bool? kycOk;
  var category = 'Fashion';
  const categories = [
    'Fashion',
    'Food',
    'Electronics',
    'Home',
    'Beauty',
    'Services',
    'Other',
  ];
  var busy = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: Colors.white,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: const Text('Apply to be a Seller'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: business,
                decoration: const InputDecoration(
                    labelText: 'Shop Name',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                    labelText: 'Shop Category',
                    border: OutlineInputBorder()),
                items: categories
                    .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => category = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: city,
                decoration: const InputDecoration(
                    labelText: 'Shop Address / City (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              KycGate(
                  onChanged: (v) => setDialogState(() => kycOk = v)),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: (busy || kycOk != true)
                ? null
                : () async {
                    if (business.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please fill in the shop name and what you sell')),
                      );
                      return;
                    }
                    setDialogState(() => busy = true);
                    await sendApplication('SELLER APPLICATION', [
                      'Business: ' + business.text.trim(),
                      'Category: ' + category,
                      'City/Address: ' + city.text.trim(),
                      'Phone: ' + phone.text.trim(),
                      'Account ID: ${user['id']}',
                    ]);
                    await UserSession.update({'pending_role': 'seller'});
                    onDone?.call();
                    if (!dialogCtx.mounted) return;
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Application sent. We will review it shortly.'),
                        backgroundColor: kNyqGreen,
                      ),
                    );
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showWorkerApplicationDialog(
    BuildContext context, Map<String, dynamic> user,
    {VoidCallback? onDone}) async {
  final name = TextEditingController(
      text: (user['name'] ?? '').toString());
  final area = TextEditingController(text: 'Freetown');
  final phone = TextEditingController(
      text: (user['phone_number'] ?? '').toString());
  var vehicle = 'Motorbike';
  const vehicles = ['Motorbike', 'Car', 'Bicycle', 'None / Walking'];
  var busy = false;
  bool? kycOk;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: Colors.white,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: const Text('Apply to be a Job Worker'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: vehicle,
                decoration: const InputDecoration(
                    labelText: 'Vehicle Type',
                    border: OutlineInputBorder()),
                items: vehicles
                    .map((v) =>
                        DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => vehicle = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: area,
                decoration: const InputDecoration(
                    labelText: 'City / Area you operate in',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              KycGate(
                  onChanged: (v) => setDialogState(() => kycOk = v)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: (busy || kycOk != true)
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter your full name')),
                      );
                      return;
                    }
                    setDialogState(() => busy = true);
                    await sendApplication('JOB WORKER APPLICATION', [
                      'Name: ' + name.text.trim(),
                      'Vehicle: ' + vehicle,
                      'Area: ' + area.text.trim(),
                      'Phone: ' + phone.text.trim(),
                      'Account ID: ${user['id']}',
                    ]);
                    await UserSession.update({'pending_role': 'runner'});
                    onDone?.call();
                    if (!dialogCtx.mounted) return;
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Application sent. We will review it shortly.'),
                        backgroundColor: kNyqGreen,
                      ),
                    );
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit'),
          ),
        ],
      ),
    ),
  );
}

Future<void> requestRoleRemoval(
    BuildContext context, String roleLabel, String message) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Stop being a ' + roleLabel + '?'),
      content: const Text(
        'NYG Support will review your request. You keep full access until they approve it.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Send Request'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await sendApplication('ROLE REMOVAL REQUEST', [message]);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Request sent to NYG Support'),
      backgroundColor: kNyqGreen,
    ),
  );
}

Future<void> showOrderDetails(
    BuildContext context, Map<String, dynamic> order) async {
  final total = ((order['price_sle'] ?? 0) as num) +
      ((order['delivery_fee_sle'] ?? 0) as num);
  Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 92,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Order #${order['id']}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Item', (order['product_title'] ?? '').toString()),
            row('Shop', (order['shop_name'] ?? '').toString()),
            row('Total', 'SLE ${total.toStringAsFixed(0)}'),
            row('Delivery', (order['delivery_status'] ?? '').toString()),
            row('Payment', (order['payment_status'] ?? '').toString()),
            row('Address', (order['delivery_address'] ?? '').toString()),
            row('Placed', formatChatTime(order['created_at'])),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

String formatChatTime(dynamic raw) {
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return '';
  final local = dt.toLocal();
  final now = DateTime.now();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return sameDay ? '$hh:$mm' : '${local.day}/${local.month} $hh:$mm';
}

String _profileRoleLabel(Map<String, dynamic>? user) {
  if (user == null) return 'Guest';
  final admin = user['is_admin'] == 1 || user['is_admin'] == true;
  if (admin) return 'Admin';
  if (isRunner(user)) return 'Job Worker';
  if (isSeller(user)) return 'Seller';
  return 'Customer';
}

// ==========================================
// ROLE-BASED ONBOARDING
// ==========================================
const List<String> kRoleOrder = ['admin', 'seller', 'worker', 'customer'];

bool kFlagTrue(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

List<String> userRoles(Map<String, dynamic>? u) {
  if (u == null) return const ['customer'];
  final roles = <String>[];
  if (kFlagTrue(u['is_admin'])) roles.add('admin');
  if (kFlagTrue(u['is_seller'])) roles.add('seller');
  if (kFlagTrue(u['is_runner'])) roles.add('worker');
  if (roles.isEmpty) roles.add('customer');
  return roles;
}

class OnboardingStep {
  final IconData icon;
  final String title;
  final String body;
  const OnboardingStep(this.icon, this.title, this.body);
}

const Map<String, List<OnboardingStep>> kOnboardingSteps = {
  'admin': [
    OnboardingStep(Icons.people_outline, 'Manage Users',
        'Grant or remove seller, worker and company roles, and suspend accounts that break the rules.'),
    OnboardingStep(Icons.badge_outlined, 'Review KYC & Companies',
        'Check uploaded IDs and approve company applications. Nobody gets verified until you do.'),
    OnboardingStep(Icons.receipt_long, 'Monitor Invoices',
        'Track commission, mark payments received, and see what NYG has earned.'),
  ],
  'seller': [
    OnboardingStep(Icons.add_business_outlined, 'Add Products',
        'Open My Shops, add products with prices, and set your shop location so buyers can find you on the map.'),
    OnboardingStep(Icons.handshake_outlined, 'Accept Orders & Negotiate',
        'Buyers can haggle in chat. Accept or decline their price, then fulfil the order.'),
    OnboardingStep(Icons.groups_outlined, 'Manage Employees & Shipments',
        'Add staff with salaries and clock-in, chat as a team, and track goods arriving from abroad.'),
  ],
  'worker': [
    OnboardingStep(Icons.toggle_on_outlined, 'Go Online',
        'Turn on your availability from Profile. You only receive jobs while you are online.'),
    OnboardingStep(Icons.delivery_dining_outlined, 'Accept Jobs',
        'Available deliveries appear on your board. Accept one, collect the item and mark it delivered.'),
    OnboardingStep(Icons.payments_outlined, 'Negotiate Delivery Fees',
        'Chat with the buyer about the fee before you accept. You are paid in cash on delivery.'),
  ],
  'customer': [
    OnboardingStep(Icons.storefront_outlined, 'Browse & Chat',
        'Shop the marketplace by list or map, and message any seller directly.'),
    OnboardingStep(Icons.handshake_outlined, 'Haggle Prices',
        'Use Negotiate to send a price offer. If the seller accepts, checkout locks to that price.'),
    OnboardingStep(Icons.shopping_cart_checkout, 'Checkout',
        'Pay the shop by Mobile Money and the worker in cash. No ID needed to buy.'),
  ],
};

Future<void> showRoleOnboarding(
    BuildContext context, Map<String, dynamic>? user) async {
  final prefs = await SharedPreferences.getInstance();
  for (final role in kRoleOrder) {
    if (!userRoles(user).contains(role)) continue;
    if (prefs.getBool('seen_onboarding_' + role) == true) continue;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingCarousel(
        role: role,
        steps: kOnboardingSteps[role]!,
        onDone: () => prefs.setBool('seen_onboarding_' + role, true),
      ),
    );
    return;
  }
}

class OnboardingCarousel extends StatefulWidget {
  final String role;
  final List<OnboardingStep> steps;
  final VoidCallback onDone;
  const OnboardingCarousel(
      {super.key, required this.role, required this.steps, required this.onDone});

  @override
  State<OnboardingCarousel> createState() => _OnboardingCarouselState();
}

class _OnboardingCarouselState extends State<OnboardingCarousel> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == widget.steps.length - 1) {
      widget.onDone();
      Navigator.pop(context);
    } else {
      _pc.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Welcome to NYG',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Your ' + widget.role + ' guide',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 18),
            SizedBox(
              height: 190,
              child: PageView.builder(
                controller: _pc,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kNyqAccent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(steps[i].icon, size: 34, color: kNyqAccent),
                    ),
                    const SizedBox(height: 16),
                    Text(steps[i].title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(steps[i].body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                steps.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? kNyqAccent : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kNyqGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _next,
                child: Text(_page == steps.length - 1
                    ? "Got it, let's go"
                    : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showAccountSheet(
  BuildContext context,
  Map<String, dynamic>? currentUser,
  VoidCallback onUserChanged, {
  Future<bool> Function({String? suggestedRole})? ensureLoggedIn,
  VoidCallback? onSignOut,
  VoidCallback? onRefreshUser,
  Map<String, dynamic>? currentShop,
}) {
  final user = currentUser;
  final shop = currentShop;

  Future<void> handleSignIn() async {
    if (ensureLoggedIn != null) {
      await ensureLoggedIn();
    }
    onUserChanged();
    onRefreshUser?.call();
  }

  final isAdmin = currentUser != null &&
      (currentUser['is_admin'] == 1 || currentUser['is_admin'] == true);

  Widget sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFF9A9088),
            ),
          ),
        ),
      );

  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            if (user == null) ...[
              const Icon(Icons.person_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Welcome to Na You Get',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'You can browse as a guest. Sign in when you want to sell, deliver, or buy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign In'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await handleSignIn();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Create Account'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await handleSignIn();
                    },
                  ),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kNyqAccent, kNyqAccentDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: kNyqAccent.withAlpha(60),
                        blurRadius: 20,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    EditableAvatar(
                      photoUrl: user['photo_url']?.toString(),
                      name: user['name']?.toString() ?? '',
                      radius: 34,
                      backgroundColor: Colors.white24,
                      onChanged: onUserChanged,
                    ),
                    const SizedBox(height: 12),
                    Text(user['name'] ?? 'User',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(user['phone_number'] ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Text(
                        isRunner(user) && isSeller(user)
                            ? 'SELLER & WORKER'
                            : isRunner(user)
                                ? 'WORKER'
                                : isSeller(user)
                                    ? 'SELLER'
                                    : 'CUSTOMER',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('My Profile'),
                subtitle: Text(_profileRoleLabel(currentUser)),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        currentUser: user,
                        onUserChanged: onUserChanged,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 8),
              sectionHeader('ACTIVITY'),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('My Orders'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyOrdersScreen(currentUser: user),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Messages'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessagesScreen(currentUser: currentUser!),
                    ),
                  );
                },
              ),
              if (isSeller(currentUser) || isAdmin)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('My Invoices'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InvoicesScreen(isAdmin: false)),
                  );
                },
              ),
              if (currentUser != null && (currentUser['is_admin'] == 1 || currentUser['is_admin'] == true))
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings, color: kNyqGreen),
                  title: const Text('Admin Dashboard'),
                  subtitle: const Text('Users, invoices and earnings'),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                    );
                  },
                ),
              if (isSeller(currentUser)) sectionHeader('SELLER TOOLS'),
              if (isSeller(currentUser) && shop != null)
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  title: const Text('Request to Stop Selling'),
                  subtitle: const Text('Ask NYG Support to close your seller account'),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: () {
                    Navigator.pop(ctx);
                    requestRoleRemoval(context, 'a Seller',
                        'I want to stop being a Seller.');
                  },
                ),
              if (isSeller(currentUser))
                ListTile(
                  leading: const Icon(Icons.storefront, color: kNyqGreen),
                  title: const Text('My Shops'),
                  subtitle: const Text('Manage your storefronts'),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          currentUser: currentUser!,
                          onUserChanged: onUserChanged,
                        ),
                      ),
                    );
                  },
                ),

              if (isRunner(currentUser)) ...[
                sectionHeader('DELIVERIES'),
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  title: const Text('Request to Stop Working'),
                  subtitle: const Text('Ask NYG Support to remove your worker role'),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: () {
                    Navigator.pop(ctx);
                    requestRoleRemoval(context, 'a Job Worker',
                        'I want to stop being a Job Worker.');
                  },
                ),
              ],
              sectionHeader('SETTINGS'),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Profile'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(
                        currentUser: currentUser!,
                        onUserChanged: onUserChanged,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  showChangePasswordDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Guide'),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFFB0A89F)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            HelpGuideScreen(currentUser: currentUser)),
                  );
                },
              ),
              const Divider(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      backgroundColor: Colors.red.shade50,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign Out',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await UserSession.clear();
                      await ShopSession.clear();
                      onUserChanged();
                      onSignOut?.call();
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

class AccountButton extends StatelessWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;
  final Future<bool> Function({String? suggestedRole})? ensureLoggedIn;
  final VoidCallback? onSignOut;
  final VoidCallback? onRefreshUser;
  final Map<String, dynamic>? currentShop;

  const AccountButton({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
    this.ensureLoggedIn,
    this.onSignOut,
    this.onRefreshUser,
    this.currentShop,
  });

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    final isLoggedIn = user != null;
    return IconButton(
      tooltip: isLoggedIn ? 'My Account' : 'Sign In',
      icon: isLoggedIn
          ? CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF1B5E20),
              backgroundImage: (user['photo_url'] != null && user['photo_url'].toString().isNotEmpty)
                  ? NetworkImage(user['photo_url'])
                  : null,
              child: (user['photo_url'] == null || user['photo_url'].toString().isEmpty)
                  ? Text(
                      (user['name']?.toString() ?? '?').isNotEmpty
                          ? user['name'][0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    )
                  : null,
            )
          : const Icon(Icons.login),
      onPressed: () async {
        // Tabs that already know the shop pass it in; others let it be
        // resolved here before the sheet is shown.
        var shop = currentShop;
        if (shop == null && user != null) {
          shop = await ShopSession.load();
        }
        if (!context.mounted) return;
        showAccountSheet(
          context,
          currentUser,
          onUserChanged,
          ensureLoggedIn: ensureLoggedIn,
          onSignOut: onSignOut,
          onRefreshUser: onRefreshUser,
          currentShop: shop,
        );
      },
    );
  }
}

// ==========================================
// EDIT PROFILE SCREEN
// ==========================================
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final VoidCallback onUserChanged;
  const EditProfileScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  String? _photoUrl;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser['name'] ?? '');
    _phoneController = TextEditingController(text: widget.currentUser['phone_number'] ?? '');
    _photoUrl = widget.currentUser['photo_url'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await UserSession.update({
      'name': _nameController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'photo_url': _photoUrl,
    });
    setState(() => _saving = false);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      widget.onUserChanged();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update profile')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will delete your account permanently. If you own a shop, the shop and its products will also be deleted. This cannot be undone.',
            ),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm:'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'DELETE',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (confirmController.text.trim() == 'DELETE') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    final err = await UserSession.deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);
    if (err == 'SESSION_EXPIRED') {
      handleSessionExpired(context);
      return;
    }
    if (err == null) {
      await ShopSession.clear();
      widget.onUserChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF1B5E20),
              backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? Text(
                      (_nameController.text.isNotEmpty ? _nameController.text[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final url = await pickAndUploadImage(context);
                if (url != null) {
                  setState(() => _photoUrl = url);
                }
              },
              icon: const Icon(Icons.photo_camera),
              label: Text(_photoUrl == null || _photoUrl!.isEmpty ? 'Upload Profile Picture' : 'Change Picture'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: _deleting ? null : _deleteAccount,
                icon: const Icon(Icons.delete_forever),
                label: Text(_deleting ? 'Deleting...' : 'Delete My Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// MESSAGES SCREEN (conversation list)
// ==========================================
class MessagesScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  const MessagesScreen({super.key, required this.currentUser});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<dynamic> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await MessageSession.getInbox();
    if (MessageSession.lastCallWasUnauthorized) {
      if (mounted) handleSessionExpired(context);
      return;
    }
    if (!mounted) return;
    final list = <dynamic>[];
    for (final c in data) {
      list.add({...Map<String, dynamic>.from(c as Map), '_kind': 'direct'});
    }
    try {
      final user = await UserSession.load();
      final tr = await http.get(
        Uri.parse('$baseUrl/threads/mine'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 8));
      if (tr.statusCode >= 200 && tr.statusCode < 300) {
        for (final t in jsonDecode(tr.body) as List) {
          list.add({...Map<String, dynamic>.from(t as Map), '_kind': 'thread'});
        }
      }
    } catch (_) {
        showNetworkError(context, 'messages');
      }
    list.sort((a, b) {
      final da = (a['last_at'] ?? '').toString();
      final db2 = (b['last_at'] ?? '').toString();
      return db2.compareTo(da);
    });
    if (!mounted) return;
    setState(() {
      _conversations = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages',
                  message: 'Chat with sellers or runners here.',
                  actionLabel: 'Back to Shopping',
                  onAction: () => Navigator.pop(context),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (ctx, i) {
                    final c = _conversations[i];
                    if ((c['_kind'] ?? 'direct') == 'thread') {
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: kNyqAccent,
                          child: Icon(Icons.groups,
                              color: Colors.white, size: 20),
                        ),
                        title: Text((c['name'] ?? 'Team Chat').toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          (c['last_message'] ?? 'No messages yet').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                            '${c['member_count'] ?? 0} members',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                threadId: (c['id'] as num).toInt(),
                                threadName:
                                    (c['name'] ?? 'Team Chat').toString(),
                              ),
                            ),
                          );
                          _load();
                        },
                      );
                    }
                    final other = c['other_user'];
                    if (other == null) return const SizedBox.shrink();
                    final unread = c['unread_count'] ?? 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1B5E20),
                        backgroundImage: (other['photo_url'] != null && other['photo_url'].toString().isNotEmpty)
                            ? NetworkImage(other['photo_url'])
                            : null,
                        child: (other['photo_url'] == null || other['photo_url'].toString().isEmpty)
                            ? Text(
                                (other['name']?.toString() ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(other['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        c['last_message'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: unread > 0
                          ? CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            )
                          : null,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              otherUserId: other['id'],
                              otherUserName: other['name'] ?? 'User',
                            ),
                          ),
                        );
                        _load();
                      },
                    );
                  },
                ),
    );
  }
}

// ==========================================
// CHAT SCREEN
// ==========================================
class ChatScreen extends StatefulWidget {
  final int? otherUserId;
  final String? otherUserName;
  final int? threadId;
  final String? threadName;
  final int? shopId;
  final int? orderId;
  final int? productId;
  final String? initialMessage;
  const ChatScreen({
    super.key,
    this.otherUserId,
    this.otherUserName,
    this.threadId,
    this.threadName,
    this.shopId,
    this.orderId,
    this.productId,
    this.initialMessage,
  }) : assert(threadId != null || otherUserId != null);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<dynamic> _messages = [];
  bool _loading = true;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;
  int? _myId;
  int _lastCount = 0;

  bool get _isThread => widget.threadId != null;
  String get _title => widget.threadName ?? widget.otherUserName ?? 'Chat';
  Map<String, dynamic>? _replyTo;
  bool _showEmoji = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = await UserSession.load();
    _myId = user?['id'];
    await _load();
    final opening = widget.initialMessage;
    if (!_isThread &&
        opening != null &&
        opening.isNotEmpty &&
        _messages.isEmpty &&
        widget.otherUserId != _myId) {
      final sent = await MessageSession.send(
        widget.otherUserId!,
        opening,
        shopId: widget.shopId,
        orderId: widget.orderId,
      );
      if (sent) await _load();
    }
    if (!_isThread && widget.otherUserId != null) {
      await MessageSession.markRead(widget.otherUserId!);
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  Future<void> _load() async {
    if (_isThread) {
      final u = await UserSession.load();
      try {
        final res = await http.get(
          Uri.parse('$baseUrl/threads/${widget.threadId}/messages'),
          headers: {
            'x-api-key': apiKey,
            'Authorization': 'Bearer ${u?['token'] ?? ''}',
          },
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final List msgs = jsonDecode(res.body) as List;
          if (!mounted) return;
          final grewThread = msgs.length > _lastCount;
          setState(() {
            _messages = msgs;
            _loading = false;
            _lastCount = msgs.length;
          });
          if (grewThread) _scrollToBottom();
          return;
        }
      } catch (_) {
        showNetworkError(context, 'messages');
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    final msgs = await MessageSession.getConversation(widget.otherUserId!);
    if (MessageSession.lastCallWasUnauthorized) {
      if (mounted) handleSessionExpired(context);
      return;
    }
    if (!mounted) return;
    final grew = msgs.length > _lastCount;
    setState(() {
      _messages = msgs;
      _loading = false;
      _lastCount = msgs.length;
    });
    if (grew) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _makeOffer() async {
    final amountCtl = TextEditingController();
    bool sending = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: const Text('Make an Offer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Enter the amount you would like to pay. The seller can accept or decline.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Amount (SLE)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kNyqGreen),
              onPressed: sending
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountCtl.text.trim());
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Enter a valid amount')),
                        );
                        return;
                      }
                      setDialogState(() => sending = true);
                      final user = await UserSession.load();
                      try {
                        final res = await http.post(
                          Uri.parse('$baseUrl/messages/offer'),
                          headers: {
                            'Content-Type': 'application/json',
                            'x-api-key': apiKey,
                            'Authorization':
                                'Bearer ${user?['token'] ?? ''}',
                          },
                          body: jsonEncode({
                            'amount_sle': amount,
                            'product_id': widget.productId,
                            'order_id': widget.orderId,
                            'shop_id': widget.shopId,
                            'recipient_id': widget.otherUserId,
                          }),
                        ).timeout(const Duration(seconds: 10));
                        if (!dialogCtx.mounted) return;
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          Navigator.pop(dialogCtx);
                          await _load();
                        } else {
                          setDialogState(() => sending = false);
                          String msg = 'Could not send offer';
                          try {
                            msg =
                                (jsonDecode(res.body)['detail'] ?? msg)
                                    .toString();
                          } catch (_) {
        showNetworkError(context, 'data');
      }
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red),
                          );
                        }
                      } catch (_) {
                        if (!dialogCtx.mounted) return;
                        setDialogState(() => sending = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Network error')),
                        );
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Send Offer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _answerOffer(int messageId, bool accept) async {
    final user = await UserSession.load();
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/messages/$messageId/offer/${accept ? 'accept' : 'decline'}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(accept ? 'Offer accepted' : 'Offer declined'),
              backgroundColor: kNyqGreen),
        );
        await _load();
      } else {
        String msg = 'Could not respond to offer';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {
        showNetworkError(context, 'data');
      }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
        showNetworkError(context, 'data');
      }
  }

  Widget _offerBubble(
      Map<String, dynamic> m, Map<String, dynamic> offer, bool isMine) {
    final status = (offer['status'] ?? 'pending').toString();
    final amount = (offer['amount_sle'] ?? 0) as num;
    final sellerId = (offer['seller_id'] as num?)?.toInt();
    final iAmSeller = sellerId != null && sellerId == _myId;
    final canAnswer = iAmSeller && status == 'pending';
    final id = (m['id'] as num).toInt();

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: status == 'accepted'
                  ? kNyqGreen
                  : (status == 'declined'
                      ? Colors.red.shade200
                      : kNyqOchre),
              width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake, size: 16, color: kNyqAccent),
                const SizedBox(width: 6),
                const Text('Price Offer',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kNyqAccent)),
                const Spacer(),
                Text(formatChatTime(m['created_at']),
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 6),
            Text('SLE ${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              status == 'accepted'
                  ? 'Agreed'
                  : (status == 'declined' ? 'Declined' : 'Awaiting response'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status == 'accepted'
                    ? kNyqGreen
                    : (status == 'declined'
                        ? Colors.red
                        : Colors.orange.shade800),
              ),
            ),
            if (canAnswer) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: kNyqGreen,
                          padding:
                              const EdgeInsets.symmetric(vertical: 10)),
                      onPressed: () => _answerOffer(id, true),
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10)),
                      onPressed: () => _answerOffer(id, false),
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    final replyId = (_replyTo?['id'] as num?)?.toInt();
    if (mounted) setState(() => _replyTo = null);
    if (_isThread) {
      final u = await UserSession.load();
      try {
        await http.post(
          Uri.parse('$baseUrl/threads/${widget.threadId}/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'Authorization': 'Bearer ${u?['token'] ?? ''}',
          },
          body: jsonEncode({
            'text': text,
            'reply_to_message_id': replyId,
          }),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        showNetworkError(context, 'messages');
      }
      await _load();
      return;
    }
    await MessageSession.send(
      widget.otherUserId!,
      text,
      shopId: widget.shopId,
      orderId: widget.orderId,
      replyToMessageId: replyId,
    );
    if (MessageSession.lastCallWasUnauthorized) {
      if (mounted) handleSessionExpired(context);
      return;
    }
    await _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (!_isThread &&
              (widget.orderId != null ||
                  widget.productId != null ||
                  widget.shopId != null))
            IconButton(
              icon: const Icon(Icons.handshake_outlined),
              tooltip: 'Make an offer',
              onPressed: _makeOffer,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final m = _messages[i];
                          final isMine = m['sender_id'] == _myId;
                          final offer = m['offer_data'];
                          if (offer is Map) {
                            return _offerBubble(m,
                                Map<String, dynamic>.from(offer), isMine);
                          }
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                              decoration: BoxDecoration(
                                color: isMine ? const Color(0xFF1B5E20) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: GestureDetector(
                                onLongPress: () =>
                                    setState(() => _replyTo = m),
                                child: Column(
                                crossAxisAlignment: isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (_isThread && !isMine)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 3),
                                      child: Text(
                                        (m['sender_name'] ?? '').toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  if ((m['reply_preview'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? Colors.white24
                                            : Colors.black12,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        m['reply_preview'].toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: isMine
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    m['text'] ?? '',
                                    style: TextStyle(
                                      color: isMine
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    formatChatTime(m['created_at']),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMine
                                          ? Colors.white70
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: kNyqSand,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Replying: ${(_replyTo!['text'] ?? '').toString()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _replyTo = null),
                          ),
                        ],
                      ),
                    ),
                  if (_showEmoji)
                    SizedBox(
                      height: 118,
                      child: GridView.count(
                        crossAxisCount: 8,
                        children: [
                          for (final e in kChatEmojis)
                            InkWell(
                              onTap: () {
                                _textController.text += e;
                                _textController.selection =
                                    TextSelection.fromPosition(
                                        TextPosition(
                                            offset: _textController
                                                .text.length));
                              },
                              child: Center(
                                  child: Text(e,
                                      style: const TextStyle(
                                          fontSize: 22))),
                            ),
                        ],
                      ),
                    ),
                  Row(
                children: [
                  IconButton(
                    icon: Icon(_showEmoji
                        ? Icons.keyboard_outlined
                        : Icons.emoji_emotions_outlined),
                    color: kNyqAccent,
                    onPressed: () =>
                        setState(() => _showEmoji = !_showEmoji),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1B5E20),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _send,
                    ),
                  ),
                ],
                  ),
                ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// CHAT BUBBLE (floating overlay)
// ==========================================
class ChatBubble extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const ChatBubble({super.key, required this.currentUser});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  int _unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (widget.currentUser == null) {
      if (mounted) setState(() => _unread = 0);
      return;
    }
    final data = await MessageSession.getInbox();
    if (!mounted) return;
    if (MessageSession.lastCallWasUnauthorized) {
      handleSessionExpired(context);
      return;
    }
    int total = 0;
    for (final c in data) {
      total += ((c['unread_count'] ?? 0) as num).toInt();
    }
    setState(() => _unread = total);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessagesScreen(currentUser: widget.currentUser!),
          ),
          );
          _refresh();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: kNyqBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.chat_bubble, color: Colors.white, size: 26),
            ),
            if (_unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      );
  }
}

// ==========================================
// CHANGE PASSWORD DIALOG
// ==========================================
Future<void> showChangePasswordDialog(BuildContext context) async {
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  bool saving = false;
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password (min 6 characters)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            onPressed: saving
                ? null
                : () async {
                    if (currentCtrl.text.isEmpty) {
                      setDialogState(() => error = 'Enter your current password');
                      return;
                    }
                    if (newCtrl.text.length < 6) {
                      setDialogState(() => error = 'New password must be at least 6 characters');
                      return;
                    }
                    if (newCtrl.text != confirmCtrl.text) {
                      setDialogState(() => error = 'New passwords do not match');
                      return;
                    }
                    if (newCtrl.text == currentCtrl.text) {
                      setDialogState(() => error = 'New password must be different');
                      return;
                    }

                    setDialogState(() {
                      saving = true;
                      error = null;
                    });

                    final err = await UserSession.changePassword(
                      currentCtrl.text,
                      newCtrl.text,
                    );

                    if (!context.mounted) return;

                    if (err == null) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password updated')),
                      );
                    } else {
                      setDialogState(() {
                        saving = false;
                        error = err;
                      });
                    }
                  },
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

// ==========================================
// MERCHANT ORDERS SCREEN
// ==========================================
// ==========================================
// MOBILE MONEY INSTRUCTIONS DIALOG
// ==========================================
Future<void> showMobileMoneyInstructions(
  BuildContext context, {
  required String method,
  required String shopPhone,
  required String total,
  required String orderRef,
}) async {
  final isOrange = method == 'orange_money';
  final dialCode = isOrange ? '*144#' : '*161#';
  final label = isOrange ? 'Orange Money' : 'Africell Money';

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Pay with $label'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('To complete your order, send the amount via $label:'),
            const SizedBox(height: 12),
            Text('1. Dial $dialCode'),
            const Text('2. Choose Send Money'),
            Text('3. Enter the amount: SLE $total'),
            Text('4. Enter the shop phone: $shopPhone'),
            Text('5. Enter the reference: $orderRef'),
            const Text('6. Complete the transaction on your phone'),
            const Text('7. The shop will confirm once payment is received'),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx),
          child: const Text("OK, I've paid"),
        ),
      ],
    ),
  );
}

class MerchantOrdersScreen extends StatefulWidget {
  final Map<String, dynamic> merchant;
  const MerchantOrdersScreen({super.key, required this.merchant});

  @override
  State<MerchantOrdersScreen> createState() => _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends State<MerchantOrdersScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await UserSession.load();
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/orders/merchant/${widget.merchant['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) setState(() {
          _orders = jsonDecode(res.body);
          _loading = false;
        });
        return;
      }
    } catch (_) {
        showNetworkError(context, 'your orders');
      }
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        return Colors.green;
      case 'accepted':
      case 'in_transit':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _decidePrice(int orderId, bool accept) async {
    final user = await UserSession.load();
    final token = user?['token'];
    if (token == null) return;
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/orders/$orderId/price-decision'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'accept': accept}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? (accept ? 'Price accepted' : 'Price declined')
            : 'Could not update the order'),
        backgroundColor: ok ? kNyqGreen : Colors.red.shade800,
      ));
      if (ok) _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No orders yet.',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Orders placed for your shop will appear here.',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _orders.length,
                  itemBuilder: (ctx, i) {
                    final o = _orders[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    o['product_title'] ?? 'Order',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(o['delivery_status'] ?? '').withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    (o['delivery_status'] ?? 'pending').toString().toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _statusColor(o['delivery_status'] ?? ''),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  '${o['customer_name'] ?? 'Unknown'} • ${o['customer_phone'] ?? ''}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    o['delivery_address'] ?? '',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total: SLE ${(o['price_sle'] ?? 0) + (o['delivery_fee_sle'] ?? 0)}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                            ),
                            if (o['price_status'] == 'proposed') ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.orange.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer offered SLE ${o['agreed_price'] ?? o['price_sle'] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.deepOrange),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: kNyqGreen),
                                            onPressed: () => _decidePrice(
                                                (o['id'] as num).toInt(),
                                                true),
                                            child: const Text('Accept'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => _decidePrice(
                                                (o['id'] as num).toInt(),
                                                false),
                                            child: const Text('Decline'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${o['payment_method'] ?? ''} • ${o['payment_status'] ?? ''}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            if (o['payment_status'] == 'paid_by_customer')
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'PAID',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(o['created_at']),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                            if (o['driver_id'] != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.directions_run, size: 14, color: Colors.blue),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Worker: ${o['driver_name'] ?? 'Unknown'} • ${o['driver_phone'] ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if ((o['payment_method'] == 'orange_money' ||
                                        o['payment_method'] == 'africell_money') &&
                                    o['payment_status'] == 'pending')
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green.shade800,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.check_circle_outline, size: 16),
                                    label: const Text('Mark as Paid', style: TextStyle(fontSize: 12)),
                                    onPressed: () async {
                                      final user = await UserSession.load();
                                      if (user == null) return;
                                      try {
                                        final res = await http.put(
                                          Uri.parse('$baseUrl/orders/${o['id']}/mark-paid'),
                                          headers: {
                                            'x-api-key': apiKey,
                                            'Authorization': 'Bearer ${user['token']}',
                                          },
                                        ).timeout(const Duration(seconds: 8));
                                        if (!context.mounted) return;
                                        if (res.statusCode >= 200 && res.statusCode < 300) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Payment confirmed')),
                                          );
                                          _load();
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Could not mark as paid')),
                                          );
                                        }
                                      } catch (_) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Cannot reach server')),
                                        );
                                      }
                                    },
                                  ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1B5E20),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                  label: const Text('Message Buyer', style: TextStyle(fontSize: 12)),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        otherUserId: (o['customer_id'] as num).toInt(),
                                        otherUserName: o['customer_name'] ?? 'Customer',
                                        orderId: o['id'],
                                      ),
                                    ),
                                  ),
                                ),
                                if (o['driver_id'] != null)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                    label: const Text('Message Worker', style: TextStyle(fontSize: 12)),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          otherUserId: (o['driver_id'] as num).toInt(),
                                          otherUserName: o['driver_name'] ?? 'Job Worker',
                                          orderId: o['id'],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ==========================================
// RUNNER DELIVERIES SCREEN
// ==========================================
// ==========================================
// MAIN NAVIGATION — 4 TABS
// ==========================================
class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  final String? currentUserRole; // 'customer', 'seller', 'runner', or null
  const OrderDetailScreen({super.key, required this.orderId, this.currentUserRole});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await UserSession.getFullOrderStatus(widget.orderId);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  Future<void> _confirmFlow(String step, String label) async {
    setState(() => _working = true);
    final err = await UserSession.confirmFlowStep(widget.orderId, step);
    if (!mounted) return;
    setState(() => _working = false);
    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label confirmed')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '?';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _stepRow(String title, String? time, {String? step, String? buttonLabel, bool enabled = true}) {
    final done = time != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : Colors.grey,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (done)
                  Text(_fmt(time), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (!done && step != null && buttonLabel != null && enabled)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: _working ? null : () => _confirmFlow(step, buttonLabel),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, dynamic value, {bool bold = false}) {
    final v = (value is num) ? value.toStringAsFixed(2) : '0.00';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text('SLE $v', style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data == null) return const Scaffold(body: Center(child: Text('Could not load order')));

    final s = (_data!['steps'] as Map<String, dynamic>?) ?? {};
    final role = widget.currentUserRole;

    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.orderId}'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment method: ${_data!['payment_method'] ?? '?'}'),
            Text('Payment status: ${_data!['payment_status'] ?? '?'}'),
            Text('Delivery status: ${_data!['delivery_status'] ?? '?'}'),
            const Divider(height: 32),
            const Text('Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _stepRow('Buyer paid', s['buyer_paid'] as String?,
              step: role == 'customer' ? 'buyer-paid' : null, buttonLabel: "I've paid"),
            _stepRow('Seller received payment', s['seller_received'] as String?,
              step: role == 'seller' ? 'seller-received' : null, buttonLabel: "I've received",
              enabled: s['buyer_paid'] != null),
            _stepRow('Seller paid worker fee', s['seller_paid_runner'] as String?,
              step: role == 'seller' ? 'seller-paid-runner' : null, buttonLabel: "I've paid worker",
              enabled: s['seller_received'] != null),
            _stepRow('Worker received fee', s['runner_received_fee'] as String?,
              step: role == 'runner' ? 'runner-received-fee' : null, buttonLabel: "I've received",
              enabled: s['seller_paid_runner'] != null),
            _stepRow('Seller handed goods to worker', s['seller_handed_goods'] as String?,
              step: role == 'seller' ? 'seller-handed' : null, buttonLabel: "I've handed goods",
              enabled: s['runner_received_fee'] != null),
            _stepRow('Worker picked up', s['runner_picked_up'] as String?,
              step: role == 'runner' ? 'runner-picked-up' : null, buttonLabel: "I've picked up",
              enabled: s['seller_handed_goods'] != null),
            _stepRow('Worker delivered', s['runner_delivered'] as String?,
              step: role == 'runner' ? 'runner-delivered' : null, buttonLabel: "I've delivered",
              enabled: s['runner_picked_up'] != null),
            _stepRow('Buyer received goods', s['buyer_received_goods'] as String?,
              step: role == 'customer' ? 'buyer-received-goods' : null, buttonLabel: "I've received",
              enabled: s['runner_delivered'] != null),
            const Divider(height: 32),
            const Text('Money breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _moneyRow('Product price', _data!['product_price_sle']),
            const Divider(height: 16),
            _moneyRow('Seller receives', _data!['seller_payout_sle'], bold: true),
            const Divider(height: 16),
            _moneyRow('Worker delivery fee', _data!['runner_fee_sle']),
          ],
        ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            labelColor: kNyqGreen,
            indicatorColor: kNyqGreen,
            tabs: [
              Tab(text: 'Users', icon: Icon(Icons.people_outline)),
              Tab(text: 'Invoices', icon: Icon(Icons.receipt_long)),
          Tab(text: 'Companies', icon: Icon(Icons.business_outlined)),
              Tab(text: 'KYC', icon: Icon(Icons.badge_outlined)),
              Tab(text: 'Overview', icon: Icon(Icons.insights_outlined)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsersScreen(embedded: true),
            InvoicesScreen(isAdmin: true, embedded: true),
          AdminCompaniesScreen(embedded: true),
            AdminKycScreen(embedded: true),
            AdminEarningsScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}
// ==========================================
// ADMIN KYC REVIEW
// ==========================================
class AdminKycScreen extends StatefulWidget {
  final bool embedded;
  const AdminKycScreen({super.key, this.embedded = false});

  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends State<AdminKycScreen> {
  List<dynamic> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/kyc'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) {
          setState(() {
            _rows = jsonDecode(res.body) as List;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'KYC submissions');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined,
                          size: 18, color: kNyqAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            '${_rows.length} ID(s) waiting for review',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _fetch),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? EmptyState(
                          icon: Icons.verified_outlined,
                          title: 'Nothing to review',
                          message: 'No identity documents are waiting.',
                          actionLabel: 'Refresh',
                          onAction: _fetch,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: _rows.length,
                          itemBuilder: (ctx, i) {
                            final r =
                                Map<String, dynamic>.from(_rows[i] as Map);
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: kNyqAccent,
                                  child: Icon(Icons.person,
                                      color: Colors.white, size: 20),
                                ),
                                title: Text(
                                    (r['name'] ?? 'Unknown').toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${r['phone_number']} - ${r['id_type'] ?? 'id'} ${r['id_number'] ?? ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminKycReviewScreen(
                                        record: r,
                                      ),
                                    ),
                                  );
                                  _fetch();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// Auth-fetched KYC image, used by both viewer screens.
class KycImageBlock extends StatefulWidget {
  final String? imageId;
  final String label;
  const KycImageBlock(
      {super.key, required this.imageId, required this.label});

  @override
  State<KycImageBlock> createState() => _KycImageBlockState();
}

class _KycImageBlockState extends State<KycImageBlock> {
  Uint8List? _bytes;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.imageId;
    if (id == null || id.isEmpty) {
      setState(() => _busy = false);
      return;
    }
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/kyc/image/$id'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _bytes = (res.statusCode >= 200 && res.statusCode < 300)
            ? res.bodyBytes
            : null;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: kNyqAccent,
                letterSpacing: 0.6)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 210,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0DAD2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _busy
              ? const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : _bytes != null
                  ? InteractiveViewer(
                      maxScale: 4,
                      child: Image.memory(_bytes!,
                          fit: BoxFit.contain, width: double.infinity),
                    )
                  : Center(
                      child: Text('Not provided',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                    ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class AdminKycReviewScreen extends StatefulWidget {
  final Map<String, dynamic> record;
  const AdminKycReviewScreen({super.key, required this.record});

  @override
  State<AdminKycReviewScreen> createState() =>
      _AdminKycReviewScreenState();
}

class _AdminKycReviewScreenState extends State<AdminKycReviewScreen> {
  bool _saving = false;

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
  }

  Future<void> _decide(String status, {String? reason}) async {
    setState(() => _saving = true);
    try {
      final res = await http.put(
        Uri.parse(
            '$baseUrl/admin/kyc/${widget.record['id']}/decide'),
        headers: await _headers(),
        body: jsonEncode({
          'status': status,
          if (reason != null) 'reason': reason,
        }),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(status == 'approved'
                  ? 'ID approved'
                  : 'ID rejected'),
              backgroundColor:
                  status == 'approved' ? kNyqGreen : Colors.red.shade700),
        );
      } else {
        setState(() => _saving = false);
        String msg = 'Could not save the decision';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showNetworkError(context, 'the decision');
      }
    }
  }

  Future<void> _reject() async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reject this ID?'),
        content: TextField(
          controller: reasonCtl,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Reason (the user will need to resubmit)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Reject',
                  style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true) return;
    if (reasonCtl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A reason is required')),
        );
      }
      return;
    }
    await _decide('rejected', reason: reasonCtl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: Text((r['name'] ?? 'Review').toString()),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0DAD2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((r['full_name_on_id'] ?? 'Not provided').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    '${(r['id_type'] ?? 'id').toString().toUpperCase()}  ${r['id_number'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 2),
                Text((r['phone_number'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          KycImageBlock(imageId: r['front_image_id']?.toString(), label: 'FRONT'),
          KycImageBlock(imageId: r['back_image_id']?.toString(), label: 'BACK'),
          KycImageBlock(imageId: r['selfie_image_id']?.toString(), label: 'SELFIE'),
          Text(
            'Opening this document is recorded in the access log.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300)),
                  onPressed: _saving ? null : _reject,
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: kNyqGreen),
                  onPressed: _saving ? null : () => _decide('approved'),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class AdminCompaniesScreen extends StatefulWidget {
  final bool embedded;
  const AdminCompaniesScreen({super.key, this.embedded = false});

  @override
  State<AdminCompaniesScreen> createState() => _AdminCompaniesScreenState();
}

class _AdminCompaniesScreenState extends State<AdminCompaniesScreen> {
  List<dynamic> _companies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/companies'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _companies = list;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
        showNetworkError(context, 'company details');
      }
    if (mounted) {
      setState(() {
        _companies = [];
        _loading = false;
      });
    }
  }

  Future<void> _approve(int id) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/admin/companies/$id/approve'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Company approved'), backgroundColor: kNyqGreen),
        );
        await _fetch();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not approve'),
              backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _companies.isEmpty
            ? EmptyState(
                icon: Icons.business_outlined,
                title: 'No companies',
                message: 'Company applications will appear here.',
                actionLabel: 'Refresh',
                onAction: _fetch,
              )
            : RefreshIndicator(
                onRefresh: _fetch,
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _companies.length,
                  itemBuilder: (ctx, i) {
                    final c = Map<String, dynamic>.from(_companies[i] as Map);
                    final approved = (c['is_approved'] ?? 0) == 1;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text((c['name'] ?? '').toString(),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: approved
                                        ? kNyqGreen.withValues(alpha: 0.12)
                                        : Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    approved ? 'APPROVED' : 'PENDING',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: approved
                                            ? kNyqGreen
                                            : Colors.orange.shade800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if ((c['owner_kyc_status'] ?? 'none') ==
                                    'approved')
                                  Text('ID verified',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: kNyqGreen))
                                else if ((c['owner_kyc_status'] ?? 'none') ==
                                    'submitted')
                                  Text('ID under review',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.orange.shade900))
                                else
                                  Text('Owner has no ID',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.red)),
                              ],
                            ),
                            Text(
                                '${c['owner_name'] ?? ''} - ${c['industry'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600)),
                            if ((c['description'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(c['description'].toString(),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                            ],
                            if (!approved)
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: kNyqGreen,
                                      foregroundColor: Colors.white),
                                  onPressed: () =>
                                      _approve((c['id'] as num).toInt()),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Approve'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );

    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Companies')),
            body: body,
          );
  }
}

class AdminUsersScreen extends StatefulWidget {
  final bool embedded;
  const AdminUsersScreen({super.key, this.embedded = false});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchCtl = TextEditingController();
  List<dynamic> _users = [];
  bool _loading = true;
  bool _pendingOnly = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    final token = user?['token'];
    return {
      'x-api-key': apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Refreshes cached role flags so a stale token does not silently
  /// produce an empty list.
  Future<void> _refreshRoles() async {
    try {
      final user = await UserSession.load();
      final token = (user?['token'] ?? '').toString();
      if (token.isEmpty) return;
      final res = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final fresh = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        await UserSession.save(fresh, token);
      }
    } catch (_) {}
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    await _refreshRoles();
    var result = <dynamic>[];
    try {
      final q = _searchCtl.text.trim();
      final uri = Uri.parse('$baseUrl/admin/users${q.isEmpty ? '' : '?q=${Uri.encodeComponent(q)}'}');
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        result = jsonDecode(res.body) as List;
      } else if (mounted) {
        final expired = res.statusCode == 401 || res.statusCode == 403;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(expired
                ? 'Session expired - please sign out and back in.'
                : 'Could not load users (${res.statusCode}).'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (_) {
        showNetworkError(context, 'users');
      }
    if (!mounted) return;
    setState(() {
      _users = result;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetch);
  }

  Future<bool> _send(String method, String path,
      [Map<String, dynamic>? body]) async {
    var ok = false;
    var msg = 'Network error. Please try again.';
    try {
      final headers = {...await _headers(), 'Content-Type': 'application/json'};
      final uri = Uri.parse('$baseUrl$path');
      http.Response res;
      if (method == 'POST') {
        res = await http
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 12));
      } else if (method == 'PUT') {
        res = await http
            .put(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 12));
      } else {
        res = await http
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 12));
      }
      ok = res.statusCode >= 200 && res.statusCode < 300;
      if (ok) {
        msg = 'Done';
      } else {
        try {
          msg = (jsonDecode(res.body)['detail'] ?? 'Action failed').toString();
        } catch (_) {
          msg = 'Action failed';
        }
      }
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? kNyqGreen : Colors.red.shade800,
      ));
    }
    return ok;
  }

  Future<void> _showUserSheet(Map<String, dynamic> u) async {
    final id = u['id'] as int;
    final isSeller = u['is_seller'] == 1;
    final isRunner = u['is_runner'] == 1;
    final isSuspended = u['is_suspended'] == 1;
    final pendingRole = (u['pending_role'] ?? '').toString();
    final isCompanyManager = (u['is_company_manager'] ?? 0) == 1;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(u['name'].toString(),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            Text(u['phone_number'].toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.lock_reset),
              title: const Text('Reset Password'),
              onTap: () {
                Navigator.pop(ctx);
                _resetPassword(id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              tileColor: (!isSeller && pendingRole == 'seller')
                  ? Colors.orange.withValues(alpha: 0.10)
                  : null,
              title: Text(isSeller ? 'Remove Seller' : 'Make Seller'),
              subtitle: (!isSeller && pendingRole == 'seller')
                  ? Text('Applied - awaiting your approval',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800))
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/roles',
                    {'is_seller': isSeller ? 0 : 1});
                if (done) await _fetch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_run),
              tileColor: (!isRunner && pendingRole == 'runner')
                  ? Colors.orange.withValues(alpha: 0.10)
                  : null,
              title: Text(isRunner ? 'Remove Job Worker' : 'Make Job Worker'),
              subtitle: (!isRunner && pendingRole == 'runner')
                  ? Text('Applied - awaiting your approval',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800))
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/roles',
                    {'is_runner': isRunner ? 0 : 1});
                if (done) await _fetch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.business_center_outlined),
              title: Text(isCompanyManager
                  ? 'Remove Company Manager'
                  : 'Make Company Manager'),
              subtitle: Text(
                  isCompanyManager
                      ? 'Can register companies without approval'
                      : 'Lets them create companies immediately',
                  style: const TextStyle(fontSize: 11)),
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/roles',
                    {'is_company_manager': isCompanyManager ? 0 : 1});
                if (done) await _fetch();
              },
            ),
            ListTile(
              leading: Icon(isSuspended
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline),
              title: Text(isSuspended ? 'Unsuspend' : 'Suspend'),
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/suspend',
                    {'suspended': !isSuspended});
                if (done) await _fetch();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete Account',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete Account?'),
                    content: Text('Permanently remove ${u['name']}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade900),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final done = await _send('DELETE', '/admin/users/$id');
                  if (done) await _fetch();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword(int id) async {
    final ctl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: ctl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            helperText: 'At least 6 characters',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (pw == null || pw.length < 6) return;
    await _send('PUT', '/admin/users/$id/password', {'new_password': pw});
  }

  Future<void> _createUser() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController(text: '+232');
    final passCtl = TextEditingController();
    var seller = false;
    var runner = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                      labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 6 characters',
                      border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seller'),
                  value: seller,
                  onChanged: (v) => setDialogState(() => seller = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Job Worker'),
                  value: runner,
                  onChanged: (v) => setDialogState(() => runner = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty || passCtl.text.length < 6) {
                  return;
                }
                final ok = await _send('POST', '/admin/users', {
                  'name': nameCtl.text.trim(),
                  'phone_number': phoneCtl.text.trim(),
                  'password': passCtl.text,
                  'is_seller': seller ? 1 : 0,
                  'is_runner': runner ? 1 : 0,
                });
                if (ok && ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameCtl.dispose();
    phoneCtl.dispose();
    passCtl.dispose();
    if (created == true) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildInner(context);
    if (!widget.embedded) return scaffold;
    return scaffold.body ?? const SizedBox.shrink();
  }

  Scaffold _buildInner(BuildContext context) {
    final pendingCount = _users
        .where((e) => (e['pending_role'] ?? '').toString().isNotEmpty)
        .length;
    final shown = _pendingOnly
        ? _users
            .where((e) =>
                (e['pending_role'] ?? '').toString().isNotEmpty)
            .toList()
        : _users;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createUser,
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create User'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('All (${_users.length})',
                      style: const TextStyle(fontSize: 12)),
                  selected: !_pendingOnly,
                  onSelected: (_) => setState(() => _pendingOnly = false),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(Icons.pending_actions,
                      size: 16,
                      color: pendingCount > 0
                          ? Colors.orange.shade800
                          : Colors.grey),
                  label: Text('Pending ($pendingCount)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: pendingCount > 0
                              ? FontWeight.w700
                              : FontWeight.normal)),
                  selected: _pendingOnly,
                  onSelected: (_) => setState(() => _pendingOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? EmptyState(
                        icon: _pendingOnly
                            ? Icons.check_circle_outline
                            : Icons.people_outline,
                        title: _pendingOnly
                            ? 'No pending applications'
                            : 'No users found',
                        message: _pendingOnly
                            ? 'Every application has been reviewed.'
                            : 'Try a different search.',
                        actionLabel: _pendingOnly ? 'Show all users' : null,
                        onAction: _pendingOnly
                            ? () => setState(() => _pendingOnly = false)
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: shown.length,
                          itemBuilder: (ctx, i) {
                            final u =
                                Map<String, dynamic>.from(shown[i] as Map);
                            final suspended = u['is_suspended'] == 1;
                            final pendingRole =
                                (u['pending_role'] ?? '').toString();
                            final roles = <String>[
                              if (u['is_admin'] == 1) 'Admin',
                              if (u['is_seller'] == 1) 'Seller',
                              if (u['is_runner'] == 1) 'Runner',
                            ];
                            final name = (u['name'] ?? '?').toString().trim();
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: suspended
                                      ? Colors.grey.shade400
                                      : kNyqAccent,
                                  child: Text(
                                    name.isEmpty
                                        ? '?'
                                        : name[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(
                                  name.isEmpty ? 'Unnamed' : name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  '${u['phone_number']}${roles.isEmpty ? '' : ' - ${roles.join(', ')}'}${suspended ? ' - SUSPENDED' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: suspended
                                        ? Colors.red.shade700
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (pendingRole.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.orange
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'PENDING ${pendingRole.toUpperCase()}',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  Colors.orange.shade800),
                                        ),
                                      ),
                                    if ((u['kyc_status'] ?? 'none') == 'approved')
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: kNyqGreen.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text('ID VERIFIED',
                                            style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: kNyqGreen)),
                                      )
                                    else if ((u['kyc_status'] ?? 'none') ==
                                        'submitted')
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: kNyqOchre.withValues(
                                              alpha: 0.20),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('UNDER REVIEW',
                                            style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade900)),
                                      )
                                    else
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.red.withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text('NO ID',
                                            style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red)),
                                      ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _showUserSheet(u),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
class AdminEarningsScreen extends StatefulWidget {
  final bool embedded;
  const AdminEarningsScreen({super.key, this.embedded = false});

  @override
  State<AdminEarningsScreen> createState() => _AdminEarningsScreenState();
}

class _AdminEarningsScreenState extends State<AdminEarningsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await UserSession.getAdminEarnings();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  Widget _statCard(String label, dynamic value, Color colour) {
    final v = (value is num) ? value.toStringAsFixed(2) : '0';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
                color: colour, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: kNyqInk)),
          ),
          Text(v,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: kNyqInk)),
        ],
      ),
    );
  }

  Widget _countRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text('${value ?? 0}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildInner(context);
    if (!widget.embedded) return scaffold;
    return scaffold.body ?? const SizedBox.shrink();
  }

  Scaffold _buildInner(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Overview'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Could not load platform stats'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Platform growth',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      _statCard('Total sales volume (SLE)',
                          _data!['total_sales_volume'], kNyqAccent),
                      _statCard('Items sold (SLE)',
                          _data!['total_items_value'], kNyqGreen),
                      _statCard('Delivery value (SLE)',
                          _data!['total_delivery_value'], kNyqOchre),
                      const SizedBox(height: 20),
                      const Text('Activity',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      _countRow('Orders paid', _data!['paid_orders']),
                      _countRow('All orders', _data!['total_orders']),
                      const SizedBox(height: 20),
                      const Text('Ecosystem',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      _countRow('Sellers', _data!['total_sellers']),
                      _countRow('Shops', _data!['total_shops']),
                      _countRow('Products', _data!['total_products']),
                      _countRow('Users', _data!['total_users']),
                      const SizedBox(height: 24),
                      Text(
                          'NYG takes no commission. These figures measure platform activity.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
    );
  }

}

class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;
  final bool isAdmin;
  const InvoiceDetailScreen({super.key, required this.invoiceId, required this.isAdmin});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await UserSession.getInvoiceDetail(widget.invoiceId);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  String _fmt(String? iso) {
    if (iso == null) return '?';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _moneyRow(String label, double value, Color colour,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 15 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                    color: colour)),
          ),
          Text('SLE ${value.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: bold ? 15 : 14,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: colour)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_data?['reference'] ?? 'Invoice'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Could not load invoice'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 20,
                                offset: Offset(0, 8)),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: kNyqAccent,
                              backgroundImage: (_data!['shop_logo'] ?? '')
                                      .toString()
                                      .isNotEmpty
                                  ? NetworkImage(
                                      _data!['shop_logo'].toString())
                                  : null,
                              child: (_data!['shop_logo'] ?? '')
                                      .toString()
                                      .isNotEmpty
                                  ? null
                                  : Text(
                                      ((_data!['seller_name'] ?? '?')
                                              .toString())[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_data!['seller_name'] ?? 'Shop',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(_data!['reference'] ?? '',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600)),
                                  Text(_fmt(_data!['created_at'] as String?),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Items',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ...(_data!['orders'] as List).map((o) {
                        final item =
                            (o['item_sle'] as num?)?.toDouble() ?? 0.0;
                        final del =
                            (o['delivery_sle'] as num?)?.toDouble() ?? 0.0;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(o['product_title'].toString()),
                            subtitle: Text(
                                'Item SLE ${item.toStringAsFixed(2)} - Delivery SLE ${del.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Text(
                                'SLE ${(item + del).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 20,
                                offset: Offset(0, 8)),
                          ],
                        ),
                        child: Builder(builder: (context) {
                          var items = 0.0;
                          var delivery = 0.0;
                          for (final o in (_data!['orders'] as List)) {
                            items +=
                                (o['item_sle'] as num?)?.toDouble() ?? 0;
                            delivery +=
                                (o['delivery_sle'] as num?)?.toDouble() ?? 0;
                          }
                          return Column(
                            children: [
                              _moneyRow('Subtotal', items, kNyqInk),
                              _moneyRow('Delivery', delivery, kNyqInk),
                              const Divider(height: 20),
                              _moneyRow('Total paid', items + delivery,
                                  kNyqInk,
                                  bold: true),
                              _moneyRow('Your net', items, kNyqGreen,
                                  bold: true),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class InvoicesScreen extends StatefulWidget {
  final bool isAdmin;
  final bool embedded;
  const InvoicesScreen({super.key, required this.isAdmin, this.embedded = false});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<dynamic> _invoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = widget.isAdmin
        ? await UserSession.getAllInvoices()
        : await UserSession.getMyInvoices();
    if (!mounted) return;
    setState(() {
      _invoices = data;
      _loading = false;
    });
  }

  Future<void> _generateReceipt() async {
    final user = await UserSession.load();
    final token = user?['token'];
    if (token == null) return;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/invoices/generate'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      var msg = 'Could not create receipt';
      if (ok) {
        final data = jsonDecode(res.body);
        msg = 'Receipt ${data['reference']} created';
      } else {
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {
        showNetworkError(context, 'invoices');
      }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? kNyqGreen : Colors.red.shade800,
      ));
      if (ok) _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    }
  }

  Future<void> _showGenerateDialog() async {
    final phoneController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the seller phone number. The invoice will include all their unsettled orders.'),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Seller Phone',
                hintText: '+23278839002',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, normalisePhone(phoneController.text)),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final err = await UserSession.generateInvoice(result);
    if (!mounted) return;
    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice generated')));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = _buildInner(context);
    if (!widget.embedded) return scaffold;
    return scaffold.body ?? const SizedBox.shrink();
  }

  Scaffold _buildInner(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All Invoices' : 'My Invoices'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No receipts yet',
                  message: 'Receipts appear here once customers have paid.',
                )
              : ListView.builder(
                  itemCount: _invoices.length,
                  itemBuilder: (ctx, i) {
                    final inv = _invoices[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: ListTile(
                        title: Text(inv['reference'] ?? 'Invoice'),
                        subtitle: Text(widget.isAdmin
                            ? '${inv['seller_name'] ?? ''} | ${inv['status'] ?? ''}'
                            : '${inv['status'] ?? ''}'),
                        trailing: Text('SLE ${(inv['total_sle'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                              invoiceId: (inv['id'] as num).toInt(),
                              isAdmin: widget.isAdmin,
                            ),
                          ),
                        ).then((_) => _load()),
                      ),
                    );
                  },
                ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: kNyqAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Generate Invoice'),
              onPressed: _showGenerateDialog,
            )
          : FloatingActionButton.extended(
              backgroundColor: kNyqGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.receipt_long),
              label: const Text('New Receipt'),
              onPressed: _generateReceipt,
            ),
    );
  }
}

class EditableAvatar extends StatefulWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  final Color backgroundColor;
  final VoidCallback? onChanged;

  const EditableAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 32,
    this.backgroundColor = Colors.white24,
    this.onChanged,
  });

  @override
  State<EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<EditableAvatar> {
  String? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.photoUrl;
  }

  @override
  void didUpdateWidget(covariant EditableAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) _photo = widget.photoUrl;
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    final url = await pickAndUploadImage(context);
    if (url != null) {
      final ok = await UserSession.update({'photo_url': url});
      if (ok && mounted) setState(() => _photo = url);
      if (ok) widget.onChanged?.call();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photo != null && _photo!.isNotEmpty;
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim()[0].toUpperCase();
    return GestureDetector(
      onTap: _pick,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: widget.backgroundColor,
            backgroundImage: hasPhoto ? NetworkImage(_photo!) : null,
            child: hasPhoto
                ? null
                : Text(initial,
                    style: TextStyle(
                        fontSize: widget.radius * 0.62,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 4),
                ],
              ),
              child: Icon(Icons.photo_camera,
                  size: widget.radius * 0.32, color: kNyqAccent),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: CircleAvatar(
                backgroundColor: Colors.black38,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;
  final VoidCallback? onOpenJobs;
  final VoidCallback? onGoShopping;

  const ProfileScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
    this.onOpenJobs,
    this.onGoShopping,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<dynamic> _deliveries = [];
  List<dynamic> _orders = [];
  List<dynamic> _companies = [];
  String _vehicleType = 'Motorbike';
  bool _isOnline = false;
  bool _isWorker = false;

  /// Re-reads the user from the server so cached role flags never go stale.
  Future<void> _refreshRoles() async {
    try {
      final user = await UserSession.load();
      final token = (user?['token'] ?? '').toString();
      if (token.isEmpty) return;
      final res = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final fresh = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        await UserSession.save(fresh, token);
        if (mounted) widget.onUserChanged();
      }
    } catch (_) {}
  }

  Future<void> _loadKycBadge() async {
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/kyc/mine'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        var employerRequests = 0;
        var approvedPlatform = false;
        var submittedPlatform = false;
        DateTime? expiry;
        for (final raw in list) {
          final m = Map<String, dynamic>.from(raw as Map);
          final st = (m['status'] ?? '').toString();
          if (m['company_id'] == null) {
            if (st == 'approved') {
              approvedPlatform = true;
              final e = m['expiry_date']?.toString();
              if (e != null && e.isNotEmpty) expiry = DateTime.tryParse(e);
            }
            if (st == 'submitted') submittedPlatform = true;
          } else if (st == 'requested') {
            employerRequests++;
          }
        }
        if (mounted) {
          setState(() {
            _kycRequests = employerRequests;
            _platformKyc = approvedPlatform
                ? 'approved'
                : (submittedPlatform ? 'submitted' : 'none');
            _platformKycUnderReview =
                approvedPlatform && submittedPlatform;
            _kycExpiry = expiry;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _renewKyc() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const KycUploadScreen(renew: true)),
    );
    _loadKycBadge();
  }

  Future<void> _openKycRequests() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KycRequestsScreen()),
    );
    _loadKycBadge();
  }

  bool get _isSellerUser => isSeller(widget.currentUser);

  /// Only roles that require verification see the KYC cards. A plain
  /// customer can buy without ever uploading an ID.
  /// Flags arrive as int (from the API) or bool (from SharedPreferences),
  /// so never compare against a single type.
  bool _flag(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

  bool get _kycExpiringSoon {
    final e = _kycExpiry;
    if (e == null) return false;
    return e.difference(DateTime.now()).inDays <= 30;
  }

  bool get _isPrivileged =>
      _flag(widget.currentUser?['is_seller']) ||
      _flag(widget.currentUser?['is_runner']) ||
      _flag(widget.currentUser?['is_company_manager']) ||
      _flag(widget.currentUser?['is_admin']);

  String? get _pendingRole {
    final v = (widget.currentUser?['pending_role'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  Widget _pendingCard(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, color: Colors.grey.shade500),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.grey.shade600)),
                  Text('NYG Support is reviewing your application',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      );
  bool get _isRunnerUser => isRunner(widget.currentUser);

  List<dynamic> _shops = [];
  int _kycRequests = 0;
  String _platformKyc = 'none';
  DateTime? _kycExpiry;
  bool _platformKycUnderReview = false;

  @override
  void initState() {
    super.initState();
    final u = widget.currentUser;
    if (u != null) {
      _vehicleType = (u['vehicle_type'] ?? 'Motorbike').toString();
      _isOnline = u['is_online'] == 1 || u['is_online'] == true;
      _isWorker = isRunner(u);
    }
    _load();
    _loadKycBadge();
    _refreshRoles();
    // Pull fresh roles from the server so admin approvals show up immediately.
    widget.onUserChanged();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final u = widget.currentUser;
    if (u == null) return;
    setState(() {
      _isWorker = isRunner(u);
      _isOnline = u['is_online'] == 1 || u['is_online'] == true;
      _vehicleType = (u['vehicle_type'] ?? 'Motorbike').toString();
    });
    _load();
  }


  Future<void> _saveRunnerSetting(
      Map<String, dynamic> patch, String successMessage) async {
    final ok = await UserSession.update(patch);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: kNyqGreen,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onUserChanged();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Could not save your settings'),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _saveRunnerSetting(patch, successMessage),
        ),
      ),
    );
  }

  Future<void> _load() async {
    await _loadDeliveries();
    await _loadShops();
    await _loadOrders();
    await _loadCompanies();
  }

  Future<void> _registerCompany() async {
    final nameCtl = TextEditingController();
    bool? kycOk;
    var industry = 'Logistics';
    const industries = [
      'Logistics', 'Cleaning', 'Construction', 'Retail',
      'Food & Catering', 'Transport', 'Beauty', 'Professional Services', 'Other',
    ];
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Register a Company'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                      labelText: 'Company Name',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: industry,
                  decoration: const InputDecoration(
                      labelText: 'Industry / Service Type',
                      border: OutlineInputBorder()),
                  items: industries
                      .map((i) =>
                          DropdownMenuItem(value: i, child: Text(i)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => industry = v);
                  },
                ),
                const SizedBox(height: 10),
                KycGate(
                    onChanged: (v) => setDialogState(() => kycOk = v)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: (saving || kycOk != true)
                  ? null
                  : () async {
                      if (nameCtl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter the company name')),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final user = await UserSession.load();
                        final res = await http.post(
                          Uri.parse('$baseUrl/companies/apply'),
                          headers: {
                            'x-api-key': apiKey,
                            'Authorization': 'Bearer ${user?['token'] ?? ''}',
                            'Content-Type': 'application/json',
                          },
                          body: jsonEncode({
                            'name': nameCtl.text.trim(),
                            'industry': industry,
                          }),
                        ).timeout(const Duration(seconds: 10));
                        if (!dialogCtx.mounted) return;
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  (widget.currentUser?['is_company_manager'] ??
                                              0) ==
                                          1
                                      ? 'Company created.'
                                      : 'Company application sent to Admin.'),
                              backgroundColor: kNyqGreen,
                            ),
                          );
                          _load();
                        } else {
                          setDialogState(() => saving = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Could not submit application'),
                                backgroundColor: Colors.red),
                          );
                        }
                      } catch (_) {
                        if (!dialogCtx.mounted) return;
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Network error')),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCompanies() async {
    final user = await UserSession.load();
    if (user?['token'] == null) return;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/companies/my-companies'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user!['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) setState(() => _companies = list);
      }
    } catch (_) {
        showNetworkError(context, 'company details');
      }
  }

  Future<void> _loadOrders() async {
    final user = await UserSession.load();
    if (user == null) return;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/orders/customer/${user['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) setState(() => _orders = list);
        return;
      }
    } catch (_) {
        showNetworkError(context, 'your orders');
      }
    if (mounted) setState(() => _orders = []);
  }

  Future<void> _loadShops() async {
    if (!_isSellerUser) return;
    final user = await UserSession.load();
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/shops/'),
            headers: {
              'x-api-key': apiKey,
              if (user?['token'] != null)
                'Authorization': 'Bearer ${user!['token']}',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final all = jsonDecode(res.body) as List;
        final mine = all
            .where((s) => (s['my_role'] ?? '').toString() == 'owner')
            .toList();
        if (mounted) setState(() => _shops = mine);
        return;
      }
    } catch (_) {
        showNetworkError(context, 'shops');
      }
    if (mounted) setState(() => _shops = []);
  }

  Future<void> _loadDeliveries() async {
    if (!_isRunnerUser) return;
    final user = await UserSession.load();
    if (user == null) return;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/deliveries/mine/${user['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _deliveries = jsonDecode(res.body) as List;
      }
    } catch (_) {
        showNetworkError(context, 'shops');
      }
  }

  int get _completed {
    var n = 0;
    for (final d in _deliveries) {
      if (d['delivered_by_runner_at'] != null) n++;
    }
    return n;
  }

  String get _earned {
    var total = 0.0;
    for (final d in _deliveries) {
      final v = d['runner_fee_sle'];
      if (v is num) total += v.toDouble();
    }
    return total.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    final name = user?['name']?.toString() ?? 'Guest';
    final phone = user?['phone_number']?.toString() ?? '';
    final photo = user?['photo_url']?.toString() ?? '';

    if (user == null) {
      return Scaffold(
        backgroundColor: kNyqSand,
        appBar: AppBar(
          title: const Text('My Profile'),
          backgroundColor: kNyqSand,
          surfaceTintColor: kNyqSand,
          foregroundColor: kNyqInk,
          elevation: 0,
        ),
        body: EmptyState(
          icon: Icons.person_outline,
          title: 'Welcome to NYG',
          message: 'Please sign in to view your profile.',
          actionLabel: 'Sign In',
          onAction: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuthScreen()),
            );
            widget.onUserChanged();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: kNyqSand,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                  20,
                  24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kNyqAccent, kNyqAccentDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  EditableAvatar(
                    photoUrl: photo,
                    name: name,
                    radius: 46,
                    backgroundColor: Colors.white24,
                    onChanged: widget.onUserChanged,
                  ),
                  const SizedBox(height: 14),
                  Text(name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(phone,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70)),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            currentUser: user,
                            onUserChanged: widget.onUserChanged,
                          ),
                        ),
                      );
                      widget.onUserChanged();
                      _load();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            if (_isSellerUser) ...[
              Row(
                children: [
                  _statCard('${_shops.length}', 'My Shops', kNyqAccent),
                  const SizedBox(width: 10),
                  _statCard('$_totalProducts', 'Products', kNyqGreen),
                  const SizedBox(width: 10),
                  _statCard('SLE $_earned', 'Earnings', kNyqOchre),
                ],
              ),
            ],
            if (widget.currentUser?['is_admin'] == 1 ||
                widget.currentUser?['is_admin'] == true) ...[
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kNyqAccent, kNyqAccentDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: kNyqAccent.withAlpha(60),
                        blurRadius: 20,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading: const Icon(Icons.admin_panel_settings,
                      color: Colors.white),
                  title: const Text('Admin Dashboard',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  subtitle: const Text('Users, invoices and overview',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminDashboardScreen()),
                  ),
                ),
              ),
            ],
            if (_kycRequests > 0) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading:
                      const Icon(Icons.badge_outlined, color: Colors.red),
                  title: const Text('Action Required',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  subtitle: Text(
                    _kycRequests == 1
                        ? 'Upload your ID for your employer'
                        : 'Upload your ID ($_kycRequests requests)',
                    style:
                        TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.red, size: 18),
                  onTap: _openKycRequests,
                ),
              ),
            ],
            if (_isPrivileged && _platformKyc == 'approved') ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: (_kycExpiringSoon ? kNyqOchre : kNyqGreen)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: (_kycExpiringSoon ? kNyqOchre : kNyqGreen)
                          .withValues(alpha: 0.35)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      leading: Icon(
                          _kycExpiringSoon
                              ? Icons.warning_amber_rounded
                              : Icons.verified,
                          color: _kycExpiringSoon ? kNyqOchre : kNyqGreen),
                      title: Text(
                          _kycExpiringSoon
                              ? 'ID Expiring Soon'
                              : 'Identity Verified',
                          style: TextStyle(
                              color: _kycExpiringSoon
                                  ? kNyqOchre
                                  : kNyqGreen,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      subtitle: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 22),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _renewKyc,
                        child: const Text('Update ID',
                            style: TextStyle(
                                fontSize: 12, color: kNyqAccent)),
                      ),
                    ),
                    if (_kycExpiringSoon)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 0, 16, 10),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 12, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                                'Expires in ${_kycExpiry!.difference(DateTime.now()).inDays} days',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade900)),
                          ],
                        ),
                      ),
                    if (_platformKycUnderReview)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 0, 16, 10),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top,
                                size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text('New ID under review',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (_isPrivileged && _platformKyc == 'submitted') ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading: Icon(Icons.hourglass_top,
                      color: Colors.grey.shade700),
                  title: Text('ID under review',
                      style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  subtitle: Text(
                      'NYG Support is checking your identity document.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ),
              ),
            ] else if (_isPrivileged && _platformKyc == 'none') ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading:
                      const Icon(Icons.badge_outlined, color: Colors.red),
                  title: const Text('Identity Verification Required',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  subtitle: Text(
                    'Upload your ID to verify your business and unlock all features.',
                    style:
                        TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.red, size: 18),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const KycUploadScreen()),
                    );
                    _loadKycBadge();
                  },
                ),
              ),
            ],
            if (!_isSellerUser && !_isRunnerUser) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kNyqAccent, kNyqAccentDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: kNyqAccent.withAlpha(70),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.waving_hand_outlined,
                        color: Colors.white, size: 26),
                    const SizedBox(height: 8),
                    const Text('Welcome to Na You Get',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                        'Discover shops and products across Sierra Leone.',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kNyqAccent),
                      onPressed: widget.onGoShopping ??
                          () => Navigator.pop(context),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                      label: const Text('Start Shopping'),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.currentUser != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 10)),
                  ],
                ),
                child: _isWorker
                    ? ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.work, color: kNyqGreen),
                        title: const Text('Available Jobs'),
                        subtitle: const Text(
                            'Status: Approved Job Worker - see jobs you can accept'),
                        trailing: const Icon(Icons.chevron_right,
                            size: 18, color: Color(0xFFB0A89F)),
                        onTap: () {
                          if (widget.onOpenJobs != null) {
                            widget.onOpenJobs!();
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RunnerDashboardScreen(
                                  currentUser: widget.currentUser,
                                  onUserChanged: widget.onUserChanged,
                                ),
                              ),
                            );
                          }
                        },
                      )
                    : _pendingRole == 'runner'
                        ? _pendingCard('Worker Application Pending...')
                        : ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.work_outline,
                            color: kNyqAccent),
                        title: const Text('Apply to be a Job Worker'),
                        subtitle:
                            const Text('Deliver and earn on your schedule'),
                        trailing: const Icon(Icons.chevron_right,
                            size: 18, color: Color(0xFFB0A89F)),
                        onTap: () => showWorkerApplicationDialog(
                            context, widget.currentUser!,
                            onDone: widget.onUserChanged),
                      ),
              ),
            ],
            if (widget.currentUser != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.business, size: 18, color: kNyqAccent),
                  const SizedBox(width: 6),
                  const Text('My Companies',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              if (_companies.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEFE9E0)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_empty,
                          size: 18, color: Colors.grey.shade400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'No companies yet. Register one below - NYG Support reviews every application.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ),
                    ],
                  ),
                )
              else
                ..._companies.map((c) {
                  final company = Map<String, dynamic>.from(c as Map);
                  final staff = company['employee_count'] ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEFE9E0)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: kNyqAccent,
                        child: Text(
                            (company['name'] ?? 'C')
                                .toString()
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text((company['name'] ?? '').toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                          '${company['industry'] ?? ''} - $staff staff',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: Color(0xFFB0A89F)),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CompanyManagementScreen(
                              company: company,
                              currentUser: widget.currentUser,
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  );
                }),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEFE9E0)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  leading:
                      const Icon(Icons.add_business, color: kNyqGreen),
                  title: const Text('Register New Company',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text('Apply to run a business on NYG',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: _registerCompany,
                ),
              ),
            ],
            if (widget.currentUser != null && !_isSellerUser) ...[
              const SizedBox(height: 12),
              if (_pendingRole == 'seller')
                _pendingCard('Seller Application Pending...')
              else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 10)),
                  ],
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront, color: kNyqGreen),
                  title: const Text('Apply to be a Seller'),
                  subtitle: const Text('Tell us about your business'),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFFB0A89F)),
                  onTap: () => showSellerApplicationDialog(
                            context, widget.currentUser!,
                            onDone: widget.onUserChanged),
                ),
              ),
            ],
            if (_isRunnerUser) ...[
              const SizedBox(height: 32),
              const Text('Delivery stats',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statBox('${_deliveries.length}', 'Deliveries'),
                  const SizedBox(width: 10),
                  _statBox('$_completed', 'Completed'),
                  const SizedBox(width: 10),
                  _statBox('SLE $_earned', 'Earned'),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Job Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Vehicle Type',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _vehicleType,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                                value: 'Motorbike', child: Text('Motorbike')),
                            DropdownMenuItem(
                                value: 'Bicycle', child: Text('Bicycle')),
                            DropdownMenuItem(value: 'Car', child: Text('Car')),
                            DropdownMenuItem(
                                value: 'On Foot', child: Text('On Foot')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _vehicleType = v);
                            _saveRunnerSetting(
                                {'vehicle_type': v}, 'Vehicle: $v');
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Available for Deliveries'),
                      subtitle: Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: _isOnline
                              ? const Color(0xFF1B5E20)
                              : Colors.grey.shade600,
                        ),
                      ),
                      value: _isOnline,
                      onChanged: (v) {
                        setState(() => _isOnline = v);
                        _saveRunnerSetting(
                            {'is_online': v ? 1 : 0},
                            v ? 'You are now Online' : 'You are now Offline');
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (_isSellerUser) ...[
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Shops',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              if (_shops.isEmpty)
                EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'No shops yet',
                  message:
                      'Open your first storefront and start selling.',
                  actionLabel: 'Add New Shop',
                  onAction: _createShop,
                )
              else
                ..._shops.map((s) {
                  final shopMap = Map<String, dynamic>.from(s as Map);
                  final theme =
                      parseThemeColour(shopMap['theme_colour']?.toString());
                  final dark =
                      ThemeData.estimateBrightnessForColor(theme) ==
                          Brightness.dark;
                  final logo = shopMap['logo_url']?.toString() ?? '';
                  final title = (shopMap['shop_name'] ?? 'Shop').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x1A5A3A28),
                            blurRadius: 16,
                            offset: Offset(0, 6)),
                      ],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white24,
                        backgroundImage:
                            logo.isNotEmpty ? NetworkImage(logo) : null,
                        child: logo.isNotEmpty
                            ? null
                            : Text(
                                title.isEmpty
                                    ? '?'
                                    : title[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: dark ? Colors.white : Colors.black87),
                      ),
                      subtitle: Text(
                        '${shopMap['product_count'] ?? 0} products',
                        style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.white70 : Colors.black54),
                      ),
                      trailing: Icon(Icons.edit_outlined,
                          color: dark ? Colors.white : Colors.black87),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShopManagementScreen(
                            shop: shopMap,
                            currentUser: widget.currentUser,
                            onUserChanged: widget.onUserChanged,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              if (_shops.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kNyqAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _createShop,
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('Add New Shop'),
                ),
              ),
            ],
            if (widget.currentUser != null &&
                !_isSellerUser &&
                !_isRunnerUser) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.receipt_long, size: 18, color: kNyqAccent),
                  const SizedBox(width: 6),
                  const Text('My Orders',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (_orders.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyOrdersScreen(
                              currentUser: widget.currentUser!),
                        ),
                      ),
                      child: const Text('See all'),
                    ),
                ],
              ),
              if (_orders.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: "You haven't placed any orders yet.",
                )
              else
                ..._orders.take(3).map((o) {
                  final order = Map<String, dynamic>.from(o as Map);
                  final total = ((order['price_sle'] ?? 0) as num) +
                      ((order['delivery_fee_sle'] ?? 0) as num);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEFE9E0)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => showOrderDetails(context, order),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (order['product_title'] ?? 'Order')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'SLE ${total.toStringAsFixed(0)} - '
                                    '${order['delivery_status'] ?? 'pending'}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 18, color: Color(0xFFB0A89F)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
            if (widget.currentUser != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign Out',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    await UserSession.clear();
                    await ShopSession.clear();
                    widget.onUserChanged();
                  },
                ),
              ),
            ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createShop() async {
    final nameCtl = TextEditingController();
    final ownerCtl = TextEditingController(
        text: (widget.currentUser?['name'] ?? '').toString());
    final phoneCtl = TextEditingController(
        text: (widget.currentUser?['phone_number'] ?? '+232').toString());
    final cityCtl = TextEditingController(text: 'Freetown');
    double? shopLat;
    double? shopLng;
    var category = 'Fashion';
    const categories = [
      'Fashion',
      'Food',
      'Electronics',
      'Home',
      'Beauty',
      'Services',
      'Other',
    ];

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Shop'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                      labelText: 'Shop Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ownerCtl,
                  decoration: const InputDecoration(
                      labelText: 'Owner Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cityCtl,
                  decoration: const InputDecoration(
                      labelText: 'Shop Address (Optional)',
                      hintText: 'Leave blank if you set a map pin',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                      labelText: 'Category', border: OutlineInputBorder()),
                  items: categories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kNyqSand,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0DAD2)),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 110,
                        child: shopLat == null || shopLng == null
                            ? Center(
                                child: Text(
                                  'A map pin is required so customers can find you',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: LatLng(shopLat!, shopLng!),
                                    initialZoom: 15,
                                    interactionOptions:
                                        const InteractionOptions(
                                            flags: InteractiveFlag.none),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: kOsmTileUrl,
                                      userAgentPackageName: 'com.nyg.app',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: LatLng(shopLat!, shopLng!),
                                          width: 28,
                                          height: 28,
                                          child: const Icon(Icons.location_on,
                                              size: 28, color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: Text(shopLat == null
                              ? 'Pick Location on Map'
                              : 'Change Location'),
                          onPressed: () async {
                            final picked = await Navigator.push<LatLng>(
                              ctx,
                              MaterialPageRoute(
                                builder: (_) => ShopLocationPickerScreen(
                                  initial: shopLat != null && shopLng != null
                                      ? LatLng(shopLat!, shopLng!)
                                      : null,
                                ),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                shopLat = picked.latitude;
                                shopLng = picked.longitude;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) return;
                if (shopLat == null || shopLng == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Please set your shop location on the map so customers can find you.')),
                  );
                  return;
                }
                final user = await UserSession.load();
                final token = user?['token'];
                if (token == null) return;
                var ok = false;
                try {
                  final res = await http
                      .post(
                        Uri.parse('$baseUrl/merchants/'),
                        headers: {
                          'Content-Type': 'application/json',
                          'x-api-key': apiKey,
                          'Authorization': 'Bearer $token',
                        },
                        body: jsonEncode({
                          'shop_name': nameCtl.text.trim(),
                          'owner_name': ownerCtl.text.trim(),
                          'phone_number': phoneCtl.text.trim(),
                          'city': cityCtl.text.trim().isEmpty
                              ? null
                              : cityCtl.text.trim(),
                          'latitude': shopLat,
                          'longitude': shopLng,
                          'category': category,
                          'theme_colour': '#0D47A1',
                          'background_colour': '#FFFFFF',
                        }),
                      )
                      .timeout(const Duration(seconds: 12));
                  ok = res.statusCode >= 200 && res.statusCode < 300;
                } catch (_) {
                  ok = false;
                }
                if (ctx.mounted) Navigator.pop(ctx, ok);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameCtl.dispose();
    ownerCtl.dispose();
    phoneCtl.dispose();
    cityCtl.dispose();
    if (created == true) {
      await _loadShops();
    }
  }
  int get _totalProducts => _shops.fold<int>(
      0,
      (sum, s) =>
          sum +
          (((Map<String, dynamic>.from(s as Map))['product_count'] as num?)
                      ?.toInt() ??
              0));

  Widget _statCard(String value, String label, Color colour) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          children: [
            Container(
                width: 22,
                height: 3,
                decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kNyqInk)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// HELP & GUIDE
// ==========================================
class HelpFaq {
  final IconData icon;
  final String title;
  final List<String> points;
  const HelpFaq(this.icon, this.title, this.points);
}

const List<HelpFaq> kHelpCustomer = [
  HelpFaq(Icons.search, 'Finding a shop', [
    'Shopping lists every product. Marketplace lists every shop.',
    'Tap Map on the Marketplace to see shops near you, then tap a pin.',
    'Use the city filter to narrow the list.',
  ]),
  HelpFaq(Icons.handshake_outlined, 'Haggling', [
    'Tap Negotiate on a product to chat with the seller.',
    'Tap the handshake icon in the chat to send a price offer.',
    'If the seller accepts, your checkout price locks to it.',
  ]),
  HelpFaq(Icons.shopping_cart_checkout, 'Paying', [
    'Buy Now goes straight to checkout at the listed price.',
    'Pay the shop by Mobile Money, and the worker in cash on delivery.',
    'You do not need an ID to buy.',
  ]),
  HelpFaq(Icons.receipt_long, 'Tracking an order', [
    'Open My Orders from the account menu.',
    'Every status change is visible there.',
  ]),
];

const List<HelpFaq> kHelpSeller = [
  HelpFaq(Icons.add_business_outlined, 'Adding products', [
    'Open My Shops, then Manage Products to add or edit items.',
    'Set your shop location so buyers can find you on the map.',
  ]),
  HelpFaq(Icons.handshake_outlined, 'Prices and orders', [
    'Buyers can send price offers in chat. Accept or decline them there.',
    'Orders appear under Manage Shop. A price below your listing needs your approval.',
  ]),
  HelpFaq(Icons.groups_outlined, 'Employees', [
    'Add staff with a phone number, salary and role.',
    'Share the temporary password so they can sign in and set their own.',
    'Staff can clock in and out, and you share a team chat.',
  ]),
  HelpFaq(Icons.local_shipping_outlined, 'Shipments', [
    'Create a shipment and list what was sent from abroad.',
    'Request delivery to bring it from the port to your shop.',
  ]),
];

const List<HelpFaq> kHelpWorker = [
  HelpFaq(Icons.toggle_on_outlined, 'Going online', [
    'Toggle online from your Profile to receive jobs.',
    'You only see jobs while you are online.',
  ]),
  HelpFaq(Icons.delivery_dining_outlined, 'Accepting jobs', [
    'Available deliveries show on your board with the fee and address.',
    'Accept one, collect the item, then mark it delivered.',
  ]),
  HelpFaq(Icons.payments_outlined, 'Fees and payment', [
    'Chat with the buyer if you want to discuss the fee first.',
    'You are paid in cash on delivery.',
  ]),
];

const List<HelpFaq> kHelpAdmin = [
  HelpFaq(Icons.people_outline, 'Users and roles', [
    'Grant or remove seller, worker and company manager roles.',
    'Suspend accounts that break the rules.',
  ]),
  HelpFaq(Icons.badge_outlined, 'KYC review', [
    'Submitted IDs appear in the KYC tab.',
    'Approve or reject with a reason. Only approved IDs unlock applications.',
  ]),
  HelpFaq(Icons.business_outlined, 'Companies', [
    'Approve company applications before they can trade.',
    'You cannot see company payroll - that stays with the owner.',
  ]),
  HelpFaq(Icons.receipt_long, 'Invoices', [
    'Generate invoices and mark NYG commission as received.',
  ]),
];

class _HelpSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> points;
  const _HelpSection(
      {required this.icon, required this.title, required this.points});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: Icon(icon, color: kNyqAccent),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        shape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: points
            .map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('- ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(p,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.grey.shade800)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class HelpGuideScreen extends StatelessWidget {
  final Map<String, dynamic>? currentUser;
  const HelpGuideScreen({super.key, this.currentUser});

  @override
  Widget build(BuildContext context) {
    final roles = userRoles(currentUser);
    final isAdmin = roles.contains('admin');
    final showSeller = isAdmin || roles.contains('seller');
    final showWorker = isAdmin || roles.contains('worker');

    final tabs = <String>[
      'Customer',
      if (showSeller) 'Seller',
      if (showWorker) 'Worker',
      if (isAdmin) 'Admin',
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: kNyqSand,
        appBar: AppBar(
          title: const Text('Help & Guide'),
          backgroundColor: kNyqAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        body: TabBarView(
          children: [
            _helpTab(kHelpCustomer),
            if (showSeller) _helpTab(kHelpSeller),
            if (showWorker) _helpTab(kHelpWorker),
            if (isAdmin) _helpTab(kHelpAdmin),
          ],
        ),
      ),
    );
  }

  Widget _helpTab(List<HelpFaq> items) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...items.map((f) =>
              _HelpSection(icon: f.icon, title: f.title, points: f.points)),
          Text('Na You Get - Small Business OS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 20),
        ],
      );
}

class ChangePasswordScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final VoidCallback onDone;
  const ChangePasswordScreen(
      {super.key, required this.currentUser, required this.onDone});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pass.text;
    if (p.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (p != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final user = await UserSession.load();
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/auth/me/password'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
        body: jsonEncode(
            {'current_password': 'guest123', 'new_password': p}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_must_change_password', false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password updated'),
              backgroundColor: kNyqGreen),
        );
        widget.onDone();
        return;
      }
      String msg = 'Could not update password';
      try {
        msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
      } catch (_) {
        showNetworkError(context, 'your account');
      }
      setState(() {
        _error = msg;
        _saving = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kNyqSand,
        appBar: AppBar(
          title: const Text('Set Your Password'),
          backgroundColor: kNyqAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_reset, size: 56, color: kNyqAccent),
                const SizedBox(height: 12),
                Text(
                  'Welcome, ${widget.currentUser['name'] ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your account was created for you. Choose your own password to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kNyqGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Password',
                            style: TextStyle(fontWeight: FontWeight.w700)),
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

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  Map<String, dynamic>? _currentUser;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/version'));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final latest = data['version']?.toString() ?? appVersion;
        if (latest != appVersion) {
          if (!mounted) return;
          _showUpdateDialog(latest);
        }
      }
    } catch (_) {
        showNetworkError(context, 'data');
      }
  }

  void _showUpdateDialog(String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'A new version of Na You Get is available ($latestVersion). '
          'Please update to get the latest features and fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(apkDownloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUser() async {
    final user = await UserSession.load();
    if (user != null) {
      await _syncShopSession(user);
    }
    if (mounted) {
      setState(() {
        _currentUser = user;
        _loadingUser = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRoleOnboarding(context, _currentUser);
      });
    }
  }

  Future<void> _syncShopSession(Map<String, dynamic> user) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/shops/')).timeout(const Duration(seconds: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final shops = jsonDecode(res.body) as List;
      final phone = normalisePhone(user['phone_number']?.toString() ?? '');
      final Map<String, dynamic>? mine = shops.firstWhere(
        (s) => normalisePhone(s['phone_number']?.toString() ?? '') == phone,
        orElse: () => null,
      );

      if (mine != null) {
        await ShopSession.save(mine);
      }
    } catch (_) {
        showNetworkError(context, 'shops');
      }
  }

  Future<void> _refreshUser() async {
    final cached = await UserSession.load();
    final token = cached?['token'];
    if (token != null) {
      try {
        final res = await http.get(
          Uri.parse('$baseUrl/auth/me'),
          headers: {
            'x-api-key': apiKey,
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final fresh = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
          await UserSession.save(fresh, token);
        }
      } catch (_) {
        showNetworkError(context, 'your account');
      }
    }
    await _loadUser();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final mustChangePassword = _currentUser != null &&
        (_currentUser!['must_change_password'] == 1 ||
            _currentUser!['must_change_password'] == true);
    if (mustChangePassword) {
      return ChangePasswordScreen(
        currentUser: _currentUser!,
        onDone: _refreshUser,
      );
    }


    final screens = <Widget>[
      MarketplaceScreen(currentUser: _currentUser, onUserChanged: _refreshUser),
      MarketplaceLocationsScreen(
          currentUser: _currentUser,
          onUserChanged: _refreshUser,
          onGoShopping: () => setState(() => _currentIndex = 0)),
      ProfileScreen(
          currentUser: _currentUser,
          onUserChanged: _refreshUser,
          onOpenJobs: null,
          onGoShopping: () => setState(() => _currentIndex = 0)),
    ];

    // Clamp in case someone loses the worker role while on the Jobs tab.
    final safeIndex = _currentIndex >= screens.length ? 0 : _currentIndex;

    return Stack(
      children: [
        PopScope(
          canPop: safeIndex == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            setState(() => _currentIndex = 0);
          },
          child: Scaffold(
      body: KenteBackground(
        child: IndexedStack(index: safeIndex, children: screens),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            elevation: 8,
            backgroundColor: Colors.white,
            shadowColor: const Color(0x33000000),
        selectedIndex: safeIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag),
              label: 'Shopping'),

          const NavigationDestination(
              icon: Icon(Icons.location_on_outlined),
              selectedIcon: Icon(Icons.location_on),
              label: 'Marketplace'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
          ),
        ),
        ),
        ),
        ),

      ],
    );
  }
}

// ==========================================
// REUSABLE: SHOP PRODUCT GRID
// ==========================================
class ProductFeedCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final void Function(dynamic product) onBuy;
  final void Function(dynamic product)? onDelete;
  final void Function(Map<String, dynamic> product)? onOpen;
  final Color? cardColour;
  final Color? accentColour;
  final void Function(Map<String, dynamic> product)? onEdit;

  const ProductFeedCard({
    super.key,
    required this.product,
    required this.onBuy,
    this.onDelete,
    this.onOpen,
    this.cardColour,
    this.accentColour,
    this.onEdit,
  });

  @override
  State<ProductFeedCard> createState() => _ProductFeedCardState();
}

class _ProductFeedCardState extends State<ProductFeedCard> {
  int _page = 0;

  Widget _photoPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text('No photo',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.product;
    final photos = productPhotos(item);
    final description = (item['description'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFE9E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A5A3A28),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onOpen == null ? null : () => widget.onOpen!(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KenteStripe(),
            SizedBox(
              height: 260,
              width: double.infinity,
              child: Stack(
                children: [
                  if (photos.isEmpty)
                    _photoPlaceholder()
                  else
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (ctx, i) => Image.network(
                        photos[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => _photoPlaceholder(),
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(photos.length, (i) {
                          final active = i == _page;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: kNyqInk,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SLE ${item['price_sle']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kNyqAccent,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kNyqAccent,
                                  side: BorderSide(
                                      color: kNyqAccent.withValues(
                                          alpha: 0.45)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                icon: const Icon(
                                    Icons.chat_bubble_outline,
                                    size: 16),
                                label: const Text('Negotiate',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                onPressed: () {
                                  final sid = item['seller_user_id'];
                                  if (sid is num) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          otherUserId: sid.toInt(),
                                          otherUserName:
                                              (item['shop_name'] ??
                                                      'Seller')
                                                  .toString(),
                                          shopId: item['merchant_id'],
                                          productId: (item['id'] as num?)
                                              ?.toInt(),
                                        ),
                                      ),
                                    );
                                  } else if (widget.onOpen != null) {
                                    widget.onOpen!(item);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: kNyqAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.shopping_cart,
                                    size: 16),
                                label: const Text('Buy Now',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                                onPressed: () => widget.onBuy(item),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onEdit != null) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit product',
                          onPressed: () => widget.onEdit!(widget.product),
                        ),
                      ],
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          tooltip: 'Delete product',
                          onPressed: () => widget.onDelete!(item),
                        ),
                      ],
                    ],
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

class KentePainter extends CustomPainter {
  final Color colour;
  final Color accent;
  const KentePainter({this.colour = kNyqAccent, this.accent = kNyqOchre});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = colour.withAlpha(17)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final accentStroke = Paint()
      ..color = accent.withAlpha(22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final bead = Paint()..color = colour.withAlpha(28);

    const step = 56.0;
    int row = 0;
    for (double y = 0; y < size.height + step; y += step) {
      final shift = row.isEven ? 0.0 : step / 2;
      for (double x = -step; x < size.width + step; x += step) {
        final cx = x + shift;
        final diamond = Path()
          ..moveTo(cx, y - 9)
          ..lineTo(cx + 9, y)
          ..lineTo(cx, y + 9)
          ..lineTo(cx - 9, y)
          ..close();
        canvas.drawPath(diamond, row.isEven ? stroke : accentStroke);

        final mx = cx + step / 2;
        final my = y + step / 2;
        canvas.drawLine(Offset(mx - 4, my), Offset(mx + 4, my), accentStroke);
        canvas.drawLine(Offset(mx, my - 4), Offset(mx, my + 4), accentStroke);

        canvas.drawCircle(Offset(cx, my), 1.7, bead);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant KentePainter old) =>
      old.colour != colour || old.accent != accent;
}

class KenteStripe extends StatelessWidget {
  final double height;
  const KenteStripe({super.key, this.height = 7});

  @override
  Widget build(BuildContext context) {
    const colours = [
      kNyqGreen,
      Colors.white,
      kNyqAccent,
      kNyqOchre,
      kNyqAccent,
      Colors.white,
      kNyqGreen,
    ];
    return SizedBox(
      height: height,
      child: Row(
        children: colours
            .map((c) => Expanded(child: Container(color: c)))
            .toList(),
      ),
    );
  }
}

class KenteBackground extends StatelessWidget {
  final Widget child;
  const KenteBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: KentePainter()),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F7F1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: const Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, height: 1.4, color: Colors.grey.shade600),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kNyqGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HexColourField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const HexColourField(
      {super.key, required this.value, required this.onChanged});

  @override
  State<HexColourField> createState() => _HexColourFieldState();
}

class _HexColourFieldState extends State<HexColourField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant HexColourField old) {
    super.didUpdateWidget(old);
    if (widget.value.toUpperCase() != _c.text.toUpperCase()) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    var v = raw.trim().toUpperCase();
    if (!v.startsWith('#')) v = '#$v';
    if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(v)) {
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onSubmitted: _submit,
      onEditingComplete: () => _submit(_c.text),
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Hex',
        hintText: '#C35A3D',
        border: const OutlineInputBorder(),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 24,
            decoration: BoxDecoration(
              color: parseThemeColour(widget.value,
                  fallback: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
        ),
      ),
    );
  }
}

class ShopProductGrid extends StatelessWidget {
  final List<dynamic> products;
  final void Function(dynamic product) onBuy;
  final void Function(dynamic product)? onDelete;
  final VoidCallback? onRefresh;
  final void Function(Map<String, dynamic> product)? onOpen;
  final Color? cardColour;
  final Color? accentColour;
  final void Function(Map<String, dynamic> product)? onEdit;
  final String? emptyActionLabel;
  final VoidCallback? emptyAction;

  const ShopProductGrid({
    super.key,
    required this.products,
    required this.onBuy,
    this.onDelete,
    this.onRefresh,
    this.onOpen,
    this.cardColour,
    this.accentColour,
    this.onEdit,
    this.emptyActionLabel,
    this.emptyAction,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: emptyActionLabel == null
            ? 'Check back soon!'
            : 'Add your first product to start selling.',
        actionLabel: emptyActionLabel,
        onAction: emptyAction,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: products.length,
      itemBuilder: (ctx, i) => ProductFeedCard(
        product: Map<String, dynamic>.from(products[i] as Map),
        onBuy: onBuy,
        onDelete: onDelete,
        onOpen: onOpen,
        onEdit: onEdit,
        cardColour: cardColour,
        accentColour: accentColour,
      ),
    );
  }
}

// ==========================================
// MARKETPLACE LOCATIONS SCREEN
// ==========================================
class MarketplaceLocationsScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;
  final VoidCallback? onGoShopping;

  const MarketplaceLocationsScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
    this.onGoShopping,
  });

  @override
  State<MarketplaceLocationsScreen> createState() =>
      _MarketplaceLocationsScreenState();
}

class _MarketplaceLocationsScreenState extends State<MarketplaceLocationsScreen> {
  List<dynamic> shops = [];
  List<String> cities = [];
  bool isLoading = true;
  bool hasError = false;
  String selectedCity = 'All Cities';
  bool _mapView = false;
  dynamic _selectedShop;

  @override
  void initState() {
    super.initState();
    _fetchShops();
  }

  Future<bool> _ensureLoggedIn({String? suggestedRole}) async {
    if (widget.currentUser != null) return true;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(suggestedRole: suggestedRole),
      ),
    );

    if (result == true) {
      widget.onUserChanged();
      return true;
    }
    return false;
  }

  Future<void> _fetchShops() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/shops/'),
        headers: {'x-api-key': apiKey},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as List;
        final uniqueCities = <String>{};
        for (final s in data) {
          final city = (s['city'] ?? '').toString().trim();
          if (city.isNotEmpty && city != 'null') uniqueCities.add(city);
        }
        final sortedCities = uniqueCities.toList()..sort();
        setState(() {
          shops = data;
          cities = sortedCities;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          hasError = true;
        });
      }
    } catch (_) {
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  List<dynamic> get _filteredShops {
    if (selectedCity == 'All Cities') return shops;
    return shops
        .where((s) => (s['city'] ?? '').toString().trim() == selectedCity)
        .toList();
  }

  void _openShop(Map<String, dynamic> shop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPageScreen(
          shop: shop,
          currentUser: null,
          onUserChanged: () {},
        ),
      ),
    );
  }

  Widget _buildCityDropdown() {
    final items = ['All Cities', ...cities];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: DropdownButtonFormField<String>(
        value: selectedCity,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filter by city',
          prefixIcon: const Icon(Icons.location_on_outlined),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items
            .map((city) => DropdownMenuItem<String>(
                  value: city,
                  child: Text(city),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => selectedCity = value);
        },
      ),
    );
  }

  Widget _buildShopCard(Map<String, dynamic> shop) {
    final logoUrl = shop['logo_url'];
    final name = (shop['shop_name'] ?? 'Shop').toString();
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    final header = parseThemeColour(shop['theme_colour']?.toString());
    final body = parseThemeColour(
      shop['background_colour']?.toString(),
      fallback: Colors.white,
    );
    final headerDark =
        ThemeData.estimateBrightnessForColor(header) == Brightness.dark;
    final bodyDark =
        ThemeData.estimateBrightnessForColor(body) == Brightness.dark;
    final onHeader = headerDark ? Colors.white : Colors.black87;
    final subBody = bodyDark ? Colors.white70 : Colors.black54;
    final hasLogo = logoUrl != null && logoUrl.toString().isNotEmpty;

    return GestureDetector(
      onTap: () => _openShop(shop),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: header,
          borderRadius: BorderRadius.circular(16),
          border: const Border(
            top: BorderSide(color: kNyqAccent, width: 3),
            left: BorderSide(color: Color(0xFFEFE9E0)),
            right: BorderSide(color: Color(0xFFEFE9E0)),
            bottom: BorderSide(color: Color(0xFFEFE9E0)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A5A3A28),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: header,
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          headerDark ? Colors.white24 : Colors.black12,
                      backgroundImage:
                          hasLogo ? NetworkImage(logoUrl.toString()) : null,
                      child: hasLogo
                          ? null
                          : Text(
                              initial,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: onHeader,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: onHeader,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: onHeader),
                  ],
                ),
              ),
              Container(
                color: body,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  '${shop['city'] ?? ''} • ${shop['category'] ?? ''}',
                  style: TextStyle(fontSize: 13, color: subBody),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewToggle(
      String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: active ? kNyqAccent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? kNyqAccent : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: active ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final located = shops
        .map((s) => Map<String, dynamic>.from(s as Map))
        .where((m) => m['latitude'] != null && m['longitude'] != null)
        .toList();
    final missing = shops.length - located.length;

    return Stack(
      children: [
        if (located.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No shops have set a map location yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
          )
        else
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                (located.first['latitude'] as num).toDouble(),
                (located.first['longitude'] as num).toDouble(),
              ),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: kOsmTileUrl,
                userAgentPackageName: 'com.nyg.app',
              ),
              MarkerLayer(
                markers: located.map((s) {
                  final lat = (s['latitude'] as num).toDouble();
                  final lng = (s['longitude'] as num).toDouble();
                  return Marker(
                    point: LatLng(lat, lng),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedShop = s),
                      child: const Icon(Icons.location_on,
                          size: 38, color: kNyqAccent),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        if (missing > 0)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade800.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$missing shop${missing == 1 ? "" : "s"} haven\'t set a location yet.',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        if (_selectedShop != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _shopPreviewCard(
                Map<String, dynamic>.from(_selectedShop as Map)),
          ),
      ],
    );
  }

  Future<void> _openUri(String? raw) async {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return;
    final uri = Uri.tryParse(
        v.startsWith('http') || v.startsWith('tel:') ? v : 'https://' + v);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showNetworkError(context, 'that link');
    }
  }

  Widget _actionIcon(IconData icon, Color colour, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.shade100
              : colour.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 18,
            color: onTap == null ? Colors.grey.shade400 : colour),
      ),
    );
  }

  Widget _shopPreviewCard(Map<String, dynamic> s) {
    final logo = (s['logo_url'] ?? '').toString();
    final name = (s['shop_name'] ?? 'Shop').toString();
    final category = (s['category'] ?? '').toString().trim();
    final hours = (s['opening_hours'] ?? '').toString().trim();
    final phone = (s['phone_number'] ?? '').toString().trim();
    final whatsapp = (s['whatsapp_number'] ?? '').toString().trim();
    final ig = (s['instagram_url'] ?? '').toString().trim();
    final tt = (s['tiktok_url'] ?? '').toString().trim();
    final x = (s['twitter_url'] ?? '').toString().trim();
    final sellerId = s['owner_user_id'];

    final subtitle = [
      if (category.isNotEmpty && category != 'null') category,
      if (hours.isNotEmpty && hours != 'null') hours,
    ].join(' - ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: kNyqAccent,
                backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
                child: logo.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kNyqGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopPageScreen(
                      shop: s,
                      currentUser: null,
                      onUserChanged: widget.onUserChanged,
                    ),
                  ),
                ),
                child: const Text('View Shop', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              _actionIcon(Icons.call, kNyqGreen,
                  phone.isEmpty ? null : () => _openUri('tel:' + phone)),
              const SizedBox(width: 8),
              _actionIcon(
                  Icons.chat_bubble_outline,
                  kNyqAccent,
                  sellerId == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otherUserId: (sellerId as num).toInt(),
                                otherUserName: name,
                                shopId: (s['id'] as num?)?.toInt(),
                              ),
                            ),
                          )),
              const SizedBox(width: 8),
              _actionIcon(
                  Icons.chat,
                  const Color(0xFF25D366),
                  whatsapp.isEmpty
                      ? null
                      : () => _openUri('https://wa.me/' +
                          whatsapp.replaceAll(RegExp(r'[^0-9]'), ''))),
              const SizedBox(width: 8),
              _actionIcon(Icons.camera_alt_outlined, const Color(0xFFE1306C),
                  ig.isEmpty ? null : () => _openUri(ig)),
              const SizedBox(width: 8),
              _actionIcon(Icons.music_note, Colors.black87,
                  tt.isEmpty ? null : () => _openUri(tt)),
              const SizedBox(width: 8),
              _actionIcon(Icons.alternate_email, Colors.black87,
                  x.isEmpty ? null : () => _openUri(x)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Could not load shops.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchShops,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredShops;

    return Column(
      children: [
        _buildCityDropdown(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _viewToggle('List', Icons.view_list, !_mapView,
                    () => setState(() => _mapView = false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _viewToggle('Map', Icons.map_outlined, _mapView,
                    () => setState(() => _mapView = true)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mapView
              ? _buildMapView()
              : filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.store_outlined,
                            size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No shops in this city yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchShops,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _buildShopCard(filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: GestureDetector(
          onTap: widget.onGoShopping,
          child: Image.asset('assets/logo.png', height: 60),
        ),
        actions: [
          AccountButton(
              currentUser: widget.currentUser,
              onUserChanged: widget.onUserChanged,
              ensureLoggedIn: _ensureLoggedIn),
        ],
      ),
      body: _buildBody(),
    );
  }
}



// ==========================================
// SHOP PAGE — PUBLIC VIEW
// ==========================================
class CompanyManagementScreen extends StatefulWidget {
  final Map<String, dynamic> company;
  final Map<String, dynamic>? currentUser;
  const CompanyManagementScreen(
      {super.key, required this.company, this.currentUser});

  @override
  State<CompanyManagementScreen> createState() =>
      _CompanyManagementScreenState();
}

class _CompanyManagementScreenState extends State<CompanyManagementScreen> {
  late Map<String, dynamic> company;
  int _staff = 0;
  int _shops = 0;
  int _pendingShipments = 0;

  @override
  void initState() {
    super.initState();
    company = Map<String, dynamic>.from(widget.company);
    _load();
    fetchIncomingShipmentCount().then((n) {
      if (mounted) setState(() => _pendingShipments = n);
    });
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'x-api-key': apiKey,
      if (user?['token'] != null) 'Authorization': 'Bearer ${user!['token']}',
    };
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/companies/${company['id']}'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final fresh = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        if (mounted) {
          setState(() {
            company = fresh;
            _staff = (fresh['employee_count'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (_) {
        showNetworkError(context, 'company details');
      }

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/shops/'), headers: await _headers())
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final all = jsonDecode(res.body) as List;
        final linked = all
            .where((s) => (s['company_id'] ?? 0) == company['id'])
            .toList();
        if (mounted) setState(() => _shops = linked.length);
      }
    } catch (_) {
        showNetworkError(context, 'shops');
      }
  }

  String get _initial {
    final n = (company['name'] ?? '').toString().trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  Future<void> _openTeamChat() async {
    final user = await UserSession.load();
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/threads/company/${company['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final t = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              threadId: (t['id'] as num).toInt(),
              threadName: (t['name'] ?? 'Team Chat').toString(),
            ),
          ),
        );
        _load();
      }
    } catch (_) {
        showNetworkError(context, 'messages');
      }
  }

  void _info(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color colour) =>
      Expanded(child: ManagementStat(value, label, colour));

  Widget _actionCard(IconData icon, String title, String subtitle,
          VoidCallback onTap) =>
      ManagementActionCard(icon, title, subtitle, onTap);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: Text((company['name'] ?? 'Company').toString()),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: kNyqAccent,
                child: Text(_initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((company['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text((company['industry'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _stat('$_staff', 'Staff', kNyqAccent),
              const SizedBox(width: 8),
              _stat('$_shops', 'Shops', kNyqGreen),
              const SizedBox(width: 8),
              _stat('0', 'Jobs', kNyqOchre),
            ],
          ),
          const SizedBox(height: 20),
          _actionCard(Icons.groups_outlined, 'Manage Employees',
              'Add staff, salaries and clock-in', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmployeeListScreen(company: company),
              ),
            );
            _load();
          }),
          _actionCard(Icons.forum_outlined, 'Team Chat',
              'Group chat with your staff', _openTeamChat),
          _actionCard(Icons.local_shipping_outlined, 'Shipments',
              _pendingShipments > 0
                  ? '$_pendingShipments incoming'
                  : 'Track overseas deliveries', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShipmentListScreen(company: company),
              ),
            );
            fetchIncomingShipmentCount().then((n) {
              if (mounted) setState(() => _pendingShipments = n);
            });
          }),

          _actionCard(Icons.info_outline, 'Company Details',
              'Registration information', () {
            _info(
                'Company Details',
                'Name: ${company['name']}\n'
                    'Industry: ${company['industry']}\n'
                    'Description: ${company['description'] ?? '-'}\n'
                    'Owner: ${company['owner_name'] ?? '-'}\n'
                    'Status: ${((company['is_approved'] ?? 0) == 1) ? 'Approved' : 'Pending'}');
          }),
        ],
      ),
    );
  }
}

class EmployeeListScreen extends StatefulWidget {
  final Map<String, dynamic>? shop;
  final Map<String, dynamic>? company;
  const EmployeeListScreen({super.key, this.shop, this.company})
      : assert(shop != null || company != null);

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  List<dynamic> _employees = [];
  Map<String, String> _kycStatus = {};
  bool _loading = true;

  bool get _isCompany => widget.company != null;
  int get _ownerId =>
      (((_isCompany ? widget.company!['id'] : widget.shop!['id'])) as num)
          .toInt();
  String get _base => _isCompany
      ? '$baseUrl/companies/$_ownerId/employees'
      : '$baseUrl/shops/$_ownerId/employees';
  String get _title =>
      'Employees - ${((_isCompany ? widget.company!['name'] : widget.shop!['shop_name']) ?? '')}';

  Future<void> _loadKycStatus() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/companies/$_ownerId/employees/kyc-status'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        if (mounted) {
          setState(() {
            _kycStatus = d.map((k, v) => MapEntry(k, v.toString()));
          });
        }
      }
    } catch (_) {}
  }

  String _kycLabel(String s) {
    switch (s) {
      case 'submitted':
      case 'approved':
        return 'View ID';
      case 'requested':
        return 'Requested';
      case 'declined':
        return 'Declined';
      case 'no_account':
        return 'No app account';
      default:
        return 'Request ID';
    }
  }

  Color _kycColour(String s) {
    switch (s) {
      case 'submitted':
      case 'approved':
        return kNyqGreen;
      case 'requested':
        return kNyqOchre;
      case 'declined':
        return Colors.red;
      case 'no_account':
        return Colors.grey;
      default:
        return kNyqAccent;
    }
  }

  bool _kycTappable(String s) =>
      s == 'none' || s == 'rejected';

  Future<void> _kycAction(Map<String, dynamic> e) async {
    final empId = (e['id'] as num).toInt();
    final status = _kycStatus[empId.toString()] ?? 'none';
    if (status == 'submitted' || status == 'approved') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => KycViewerScreen(
            companyId: _ownerId,
            employeeId: empId,
            employeeName: (e['name'] ?? 'Employee').toString(),
          ),
        ),
      );
      return;
    }
    if (!_kycTappable(status)) return;

    try {
      final res = await http.post(
        Uri.parse(
            '$baseUrl/companies/$_ownerId/employees/$empId/request-kyc'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ID request sent to employee.'),
              backgroundColor: kNyqGreen),
        );
        _loadKycStatus();
      } else {
        String msg = 'Could not send the request';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'the ID request');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'x-api-key': apiKey,
      if (user?['token'] != null) 'Authorization': 'Bearer ${user!['token']}',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse(_base),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _employees = list;
            _loading = false;
          });
          if (_isCompany) _loadKycStatus();
        }
        return;
      }
    } catch (_) {
        showNetworkError(context, 'employees');
      }
    if (mounted) {
      setState(() {
        _employees = [];
        _loading = false;
      });
    }
  }

  Future<void> _clock(int id, bool clockIn) async {
    try {
      final res = await http.post(
        Uri.parse(
            '$baseUrl/employees/$id/${clockIn ? 'clock-in' : 'clock-out'}'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _load();
        return;
      }
      String msg = 'Could not update';
      try {
        msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
      } catch (_) {
        showNetworkError(context, 'employees');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    }
  }

  Future<void> _deactivateEmployee(Map<String, dynamic> e) async {
    final name = (e['name'] ?? 'this employee').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Deactivate $name?'),
        content: const Text(
            'They will be removed from your active staff list, but their clock history will be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await http.put(
        Uri.parse('$_base/${(e['id'] as num).toInt()}/deactivate'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$name deactivated'),
              backgroundColor: kNyqGreen),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not deactivate employee'),
              backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error')),
        );
      }
    }
  }

  Future<void> _addEmployee() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController(text: '+232');
    final roleCtl = TextEditingController(text: 'Staff');
    final salaryCtl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: const Text('Add Employee'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roleCtl,
                  decoration: const InputDecoration(
                      labelText: 'Role (e.g. Cashier)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: salaryCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Monthly Salary (SLE)',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter the name')),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final res = await http.post(
                          Uri.parse(_base),
                          headers: {
                            ...await _headers(),
                            'Content-Type': 'application/json',
                          },
                          body: jsonEncode({
                            'name': nameCtl.text.trim(),
                            'phone': phoneCtl.text.trim(),
                            'role_title': roleCtl.text.trim(),
                            'monthly_salary_sle':
                                double.tryParse(salaryCtl.text.trim()) ?? 0,
                          }),
                        ).timeout(const Duration(seconds: 10));
                        if (!dialogCtx.mounted) return;
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          Map<String, dynamic> added = {};
                          try {
                            final body = jsonDecode(res.body);
                            added = Map<String, dynamic>.from(
                                (body['employee'] ?? body) as Map);
                          } catch (_) {
        showNetworkError(context, 'data');
      }
                          final temp = added['temp_password']?.toString();
                          Navigator.pop(dialogCtx);
                          await _load();
                          if (!mounted) return;
                          if (temp != null && temp.isNotEmpty) {
                            await showDialog<void>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(24)),
                                title: const Text('Employee Added'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('Temporary Password:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: kNyqSand,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: SelectableText(temp,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.5)),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                        'Please share this with them so they can log in and change it.',
                                        style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                                actions: [
                                  FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: kNyqGreen),
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Got it')),
                                ],
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('${nameCtl.text.trim()} added'),
                                backgroundColor: kNyqGreen,
                              ),
                            );
                          }
                        } else {
                          setDialogState(() => saving = false);
                          String msg = 'Could not add employee';
                          try {
                            msg =
                                (jsonDecode(res.body)['detail'] ?? msg).toString();
                          } catch (_) {
        showNetworkError(context, 'data');
      }
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red.shade800),
                          );
                        }
                      } catch (_) {
                        if (!dialogCtx.mounted) return;
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Network error')),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _employeeTile(Map<String, dynamic> e) {
    final clockedIn = e['clocked_in'] == true;
    final today = e['today'];
    final salary = (e['monthly_salary_sle'] ?? 0) as num;
    final inTime = today is Map ? formatChatTime(today['clock_in_time']) : '';
    final outTime = today is Map ? formatChatTime(today['clock_out_time']) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFE9E0)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: (e['employee_user_id'] == null)
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      otherUserId:
                          (e['employee_user_id'] as num).toInt(),
                      otherUserName:
                          (e['name'] ?? 'Employee').toString(),
                    ),
                  ),
                ),
        title: Text((e['name'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${e['role_title'] ?? 'Staff'} - SLE ${salary.toStringAsFixed(0)}/month',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if ((e['phone'] ?? '').toString().trim().isNotEmpty)
              Text((e['phone'] ?? '').toString().trim(),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            if (e['employee_user_id'] == null)
              Text('No app account yet',
                  style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade400)),
            const SizedBox(height: 2),
            Text(
              clockedIn
                  ? 'Clocked in at $inTime'
                  : (inTime.isEmpty
                      ? 'Not clocked in today'
                      : 'Clocked in $inTime - out $outTime'),
              style: TextStyle(
                fontSize: 11,
                color: clockedIn ? kNyqGreen : Colors.grey.shade500,
                fontWeight: clockedIn ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (_isCompany)
              Builder(builder: (context) {
                final status =
                    _kycStatus[(e['id'] as num).toInt().toString()] ?? 'none';
                final colour = _kycColour(status);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    height: 30,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: colour,
                        side: BorderSide(color: colour),
                        textStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      icon: Icon(
                          status == 'submitted' || status == 'approved'
                              ? Icons.badge
                              : Icons.badge_outlined,
                          size: 14),
                      label: Text(_kycLabel(status)),
                      onPressed: _kycTappable(status) ||
                              status == 'submitted' ||
                              status == 'approved'
                          ? () => _kycAction(e)
                          : null,
                    ),
                  ),
                );
              }),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    clockedIn ? Colors.orange.shade800 : kNyqGreen,
              ),
              onPressed: () => _clock((e['id'] as num).toInt(), !clockedIn),
              child: Text(clockedIn ? 'Clock Out' : 'Clock In',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Deactivate employee',
              icon: const Icon(Icons.person_off_outlined,
                  size: 20, color: Colors.red),
              onPressed: () => _deactivateEmployee(e),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEmployee,
        backgroundColor: kNyqGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Employee'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No employees yet',
                  message: 'Add your first employee to start tracking hours.',
                  actionLabel: 'Add Employee',
                  onAction: _addEmployee,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: _employees
                      .map((e) =>
                          _employeeTile(Map<String, dynamic>.from(e as Map)))
                      .toList(),
                ),
    );
  }
}

Future<int> fetchIncomingShipmentCount() async {
  try {
    final user = await UserSession.load();
    final res = await http.get(
      Uri.parse('$baseUrl/shipments/mine'),
      headers: {
        'x-api-key': apiKey,
        'Authorization': 'Bearer ${user?['token'] ?? ''}',
      },
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final list = jsonDecode(res.body) as List;
      return list.where((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final status = (m['status'] ?? '').toString();
        return m['my_role'] == 'receiver' &&
            (status == 'In Transit' || status == 'Arrived');
      }).length;
    }
  } catch (_) {}
  return 0;
}

// ==========================================
// DIASPORA SHIPMENTS
// ==========================================
class ShipmentListScreen extends StatefulWidget {
  final Map<String, dynamic>? company;
  final Map<String, dynamic>? shop;
  const ShipmentListScreen({super.key, this.company, this.shop});

  @override
  State<ShipmentListScreen> createState() => _ShipmentListScreenState();
}

class _ShipmentListScreenState extends State<ShipmentListScreen> {
  List<dynamic> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/shipments/mine'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _rows = list;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
        showNetworkError(context, 'shipments');
      }
    if (mounted) {
      setState(() {
        _rows = [];
        _loading = false;
      });
    }
  }

  Color _statusColour(String s) {
    switch (s) {
      case 'Received':
        return kNyqGreen;
      case 'Arrived':
        return kNyqOchre;
      default:
        return kNyqAccent;
    }
  }

  Widget _tile(Map<String, dynamic> s) {
    final status = (s['status'] ?? 'In Transit').toString();
    final shortfall = (s['shortfall'] ?? 0) as num;
    final role = (s['my_role'] ?? 'sender').toString();
    final colour = _statusColour(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFE9E0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiveShipmentScreen(
                shipmentId: (s['id'] as num).toInt(),
                canReceive: role == 'receiver' && status != 'Received',
              ),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 18, color: kNyqAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text((s['tracking_number'] ?? '').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status.toUpperCase(),
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: colour)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${s['origin'] ?? ''} to ${s['destination'] ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if ((s['receiver_name'] ?? '').toString().isNotEmpty)
                Text(
                  '${role == 'receiver' ? 'Incoming to you' : 'Sent to'} ${s['receiver_name']}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${s['item_count'] ?? 0} items - ${s['total_sent'] ?? 0} units',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (shortfall > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${shortfall.toStringAsFixed(0)} missing',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isShop = widget.shop != null;
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: const Text('Shipments'),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: (widget.company != null)
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: kNyqGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Shipment'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'No shipments',
                  message: isShop
                      ? 'Incoming shipments from overseas will appear here.'
                      : 'Create a shipment and add your manifest.',
                  actionLabel: 'Refresh',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: _rows
                        .map((r) =>
                            _tile(Map<String, dynamic>.from(r as Map)))
                        .toList(),
                  ),
                ),
    );
  }

  Future<void> _openCreate() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => CreateShipmentDialog(companyId: (widget.company!['id'] as num).toInt()),
    );
    if (created == true) _load();
  }
}

class CreateShipmentDialog extends StatefulWidget {
  final int companyId;
  const CreateShipmentDialog({super.key, required this.companyId});

  @override
  State<CreateShipmentDialog> createState() => _CreateShipmentDialogState();
}

class _CreateShipmentDialogState extends State<CreateShipmentDialog> {
  final _tracking = TextEditingController();
  final _carrier = TextEditingController(text: 'DHL');
  final _origin = TextEditingController(text: 'USA');
  final _destination = TextEditingController(text: 'Freetown');
  final List<Map<String, dynamic>> _items = [
    {'name': TextEditingController(), 'qty': TextEditingController(text: '1')}
  ];
  List<dynamic> _receivers = [];
  String? _receiverKey;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReceivers();
  }

  Future<void> _loadReceivers() async {
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/shipments/receivers'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) setState(() => _receivers = list);
      }
    } catch (_) {
        showNetworkError(context, 'shipments');
      }
  }

  @override
  void dispose() {
    _tracking.dispose();
    _carrier.dispose();
    _origin.dispose();
    _destination.dispose();
    for (final i in _items) {
      (i['name'] as TextEditingController).dispose();
      (i['qty'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_tracking.text.trim().isEmpty) {
      setState(() => _error = 'Tracking number is required');
      return;
    }
    final valid = _items.where((i) {
      final c = i['name'] as TextEditingController;
      return c.text.trim().isNotEmpty;
    }).toList();
    if (valid.isEmpty) {
      setState(() => _error = 'Add at least one item');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final user = await UserSession.load();
    final hdrs = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
    try {
      final body = <String, dynamic>{
        'tracking_number': _tracking.text.trim(),
        'carrier': _carrier.text.trim(),
        'origin': _origin.text.trim(),
        'destination': _destination.text.trim(),
      };
      if (_receiverKey != null) {
        final parts = _receiverKey!.split(':');
        if (parts[0] == 'shop') {
          body['receiver_shop_id'] = int.parse(parts[1]);
        } else {
          body['receiver_company_id'] = int.parse(parts[1]);
        }
      }
      final res = await http.post(
        Uri.parse('$baseUrl/companies/${widget.companyId}/shipments'),
        headers: hdrs,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        String msg = 'Could not create shipment';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {
        showNetworkError(context, 'shipments');
      }
        setState(() {
          _error = msg;
          _saving = false;
        });
        return;
      }
      final sid = (jsonDecode(res.body)['shipment']['id'] as num).toInt();
      final items = valid
          .map((i) => {
                'item_name': (i['name'] as TextEditingController).text.trim(),
                'quantity_sent': int.tryParse(
                        (i['qty'] as TextEditingController).text.trim()) ??
                    0,
              })
          .toList();
      final res2 = await http.post(
        Uri.parse('$baseUrl/shipments/$sid/items'),
        headers: hdrs,
        body: jsonEncode({'items': items}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res2.statusCode < 200 || res2.statusCode >= 300) {
        setState(() {
          _error =
              'Shipment created, but the manifest failed to save. Add items from the list.';
          _saving = false;
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('New Shipment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tracking,
              decoration: const InputDecoration(
                  labelText: 'Tracking Number',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _carrier,
              decoration: const InputDecoration(
                  labelText: 'Carrier', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _origin,
                    decoration: const InputDecoration(
                        labelText: 'From', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _destination,
                    decoration: const InputDecoration(
                        labelText: 'To', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _receiverKey,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Receiver (shop or company)',
                  border: OutlineInputBorder()),
              items: _receivers.map((r) {
                final key = '${r['type']}:${r['id']}';
                return DropdownMenuItem<String>(
                  value: key,
                  child: Text(
                      '${r['name']} (${r['type'] == 'shop' ? 'Shop' : 'Company'})',
                      overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (v) => setState(() => _receiverKey = v),
            ),
            const Divider(height: 24),
            const Text('Manifest',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            ..._items.asMap().entries.map((entry) {
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller:
                            _items[i]['name'] as TextEditingController,
                        decoration: const InputDecoration(
                            labelText: 'Item',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller:
                            _items[i]['qty'] as TextEditingController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 20, color: Colors.red),
                      onPressed: _items.length == 1
                          ? null
                          : () => setState(() => _items.removeAt(i)),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() {
                _items.add({
                  'name': TextEditingController(),
                  'qty': TextEditingController(text: '1'),
                });
              }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add another item'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kNyqGreen),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Create'),
        ),
      ],
    );
  }
}

class ReceiveShipmentScreen extends StatefulWidget {
  final int shipmentId;
  final bool canReceive;
  const ReceiveShipmentScreen(
      {super.key, required this.shipmentId, this.canReceive = false});

  @override
  State<ReceiveShipmentScreen> createState() =>
      _ReceiveShipmentScreenState();
}

class _ReceiveShipmentScreenState extends State<ReceiveShipmentScreen> {
  Map<String, dynamic>? _s;
  bool _loading = true;
  bool _saving = false;
  final Map<int, TextEditingController> _qty = {};
  final Map<int, TextEditingController> _reason = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    for (final c in _reason.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final user = await UserSession.load();
    return {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'Authorization': 'Bearer ${user?['token'] ?? ''}',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/shipments/${widget.shipmentId}'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        final items = (d['items'] as List?) ?? [];
        for (final raw in items) {
          final it = Map<String, dynamic>.from(raw as Map);
          final id = (it['id'] as num).toInt();
          _qty.putIfAbsent(
              id,
              () => TextEditingController(
                  text: it['quantity_received'] == null
                      ? ''
                      : it['quantity_received'].toString()));
          _reason.putIfAbsent(
              id,
              () => TextEditingController(
                  text: (it['discrepancy_reason'] ?? '').toString()));
        }
        if (mounted) {
          setState(() {
            _s = d;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
        showNetworkError(context, 'shipments');
      }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestDelivery() async {
    final s = _s;
    if (s == null) return;
    final feeCtl = TextEditingController();
    final addrCtl = TextEditingController();
    bool sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: const Text('Request Delivery to Shop'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'A job worker will pick the shipment up and bring it to you. You pay them on delivery.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Shop address',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Delivery offer (SLE)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kNyqGreen),
              onPressed: sending
                  ? null
                  : () async {
                      final fee = double.tryParse(feeCtl.text.trim());
                      if (fee == null || fee <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Enter a delivery offer')),
                        );
                        return;
                      }
                      if (addrCtl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Enter your shop address')),
                        );
                        return;
                      }
                      setDialogState(() => sending = true);
                      final hdrs = await _headers();
                      try {
                        final res = await http.post(
                          Uri.parse(
                              '$baseUrl/shipments/${widget.shipmentId}/request-delivery'),
                          headers: hdrs,
                          body: jsonEncode({
                            'offer_sle': fee,
                            'shop_address': addrCtl.text.trim(),
                          }),
                        ).timeout(const Duration(seconds: 10));
                        if (!dialogCtx.mounted) return;
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                          Navigator.pop(dialogCtx);
                          await _load();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Delivery requested'),
                                backgroundColor: kNyqGreen),
                          );
                        } else {
                          setDialogState(() => sending = false);
                          String msg = 'Could not request delivery';
                          try {
                            msg =
                                (jsonDecode(res.body)['detail'] ?? msg)
                                    .toString();
                          } catch (_) {
        showNetworkError(context, 'shipments');
      }
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red),
                          );
                        }
                      } catch (_) {
                        if (!dialogCtx.mounted) return;
                        setDialogState(() => sending = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Network error')),
                        );
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save({bool finalise = false}) async {
    if (_s == null) return;
    if (finalise) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Close this shipment?'),
          content: const Text(
              'The manifest will lock. You cannot record more arrivals after this.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kNyqGreen),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Close shipment')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    final items = ((_s!['items'] as List?) ?? []).map((raw) {
      final it = Map<String, dynamic>.from(raw as Map);
      final id = (it['id'] as num).toInt();
      final txt = _qty[id]?.text.trim() ?? '';
      return {
        'item_id': id,
        'quantity_received': txt.isEmpty ? null : int.tryParse(txt),
        'discrepancy_reason': _reason[id]?.text.trim(),
      };
    }).toList();
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/shipments/${widget.shipmentId}/receive'),
        headers: await _headers(),
        body: jsonEncode({'items': items, 'final': finalise}),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _saving = false);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        setState(() => _s = d['shipment']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(finalise
                  ? 'Shipment closed'
                  : 'Progress saved'),
              backgroundColor: kNyqGreen),
        );
      } else {
        String msg = 'Could not save';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {
        showNetworkError(context, 'shipments');
      }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: Text(s == null
            ? 'Shipment'
            : (s['tracking_number'] ?? 'Shipment').toString()),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if ((s['delivery_status'] ?? '').toString().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kNyqAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping,
                            size: 18, color: kNyqAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (s['delivery_status'] ?? '').toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: kNyqAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.canReceive &&
                    (s['delivery_status'] ?? '').toString().isEmpty &&
                    s['status'] != 'Received' &&
                    s['receiver_shop_id'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kNyqAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.local_shipping, size: 18),
                        label: const Text('Request Delivery to Shop'),
                        onPressed: _requestDelivery,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEFE9E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${s['origin'] ?? ''} to ${s['destination'] ?? ''}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                          'Status: ${s['status']} | ${s['receiver_name'] ?? 'No receiver'}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      if ((s['shortfall'] ?? 0) > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                            '${s['shortfall']} unit(s) missing',
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...((s['items'] as List?) ?? []).map((raw) {
                  final it = Map<String, dynamic>.from(raw as Map);
                  final id = (it['id'] as num).toInt();
                  final sent = (it['quantity_sent'] ?? 0) as num;
                  final recvTxt = _qty[id]?.text.trim() ?? '';
                  final recv =
                      recvTxt.isEmpty ? null : int.tryParse(recvTxt);
                  final short = recv != null && recv < sent;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: short
                          ? Colors.red.withValues(alpha: 0.06)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: short
                              ? Colors.red.shade300
                              : const Color(0xFFEFE9E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((it['item_name'] ?? '').toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        if ((it['notes'] ?? '').toString().isNotEmpty)
                          Text((it['notes'] ?? '').toString(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('Sent: ${sent.toStringAsFixed(0)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700)),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _qty[id],
                                enabled: widget.canReceive &&
                                    s['status'] != 'Received',
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                    labelText: 'Received',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                              ),
                            ),
                            if (short) ...[
                              const SizedBox(width: 8),
                              Text(
                                  '${(sent - recv).toStringAsFixed(0)} short',
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12)),
                            ],
                          ],
                        ),
                        if (short) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reason[id],
                            enabled: widget.canReceive &&
                                s['status'] != 'Received',
                            decoration: const InputDecoration(
                                labelText: 'What happened?',
                                border: OutlineInputBorder(),
                                isDense: true),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
      bottomNavigationBar: (s == null || !widget.canReceive || s['status'] == 'Received')
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _save(),
                        child: const Text('Save progress'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style:
                            FilledButton.styleFrom(backgroundColor: kNyqGreen),
                        onPressed:
                            _saving ? null : () => _save(finalise: true),
                        child: const Text('Close shipment'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ==========================================
// KYC VIEWER (EMPLOYER)
// ==========================================
class KycViewerScreen extends StatefulWidget {
  final int companyId;
  final int employeeId;
  final String employeeName;
  const KycViewerScreen({
    super.key,
    required this.companyId,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<KycViewerScreen> createState() => _KycViewerScreenState();
}

class _KycViewerScreenState extends State<KycViewerScreen> {
  Map<String, dynamic>? _data;
  String _token = '';
  bool _loading = true;
  final Map<String, Uint8List?> _images = {};
  final Map<String, bool> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await UserSession.load();
    _token = (user?['token'] ?? '').toString();
    try {
      final res = await http.get(
        Uri.parse(
            '$baseUrl/companies/${widget.companyId}/employees/${widget.employeeId}/kyc'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        if (mounted) {
          setState(() {
            _data = d;
            _loading = false;
          });
        }
        for (final slot in ['front', 'back', 'selfie']) {
          final id = d[slot + '_image_id']?.toString();
          if (id != null && id.isNotEmpty) _fetchImage(slot, id);
        }
        return;
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'this ID');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchImage(String slot, String id) async {
    setState(() => _busy[slot] = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/kyc/image/$id'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _busy[slot] = false;
        _images[slot] =
            (res.statusCode >= 200 && res.statusCode < 300) ? res.bodyBytes : null;
      });
    } catch (_) {
      if (mounted) setState(() => _busy[slot] = false);
    }
  }

  Widget _block(String slot, String label) {
    final busy = _busy[slot] == true;
    final bytes = _images[slot];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: kNyqAccent,
                letterSpacing: 0.6)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 210,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0DAD2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : bytes != null
                  ? InteractiveViewer(
                      maxScale: 4,
                      child: Image.memory(bytes,
                          fit: BoxFit.contain, width: double.infinity),
                    )
                  : Center(
                      child: Text('Not provided',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                    ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final status = (d?['status'] ?? '').toString();
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: Text(widget.employeeName),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading || d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0DAD2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                (d['full_name_on_id'] ?? 'Not provided')
                                    .toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (status == 'approved'
                                      ? kNyqGreen
                                      : kNyqOchre)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(status.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: status == 'approved'
                                        ? kNyqGreen
                                        : kNyqOchre)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(d['id_type'] ?? 'id').toString().toUpperCase()}  '
                        '${(d['id_number'] ?? '').toString()}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _block('front', 'FRONT'),
                _block('back', 'BACK'),
                _block('selfie', 'SELFIE'),
                Text(
                  'Viewing this document is recorded in the access log.',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }
}

// ==========================================
// KYC (EMPLOYEE SIDE)
// ==========================================
class KycRequestsScreen extends StatefulWidget {
  const KycRequestsScreen({super.key});

  @override
  State<KycRequestsScreen> createState() => _KycRequestsScreenState();
}

class _KycRequestsScreenState extends State<KycRequestsScreen> {
  List<dynamic> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/kyc/mine'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) {
          setState(() {
            _rows = jsonDecode(res.body) as List;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'your ID requests');
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _chip(String s) {
    switch (s) {
      case 'submitted':
        return kNyqGreen;
      case 'declined':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      default:
        return kNyqOchre;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: const Text('Identity Verification'),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'Nothing to upload',
                  message: 'No employer has asked for your ID.',
                  actionLabel: 'Back',
                  onAction: () => Navigator.pop(context),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _rows.map((raw) {
                    final r = Map<String, dynamic>.from(raw as Map);
                    final status = (r['status'] ?? '').toString();
                    final company =
                        (r['company_name'] ?? 'Your employer').toString();
                    final done = status != 'requested';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEFE9E0)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        leading: Icon(Icons.badge_outlined,
                            color: done ? Colors.grey : kNyqAccent),
                        title: Text(company,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(
                          done ? 'Status: $status' : 'This employer has asked to see your ID',
                          style: TextStyle(
                              fontSize: 11,
                              color: _chip(status),
                              fontWeight: FontWeight.w600),
                        ),
                        trailing: done
                            ? null
                            : const Icon(Icons.chevron_right,
                                color: kNyqAccent),
                        onTap: done
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => KycUploadScreen(
                                      kycId: (r['id'] as num).toInt(),
                                      companyName: company,
                                    ),
                                  ),
                                );
                                _load();
                              },
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

class KycUploadScreen extends StatefulWidget {
  final int? kycId;
  final String? companyName;
  final bool renew;
  const KycUploadScreen(
      {super.key, this.kycId, this.companyName, this.renew = false});

  @override
  State<KycUploadScreen> createState() => _KycUploadScreenState();
}

class _KycUploadScreenState extends State<KycUploadScreen> {
  int? _kycId;
  final _idNumber = TextEditingController();
  final _fullName = TextEditingController();
  String _idType = 'nin';
  DateTime? _expiry;
  String? _front;
  String? _back;
  String? _selfie;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kycId = widget.kycId;
    if (_kycId == null) {
      if (widget.renew) {
        _startRenewal();
      } else {
        _startPlatformKyc();
      }
    }
  }

  Future<void> _startRenewal() async {
    try {
      final user = await UserSession.load();
      final res = await http.post(
        Uri.parse('$baseUrl/kyc/renew'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = jsonDecode(res.body) as Map;
        if (mounted) setState(() => _kycId = (d['kyc_id'] as num).toInt());
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'your new ID');
    }
  }

  Future<void> _startPlatformKyc() async {
    try {
      final user = await UserSession.load();
      final res = await http.post(
        Uri.parse('$baseUrl/kyc/start'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = jsonDecode(res.body) as Map;
        if (mounted) setState(() => _kycId = (d['kyc_id'] as num).toInt());
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'your verification');
    }
  }

  @override
  void dispose() {
    _idNumber.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _pick(String slot) async {
    final id = await uploadKycImage(context);
    if (id == null || !mounted) return;
    setState(() {
      if (slot == 'front') _front = id;
      if (slot == 'back') _back = id;
      if (slot == 'selfie') _selfie = id;
    });
  }

  Future<void> _submit() async {
    if (_front == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a photo of the front of your ID')),
      );
      return;
    }
    if (_idNumber.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your ID number')),
      );
      return;
    }
    if (_expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the expiry date on your ID')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final user = await UserSession.load();
      final res = await http.post(
        Uri.parse('$baseUrl/kyc/submit'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
        body: jsonEncode({
          'id_type': _idType,
          'expiry_date': _expiry == null
              ? null
              : '${_expiry!.year.toString().padLeft(4, '0')}-'
                  '${_expiry!.month.toString().padLeft(2, '0')}-'
                  '${_expiry!.day.toString().padLeft(2, '0')}',
          'id_number': _idNumber.text.trim(),
          'full_name_on_id': _fullName.text.trim(),
          'front_image_id': _front,
          'back_image_id': _back,
          'selfie_image_id': _selfie,
        }),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ID sent to your employer'),
              backgroundColor: kNyqGreen),
        );
      } else {
        setState(() => _saving = false);
        String msg = 'Could not submit your ID';
        try {
          msg = (jsonDecode(res.body)['detail'] ?? msg).toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showNetworkError(context, 'your ID');
      }
    }
  }

  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Not now?'),
        content: Text(
            '${widget.companyName} will be told you did not share your ID.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Not now',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final user = await UserSession.load();
      final res = await http.post(
        Uri.parse('$baseUrl/kyc/$_kycId/decline'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You did not share your ID')),
        );
      }
    } catch (_) {
      if (mounted) showNetworkError(context, 'your request');
    }
  }

  Widget _tile(String label, String? id, String slot, IconData icon) {
    final done = id != null;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : () => _pick(slot),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: done ? kNyqGreen.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: done ? kNyqGreen : const Color(0xFFE0DAD2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(done ? Icons.check_circle : icon,
                  color: done ? kNyqGreen : Colors.grey.shade400, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: done ? kNyqGreen : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: const Text('Verify Your Identity'),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.renew) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kNyqOchre.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Upload your new ID. Your old ID stays active until the new one is approved.',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kNyqAccent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Requested by',
                    style: TextStyle(fontSize: 11, color: kNyqAccent)),
                Text(widget.companyName ?? 'Na You Get',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    widget.companyName == null
                        ? 'Your ID is stored privately and reviewed once. It is never shown on your profile.'
                        : 'They will see your ID photo. It is not public and is never shown on your profile.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _idType,
            decoration: const InputDecoration(
                labelText: 'ID type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'nin', child: Text('National ID (NIN)')),
              DropdownMenuItem(
                  value: 'passport', child: Text('Passport')),
              DropdownMenuItem(
                  value: 'licence', child: Text('Driving Licence')),
            ],
            onChanged: (v) => setState(() => _idType = v ?? 'nin'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _idNumber,
            decoration: const InputDecoration(
                labelText: 'ID number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fullName,
            decoration: const InputDecoration(
                labelText: 'Name as written on the ID',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: now.add(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 365 * 15)),
                initialDate: _expiry ?? now.add(const Duration(days: 365)),
                helpText: 'ID expiry date',
              );
              if (picked != null) setState(() => _expiry = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'ID Expiry Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(
                _expiry == null
                    ? 'Select the expiry date'
                    : '${_expiry!.day}/${_expiry!.month}/${_expiry!.year}',
                style: TextStyle(
                    fontSize: 13,
                    color: _expiry == null
                        ? Colors.grey.shade500
                        : Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _tile('Front', _front, 'front', Icons.add_a_photo_outlined),
              const SizedBox(width: 10),
              _tile('Back', _back, 'back', Icons.add_a_photo_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _tile('Selfie', _selfie, 'selfie', Icons.face_outlined),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.kycId != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _decline,
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: kNyqGreen),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Submit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShopManagementScreen extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Map<String, dynamic>? currentUser;
  final VoidCallback? onUserChanged;

  const ShopManagementScreen({
    super.key,
    required this.shop,
    this.currentUser,
    this.onUserChanged,
  });

  @override
  State<ShopManagementScreen> createState() => _ShopManagementScreenState();
}

class _ShopManagementScreenState extends State<ShopManagementScreen> {
  late Map<String, dynamic> shop;
  int _products = 0;
  int _employees = 0;
  int _pendingShipments = 0;

  @override
  void initState() {
    super.initState();
    shop = Map<String, dynamic>.from(widget.shop);
    _products = (shop['product_count'] as num?)?.toInt() ?? 0;
    _refresh();
    fetchIncomingShipmentCount().then((n) {
      if (mounted) setState(() => _pendingShipments = n);
    });
  }

  String get _initial {
    final n = (shop['shop_name'] ?? '').toString().trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  Future<void> _refresh() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/merchants/${shop['id']}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final fresh = Map<String, dynamic>.from(data['merchant'] ?? data);
        if (!mounted) return;
        setState(() {
          shop = fresh;
          _products = (fresh['product_count'] as num?)?.toInt() ?? _products;
        });
      }
    } catch (_) {
        showNetworkError(context, 'shop details');
      }
    await _refreshEmployeeCount();
  }

  Future<void> _openTeamChat() async {
    final user = await UserSession.load();
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/threads/shop/${shop['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final t = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              threadId: (t['id'] as num).toInt(),
              threadName: (t['name'] ?? 'Team Chat').toString(),
            ),
          ),
        );
        _refresh();
      }
    } catch (_) {
        showNetworkError(context, 'messages');
      }
  }

  Future<void> _refreshEmployeeCount() async {
    final user = await UserSession.load();
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/shops/${shop['id']}/employees'),
        headers: {
          'x-api-key': apiKey,
          if (user?['token'] != null)
            'Authorization': 'Bearer ${user!['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body) as List;
        if (mounted) setState(() => _employees = list.length);
      }
    } catch (_) {
        showNetworkError(context, 'employees');
      }
  }

  void _openShop({String? action}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPageScreen(
          shop: shop,
          currentUser: widget.currentUser,
          onUserChanged: widget.onUserChanged,
          openAction: action,
        ),
      ),
    ).then((_) => _refresh());
  }

  Widget _stat(String value, String label, Color colour) =>
      Expanded(child: ManagementStat(value, label, colour));

  Widget _actionCard(IconData icon, String title, String subtitle,
          VoidCallback onTap) =>
      ManagementActionCard(icon, title, subtitle, onTap);

  @override
  Widget build(BuildContext context) {
    final logo = (shop['logo_url'] ?? '').toString().trim();
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(
        title: const Text('Manage Shop'),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              ClipOval(
                child: Container(
                  width: 56,
                  height: 56,
                  color: kNyqAccent,
                  child: logo.isEmpty
                      ? Center(
                          child: Text(_initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                        )
                      : Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(_initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((shop['shop_name'] ?? 'Shop').toString(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text((shop['city'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _stat('SLE 0', 'Sales', kNyqGreen),
              const SizedBox(width: 8),
              _stat('$_products', 'Products', kNyqAccent),
              const SizedBox(width: 8),
              _stat('$_employees', 'Employees', kNyqOchre),
            ],
          ),
          const SizedBox(height: 20),
          _actionCard(Icons.storefront, 'View Public Shop',
              'See what customers see', () => _openShop()),
          _actionCard(Icons.inventory_2_outlined, 'Manage Products',
              'Add, edit and remove items', () => _openShop()),
          _actionCard(Icons.groups_outlined, 'Manage Employees',
              'Clock-in and staff records', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmployeeListScreen(shop: shop),
              ),
            );
            _refresh();
          }),
          _actionCard(Icons.forum_outlined, 'Team Chat',
              'Group chat with your staff', _openTeamChat),
          _actionCard(Icons.local_shipping_outlined, 'Shipments',
              _pendingShipments > 0
                  ? '$_pendingShipments incoming'
                  : 'Track overseas deliveries', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ShipmentListScreen(shop: shop),
              ),
            );
            fetchIncomingShipmentCount().then((n) {
              if (mounted) setState(() => _pendingShipments = n);
            });
          }),
          _actionCard(Icons.settings_outlined, 'Settings',
              'Edit shop details and branding',
              () => _openShop(action: 'settings')),
        ],
      ),
    );
  }
}

// ==========================================
// SHOP LOCATION PICKER
// ==========================================
// DEV ONLY: OpenStreetMap public tiles. Their usage policy forbids
// production-scale traffic. Switch to MapTiler before public launch.
const String kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const LatLng kFreetown = LatLng(8.4840, -13.2299);

class ShopLocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const ShopLocationPickerScreen({super.key, this.initial});

  @override
  State<ShopLocationPickerScreen> createState() =>
      _ShopLocationPickerScreenState();
}

class _ShopLocationPickerScreenState extends State<ShopLocationPickerScreen> {
  final MapController _map = MapController();
  late LatLng _centre;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _centre = widget.initial ?? kFreetown;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Turn on location services to use this.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission denied. Tap the map to place the pin.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 15));
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      _map.move(p, 16);
      setState(() => _centre = p);
    } catch (_) {
      _toast('Could not get your location. Tap the map instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Shop Location'),
        backgroundColor: kNyqAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _centre,
              initialZoom: 15,
              onPositionChanged: (camera, hasGesture) {
                _centre = camera.center;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: kOsmTileUrl,
                userAgentPackageName: 'com.nyg.app',
              ),
            ],
          ),
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 34),
                child: Icon(Icons.location_on,
                    size: 44, color: Colors.red),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              onPressed: _locating ? null : _useMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, color: kNyqAccent),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Color(0x22000000), blurRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lat ${_centre.latitude.toStringAsFixed(5)}, '
                    'Lng ${_centre.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: kNyqGreen),
                          onPressed: () => Navigator.pop(context, _centre),
                          child: const Text('Use This Spot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShopPageScreen extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Map<String, dynamic>? currentUser;
  final VoidCallback? onUserChanged;
  final String? openAction;

  const ShopPageScreen({
    super.key,
    required this.shop,
    this.currentUser,
    this.onUserChanged,
    this.openAction,
  });

  @override
  State<ShopPageScreen> createState() => _ShopPageScreenState();
}

class _ShopPageScreenState extends State<ShopPageScreen> {
  List<dynamic> products = [];
  bool isLoading = true;
  late Map<String, dynamic> shop;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    shop = Map<String, dynamic>.from(widget.shop);
    _currentUser = widget.currentUser;
    if (_currentUser == null) _loadUser();
    _fetchProducts();
    _refreshShop();
    if (widget.openAction == 'settings') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditShopDialog();
      });
    }
  }

  Future<void> _loadUser() async {
    final u = await UserSession.load();
    if (mounted) setState(() => _currentUser = u);
  }

  Future<void> _refreshShop() async {
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${shop['id']}'),
        headers: {
          'x-api-key': apiKey,
          if (user?['token'] != null)
            'Authorization': 'Bearer ${user!['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final fresh = Map<String, dynamic>.from(data['merchant'] ?? data);
        if (mounted) setState(() => shop = fresh);
      }
    } catch (_) {
        showNetworkError(context, 'shop details');
      }
  }

  Color get _headerColour =>
      parseThemeColour(shop['theme_colour']?.toString());

  Color get _headerTextColour =>
      ThemeData.estimateBrightnessForColor(_headerColour) == Brightness.dark
          ? Colors.white
          : Colors.black87;

  Color get _pageBackground => parseThemeColour(
      shop['background_colour']?.toString(),
      fallback: Colors.white);

  Color get _pageTextColour =>
      ThemeData.estimateBrightnessForColor(_pageBackground) == Brightness.dark
          ? Colors.white
          : Colors.black87;

  String _toHex(Color c) {
    final argb = c.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Widget _buildModeToggle({
    required String selectedBg,
    required ValueChanged<String> onBg,
    required ValueChanged<String> onHeader,
  }) {
    final isDark =
        parseThemeColour(selectedBg, fallback: Colors.white) == Colors.black;
    return Row(
      children: [
        const Text('Theme mode',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        ChoiceChip(
          label: const Text('Light'),
          selected: !isDark,
          onSelected: (_) {
            onBg('#FFFFFF');
            onHeader('#FFFFFF');
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Dark'),
          selected: isDark,
          onSelected: (_) {
            onBg('#000000');
            onHeader('#000000');
          },
        ),
      ],
    );
  }

  Widget _buildHueSlider(String selectedHex, ValueChanged<String> onPick) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(Offset local) {
          final hue = (local.dx.clamp(0.0, width) / width) * 359.9;
          final base =
              parseThemeColour(selectedHex, fallback: kNyqAccent);
          final hsv = HSVColor.fromColor(base);
          final colour = HSVColor.fromAHSV(
            1,
            hue,
            hsv.saturation < 0.05 ? 0.72 : hsv.saturation,
            hsv.value < 0.05 ? 0.88 : hsv.value,
          ).toColor();
          onPick(_toHex(colour));
        }

        return GestureDetector(
          onTapDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: LinearGradient(
                colors: [
                  for (int i = 0; i <= 6; i++)
                    HSVColor.fromAHSV(1, (i * 60) % 360, 0.72, 0.88)
                        .toColor(),
                ],
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'Tap or drag to pick any colour',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withAlpha(90),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildColourPicker({
    required String label,
    required String selectedHex,
    required ValueChanged<String> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        _buildHueSlider(selectedHex, onPick),
        const SizedBox(height: 10),
        HexColourField(value: selectedHex, onChanged: onPick),
        const SizedBox(height: 10),
        Text('Quick picks',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kShopPalette.keys.map((hex) {
            final colour = parseThemeColour(hex, fallback: Colors.white);
            final isSelected = selectedHex.toUpperCase() == hex.toUpperCase();
            final isDark =
                ThemeData.estimateBrightnessForColor(colour) == Brightness.dark;
            return GestureDetector(
              onTap: () => onPick(hex),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? kNyqAccent
                        : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check,
                        size: 18, color: isDark ? Colors.white : Colors.black87)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _fetchProducts() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${shop['id']}/products/'),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as List;
        final enriched = data.map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          m['shop_name'] = shop['shop_name'];
          m['shop_city'] = shop['city'];
          m['shop_category'] = shop['category'];
          return m;
        }).toList();
        setState(() {
          products = enriched;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  void _showAddItemDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    String selectedCategory = 'Other';
    List<String> uploadedPhotos = [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Item to ${shop['shop_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Item Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price in Leones (SLE)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Product Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Fashion', child: Text('Fashion')),
                    DropdownMenuItem(value: 'Food', child: Text('Food & Groceries')),
                    DropdownMenuItem(value: 'Electronics', child: Text('Electronics')),
                    DropdownMenuItem(value: 'Home', child: Text('Home & Furniture')),
                    DropdownMenuItem(value: 'Beauty', child: Text('Beauty & Health')),
                    DropdownMenuItem(value: 'Services', child: Text('Services')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await showMultiPhotoPicker(context, uploadedPhotos, (newPhotos) {
                        setDialogState(() => uploadedPhotos = newPhotos);
                      });
                    },
                    icon: const Icon(Icons.photo_library),
                    label: Text(uploadedPhotos.isEmpty ? 'Add Photos (up to 4)' : '${uploadedPhotos.length} photo(s) added'),
                  ),
                ),
                if (uploadedPhotos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: uploadedPhotos.map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(url, width: 60, height: 60, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty ||
                    priceController.text.isEmpty) return;

                final price = double.tryParse(priceController.text) ?? 0.0;

                final user = await UserSession.load();
                final response = await http.post(
                  Uri.parse('$baseUrl/products/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                    'Authorization': 'Bearer ${user?['token'] ?? ''}',
                  },
                  body: jsonEncode({
                    'merchant_id': shop['id'],
                    'title': titleController.text,
                    'description': descController.text,
                    'category': selectedCategory,
                    'price_sle': price,
                    'image_url': uploadedPhotos.isNotEmpty ? uploadedPhotos[0] : null,
                    'image_urls': uploadedPhotos,
                  }),
                );

                if (mounted) {
                  Navigator.pop(ctx);
                  if (response.statusCode >= 200 &&
                      response.statusCode < 300) {
                    _fetchProducts();
                  } else {
                    showApiError(context, response.statusCode, response.body,
                        fallback: 'Failed to add product.');
                  }
                }
              },
              child: const Text('Add to Shop'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProductDialog(Map<String, dynamic> product) {
    final titleController = TextEditingController(text: product['title'] ?? '');
    final descController = TextEditingController(text: product['description'] ?? '');
    final priceController = TextEditingController(text: (product['price_sle'] ?? '').toString());
    List<String> uploadedPhotos = productPhotos(product);
    String selectedCategory = product['category'] ?? 'Other';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${product['title']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Item Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price in Leones (SLE)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Product Category', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Fashion', child: Text('Fashion')),
                    DropdownMenuItem(value: 'Food', child: Text('Food & Groceries')),
                    DropdownMenuItem(value: 'Electronics', child: Text('Electronics')),
                    DropdownMenuItem(value: 'Home', child: Text('Home & Furniture')),
                    DropdownMenuItem(value: 'Beauty', child: Text('Beauty & Health')),
                    DropdownMenuItem(value: 'Services', child: Text('Services')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selectedCategory = value);
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await showMultiPhotoPicker(context, uploadedPhotos, (newPhotos) {
                        setDialogState(() => uploadedPhotos = newPhotos);
                      });
                    },
                    icon: const Icon(Icons.photo_library),
                    label: Text(uploadedPhotos.isEmpty ? 'Add Photos (up to 4)' : '${uploadedPhotos.length} photo(s)'),
                  ),
                ),
                if (uploadedPhotos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: uploadedPhotos.map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(url, width: 60, height: 60, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty || priceController.text.isEmpty) return;
                final price = double.tryParse(priceController.text) ?? 0.0;
                final err = await UserSession.updateProduct(
                  (product['id'] as num).toInt(),
                  {
                    'title': titleController.text,
                    'description': descController.text,
                    'category': selectedCategory,
                    'price_sle': price,
                    'image_url': uploadedPhotos.isNotEmpty ? uploadedPhotos[0] : null,
                    'image_urls': uploadedPhotos,
                  },
                );
                if (!context.mounted) return;
                if (err == 'SESSION_EXPIRED') {
                  handleSessionExpired(context);
                  return;
                }
                if (err == null) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product updated')),
                  );
                  _fetchProducts();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProduct(int productId, String productTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Delete "$productTitle"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = await UserSession.load();
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/products/$productId'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product deleted')),
          );
          _fetchProducts();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You cannot delete this product')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot reach server')),
        );
      }
    }
  }

  Future<void> _launchExternal(String? raw) async {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return;
    final normalized =
        value.startsWith('http://') || value.startsWith('https://')
            ? value
            : 'https://$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _socialDot(String label, Color colour, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(45),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp() async {
    final digits = (shop['whatsapp_number'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openEditProfile() async {
    final u = _currentUser;
    if (u == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          currentUser: u,
          onUserChanged: () {
            widget.onUserChanged?.call();
            _loadUser();
          },
        ),
      ),
    );
    await _loadUser();
  }

  Future<void> _deleteShop() async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this shop?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will delete the shop and all its products. This cannot be undone.',
            ),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm:'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'DELETE',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (confirmController.text.trim() == 'DELETE') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Delete Shop'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = await UserSession.load();
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/merchants/${shop['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user?['token'] ?? ''}',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Revoke seller status so the user can become a seller again
        await UserSession.revokeSeller();
        widget.onUserChanged?.call();
        await ShopSession.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shop deleted')),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You do not own this shop')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot reach server')),
        );
      }
    }
  }

  double _agreed(dynamic product, TextEditingController c) {
    final typed = double.tryParse(c.text.trim());
    if (typed != null && typed > 0) return typed;
    return (product['price_sle'] as num? ?? 0).toDouble();
  }

  Widget _payCard(String current, String value, String label, IconData icon,
      String hint, ValueChanged<String> onPick) {
    final selected = current == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onPick(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? kNyqAccent.withAlpha(18) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kNyqAccent : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: selected ? kNyqAccent : Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: selected ? kNyqAccent : kNyqInk)),
                    if (hint.isNotEmpty)
                      Text(hint,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: kNyqAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCheckout(dynamic product) async {
    if (_currentUser == null) {
      final guest = await guestSignupFlow(context);
      if (guest == null || !mounted) return;
      widget.onUserChanged?.call();
      await _loadUser();
    }

    if (!mounted) return;

    double? agreedOffer;
    try {
      final u = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/products/${product['id']}/my-offer'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${u?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final o = jsonDecode(res.body)['offer'];
        if (o is Map && o['amount_sle'] != null) {
          agreedOffer = (o['amount_sle'] as num).toDouble();
        }
      }
    } catch (_) {
        showNetworkError(context, 'products');
      }

    String paymentMethod = 'cash_on_delivery';
    String shopPaymentMethod = 'orange_money';
    String workerPaymentMethod = 'cash_on_delivery';
    bool collectInStore = false;
    final deliveryController = TextEditingController();
    final offerController = TextEditingController(text: '25');
    final agreedController = TextEditingController(
        text: (agreedOffer ?? (product['price_sle'] ?? 0)).toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: Text('Buy ${product['title']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Text('Price: SLE ${product['price_sle']}'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Collect from Shop'),
                subtitle: const Text('No delivery fee'),
                value: collectInStore,
                onChanged: (v) => setDialogState(() => collectInStore = v),
              ),
              const SizedBox(height: 6),
              if (!collectInStore) ...[
                TextField(
                  controller: offerController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Delivery Offer (SLE)',
                    helperText: 'Offer what the delivery is worth to you',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kNyqAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deliveryController,
                  decoration: InputDecoration(
                    labelText: 'Delivery Address',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kNyqAccent, width: 1.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: agreedController,
                keyboardType: TextInputType.number,
                readOnly: agreedOffer != null,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Agreed Price (SLE)',
                  helperText: agreedOffer != null
                      ? 'You agreed to SLE ${agreedOffer.toStringAsFixed(0)} in chat with the seller.'
                      : 'Change this if you agreed a deal in chat',
                  helperMaxLines: 2,
                  helperStyle: agreedOffer != null
                      ? const TextStyle(
                          color: kNyqGreen,
                          fontWeight: FontWeight.w600)
                      : null,
                  suffixIcon: agreedOffer != null
                      ? const Icon(Icons.lock_outline,
                          size: 18, color: kNyqGreen)
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: kNyqAccent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!collectInStore) ...[
                Row(
                  children: [
                    const Text('Item Price', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text('SLE ${_agreed(product, agreedController)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Delivery Offer',
                        style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                        'SLE ${(double.tryParse(offerController.text.trim()) ?? 25).toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Pay Shop (SLE ${_agreed(product, agreedController)})',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _payCard(
                    shopPaymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                _payCard(
                    shopPaymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                _payCard(
                    shopPaymentMethod,
                    'shop_on_pickup',
                    'Shop is paid on pickup',
                    Icons.handshake_outlined,
                    'Worker pays the shop and collects the total from you',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                const SizedBox(height: 16),
                Text(
                    'Pay Job Worker (SLE ${(double.tryParse(offerController.text.trim()) ?? 25).toStringAsFixed(0)})',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _payCard(
                    workerPaymentMethod,
                    'cash_on_delivery',
                    'Cash on Delivery',
                    Icons.payments_outlined,
                    'Pay the worker when the goods arrive',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
                _payCard(
                    workerPaymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
                _payCard(
                    workerPaymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
              ] else ...[
                _payCard(
                    paymentMethod,
                    'cash_on_delivery',
                    'Cash at Shop',
                    Icons.payments_outlined,
                    'Pay the seller when you collect',
                    (v) => setDialogState(() => paymentMethod = v)),
                _payCard(
                    paymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => paymentMethod = v)),
                _payCard(
                    paymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => paymentMethod = v)),
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kNyqAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                if (!collectInStore && deliveryController.text.isEmpty) {
                  return;
                }
                final response = await http.post(
                  Uri.parse('$baseUrl/orders/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                  },
                  body: jsonEncode({
                    'customer_id': _currentUser!['id'],
                    'merchant_id': product['merchant_id'],
                    'product_id': product['id'],
                    'pickup_address': 'Freetown Central Market',
                    'delivery_address': collectInStore
                        ? 'Collect from shop'
                        : deliveryController.text,
                    'delivery_fee_sle': collectInStore
                        ? 0.0
                        : (double.tryParse(offerController.text.trim()) ?? 25.0),
                    'delivery_offer': collectInStore
                        ? null
                        : (double.tryParse(offerController.text.trim()) ?? 25.0),
                    'requires_delivery': !collectInStore,
                    'agreed_price': _agreed(product, agreedController),
                    'payment_method':
                        collectInStore ? paymentMethod : shopPaymentMethod,
                    'worker_payment_method':
                        collectInStore ? null : workerPaymentMethod,
                  }),
                );
                var newOrderId = '';
                try {
                  final decoded = jsonDecode(response.body);
                  if (decoded is Map) {
                    final ord = decoded['order'];
                    if (ord is Map && ord['id'] != null) {
                      newOrderId = ord['id'].toString();
                    } else if (decoded['id'] != null) {
                      newOrderId = decoded['id'].toString();
                    }
                  }
                } catch (_) {
        showNetworkError(context, 'your orders');
      }
                if (mounted) {
                  Navigator.pop(ctx);
                  final shopMethod =
                      collectInStore ? paymentMethod : shopPaymentMethod;
                  if (shopMethod == 'orange_money' ||
                      shopMethod == 'africell_money') {
                    final shopPhone =
                        (product['shop_phone'] ?? '+232 78 839002').toString();
                    showMobileMoneyInstructions(
                      context,
                      method: shopMethod,
                      shopPhone: shopPhone,
                      total: '${_agreed(product, agreedController)}',
                      orderRef: 'NYG-$newOrderId',
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Order placed! A job worker will be assigned.')),
                    );
                  }
                }
              },
                child: const Text('Confirm Order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isOwner {
    final role = (shop['my_role'] ?? '').toString();
    if (role.isNotEmpty) return role == 'owner' || role == 'admin';
    if (_currentUser == null) return false;
    return _currentUser!['phone_number'] == shop['phone_number'];
  }

  Future<void> _showEditShopDialog() async {
    final shopNameController =
        TextEditingController(text: shop['shop_name'] ?? '');
    final ownerNameController =
        TextEditingController(text: shop['owner_name'] ?? '');
    final phoneController =
        TextEditingController(text: shop['phone_number'] ?? '');
    final cityController =
        TextEditingController(text: shop['city'] ?? 'Freetown');
    String? currentLogo = shop['logo_url'];
    String selectedCategory = shop['category'] ?? 'Other';
    String selectedTheme = shop['theme_colour'] ?? '#1B5E20';
    String selectedBg = shop['background_colour'] ?? '#FFFFFF';
    final bioController =
        TextEditingController(text: shop['description'] ?? '');
    final whatsappController =
        TextEditingController(text: shop['whatsapp_number'] ?? '');
    String? currentBanner = shop['banner_url'];
    final igController =
        TextEditingController(text: shop['instagram_url'] ?? '');
    final ttController =
        TextEditingController(text: shop['tiktok_url'] ?? '');
    final xController =
        TextEditingController(text: shop['twitter_url'] ?? '');
    double? shopLat = (shop['latitude'] as num?)?.toDouble();
    double? shopLng = (shop['longitude'] as num?)?.toDouble();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Shop Info'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: shopNameController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ownerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Owner Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Address (Optional)',
                    hintText: 'Leave blank if you set a map pin',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bioController,
                  maxLines: 3,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Shop Bio',
                    hintText: 'Tell customers about your shop',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Number',
                    hintText: '+232 78 839002',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: igController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Instagram URL',
                    hintText: 'instagram.com/yourshop',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ttController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'TikTok URL',
                    hintText: 'tiktok.com/@yourshop',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: xController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'X (Twitter) URL',
                    hintText: 'x.com/yourshop',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = await pickAndUploadImage(context);
                      if (url != null) {
                        setDialogState(() => currentLogo = url);
                      }
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: Text((currentLogo ?? '').isEmpty
                        ? 'Pick Shop Logo'
                        : 'Change Logo'),
                  ),
                ),
                if ((currentLogo ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        currentLogo ?? '',
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = await pickAndUploadImage(context);
                      if (url != null) {
                        setDialogState(() => currentBanner = url);
                      }
                    },
                    icon: const Icon(Icons.wallpaper),
                    label: Text((currentBanner ?? '').isEmpty
                        ? 'Upload Banner Image'
                        : 'Change Banner'),
                  ),
                ),
                if ((currentBanner ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        currentBanner ?? '',
                        height: 90,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                _buildModeToggle(
                  selectedBg: selectedBg,
                  onBg: (hex) => setDialogState(() => selectedBg = hex),
                  onHeader: (hex) => setDialogState(() => selectedTheme = hex),
                ),
                const SizedBox(height: 12),
                _buildColourPicker(
                  label: 'Header Colour',
                  selectedHex: selectedTheme,
                  onPick: (hex) => setDialogState(() => selectedTheme = hex),
                ),
                const SizedBox(height: 14),
                _buildColourPicker(
                  label: 'Background Colour',
                  selectedHex: selectedBg,
                  onPick: (hex) => setDialogState(() => selectedBg = hex),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Fashion', child: Text('Fashion')),
                    DropdownMenuItem(value: 'Food', child: Text('Food & Groceries')),
                    DropdownMenuItem(value: 'Electronics', child: Text('Electronics')),
                    DropdownMenuItem(value: 'Home', child: Text('Home & Furniture')),
                    DropdownMenuItem(value: 'Beauty', child: Text('Beauty & Health')),
                    DropdownMenuItem(value: 'Services', child: Text('Services')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kNyqSand,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0DAD2)),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 110,
                        child: shopLat == null || shopLng == null
                            ? Center(
                                child: Text(
                                  'No location set - customers cannot find you on the map',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter:
                                        LatLng(shopLat!, shopLng!),
                                    initialZoom: 15,
                                    interactionOptions:
                                        const InteractionOptions(
                                            flags: InteractiveFlag.none),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: kOsmTileUrl,
                                      userAgentPackageName: 'com.nyg.app',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: LatLng(
                                              shopLat!, shopLng!),
                                          width: 28,
                                          height: 28,
                                          child: const Icon(
                                              Icons.location_on,
                                              size: 28,
                                              color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      if (shopLat != null && shopLng != null)
                        Text(
                          'Lat ${shopLat!.toStringAsFixed(5)}, '
                          'Lng ${shopLng!.toStringAsFixed(5)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Pick Location on Map'),
                          onPressed: () async {
                            final picked = await Navigator.push<LatLng>(
                              ctx,
                              MaterialPageRoute(
                                builder: (_) => ShopLocationPickerScreen(
                                  initial: shopLat != null && shopLng != null
                                      ? LatLng(shopLat!, shopLng!)
                                      : null,
                                ),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                shopLat = picked.latitude;
                                shopLng = picked.longitude;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (shopLat == null || shopLng == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Please set your shop location on the map so customers can find you.')),
                  );
                  return;
                }
                final user = await UserSession.load();
                final response = await http.put(
                  Uri.parse('$baseUrl/merchants/${shop['id']}'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                    'Authorization': 'Bearer ${user?['token'] ?? ''}',
                  },
                  body: jsonEncode({
                    'shop_name': shopNameController.text,
                    'owner_name': ownerNameController.text,
                    'phone_number': phoneController.text,
                    'city': cityController.text.trim().isEmpty
                        ? null
                        : cityController.text.trim(),
                    'category': selectedCategory,
                    'logo_url': currentLogo,
                    'theme_colour': selectedTheme,
                    'background_colour': selectedBg,
                    'description': bioController.text.trim(),
                    'whatsapp_number': whatsappController.text.trim(),
                    'banner_url': currentBanner,
                    'instagram_url': igController.text.trim(),
                    'tiktok_url': ttController.text.trim(),
                    'twitter_url': xController.text.trim(),
                    if (shopLat != null) 'latitude': shopLat,
                    if (shopLng != null) 'longitude': shopLng,
                  }),
                );

                if (response.statusCode >= 200 && response.statusCode < 300) {
                  final updated = jsonDecode(response.body)['merchant'];
                  await ShopSession.save(updated);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => shop = Map<String, dynamic>.from(updated));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Shop updated')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to update shop')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String get _shopInitial {
    final n = (shop['shop_name'] ?? '').toString().trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        surfaceTintColor: _pageBackground,
        foregroundColor: _pageTextColour,
        elevation: 0,
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit shop info',
              onPressed: _showEditShopDialog,
            ),
          if (_isOwner)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _deleteShop();
                if (value == 'profile') _openEditProfile();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem<String>(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline),
                      SizedBox(width: 8),
                      Text('Edit Profile'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Shop', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if ((shop['banner_url'] ?? '').toString().isNotEmpty)
            Image.network(
              shop['banner_url'].toString(),
              width: double.infinity,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 150,
                width: double.infinity,
                color: _headerColour,
                child: Icon(Icons.storefront_outlined,
                    size: 44, color: _headerTextColour.withAlpha(120)),
              ),
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 150,
                      width: double.infinity,
                      color: _headerColour,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white70),
                        ),
                      ),
                    ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            color: _headerColour,
            width: double.infinity,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: _headerTextColour),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(
                  children: [
                    ClipOval(
                      child: Container(
                        width: 48,
                        height: 48,
                        color: _headerTextColour == Colors.white
                            ? Colors.white24
                            : const Color(0xFF1B5E20),
                        child: (shop['logo_url'] ?? '')
                                .toString()
                                .trim()
                                .isEmpty
                            ? Center(
                                child: Text(
                                  _shopInitial,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              )
                            : Image.network(
                                shop['logo_url'].toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    _shopInitial,
                                    style: const TextStyle(
                                        fontSize: 22,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop['shop_name'] ?? 'Shop',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (shop['owner_name'] != null)
                            Text(
                              'Owner: ${shop['owner_name']}',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((shop['description'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      shop['description'].toString().trim(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: _headerTextColour.withAlpha(200),
                      ),
                    ),
                  ),
                if ((shop['whatsapp_number'] ?? '').toString().isNotEmpty ||
                    (shop['instagram_url'] ?? '').toString().isNotEmpty ||
                    (shop['tiktok_url'] ?? '').toString().isNotEmpty ||
                    (shop['twitter_url'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        if ((shop['whatsapp_number'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _socialDot(
                              'WA', const Color(0xFF25D366), _openWhatsApp),
                        if ((shop['instagram_url'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _socialDot(
                              'IG',
                              const Color(0xFFE1306C),
                              () => _launchExternal(
                                  shop['instagram_url']?.toString())),
                        if ((shop['tiktok_url'] ?? '').toString().isNotEmpty)
                          _socialDot(
                              'TT',
                              const Color(0xFF111111),
                              () => _launchExternal(
                                  shop['tiktok_url']?.toString())),
                        if ((shop['twitter_url'] ?? '').toString().isNotEmpty)
                          _socialDot(
                              'X',
                              const Color(0xFF111111),
                              () => _launchExternal(
                                  shop['twitter_url']?.toString())),
                      ],
                    ),
                  ),
                if ((shop['owner_user_id'] ?? 0) != 0 &&
                    shop['owner_user_id'] != widget.currentUser?['id'])
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _headerTextColour == Colors.white
                              ? kNyqGreen
                              : Colors.white,
                          foregroundColor: _headerTextColour == Colors.white
                              ? Colors.white
                              : kNyqGreen,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otherUserId:
                                    (shop['owner_user_id'] as num).toInt(),
                                otherUserName:
                                    (shop['shop_name'] ?? 'Shop').toString(),
                                shopId: shop['id'],
                                initialMessage:
                                    'Hi, I would like to ask about your products.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Message & Buy'),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (shop['city'] != null)
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('${shop['city']}, Sierra Leone',
                          style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (shop['category'] != null) ...[
                      Icon(Icons.category,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(shop['category'] ?? '',
                          style: TextStyle(color: Colors.grey.shade700)),
                    ],
                    if (_isOwner && shop['phone_number'] != null) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(shop['phone_number'] ?? '',
                          style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ],
                ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(Icons.inventory_2, size: 18, color: _pageTextColour),
                const SizedBox(width: 8),
                Text(
                  '${products.length} product${products.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _pageTextColour),
                ),
                const Spacer(),
                if (_isOwner)
                  ElevatedButton.icon(
                    onPressed: _showAddItemDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Product'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ShopProductGrid(
                    products: products,
                    cardColour: Colors.white.withAlpha(230),
                    accentColour: _headerColour,
                    onEdit: _isOwner ? _showEditProductDialog : null,
                    emptyActionLabel: _isOwner ? 'Add Product' : null,
                    emptyAction: _isOwner ? _showAddItemDialog : null,
                    onBuy: _showCheckout,
                    onDelete: _isOwner
                        ? (product) => _deleteProduct(
                              product['id'],
                              product['title'] ?? 'this product',
                            )
                        : null,
                    onOpen: (product) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(
                          product: product,
                          onBuy: _showCheckout,
                          onDelete: _isOwner
                              ? (p) => _deleteProduct(
                                  p['id'], p['title'] ?? 'this product')
                              : null,
                          isOwner: _isOwner,
                          themeColour: _headerColour,
                          sellerUserId: product['seller_user_id'],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SHOPS BROWSE SCREEN
// ==========================================
class _ShopBanner extends StatefulWidget {
  final Map<String, dynamic> product;
  const _ShopBanner({required this.product});

  @override
  State<_ShopBanner> createState() => _ShopBannerState();
}

class _ShopBannerState extends State<_ShopBanner> {
  Map<String, dynamic>? _merchant;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.product['merchant_id'];
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/$id'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() => _merchant =
              Map<String, dynamic>.from(data['merchant'] ?? data));
        }
      }
    } catch (_) {
        showNetworkError(context, 'shop details');
      }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openShop() async {
    if (widget.product['merchant_id'] == null) return;
    if (_merchant == null) {
      await _load();
      if (!mounted || _merchant == null) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPageScreen(shop: _merchant!),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final shopName =
        (_merchant?['shop_name'] ?? widget.product['shop_name'] ?? 'Shop')
            .toString();
    final city =
        (_merchant?['city'] ?? widget.product['shop_city'] ?? '').toString();
    final logo = (_merchant?['logo_url'] ?? '').toString();

    return InkWell(
      onTap: _openShop,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF1B5E20),
              backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
              child: logo.isEmpty
                  ? Text(
                      shopName.isNotEmpty ? shopName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (city.isNotEmpty)
                    Text(
                      city,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

String generateGuestPassword() {
  final rnd = Random.secure();
  return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
}

Future<Map<String, dynamic>?> guestSignupFlow(BuildContext context) async {
  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();
  final passCtl = TextEditingController();
  bool busy = false;
  bool loginMode = false;
  String? error;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> submit() async {
          final name = nameCtl.text.trim();
          final phone = normalisePhone(phoneCtl.text);
          if (phone.isEmpty) {
            setDialogState(() => error = 'Enter your phone number.');
            return;
          }
          if (!loginMode && name.isEmpty) {
            setDialogState(() => error = 'Enter your name.');
            return;
          }
          if (loginMode && passCtl.text.isEmpty) {
            setDialogState(() => error = 'Enter your password.');
            return;
          }
          setDialogState(() {
            busy = true;
            error = null;
          });
          try {
            final url =
                loginMode ? '$baseUrl/auth/login' : '$baseUrl/auth/signup';
            final body = loginMode
                ? {'phone_number': phone, 'password': passCtl.text}
                : {
                    'phone_number': phone,
                    'name': name,
                    'password': generateGuestPassword(),
                    'role': 'customer',
                  };
            final res = await http
                .post(
                  Uri.parse(url),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                  },
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 12));
            final data = jsonDecode(res.body);
            if (res.statusCode >= 200 && res.statusCode < 300) {
              final user = {
                ...Map<String, dynamic>.from(data['user'] as Map),
                'token': data['token'],
              };
              await UserSession.save(user, data['token'] as String);
              if (context.mounted) Navigator.pop(ctx, user);
              return;
            }
            final detail =
                (data['detail'] ?? 'Could not continue.').toString();
            final already = detail.toLowerCase().contains('already');
            setDialogState(() {
              busy = false;
              if (already && !loginMode) {
                loginMode = true;
                error =
                    'This number already has an account. Enter your password to log in.';
              } else {
                error = detail;
              }
            });
          } catch (_) {
            setDialogState(() {
              busy = false;
              error = 'Network error. Please try again.';
            });
          }
        }

        return AlertDialog(
          title: Text(loginMode ? 'Log In to Buy' : 'Continue as Guest'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loginMode
                    ? 'Your number is already registered. Enter your password.'
                    : 'Just your name and phone number to buy.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (!loginMode) ...[
                TextField(
                  controller: nameCtl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: phoneCtl,
                keyboardType: TextInputType.phone,
                enabled: !loginMode,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+232 78 839002',
                  border: OutlineInputBorder(),
                ),
              ),
              if (loginMode) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: passCtl,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style:
                      const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(loginMode ? 'Log In' : 'Continue'),
            ),
          ],
        );
      },
    ),
  );

  nameCtl.dispose();
  phoneCtl.dispose();
  passCtl.dispose();
  return result;
}
class ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;
  final void Function(Map<String, dynamic> product) onBuy;
  final void Function(Map<String, dynamic> product)? onDelete;
  final bool isOwner;
  final int? sellerUserId;
  final Color? themeColour;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.onBuy,
    this.onDelete,
    this.isOwner = false,
    this.sellerUserId,
    this.themeColour,
  });

  Color get _accent => themeColour ?? const Color(0xFF1B5E20);

  Color get _onAccent =>
      ThemeData.estimateBrightnessForColor(_accent) == Brightness.dark
          ? Colors.white
          : Colors.black87;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: _onAccent,
        surfaceTintColor: _accent,
        elevation: 0,
        title: Text(product['title'] ?? 'Product'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(builder: (context) {
              final photos = productPhotos(product);
              if (photos.isEmpty) {
                return SizedBox(
                  height: 280,
                  child: Container(
                    color: Colors.white,
                    child: const Center(
                      child: Icon(Icons.shopping_bag, size: 80, color: Colors.grey),
                    ),
                  ),
                );
              }
              if (photos.length == 1) {
                return SizedBox(
                  height: 280,
                  child: Container(
                    color: Colors.white,
                    child: Image.network(
                      photos[0],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.shopping_bag, size: 80, color: Colors.grey),
                      ),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 280,
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: photos.length,
                      itemBuilder: (ctx, i) => Container(
                        color: Colors.white,
                        child: Image.network(
                          photos[i],
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.shopping_bag, size: 80, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '${photos.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['title'] ?? 'Product',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SLE ${product['price_sle']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(
                      (product['category'] ?? 'Other').toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 32),
                  _ShopBanner(product: product),
                  const SizedBox(height: 24),
                  const Text(
                    'Description',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product['description'] ?? 'No description provided.',
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (isOwner && onDelete != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    onDelete!(product);
                    Navigator.pop(context);
                  },
                ),
              if (isOwner && onDelete != null) const SizedBox(width: 8),
              if (!isOwner && sellerUserId != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B5E20),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message & Buy'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUserId: sellerUserId!,
                        otherUserName: product['shop_name'] ?? 'Seller',
                        shopId: product['merchant_id'],
                        productId: (product['id'] as num?)?.toInt(),
                        initialMessage:
                            'Hi, I would like to negotiate the price of this item.',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kNyqAccent, kNyqAccentDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: kNyqAccent.withAlpha(85),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        onBuy(product);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.shopping_cart,
                                size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Buy Now',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
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
      ),
    );
  }
}

// ==========================================
// MARKETPLACE SCREEN
// ==========================================
class MarketplaceScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;

  const MarketplaceScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  List<dynamic> products = [];
  Map<String, dynamic>? myShop;
  bool isLoading = true;
  String selectedFilterCategory = 'All';
  String searchQuery = '';

  final List<String> categories = const [
    'All', 'Fashion', 'Food', 'Electronics', 'Home', 'Beauty', 'Services', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() => isLoading = true);
    myShop = await ShopSession.load();
    await fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/products/'));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() {
          products = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  List<dynamic> get filteredProducts {
    var list = products;
    if (selectedFilterCategory != 'All') {
      list = list.where((p) => p['category'] == selectedFilterCategory).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((p) {
        final title = (p['title'] ?? '').toString().toLowerCase();
        final shop = (p['shop_name'] ?? '').toString().toLowerCase();
        final cat = (p['category'] ?? '').toString().toLowerCase();
        return title.contains(q) || shop.contains(q) || cat.contains(q);
      }).toList();
    }
    return list;
  }

  Future<bool> _ensureLoggedIn({String? suggestedRole}) async {
    if (widget.currentUser != null) return true;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(suggestedRole: suggestedRole),
      ),
    );

    if (result == true) {
      widget.onUserChanged();
      return true;
    }
    return false;
  }

  double _agreed(dynamic product, TextEditingController c) {
    final typed = double.tryParse(c.text.trim());
    if (typed != null && typed > 0) return typed;
    return (product['price_sle'] as num? ?? 0).toDouble();
  }

  Widget _payCard(String current, String value, String label, IconData icon,
      String hint, ValueChanged<String> onPick) {
    final selected = current == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onPick(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? kNyqAccent.withAlpha(18) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kNyqAccent : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: selected ? kNyqAccent : Colors.grey.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: selected ? kNyqAccent : kNyqInk)),
                    if (hint.isNotEmpty)
                      Text(hint,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: kNyqAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCheckout(dynamic product) async {
    var buyer = widget.currentUser;
    if (buyer == null) {
      final guest = await guestSignupFlow(context);
      if (guest == null || !mounted) return;
      widget.onUserChanged();
      buyer = guest;
    }
    if (!mounted) return;

    double? agreedOffer;
    try {
      final u = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/products/${product['id']}/my-offer'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${u?['token'] ?? ''}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final o = jsonDecode(res.body)['offer'];
        if (o is Map && o['amount_sle'] != null) {
          agreedOffer = (o['amount_sle'] as num).toDouble();
        }
      }
    } catch (_) {
        showNetworkError(context, 'products');
      }

    String paymentMethod = 'cash_on_delivery';
    String shopPaymentMethod = 'orange_money';
    String workerPaymentMethod = 'cash_on_delivery';
    bool collectInStore = false;
    final deliveryController = TextEditingController();
    final offerController = TextEditingController(text: '25');
    final agreedController = TextEditingController(
        text: (agreedOffer ?? (product['price_sle'] ?? 0)).toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: Text('Buy ${product['title']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Text('Price: SLE ${product['price_sle']}'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Collect from Shop'),
                subtitle: const Text('No delivery fee'),
                value: collectInStore,
                onChanged: (v) => setDialogState(() => collectInStore = v),
              ),
              const SizedBox(height: 6),
              if (!collectInStore) ...[
                TextField(
                  controller: offerController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Delivery Offer (SLE)',
                    helperText: 'Offer what the delivery is worth to you',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kNyqAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deliveryController,
                  decoration: InputDecoration(
                    labelText: 'Delivery Address',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kNyqAccent, width: 1.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: agreedController,
                keyboardType: TextInputType.number,
                readOnly: agreedOffer != null,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Agreed Price (SLE)',
                  helperText: agreedOffer != null
                      ? 'You agreed to SLE ${agreedOffer.toStringAsFixed(0)} in chat with the seller.'
                      : 'Change this if you agreed a deal in chat',
                  helperMaxLines: 2,
                  helperStyle: agreedOffer != null
                      ? const TextStyle(
                          color: kNyqGreen,
                          fontWeight: FontWeight.w600)
                      : null,
                  suffixIcon: agreedOffer != null
                      ? const Icon(Icons.lock_outline,
                          size: 18, color: kNyqGreen)
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: kNyqAccent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!collectInStore) ...[
                Row(
                  children: [
                    const Text('Item Price', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text('SLE ${_agreed(product, agreedController)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Delivery Offer',
                        style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                        'SLE ${(double.tryParse(offerController.text.trim()) ?? 25).toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Pay Shop (SLE ${_agreed(product, agreedController)})',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _payCard(
                    shopPaymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                _payCard(
                    shopPaymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                _payCard(
                    shopPaymentMethod,
                    'shop_on_pickup',
                    'Shop is paid on pickup',
                    Icons.handshake_outlined,
                    'Worker pays the shop and collects the total from you',
                    (v) => setDialogState(() => shopPaymentMethod = v)),
                const SizedBox(height: 16),
                Text(
                    'Pay Job Worker (SLE ${(double.tryParse(offerController.text.trim()) ?? 25).toStringAsFixed(0)})',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _payCard(
                    workerPaymentMethod,
                    'cash_on_delivery',
                    'Cash on Delivery',
                    Icons.payments_outlined,
                    'Pay the worker when the goods arrive',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
                _payCard(
                    workerPaymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
                _payCard(
                    workerPaymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => workerPaymentMethod = v)),
              ] else ...[
                _payCard(
                    paymentMethod,
                    'cash_on_delivery',
                    'Cash at Shop',
                    Icons.payments_outlined,
                    'Pay the seller when you collect',
                    (v) => setDialogState(() => paymentMethod = v)),
                _payCard(
                    paymentMethod,
                    'orange_money',
                    'Orange Money',
                    Icons.smartphone,
                    '*144#',
                    (v) => setDialogState(() => paymentMethod = v)),
                _payCard(
                    paymentMethod,
                    'africell_money',
                    'Afrimoney',
                    Icons.phone_android,
                    '*161#',
                    (v) => setDialogState(() => paymentMethod = v)),
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kNyqAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                if (!collectInStore && deliveryController.text.isEmpty) {
                  return;
                }
                final response = await http.post(
                  Uri.parse('$baseUrl/orders/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                  },
                  body: jsonEncode({
                    'customer_id': buyer!['id'],
                    'merchant_id': product['merchant_id'],
                    'product_id': product['id'],
                    'pickup_address': 'Freetown Central Market',
                    'delivery_address': collectInStore
                        ? 'Collect from shop'
                        : deliveryController.text,
                    'delivery_fee_sle': collectInStore
                        ? 0.0
                        : (double.tryParse(offerController.text.trim()) ?? 25.0),
                    'delivery_offer': collectInStore
                        ? null
                        : (double.tryParse(offerController.text.trim()) ?? 25.0),
                    'requires_delivery': !collectInStore,
                    'agreed_price': _agreed(product, agreedController),
                    'payment_method':
                        collectInStore ? paymentMethod : shopPaymentMethod,
                    'worker_payment_method':
                        collectInStore ? null : workerPaymentMethod,
                  }),
                );
                var newOrderId = '';
                try {
                  final decoded = jsonDecode(response.body);
                  if (decoded is Map) {
                    final ord = decoded['order'];
                    if (ord is Map && ord['id'] != null) {
                      newOrderId = ord['id'].toString();
                    } else if (decoded['id'] != null) {
                      newOrderId = decoded['id'].toString();
                    }
                  }
                } catch (_) {
        showNetworkError(context, 'your orders');
      }
                if (mounted) {
                  Navigator.pop(ctx);
                  final shopMethod =
                      collectInStore ? paymentMethod : shopPaymentMethod;
                  if (shopMethod == 'orange_money' ||
                      shopMethod == 'africell_money') {
                    final shopPhone =
                        (product['shop_phone'] ?? '+232 78 839002').toString();
                    showMobileMoneyInstructions(
                      context,
                      method: shopMethod,
                      shopPhone: shopPhone,
                      total: '${_agreed(product, agreedController)}',
                      orderRef: 'NYG-$newOrderId',
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Order placed! A job worker will be assigned.')),
                    );
                  }
                }
              },
                child: const Text('Confirm Order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = filteredProducts;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
        actions: [
          AccountButton(
              currentUser: widget.currentUser,
              onUserChanged: widget.onUserChanged,
              ensureLoggedIn: _ensureLoggedIn,
              onSignOut: () {
                if (mounted) setState(() => myShop = null);
              },
              onRefreshUser: () {
                if (mounted) setState(() {});
              },
              currentShop: myShop),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search products, shops, categories...',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade500, fontSize: 14),
                      prefixIcon:
                          Icon(Icons.search, color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: Color(0xFF1B5E20), width: 1.5),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 18, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: categories.length,
                    itemBuilder: (ctx, i) {
                      final cat = categories[i];
                      final selected = cat == selectedFilterCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: selected,
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.white,
                          selectedColor: const Color(0xFF1B5E20),
                          side: selected
                              ? BorderSide.none
                              : BorderSide(color: Colors.grey.shade300),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                          onSelected: (val) {
                            setState(() => selectedFilterCategory = cat);
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: visible.isEmpty
                      ? EmptyState(
                          icon: Icons.storefront_outlined,
                          title: searchQuery.isNotEmpty
                              ? 'No matches for "$searchQuery"'
                              : selectedFilterCategory == 'All'
                                  ? 'No products yet'
                                  : 'Nothing in "$selectedFilterCategory"',
                          message: searchQuery.isNotEmpty
                              ? 'Try a different search.'
                              : 'Check back soon!',
                        )
                      : ShopProductGrid(
                          products: visible,
                          onBuy: _showCheckout,
                          onRefresh: fetchProducts,
                          onOpen: (product) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(
                                product: product,
                                onBuy: _showCheckout,
                                isOwner: false,
                                sellerUserId: product['seller_user_id'],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}


// ==========================================
// SHOP PROFILE — SELLER'S OWN VIEW
// ==========================================

// ==========================================
// RUNNER DASHBOARD
// ==========================================
class RunnerDashboardScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;

  const RunnerDashboardScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<RunnerDashboardScreen> createState() => _RunnerDashboardScreenState();
}

class _RunnerDashboardScreenState extends State<RunnerDashboardScreen> {
  List<dynamic> jobs = [];
  bool _loadingJobs = false;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    final u = widget.currentUser;
    _isOnline = u != null && (u['is_online'] == 1 || u['is_online'] == true);
    fetchJobs();
  }

  Future<bool> _ensureLoggedIn({String? suggestedRole}) async {
    if (widget.currentUser != null) return true;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(suggestedRole: suggestedRole),
      ),
    );

    if (result == true) {
      widget.onUserChanged();
      return true;
    }
    return false;
  }

  Future<void> _setOnline(bool v) async {
    setState(() => _isOnline = v);
    final ok = await UserSession.update({'is_online': v ? 1 : 0});
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change your status')),
      );
      setState(() => _isOnline = !v);
      return;
    }
    await fetchJobs();
  }

  Future<void> fetchJobs() async {
    setState(() => _loadingJobs = true);
    try {
      final user = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/deliveries/available/'),
        headers: {
          'x-api-key': apiKey,
          if (user?['token'] != null)
            'Authorization': 'Bearer ${user!['token']}',
        },
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => jobs = jsonDecode(res.body));
      } else {
        setState(() => jobs = []);
      }
    } catch (_) {
        showNetworkError(context, 'data');
      }
    if (mounted) setState(() => _loadingJobs = false);
  }

  Future<bool> _ensureLoggedInAsRunner() async {
    if (widget.currentUser != null) {
      if (isRunner(widget.currentUser)) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Only job workers can accept jobs.')),
      );
      return false;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthScreen(suggestedRole: 'driver'),
      ),
    );

    if (result == true) {
      widget.onUserChanged();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
        actions: [
          AccountButton(
              currentUser: widget.currentUser,
              onUserChanged: widget.onUserChanged,
              ensureLoggedIn: _ensureLoggedIn),
        ],
      ),
      body: Column(
        children: [
          if (isRunner(widget.currentUser))
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  Icon(_isOnline ? Icons.bolt : Icons.bolt_outlined,
                      color: _isOnline ? kNyqGreen : Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isOnline ? 'You are online' : 'You are offline',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color:
                            _isOnline ? kNyqGreen : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isOnline,
                    onChanged: (v) => _setOnline(v),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadingJobs
                ? const Center(child: CircularProgressIndicator())
                : jobs.isEmpty
                    ? EmptyState(
                        icon: Icons.work_off,
                        title: 'No jobs available',
                        message: _isOnline
                            ? 'Check back later - new jobs appear here.'
                            : 'Check back later or toggle online.',
                        actionLabel: 'Refresh',
                        onAction: fetchJobs,
                      )
                    : ListView.builder(
                        itemCount: jobs.length,
                        itemBuilder: (ctx, i) {
                          final job = jobs[i];
                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (job['shipment_id'] != null) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.local_shipping,
                                            size: 18, color: kNyqOchre),
                                        const SizedBox(width: 6),
                                        Text('SHIPMENT ${job['shipment_tracking'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: kNyqOchre,
                                                letterSpacing: 0.5)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Pick up shipment from ${job['shipment_origin'] ?? 'abroad'} and deliver to ${job['shipment_receiver_name'] ?? 'the shop'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Row(
                                    children: [
                                      const Icon(Icons.work_outline,
                                          size: 20, color: kNyqAccent),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Address: ${job['delivery_address']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Offer: SLE ${job['delivery_offer'] ?? job['delivery_fee_sle']}',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: kNyqGreen),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Payment: ${job['payment_method']}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                  if (job['payment_method'] == 'shop_on_pickup') ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Collect SLE ${(job['product_price_sle'] ?? 0) + (job['delivery_offer'] ?? job['delivery_fee_sle'] ?? 0)} from customer, pay shop SLE ${job['product_price_sle'] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: kNyqAccent),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () async {

                                  final ok = await _ensureLoggedInAsRunner();
                                  if (!ok) return;

                                  final session = await UserSession.load();
                                  final res = await http.put(
                                    Uri.parse(
                                        '$baseUrl/deliveries/${job['id']}/accept/${widget.currentUser!['id']}'),
                                    headers: {
                                      'x-api-key': apiKey,
                                      'Authorization':
                                          'Bearer ${session?['token'] ?? ''}',
                                    },
                                  );
                                  if (!mounted) return;
                                  if (res.statusCode < 200 ||
                                      res.statusCode >= 300) {
                                    showApiError(context, res.statusCode, res.body,
                                        fallback: 'Could not accept job.');
                                  }
                                  fetchJobs();
                                
                                          },
                                          child: const Text('Accept Job'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(
                                              Icons.chat_bubble_outline,
                                              size: 16),
                                          label: const Text('Negotiate'),
                                          onPressed: job['customer_id'] == null
                                              ? null
                                              : () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ChatScreen(
                                                        otherUserId: (job[
                                                                    'customer_id']
                                                                as num)
                                                            .toInt(),
                                                        otherUserName:
                                                            'Customer',
                                                        initialMessage:
                                                            'Hi, I would like to negotiate the delivery fee for this job.',
                                                        orderId: job['id'],
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

}

// ==========================================
// MY ORDERS SCREEN
// ==========================================
class MyOrdersScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  const MyOrdersScreen({super.key, required this.currentUser});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<dynamic> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() => isLoading = true);
    try {
      final session = await UserSession.load();
      final res = await http.get(
        Uri.parse('$baseUrl/orders/customer/${widget.currentUser['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization':
              'Bearer ${session?['token'] ?? ''}',
        },
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() {
          orders = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'accepted':
      case 'in_transit':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOrders,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: "Looks like you haven't bought anything!",
                  actionLabel: 'Start Shopping',
                  onAction: () => Navigator.pop(context),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: orders.length,
                  itemBuilder: (ctx, i) {
                    final order = orders[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(
                              orderId: (order['id'] as num).toInt(),
                              currentUserRole: 'customer',
                            ),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      order['product_title'] ?? 'Order',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(
                                              order['delivery_status'] ?? '')
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      (order['delivery_status'] ?? 'pending')
                                          .toString()
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _statusColor(
                                            order['delivery_status'] ?? ''),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Shop: ${order['shop_name'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total: SLE ${(order['price_sle'] ?? 0) + (order['delivery_fee_sle'] ?? 0)}',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Delivery to: ${order['delivery_address'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.payment,
                                      size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${order['payment_method'] ?? ''} • ${order['payment_status'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDate(order['created_at']),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                              if (order['driver_id'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF1B5E20),
                                        ),
                                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                        label: const Text('Message Worker'),
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              otherUserId: (order['driver_id'] as num).toInt(),
                                              otherUserName: 'Job Worker',
                                              orderId: order['id'],
                                            ),
                                          ),
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
                  },
                ),
    );
  }
}