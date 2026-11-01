import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

const String baseUrl = 'https://random.taila91e03.ts.net';
const String apiKey = '3269e65be9a1970f8dc3874d4da06407e19e12d63427e75213bff1785acabfd295';
const String appVersion = '1.0.0';
const Color kNyqBlue = Color(0xFF1A5AD7);
const Color kNyqBlueDeep = Color(0xFF0D47A1);
const Color kNyqAccent = Color(0xFF0D47A1);
const Color kNyqOchre = Color(0xFFD4A017);
const Color kNyqSand = Color(0xFFFAF7F2);
const Color kNyqInk = Color(0xFF231F1C);
const Color kNyqAccentDeep = Color(0xFF072E66);
const Color kNyqGreen = Color(0xFF1B5E20);
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
    if (user['vehicle_type'] != null) {
      await prefs.setString('user_vehicle_type', user['vehicle_type']);
    }
    if (user['is_online'] != null) {
      await prefs.setBool('user_is_online', user['is_online'] == 1 || user['is_online'] == true);
    }
    if (user['photo_url'] != null) {
      await prefs.setString(_photoKey, user['photo_url']);
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
      'vehicle_type': prefs.getString('user_vehicle_type'),
      'is_online': prefs.getBool('user_is_online') ?? false,
      'photo_url': prefs.getString(_photoKey),
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

  static Future<bool> send(int recipientId, String text, {int? shopId, int? orderId}) async {
    lastCallWasUnauthorized = false;
    final user = await UserSession.load();
    if (user == null) return false;
    try {
      // Map<String, dynamic> so the optional int values below can be added.
      final Map<String, dynamic> body = {'recipient_id': recipientId, 'text': text};
      if (shopId != null) body['shop_id'] = shopId;
      if (orderId != null) body['order_id'] = orderId;
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
    BuildContext context, Map<String, dynamic> user) async {
  final business = TextEditingController();
  final city = TextEditingController(text: 'Freetown');
  final about = TextEditingController();
  final phone = TextEditingController(
      text: (user['phone_number'] ?? '').toString());
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
                    labelText: 'Business Name',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                    labelText: 'Business Category',
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
                    labelText: 'Business Address / City',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: about,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'What do you intend to sell?',
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
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (business.text.trim().isEmpty ||
                        about.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please fill in the business name and what you sell')),
                      );
                      return;
                    }
                    setDialogState(() => busy = true);
                    await sendApplication('SELLER APPLICATION', [
                      'Business: ' + business.text.trim(),
                      'Category: ' + category,
                      'City/Address: ' + city.text.trim(),
                      'Intends to sell: ' + about.text.trim(),
                      'Phone: ' + phone.text.trim(),
                      'Account ID: ${user['id']}',
                    ]);
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
    BuildContext context, Map<String, dynamic> user) async {
  final name = TextEditingController(
      text: (user['name'] ?? '').toString());
  final area = TextEditingController(text: 'Freetown');
  final phone = TextEditingController(
      text: (user['phone_number'] ?? '').toString());
  var vehicle = 'Motorbike';
  const vehicles = ['Motorbike', 'Car', 'Bicycle', 'None / Walking'];
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
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
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

String _profileRoleLabel(Map<String, dynamic>? user) {
  if (user == null) return 'Guest';
  final admin = user['is_admin'] == 1 || user['is_admin'] == true;
  if (admin) return 'Admin';
  if (isRunner(user)) return 'Job Worker';
  if (isSeller(user)) return 'Seller';
  return 'Customer';
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
    setState(() {
      _conversations = data;
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('No messages yet.', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      Text('Start a chat from any product page.', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (ctx, i) {
                    final c = _conversations[i];
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
  final int otherUserId;
  final String otherUserName;
  final int? shopId;
  final int? orderId;
  final String? initialMessage;
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.shopId,
    this.orderId,
    this.initialMessage,
  });

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
    if (opening != null &&
        opening.isNotEmpty &&
        _messages.isEmpty &&
        widget.otherUserId != _myId) {
      final sent = await MessageSession.send(
        widget.otherUserId,
        opening,
        shopId: widget.shopId,
        orderId: widget.orderId,
      );
      if (sent) await _load();
    }
    await MessageSession.markRead(widget.otherUserId);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  Future<void> _load() async {
    final msgs = await MessageSession.getConversation(widget.otherUserId);
    if (MessageSession.lastCallWasUnauthorized) {
      if (mounted) handleSessionExpired(context);
      return;
    }
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    _scrollToBottom();
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

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await MessageSession.send(
      widget.otherUserId,
      text,
      shopId: widget.shopId,
      orderId: widget.orderId,
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
      appBar: AppBar(title: Text(widget.otherUserName)),
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
                              child: Text(
                                m['text'] ?? '',
                                style: TextStyle(
                                  color: isMine ? Colors.white : Colors.black87,
                                  fontSize: 15,
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
              child: Row(
                children: [
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
    } catch (_) {}
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            labelColor: kNyqGreen,
            indicatorColor: kNyqGreen,
            tabs: [
              Tab(text: 'Users', icon: Icon(Icons.people_outline)),
              Tab(text: 'Invoices', icon: Icon(Icons.receipt_long)),
              Tab(text: 'Overview', icon: Icon(Icons.insights_outlined)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsersScreen(embedded: true),
            InvoicesScreen(isAdmin: true, embedded: true),
            AdminEarningsScreen(embedded: true),
          ],
        ),
      ),
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

  Future<void> _fetch() async {
    setState(() => _loading = true);
    var result = <dynamic>[];
    try {
      final q = _searchCtl.text.trim();
      final uri = Uri.parse('$baseUrl/admin/users${q.isEmpty ? '' : '?q=${Uri.encodeComponent(q)}'}');
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        result = jsonDecode(res.body) as List;
      }
    } catch (_) {}
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
              title: Text(isSeller ? 'Remove Seller' : 'Make Seller'),
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/roles',
                    {'is_seller': isSeller ? 0 : 1});
                if (done) await _fetch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_run),
              title: Text(isRunner ? 'Remove Job Worker' : 'Make Job Worker'),
              onTap: () async {
                Navigator.pop(ctx);
                final done = await _send('PUT', '/admin/users/$id/roles',
                    {'is_runner': isRunner ? 0 : 1});
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
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        title: 'No users found',
                        message: 'Try a different search.',
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: _users.length,
                          itemBuilder: (ctx, i) {
                            final u =
                                Map<String, dynamic>.from(_users[i] as Map);
                            final suspended = u['is_suspended'] == 1;
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
                                trailing: const Icon(Icons.chevron_right),
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
        } catch (_) {}
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

  const ProfileScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
    this.onOpenJobs,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<dynamic> _deliveries = [];
  String _vehicleType = 'Motorbike';
  bool _isOnline = false;
  bool _isWorker = false;

  bool get _isSellerUser => isSeller(widget.currentUser);
  bool get _isRunnerUser => isRunner(widget.currentUser);

  List<dynamic> _shops = [];

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
  }

  Future<void> _loadShops() async {
    if (!_isSellerUser) return;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/shops/'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final all = jsonDecode(res.body) as List;
        final phone = normalisePhone(
            (widget.currentUser?['phone_number'] ?? '').toString());
        final mine = all
            .where((s) =>
                normalisePhone((s['phone_number'] ?? '').toString()) == phone)
            .toList();
        if (mounted) setState(() => _shops = mine);
        return;
      }
    } catch (_) {}
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
    } catch (_) {}
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
                            currentUser: user!,
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
                      onPressed: () => Navigator.pop(context),
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
                            context, widget.currentUser!),
                      ),
              ),
            ],
            if (widget.currentUser != null && !_isSellerUser) ...[
              const SizedBox(height: 12),
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
                      context, widget.currentUser!),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
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
                  child: Column(
                    children: [
                      const Icon(Icons.storefront_outlined,
                          size: 40, color: kNyqAccent),
                      const SizedBox(height: 10),
                      const Text('No shops yet',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Tap "Add New Shop" to open your first storefront.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
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
                          builder: (_) => ShopPageScreen(
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
                      labelText: 'City', border: OutlineInputBorder()),
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
                          'city': cityCtl.text.trim(),
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
    } catch (_) {}
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
    } catch (_) {}
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
      } catch (_) {}
    }
    await _loadUser();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final canTakeJobs = isRunner(_currentUser);
    final isLoggedIn = _currentUser != null;

    final screens = <Widget>[
      MarketplaceScreen(currentUser: _currentUser, onUserChanged: _refreshUser),
      MarketplaceLocationsScreen(
          currentUser: _currentUser, onUserChanged: _refreshUser),
      if (canTakeJobs)
        RunnerDashboardScreen(
            currentUser: _currentUser, onUserChanged: _refreshUser),
      if (isLoggedIn)
        ProfileScreen(
            currentUser: _currentUser,
            onUserChanged: _refreshUser,
            onOpenJobs: canTakeJobs
                ? () => setState(() => _currentIndex = 2)
                : null),
    ];

    // Clamp in case someone loses the worker role while on the Jobs tab.
    final safeIndex = _currentIndex >= screens.length ? 0 : _currentIndex;

    return Stack(
      children: [
        Scaffold(
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
          if (canTakeJobs)
            const NavigationDestination(
                icon: Icon(Icons.work_outline),
                selectedIcon: Icon(Icons.work),
                label: 'Jobs'),
          if (isLoggedIn)
            const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile'),
        ],
          ),
        ),
        ),
        ),
        Positioned(
          right: 16,
          bottom: 108,
          child: ChatBubble(currentUser: _currentUser),
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
                              onTap: () => widget.onBuy(item),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.shopping_cart,
                                        size: 18, color: Colors.white),
                                    const SizedBox(width: 8),
                                    const Text('Buy Now',
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

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
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
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: 'Check back soon!',
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

  const MarketplaceLocationsScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
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
        Expanded(
          child: filtered.isEmpty
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
        title: Image.asset('assets/logo.png', height: 60),
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
class ShopPageScreen extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Map<String, dynamic>? currentUser;
  final VoidCallback? onUserChanged;

  const ShopPageScreen({
    super.key,
    required this.shop,
    this.currentUser,
    this.onUserChanged,
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
  }

  Future<void> _loadUser() async {
    final u = await UserSession.load();
    if (mounted) setState(() => _currentUser = u);
  }

  Future<void> _refreshShop() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${shop['id']}'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final fresh = Map<String, dynamic>.from(data['merchant'] ?? data);
        if (mounted) setState(() => shop = fresh);
      }
    } catch (_) {}
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

    String paymentMethod = 'cash_on_delivery';
    String shopPaymentMethod = 'orange_money';
    String workerPaymentMethod = 'cash_on_delivery';
    bool collectInStore = false;
    final deliveryController = TextEditingController();
    final offerController = TextEditingController(text: '25');
    final agreedController = TextEditingController(
        text: (product['price_sle'] ?? '').toString());

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
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Agreed Price (SLE)',
                  helperText: 'Change this if you agreed a deal in chat',
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
                } catch (_) {}
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
                    labelText: 'City',
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
                    'city': cityController.text,
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
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: _headerTextColour == Colors.white
                          ? Colors.white24
                          : const Color(0xFF1B5E20),
                      backgroundImage: shop['logo_url'] != null &&
                              shop['logo_url'].toString().isNotEmpty
                          ? NetworkImage(shop['logo_url'])
                          : null,
                      child: shop['logo_url'] != null &&
                              shop['logo_url'].toString().isNotEmpty
                          ? null
                          : Text(
                              (shop['shop_name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
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
class ShopsBrowseScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;

  const ShopsBrowseScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<ShopsBrowseScreen> createState() => _ShopsBrowseScreenState();
}

class _ShopsBrowseScreenState extends State<ShopsBrowseScreen> {
  List<dynamic> shops = [];
  List<dynamic> filteredShops = [];
  bool isLoading = true;
  String searchQuery = '';
  Map<String, dynamic>? myShop;

  @override
  void initState() {
    super.initState();
    _loadMyShop();
    _fetchShops();
  }

  Future<void> _loadMyShop() async {
    final shop = await ShopSession.load();
    if (!mounted) return;
    setState(() => myShop = shop);
  }

  Future<void> _fetchShops() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/shops/'));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          shops = data;
          filteredShops = data;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  void _applySearch(String query) {
    setState(() {
      searchQuery = query;
      if (query.trim().isEmpty) {
        filteredShops = shops;
      } else {
        final q = query.toLowerCase();
        filteredShops = shops.where((s) {
          final name = (s['shop_name'] ?? '').toString().toLowerCase();
          final city = (s['city'] ?? '').toString().toLowerCase();
          final category = (s['category'] ?? '').toString().toLowerCase();
          return name.contains(q) || city.contains(q) || category.contains(q);
        }).toList();
      }
    });
  }

  void _openShop(Map<String, dynamic> shop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPageScreen(
          shop: shop,
          currentUser: widget.currentUser,
          onUserChanged: widget.onUserChanged,
        ),
      ),
    ).then((_) => _fetchShops());
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
              ensureLoggedIn: _ensureLoggedIn,
              onRefreshUser: () {
                if (mounted) setState(() => myShop = null);
                _loadMyShop();
              },
              currentShop: myShop),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: _applySearch,
              decoration: InputDecoration(
                hintText: 'Search shops by name, city, or category...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${filteredShops.length} shop${filteredShops.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredShops.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.store_outlined,
                                size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              searchQuery.isEmpty
                                  ? 'No shops yet in Sierra Leone.'
                                  : 'No shops match "$searchQuery".',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: filteredShops.length,
                        itemBuilder: (ctx, i) {
                          final shop = filteredShops[i];
                          final bg = parseThemeColour(
                              shop['theme_colour']?.toString());
                          final isDark =
                              ThemeData.estimateBrightnessForColor(bg) ==
                                  Brightness.dark;
                          final onBg = isDark ? Colors.white : Colors.black87;
                          final sub = isDark ? Colors.white70 : Colors.black54;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            decoration: BoxDecoration(
                              color: bg,
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
                            child: InkWell(
                              onTap: () => _openShop(shop),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 32,
                                      backgroundColor: isDark
                                          ? Colors.white24
                                          : const Color(0xFF1B5E20),
                                      backgroundImage: shop['logo_url'] != null &&
                                              shop['logo_url'].toString().isNotEmpty
                                          ? NetworkImage(shop['logo_url'])
                                          : null,
                                      child: shop['logo_url'] != null &&
                                              shop['logo_url'].toString().isNotEmpty
                                          ? null
                                          : Text(
                                              (shop['shop_name'] ?? '?')[0]
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 26,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shop['shop_name'] ?? 'Shop',
                                            style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                                color: onBg),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${shop['city'] ?? ''} • ${shop['category'] ?? 'Other'}',
                                            style: TextStyle(
                                                fontSize: 13, color: sub),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.inventory_2,
                                                  size: 14, color: sub),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${shop['product_count'] ?? 0} products',
                                                style: TextStyle(
                                                    fontSize: 12, color: sub),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, color: sub),
                                  ],
                                ),
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
// PRODUCT DETAIL SCREEN
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
    } catch (_) {}
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
                  label: const Text('Negotiate'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUserId: sellerUserId!,
                        otherUserName: product['shop_name'] ?? 'Seller',
                        shopId: product['merchant_id'],
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

    String paymentMethod = 'cash_on_delivery';
    String shopPaymentMethod = 'orange_money';
    String workerPaymentMethod = 'cash_on_delivery';
    bool collectInStore = false;
    final deliveryController = TextEditingController();
    final offerController = TextEditingController(text: '25');
    final agreedController = TextEditingController(
        text: (product['price_sle'] ?? '').toString());

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
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Agreed Price (SLE)',
                  helperText: 'Change this if you agreed a deal in chat',
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
                } catch (_) {}
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
class BecomeJobWorkerScreen extends StatelessWidget {
  const BecomeJobWorkerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNyqSand,
      appBar: AppBar(title: const Text('Become a Job Worker')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
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
                child: const Icon(Icons.work_outline,
                    size: 44, color: kNyqAccent),
              ),
              const SizedBox(height: 20),
              const Text('Coming soon',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Applications to become a Job Worker are being set up. '
                'Check back shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    } catch (_) {}
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_off,
                                size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _isOnline
                                  ? 'No jobs available right now.'
                                  : 'You are offline. Go online to see available jobs.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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
      final res = await http.get(
        Uri.parse('$baseUrl/orders/customer/${widget.currentUser['id']}'),
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'You have no orders yet.',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Browse the marketplace to place your first order.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
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