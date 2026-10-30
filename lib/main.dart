import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

const String baseUrl = 'https://random.taila91e03.ts.net';
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          primary: const Color(0xFF1B5E20),
          secondary: const Color(0xFF0D47A1),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9F7),
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

    final res = await http.put(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(updates),
    );

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
      if (user['photo_url'] != null) {
        await prefs.setString('user_photo', user['photo_url']);
      }
      return true;
    }
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
          child: Column(
            children: [
              Image.asset('assets/logo.png', height: 80),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
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
            ],
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
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFF1B5E20),
                child: Text(
                  user['name'].toString().isNotEmpty
                      ? user['name'][0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user['name'] ?? 'User',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(user['phone_number'] ?? ''),
              const SizedBox(height: 4),
              Chip(
                label: Text(
                  isSeller(user) && isRunner(user)
                      ? 'SELLER + RUNNER'
                      : isSeller(user)
                          ? 'SELLER'
                          : isRunner(user)
                              ? 'RUNNER'
                              : 'CUSTOMER',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 24),
              if (shop != null)
                ListTile(
                  leading: const Icon(Icons.storefront),
                  title: const Text('My Shop'),
                  subtitle: Text(shop['shop_name'] ?? ''),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShopPageScreen(
                          shop: shop,
                          currentUser: currentUser,
                          onUserChanged: onUserChanged,
                        ),
                      ),
                    );
                  },
                ),
              if (isSeller(currentUser) && shop != null)
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  title: const Text('Stop Selling'),
                  subtitle: const Text('Pause your shop temporarily'),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Stop selling?'),
                        content: const Text(
                          'You will not be able to add or edit products until you turn selling back on. Your shop, products, and existing orders all stay safe and visible — you can re-enable selling anytime.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Stop Selling'),
                          ),
                        ],
                      ),
                    );
                    if (!context.mounted) return;
                    if (confirmed != true) return;
                    Navigator.pop(ctx);
                    final err = await UserSession.revokeSeller();
                    if (!context.mounted) return;
                    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
                    if (err == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selling paused')),
                      );
                      onUserChanged();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  },
                ),
              if (isRunner(currentUser))
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  title: const Text('Stop Running'),
                  subtitle: const Text('Pause deliveries temporarily'),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Stop running?'),
                        content: const Text(
                          'You will not see delivery jobs or be able to accept them until you turn running back on. Past deliveries stay in your history.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Stop Running'),
                          ),
                        ],
                      ),
                    );
                    if (!context.mounted) return;
                    if (confirmed != true) return;
                    Navigator.pop(ctx);
                    final err = await UserSession.revokeRunner();
                    if (!context.mounted) return;
                    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
                    if (err == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Running paused')),
                      );
                      onUserChanged();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  },
                ),
              if (shop == null)
                ListTile(
                  leading: const Icon(Icons.storefront, color: Color(0xFF1B5E20)),
                  title: const Text('Become a Seller'),
                  subtitle: const Text('Create your own shop'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final err = await UserSession.becomeSeller();
                    if (!context.mounted) return;
                    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
                    if (err == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You can now sell on NYG')),
                      );
                      onUserChanged();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  },
                ),
              if (!isRunner(currentUser))
                ListTile(
                  leading: const Icon(Icons.directions_run, color: Color(0xFF0D47A1)),
                  title: const Text('Become a Runner'),
                  subtitle: const Text('Deliver items and earn'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final err = await UserSession.becomeRunner();
                    if (!context.mounted) return;
                    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
                    if (err == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You can now deliver on NYG')),
                      );
                      onUserChanged();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  },
                ),
              if (user != null)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('View Profile'),
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
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('My Orders'),
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
              if (currentUser != null && (currentUser['is_admin'] == 1 || currentUser['is_admin'] == true))
                ListTile(
                  leading: const Icon(Icons.attach_money, color: Color(0xFF1B5E20)),
                  title: const Text('My Earnings'),
                  subtitle: const Text('Admin only'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminEarningsScreen()),
                    );
                  },
                ),
              if (currentUser != null && (currentUser['is_admin'] == 1 || currentUser['is_admin'] == true))
                ListTile(
                  leading: const Icon(Icons.receipt, color: Color(0xFF1B5E20)),
                  title: const Text('All Invoices'),
                  subtitle: const Text('Admin - generate and confirm'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InvoicesScreen(isAdmin: true)),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('My Invoices'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InvoicesScreen(isAdmin: false)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Messages'),
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
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Profile'),
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
                onTap: () {
                  Navigator.pop(ctx);
                  showChangePasswordDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title:
                    const Text('Sign Out', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await UserSession.clear();
                  await ShopSession.clear();
                  onUserChanged();
                  onSignOut?.call();
                },
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
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.shopId,
    this.orderId,
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
                color: const Color(0xFF1B5E20),
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
                                    'Runner: ${o['driver_name'] ?? 'Unknown'} • ${o['driver_phone'] ?? ''}',
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
                                    label: const Text('Message Runner', style: TextStyle(fontSize: 12)),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          otherUserId: (o['driver_id'] as num).toInt(),
                                          otherUserName: o['driver_name'] ?? 'Runner',
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
class RunnerDeliveriesScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  const RunnerDeliveriesScreen({super.key, required this.currentUser});

  @override
  State<RunnerDeliveriesScreen> createState() => _RunnerDeliveriesScreenState();
}

class _RunnerDeliveriesScreenState extends State<RunnerDeliveriesScreen> {
  List<dynamic> _jobs = [];
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
        Uri.parse('$baseUrl/deliveries/mine/${widget.currentUser['id']}'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final all = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _jobs = all;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _completeDelivery(int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as delivered?'),
        content: const Text('Confirm you have delivered this order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, delivered'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = await UserSession.load();
    if (user == null) return;

    try {
      final res = await http.put(
        Uri.parse('$baseUrl/deliveries/$orderId/complete'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token'] ?? ''}',
        },
        body: jsonEncode({
          'status': 'delivered',
          'cash_collected': false,
        }),
      ).timeout(const Duration(seconds: 8));

      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery completed')),
        );
        _load();
      } else {
        showApiError(context, res.statusCode, res.body,
            fallback: 'Could not complete delivery');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot reach server')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Deliveries'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _jobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delivery_dining, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No deliveries assigned to you yet.',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _jobs.length,
                  itemBuilder: (ctx, i) {
                    final job = _jobs[i];
                    final status = (job['delivery_status'] ?? 'pending').toString();
                    final isDelivered = status == 'delivered' || status == 'completed';
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
                                    job['product_title'] ?? 'Order',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDelivered ? Colors.green.shade100 : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDelivered ? Colors.green.shade800 : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    job['delivery_address'] ?? '',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Fee: SLE ${job['delivery_fee_sle'] ?? 0}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Payment: ${job['payment_method'] ?? ''} • ${job['payment_status'] ?? ''}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(job['created_at']),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 10),
                            if (!isDelivered)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Mark as Delivered'),
                                  onPressed: () => _completeDelivery((job['id'] as num).toInt()),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Delivered ✓',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
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
            _stepRow('Seller paid runner fee', s['seller_paid_runner'] as String?,
              step: role == 'seller' ? 'seller-paid-runner' : null, buttonLabel: "I've paid runner",
              enabled: s['seller_received'] != null),
            _stepRow('Runner received fee', s['runner_received_fee'] as String?,
              step: role == 'runner' ? 'runner-received-fee' : null, buttonLabel: "I've received",
              enabled: s['seller_paid_runner'] != null),
            _stepRow('Seller handed goods to runner', s['seller_handed_goods'] as String?,
              step: role == 'seller' ? 'seller-handed' : null, buttonLabel: "I've handed goods",
              enabled: s['runner_received_fee'] != null),
            _stepRow('Runner picked up', s['runner_picked_up'] as String?,
              step: role == 'runner' ? 'runner-picked-up' : null, buttonLabel: "I've picked up",
              enabled: s['seller_handed_goods'] != null),
            _stepRow('Runner delivered', s['runner_delivered'] as String?,
              step: role == 'runner' ? 'runner-delivered' : null, buttonLabel: "I've delivered",
              enabled: s['runner_picked_up'] != null),
            _stepRow('Buyer received goods', s['buyer_received_goods'] as String?,
              step: role == 'customer' ? 'buyer-received-goods' : null, buttonLabel: "I've received",
              enabled: s['runner_delivered'] != null),
            _stepRow('Seller paid NYG commission', s['seller_paid_nyg'] as String?,
              step: role == 'seller' ? 'seller-paid-nyg' : null, buttonLabel: "I've paid NYG",
              enabled: s['buyer_received_goods'] != null),
            _stepRow('NYG confirmed commission', s['nyg_received'] as String?,
              step: null, buttonLabel: null),
            const Divider(height: 32),
            const Text('Money breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _moneyRow('Product price', _data!['product_price_sle']),
            _moneyRow('NYG commission (5%)', _data!['commission_sle']),
            _moneyRow('Seller receives', _data!['seller_payout_sle']),
            const Divider(height: 16),
            _moneyRow('Runner fee (80% delivery)', _data!['runner_fee_sle']),
            const Divider(height: 16),
            _moneyRow('NYG total on this order', _data!['nyg_total_sle'], bold: true),
          ],
        ),
      ),
    );
  }
}

class AdminEarningsScreen extends StatefulWidget {
  const AdminEarningsScreen({super.key});

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

  Widget _row(String label, dynamic value, {bool bold = false}) {
    final v = (value is num) ? value.toStringAsFixed(2) : '0.00';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 15))),
          Text('SLE $v', style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 15)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Earnings'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Could not load earnings'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Totals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _row('Commission earned (5%)', _data!['total_commission_earned']),
                      _row('Delivery cut earned (20%)', _data!['total_delivery_cut_earned']),
                      const Divider(height: 24),
                      _row('Settled', _data!['total_settled']),
                      _row('Still owed to you', _data!['total_still_owed'], bold: true),
                      const SizedBox(height: 24),
                      const Text('Unsettled orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if ((_data!['unsettled_orders'] as List?)?.isEmpty ?? true)
                        const Text('Nothing outstanding. All settled.')
                      else
                        ...(_data!['unsettled_orders'] as List).map((o) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text('Order #${o['order_id']}'),
                              subtitle: Text('Merchant ID ${o['merchant_id']}'),
                              trailing: Text('SLE ${(o['amount_owed'] as num).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                            ),
                          );
                        }).toList(),
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
  bool _working = false;

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

  Future<void> _sellerMarkPaid() async {
    setState(() => _working = true);
    final err = await UserSession.markInvoiceSellerPaid(widget.invoiceId);
    if (!mounted) return;
    setState(() => _working = false);
    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as paid')));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _nygReceived() async {
    setState(() => _working = true);
    final err = await UserSession.markInvoiceNygReceived(widget.invoiceId);
    if (!mounted) return;
    setState(() => _working = false);
    if (err == 'SESSION_EXPIRED') { handleSessionExpired(context); return; }
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt confirmed')));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
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
                      Text('Seller: ${_data!['seller_name'] ?? '?'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Phone: ${_data!['seller_phone'] ?? '?'}'),
                      Text('Status: ${_data!['status'] ?? '?'}'),
                      const SizedBox(height: 8),
                      Text('Total: SLE ${(_data!['total_sle'] as num).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                      const Divider(height: 32),
                      const Text('Orders covered', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...(_data!['orders'] as List).map((o) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text('#${o['order_id']} - ${o['product_title']}'),
                            subtitle: Text('Commission SLE ${(o['commission_sle'] as num).toStringAsFixed(2)} | Delivery SLE ${(o['delivery_cut_sle'] as num).toStringAsFixed(2)}'),
                            trailing: Text('SLE ${(o['total_sle'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                      const Divider(height: 32),
                      Text('Seller marked paid: ${_fmt(_data!['seller_paid_at'])}'),
                      Text('NYG confirmed receipt: ${_fmt(_data!['nyg_received_at'])}'),
                      const SizedBox(height: 24),
                      if (!widget.isAdmin && _data!['seller_paid_at'] == null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _working ? null : _sellerMarkPaid,
                            child: const Text("I've paid this invoice"),
                          ),
                        ),
                      if (widget.isAdmin && _data!['seller_paid_at'] != null && _data!['nyg_received_at'] == null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B5E20),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _working ? null : _nygReceived,
                            child: const Text('Confirm receipt'),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class InvoicesScreen extends StatefulWidget {
  final bool isAdmin;
  const InvoicesScreen({super.key, required this.isAdmin});

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All Invoices' : 'My Invoices'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const Center(child: Text('No invoices yet.'))
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
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Generate Invoice'),
              onPressed: _showGenerateDialog,
            )
          : null,
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  final VoidCallback onUserChanged;

  const ProfileScreen({
    super.key,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<dynamic> _products = [];
  List<dynamic> _deliveries = [];
  bool _loading = true;

  bool get _isSellerUser => isSeller(widget.currentUser);
  bool get _isRunnerUser => isRunner(widget.currentUser);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _loadProducts();
    await _loadDeliveries();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProducts() async {
    if (!_isSellerUser) return;
    try {
      final shop = await ShopSession.load();
      if (shop == null) return;
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${shop['id']}/products/'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _products = jsonDecode(res.body) as List;
      }
    } catch (_) {}
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SizedBox(height: 8),
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFF1B5E20),
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  phone,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (user != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                  child: const Text('Edit Profile'),
                ),
              ),
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
            ],
            if (_isSellerUser) ...[
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Products',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${_products.length}',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_products.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No products listed yet',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _products.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (ctx, i) {
                    final photos =
                        productPhotos(_products[i] as Map<String, dynamic>);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: photos.isEmpty
                          ? Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.image_outlined,
                                  color: Colors.grey.shade400),
                            )
                          : Image.network(
                              photos.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey.shade200,
                                child: Icon(Icons.broken_image_outlined,
                                    color: Colors.grey.shade400),
                              ),
                            ),
                    );
                  },
                ),
            ],
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

  void _refreshUser() => _loadUser();

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      MarketplaceScreen(currentUser: _currentUser, onUserChanged: _refreshUser),
      ShopsBrowseScreen(currentUser: _currentUser, onUserChanged: _refreshUser),
      MarketplaceLocationsScreen(
          currentUser: _currentUser, onUserChanged: _refreshUser),
      RunnerDashboardScreen(
          currentUser: _currentUser, onUserChanged: _refreshUser),
    ];

    return Stack(
      children: [
        Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined), label: 'Shopping'),
          NavigationDestination(icon: Icon(Icons.store), label: 'Shops'),
          NavigationDestination(
              icon: Icon(Icons.location_on_outlined), label: 'Marketplace'),
          NavigationDestination(
              icon: Icon(Icons.directions_run), label: 'Runner'),
        ],
      ),
        ),
        Positioned(
          right: 16,
          bottom: 90,
          child: ChatBubble(currentUser: _currentUser),
        ),
      ],
    );
  }
}

// ==========================================
// REUSABLE: SHOP PRODUCT GRID
// ==========================================
class ShopProductGrid extends StatelessWidget {
  final List<dynamic> products;
  final void Function(dynamic product) onBuy;
  final void Function(dynamic product)? onDelete;
  final VoidCallback? onRefresh;
  final void Function(Map<String, dynamic> product)? onOpen;

  const ShopProductGrid({
    super.key,
    required this.products,
    required this.onBuy,
    this.onDelete,
    this.onRefresh,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined,
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No items listed yet.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: products.length,
      itemBuilder: (ctx, i) {
        final item = products[i];
        return InkWell(
          onTap: onOpen == null ? null : () => onOpen!(item),
          borderRadius: BorderRadius.circular(12),
          child: Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    color: Colors.white,
                    width: double.infinity,
                    child: Builder(builder: (context) {
                      final photos = productPhotos(item);
                      final url = photos.isNotEmpty ? photos[0] : null;
                      if (url == null) {
                        return const Center(child: Icon(Icons.shopping_bag, size: 40));
                      }
                      return Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.shopping_bag, size: 40)),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('SLE ${item['price_sle']}'),
                if (item['shop_name'] != null)
                  Text(
                    '🏪 ${item['shop_name']} • ${item['shop_city'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => onBuy(item),
                        child: const Text('Buy'),
                      ),
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Delete product',
                        onPressed: () => onDelete!(item),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        );
      },
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: (logoUrl != null && logoUrl.toString().isNotEmpty)
            ? CircleAvatar(
                backgroundImage: NetworkImage(logoUrl.toString()),
                child: Text(initial),
              )
            : CircleAvatar(
                backgroundColor: const Color(0xFF1B5E20),
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${shop['city'] ?? ''} • ${shop['category'] ?? ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openShop(shop),
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
                        ? const Color(0xFF1B5E20)
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
          return {
            ...p,
            'shop_name': shop['shop_name'],
            'shop_city': shop['city'],
            'shop_category': shop['category'],
          };
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

  Future<void> _showCheckout(dynamic product) async {
    if (_currentUser == null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (ok == true) {
        widget.onUserChanged?.call();
        await _loadUser();
      }
      if (ok != true || !mounted) return;
    }

    if (!mounted) return;

    String paymentMethod = 'cash_on_delivery';
    final deliveryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Buy ${product['title']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Price: SLE ${product['price_sle']}'),
              const SizedBox(height: 10),
              TextField(
                controller: deliveryController,
                decoration: const InputDecoration(
                  labelText: 'Delivery Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              RadioListTile(
                title: const Text('Cash on Delivery'),
                value: 'cash_on_delivery',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
              RadioListTile(
                title: const Text('Orange Money (*144#)'),
                value: 'orange_money',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
              RadioListTile(
                title: const Text('Afrimoney (*161#)'),
                value: 'africell_money',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (deliveryController.text.isEmpty) return;
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
                    'delivery_address': deliveryController.text,
                    'delivery_fee_sle': 25.0,
                    'payment_method': paymentMethod,
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
                  if (paymentMethod == 'orange_money' ||
                      paymentMethod == 'africell_money') {
                    final shopPhone =
                        (product['shop_phone'] ?? '+232 78 839002').toString();
                    showMobileMoneyInstructions(
                      context,
                      method: paymentMethod,
                      shopPhone: shopPhone,
                      total: '${(product['price_sle'] ?? 0) + 25.0}',
                      orderRef: 'NYG-$newOrderId',
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Order placed! Runner will be assigned.')),
                    );
                  }
                }
              },
              child: const Text('Confirm Order'),
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
        title: Text(shop['shop_name'] ?? 'Shop'),
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
              },
              itemBuilder: (ctx) => const [
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
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ShopProductGrid(
                    products: products,
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

  Future<void> _showCreateShopDialog() async {
    final loggedIn = await _ensureLoggedIn(suggestedRole: 'merchant');
    if (!loggedIn) return;
    if (!mounted) return;

    final shopNameController = TextEditingController();
    final ownerNameController =
        TextEditingController(text: widget.currentUser?['name'] ?? '');
    final phoneController = TextEditingController(
        text: widget.currentUser?['phone_number'] ?? '+232');
    final cityController = TextEditingController(text: 'Freetown');
    String selectedCategory = 'Fashion';
    String? uploadedLogoUrl;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Your Shop Page'),
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
                    labelText: 'Your Full Name',
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
                    labelText: 'City in Sierra Leone',
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
                        setDialogState(() => uploadedLogoUrl = url);
                      }
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: Text(uploadedLogoUrl == null
                        ? 'Pick Shop Logo'
                        : 'Logo Uploaded'),
                  ),
                ),
                if (uploadedLogoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        uploadedLogoUrl!,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Shop Category',
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
                if (shopNameController.text.isEmpty ||
                    ownerNameController.text.isEmpty) return;

                final user = await UserSession.load();
                final response = await http.post(
                  Uri.parse('$baseUrl/merchants/'),
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
                    'logo_url': uploadedLogoUrl,
                  }),
                );

                if (response.statusCode >= 200 && response.statusCode < 300) {
                  final merchantData = jsonDecode(response.body)['merchant'];

                  // Creating a shop auto-enables seller status on the backend,
                  // so refresh the user or the account sheet stays stale.
                  final meRes = await http.get(
                    Uri.parse('$baseUrl/auth/me'),
                    headers: {
                      'x-api-key': apiKey,
                      'Authorization': 'Bearer ${user?['token'] ?? ''}',
                    },
                  ).timeout(const Duration(seconds: 8));
                  if (meRes.statusCode >= 200 && meRes.statusCode < 300) {
                    final meData = jsonDecode(meRes.body);
                    await UserSession.save({
                      'id': meData['id'],
                      'phone_number': meData['phone_number'],
                      'name': meData['name'],
                      'role': meData['role'] ?? 'customer',
                      'is_seller': meData['is_seller'] ?? 0,
                      'is_runner': meData['is_runner'] ?? 0,
                      'is_admin': meData['is_admin'] ?? 0,
                      'photo_url': meData['photo_url'],
                    }, user?['token'] ?? '');
                  }

                  await ShopSession.save(merchantData);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => myShop = merchantData);
                    _openShopProfilePage(merchantData);
                  }
                } else {
                  if (mounted) {
                    showApiError(context, response.statusCode, response.body,
                        fallback: 'Failed to create shop. Try a different name.');
                  }
                }
              },
              child: const Text('Create Shop'),
            ),
          ],
        ),
      ),
    );
  }

  void _openShopProfilePage(Map<String, dynamic> merchantData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pageContext) => ShopPageScreen(
          shop: merchantData,
          currentUser: widget.currentUser,
          onUserChanged: widget.onUserChanged,
        ),
      ),
    ).then((_) {
      _fetchShops();
      _loadMyShop();
    });
  }

  Widget _buildTopCard() {
    final hasShop = myShop != null;
    final seller = isSeller(widget.currentUser);
    final needsSeller = !seller;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasShop
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasShop
                    ? Icons.store
                    : (needsSeller ? Icons.person_add : Icons.store),
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasShop
                      ? myShop!['shop_name']
                      : (needsSeller ? 'Become a Seller' : 'Create My Shop'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasShop
                ? 'Owner: ${myShop!['owner_name']} • ${myShop!['city']}'
                : (needsSeller
                    ? 'Turn on selling to create your shop.'
                    : 'Create your shop to start selling.'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: hasShop
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFF0D47A1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(hasShop
                  ? Icons.open_in_new
                  : (needsSeller ? Icons.storefront : Icons.store)),
              label: Text(
                hasShop
                    ? 'Open My Shop'
                    : (needsSeller ? 'Become a Seller' : 'Create My Shop'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                if (hasShop) {
                  _openShopProfilePage(myShop!);
                } else if (needsSeller) {
                  final err = await UserSession.becomeSeller();
                  if (!mounted) return;
                  if (err == 'SESSION_EXPIRED') {
                    handleSessionExpired(context);
                    return;
                  }
                  if (err == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('You can now sell on NYG')),
                    );
                    widget.onUserChanged();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                  }
                } else {
                  _showCreateShopDialog();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          _buildTopCard(),
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
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
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

class ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;
  final void Function(Map<String, dynamic> product) onBuy;
  final void Function(Map<String, dynamic> product)? onDelete;
  final bool isOwner;
  final int? sellerUserId;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.onBuy,
    this.onDelete,
    this.isOwner = false,
    this.sellerUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product['title'] ?? 'Product')),
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
                  label: const Text('Message'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUserId: sellerUserId!,
                        otherUserName: product['shop_name'] ?? 'Seller',
                        shopId: product['merchant_id'],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Buy Now'),
                  onPressed: () {
                    onBuy(product);
                  },
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

  Future<void> _showCreateShopDialog() async {
    final loggedIn = await _ensureLoggedIn(suggestedRole: 'merchant');
    if (!loggedIn) return;
    if (!mounted) return;

    final shopNameController = TextEditingController();
    final ownerNameController =
        TextEditingController(text: widget.currentUser?['name'] ?? '');
    final phoneController = TextEditingController(
        text: widget.currentUser?['phone_number'] ?? '+232');
    final cityController = TextEditingController(text: 'Freetown');
    String selectedCategory = 'Fashion';
    String? uploadedLogoUrl;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Your Shop Page'),
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
                    labelText: 'Your Full Name',
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
                    labelText: 'City in Sierra Leone',
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
                        setDialogState(() => uploadedLogoUrl = url);
                      }
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: Text(uploadedLogoUrl == null
                        ? 'Pick Shop Logo'
                        : 'Logo Uploaded'),
                  ),
                ),
                if (uploadedLogoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        uploadedLogoUrl!,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Shop Category',
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
                if (shopNameController.text.isEmpty ||
                    ownerNameController.text.isEmpty) return;

                final user = await UserSession.load();
                final response = await http.post(
                  Uri.parse('$baseUrl/merchants/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                    'Authorization': 'Bearer ${user?['token'] ?? ''}',
                  },
                  body: jsonEncode({
                    'shop_name': shopNameController.text,
                    'owner_name': ownerNameController.text,
                    'phone_number': normalisePhone(phoneController.text),
                    'city': cityController.text,
                    'category': selectedCategory,
                    'logo_url': uploadedLogoUrl,
                  }),
                );

                if (response.statusCode >= 200 && response.statusCode < 300) {
                  final merchantData = jsonDecode(response.body)['merchant'];

                  // Creating a shop auto-enables seller status on the backend,
                  // so refresh the user or the account sheet stays stale.
                  final meRes = await http.get(
                    Uri.parse('$baseUrl/auth/me'),
                    headers: {
                      'x-api-key': apiKey,
                      'Authorization': 'Bearer ${user?['token'] ?? ''}',
                    },
                  ).timeout(const Duration(seconds: 8));
                  if (meRes.statusCode >= 200 && meRes.statusCode < 300) {
                    final meData = jsonDecode(meRes.body);
                    await UserSession.save({
                      'id': meData['id'],
                      'phone_number': meData['phone_number'],
                      'name': meData['name'],
                      'role': meData['role'] ?? 'customer',
                      'is_seller': meData['is_seller'] ?? 0,
                      'is_runner': meData['is_runner'] ?? 0,
                      'is_admin': meData['is_admin'] ?? 0,
                      'photo_url': meData['photo_url'],
                    }, user?['token'] ?? '');
                  }

                  await ShopSession.save(merchantData);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => myShop = merchantData);
                    _openShopProfilePage(merchantData);
                  }
                } else {
                  if (mounted) {
                    showApiError(context, response.statusCode, response.body,
                        fallback: 'Failed to create shop. Try a different name.');
                  }
                }
              },
              child: const Text('Create Shop'),
            ),
          ],
        ),
      ),
    );
  }

  void _openShopProfilePage(Map<String, dynamic> merchantData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopPageScreen(
          shop: merchantData,
          currentUser: widget.currentUser,
          onUserChanged: widget.onUserChanged,
        ),
      ),
    ).then((_) {
      fetchProducts();
      _loadEverything();
    });
  }

  Future<void> _showCheckout(dynamic product) async {
    final loggedIn = await _ensureLoggedIn();
    if (!loggedIn) return;
    if (!mounted) return;

    String paymentMethod = 'cash_on_delivery';
    final deliveryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Buy ${product['title']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Price: SLE ${product['price_sle']}'),
              const SizedBox(height: 10),
              TextField(
                controller: deliveryController,
                decoration: const InputDecoration(
                  labelText: 'Delivery Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              RadioListTile(
                title: const Text('Cash on Delivery'),
                value: 'cash_on_delivery',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
              RadioListTile(
                title: const Text('Orange Money (*144#)'),
                value: 'orange_money',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
              RadioListTile(
                title: const Text('Afrimoney (*161#)'),
                value: 'africell_money',
                groupValue: paymentMethod,
                onChanged: (val) => setDialogState(() => paymentMethod = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (deliveryController.text.isEmpty) return;
                final response = await http.post(
                  Uri.parse('$baseUrl/orders/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                  },
                  body: jsonEncode({
                    'customer_id': widget.currentUser!['id'],
                    'merchant_id': product['merchant_id'],
                    'product_id': product['id'],
                    'pickup_address': 'Freetown Central Market',
                    'delivery_address': deliveryController.text,
                    'delivery_fee_sle': 25.0,
                    'payment_method': paymentMethod,
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
                  if (paymentMethod == 'orange_money' ||
                      paymentMethod == 'africell_money') {
                    final shopPhone =
                        (product['shop_phone'] ?? '+232 78 839002').toString();
                    showMobileMoneyInstructions(
                      context,
                      method: paymentMethod,
                      shopPhone: shopPhone,
                      total: '${(product['price_sle'] ?? 0) + 25.0}',
                      orderRef: 'NYG-$newOrderId',
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Order placed! Runner will be assigned.')),
                    );
                  }
                }
              },
              child: const Text('Confirm Order'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCard() {
    final hasShop = myShop != null;
    final user = widget.currentUser;
    final userName = user?['name'] ?? 'there';
    final seller = isSeller(user);
    final needsSeller = !seller;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasShop
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasShop
                    ? Icons.storefront
                    : (needsSeller ? Icons.person_add : Icons.add_business),
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasShop
                      ? myShop!['shop_name']
                      : (needsSeller ? 'Become a Seller' : 'Create My Shop'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasShop
                ? 'Owner: ${myShop!['owner_name']} • ${myShop!['city']}'
                : (needsSeller
                    ? 'Turn on selling to create your shop.'
                    : 'Hi $userName! Create your shop to start selling.'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: hasShop
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFF0D47A1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(hasShop
                  ? Icons.open_in_new
                  : (needsSeller ? Icons.storefront : Icons.store)),
              label: Text(
                hasShop
                    ? 'Upload Your Goods Items You Are Selling'
                    : (needsSeller ? 'Become a Seller' : 'Create My Shop'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                if (hasShop) {
                  _openShopProfilePage(myShop!);
                } else if (needsSeller) {
                  final err = await UserSession.becomeSeller();
                  if (!mounted) return;
                  if (err == 'SESSION_EXPIRED') {
                    handleSessionExpired(context);
                    return;
                  }
                  if (err == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('You can now sell on NYG')),
                    );
                    widget.onUserChanged();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                  }
                } else {
                  _showCreateShopDialog();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = filteredProducts;

    return Scaffold(
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
                _buildTopCard(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search products, shops, categories...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.storefront_outlined,
                                  size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                searchQuery.isNotEmpty
                                    ? 'No products match "$searchQuery".'
                                    : selectedFilterCategory == 'All'
                                        ? 'No items listed yet in Sierra Leone.'
                                        : 'No items in "$selectedFilterCategory".',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
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

  @override
  void initState() {
    super.initState();
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

  Future<void> fetchJobs() async {
    setState(() => _loadingJobs = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/deliveries/available/'));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => jobs = jsonDecode(res.body));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingJobs = false);
  }

  Future<bool> _ensureLoggedInAsRunner() async {
    if (widget.currentUser != null) {
      if (isRunner(widget.currentUser)) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Only Runners can accept delivery jobs.')),
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
          _buildTopCard(),
          Expanded(
            child: _loadingJobs
                ? const Center(child: CircularProgressIndicator())
                : jobs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delivery_dining,
                                size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No delivery jobs available right now.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
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
                            child: ListTile(
                              leading: const Icon(Icons.delivery_dining,
                                  size: 36, color: Colors.blue),
                              title: Text('Dropoff: ${job['delivery_address']}'),
                              subtitle: Text(
                                  'Fee: SLE ${job['delivery_fee_sle']} | Payment: ${job['payment_method']}'),
                              trailing: ElevatedButton(
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
                                child: const Text('Accept'),
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

  Widget _buildTopCard() {
    final user = widget.currentUser;
    final isUserRunner = isRunner(user);

    final String subtitle;
    if (isUserRunner) {
      subtitle = 'You are registered as a Runner';
    } else if (user == null) {
      subtitle = 'Sign up to deliver items and earn';
    } else {
      subtitle = 'Sign out and create a Runner account to earn';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUserRunner
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_run,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Become a Runner',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: isUserRunner
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFF0D47A1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(isUserRunner ? Icons.list_alt : Icons.directions_run),
              label: Text(
                isUserRunner ? 'View Available Jobs' : 'How to become a Runner',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (isUserRunner) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RunnerDeliveriesScreen(currentUser: user!),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Sign out from the profile menu, then create a new account and choose Runner.'),
                    ),
                  );
                }
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
                                        label: const Text('Message Runner'),
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              otherUserId: (order['driver_id'] as num).toInt(),
                                              otherUserName: 'Runner',
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