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

  static Future<void> save(Map<String, dynamic> user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, user['id']);
    await prefs.setString(_nameKey, user['name']);
    await prefs.setString(_phoneKey, user['phone_number']);
    await prefs.setString(_roleKey, user['role'] ?? 'customer');
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
      if (user['photo_url'] != null) {
        await prefs.setString('user_photo', user['photo_url']);
      }
      return true;
    }
    return false;
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

  static Future<bool> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    if (token == null) return false;

    final res = await http.delete(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'x-api-key': apiKey,
        'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      await clear();
      return true;
    }
    return false;
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
  static Future<List<dynamic>> getInbox() async {
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
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      return jsonDecode(res.body) as List;
    } catch (_) {
      return [];
    }
  }

  static Future<List<dynamic>> getConversation(int otherUserId) async {
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
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final data = jsonDecode(res.body);
      return data['messages'] as List;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> send(int recipientId, String text, {int? shopId, int? orderId}) async {
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
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markRead(int otherUserId) async {
    final user = await UserSession.load();
    if (user == null) return;
    try {
      await http.put(
        Uri.parse('$baseUrl/messages/conversation/$otherUserId/read'),
        headers: {
          'x-api-key': apiKey,
          'Authorization': 'Bearer ${user['token']}',
        },
      ).timeout(const Duration(seconds: 5));
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
  String _selectedRole = 'customer';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedRole != null) {
      _selectedRole = widget.suggestedRole!;
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
            'role': _selectedRole,
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
              if (!_isLogin) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'I am a...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'customer', child: Text('Customer (Buy things)')),
                    DropdownMenuItem(
                        value: 'merchant', child: Text('Merchant (Sell things)')),
                    DropdownMenuItem(
                        value: 'driver', child: Text('Runner (Deliver jobs)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedRole = v);
                  },
                ),
              ],
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
                  (user['role'] ?? 'customer').toUpperCase(),
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
                        builder: (_) => ShopProfileScreen(merchant: shop),
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
    final ok = await UserSession.deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      await ShopSession.clear();
      widget.onUserChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete account')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not complete delivery')),
        );
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
                    child: item['image_url'] != null &&
                            item['image_url'].toString().isNotEmpty
                        ? Image.network(
                            item['image_url'],
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                    child: Icon(Icons.shopping_bag, size: 40)),
                          )
                        : const Center(
                            child: Icon(Icons.shopping_bag, size: 40)),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchShops,
          ),
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
  final VoidCallback onUserChanged;

  const ShopPageScreen({
    super.key,
    required this.shop,
    required this.currentUser,
    required this.onUserChanged,
  });

  @override
  State<ShopPageScreen> createState() => _ShopPageScreenState();
}

class _ShopPageScreenState extends State<ShopPageScreen> {
  List<dynamic> products = [];
  bool isLoading = true;
  late Map<String, dynamic> shop;

  @override
  void initState() {
    super.initState();
    shop = Map<String, dynamic>.from(widget.shop);
    _fetchProducts();
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
    if (widget.currentUser == null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (ok == true) widget.onUserChanged();
      if (ok != true) return;
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

  bool get _isOwner {
    if (widget.currentUser == null) return false;
    return widget.currentUser!['phone_number'] == shop['phone_number'];
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
      appBar: AppBar(
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
            color: Colors.green.shade50,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF1B5E20),
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
                    if (shop['phone_number'] != null) ...[
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
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${products.length} product${products.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
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

                final response = await http.post(
                  Uri.parse('$baseUrl/merchants/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
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
                  await ShopSession.save(merchantData);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => myShop = merchantData);
                    _openShopProfilePage(merchantData);
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Failed to create shop. Try a different name.')),
                    );
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
        builder: (pageContext) => ShopProfileScreen(merchant: merchantData),
      ),
    ).then((_) {
      _fetchShops();
      _loadMyShop();
    });
  }

  Widget _buildTopCard() {
    final hasShop = myShop != null;

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
              const Icon(
                Icons.store,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasShop ? myShop!['shop_name'] : 'Sell on Na You Get',
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
                : 'Create your shop to start selling.',
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
              icon: Icon(hasShop ? Icons.open_in_new : Icons.store),
              label: Text(
                hasShop ? 'Open My Shop' : 'Create My Shop',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (hasShop) {
                  _openShopProfilePage(myShop!);
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchShops,
          ),
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
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: InkWell(
                              onTap: () => _openShop(shop),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: const Color(0xFF1B5E20),
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
                                                fontSize: 24,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shop['shop_name'] ?? 'Shop',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${shop['city'] ?? ''} • ${shop['category'] ?? 'Other'}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.inventory_2,
                                                  size: 14,
                                                  color: Colors.grey.shade500),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${shop['product_count'] ?? 0} products',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        color: Colors.grey.shade400),
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
    final imageUrl = product['image_url'];
    final hasImage =
        imageUrl != null && imageUrl.toString().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(product['title'] ?? 'Product')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 280,
              color: Colors.white,
              child: hasImage
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.white,
                        child: const Center(
                          child: Icon(Icons.shopping_bag,
                              size: 80, color: Colors.green),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white,
                      child: const Center(
                        child: Icon(Icons.shopping_bag,
                            size: 80, color: Colors.green),
                      ),
                    ),
            ),
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
                  Row(
                    children: [
                      const Icon(Icons.store, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${product['shop_name'] ?? ''} • ${product['shop_city'] ?? ''}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
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

                final response = await http.post(
                  Uri.parse('$baseUrl/merchants/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
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
                  await ShopSession.save(merchantData);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => myShop = merchantData);
                    _openShopProfilePage(merchantData);
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Failed to create shop. Try a different name.')),
                    );
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
        builder: (context) => ShopProfileScreen(merchant: merchantData),
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
                hasShop ? Icons.storefront : Icons.add_business,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasShop ? myShop!['shop_name'] : 'Sell on Na You Get',
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
                : 'Hi $userName! Create your shop to start selling.',
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
              icon: Icon(hasShop ? Icons.open_in_new : Icons.store),
              label: Text(
                hasShop ? 'Upload Your Goods Items You Are Selling' : 'Create My Shop',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (hasShop) {
                  _openShopProfilePage(myShop!);
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEverything,
          ),
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
class ShopProfileScreen extends StatefulWidget {
  final Map<String, dynamic> merchant;
  const ShopProfileScreen({super.key, required this.merchant});

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  List<dynamic> myProducts = [];
  bool isLoading = true;
  late Map<String, dynamic> merchant;

  @override
  void initState() {
    super.initState();
    merchant = Map<String, dynamic>.from(widget.merchant);
    fetchShopProducts();
  }

  Future<void> fetchShopProducts() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${merchant['id']}/products/'),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() {
          myProducts = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _showEditShopDialog() async {
    final shopNameController =
        TextEditingController(text: merchant['shop_name'] ?? '');
    final ownerNameController =
        TextEditingController(text: merchant['owner_name'] ?? '');
    final phoneController =
        TextEditingController(text: merchant['phone_number'] ?? '');
    final cityController =
        TextEditingController(text: merchant['city'] ?? 'Freetown');
    String? currentLogo = merchant['logo_url'];
    String selectedCategory = merchant['category'] ?? 'Other';

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
                  Uri.parse('$baseUrl/merchants/${merchant['id']}'),
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
                  }),
                );

                if (response.statusCode >= 200 && response.statusCode < 300) {
                  final updated = jsonDecode(response.body)['merchant'];
                  await ShopSession.save(updated);
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => merchant = Map<String, dynamic>.from(updated));
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
          fetchShopProducts();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You cannot delete this product')),
          );
        }
      }
    } catch (_) {}
  }

  void _showAddItemDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    final imageUrlController = TextEditingController();
    String selectedCategory = 'Other';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Item to ${merchant['shop_name']}'),
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
                      final url = await pickAndUploadImage(context);
                      if (url != null) {
                        imageUrlController.text = url;
                        setDialogState(() {});
                      }
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Pick Photo from Phone'),
                  ),
                ),
                if (imageUrlController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrlController.text,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image Web Link (Optional)',
                    border: OutlineInputBorder(),
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

                final response = await http.post(
                  Uri.parse('$baseUrl/products/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': apiKey,
                  },
                  body: jsonEncode({
                    'merchant_id': merchant['id'],
                    'title': titleController.text,
                    'description': descController.text,
                    'category': selectedCategory,
                    'price_sle': price,
                    'image_url': imageUrlController.text.isNotEmpty
                        ? imageUrlController.text
                        : null,
                  }),
                );

                if (mounted) {
                  Navigator.pop(ctx);
                  if (response.statusCode >= 200 &&
                      response.statusCode < 300) {
                    fetchShopProducts();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to add product.')),
                    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(merchant['shop_name'] ?? 'My Shop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Orders',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MerchantOrdersScreen(merchant: merchant),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit shop info',
            onPressed: _showEditShopDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF1B5E20),
                      backgroundImage: merchant['logo_url'] != null &&
                              merchant['logo_url'].toString().isNotEmpty
                          ? NetworkImage(merchant['logo_url'])
                          : null,
                      child: merchant['logo_url'] != null &&
                              merchant['logo_url'].toString().isNotEmpty
                          ? null
                          : Text(
                              (merchant['shop_name'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        merchant['shop_name'] ?? '',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Owner: ${merchant['owner_name']}'),
                Text('Location: ${merchant['city']}, Sierra Leone'),
                Text('Category: ${merchant['category'] ?? 'Other'}'),
                Text('Contact: ${merchant['phone_number']}'),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Inventory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddItemDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : myProducts.isEmpty
                    ? const Center(
                        child: Text(
                            'No items in your shop yet.\nTap "Add Product" to list your first item.'),
                      )
                    : ListView.builder(
                        itemCount: myProducts.length,
                        itemBuilder: (ctx, i) {
                          final item = myProducts[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: ListTile(
                              leading: const Icon(Icons.shopping_bag,
                                  size: 36, color: Colors.green),
                              title: Text(item['title']),
                              subtitle: Text(
                                  'Price: SLE ${item['price_sle']} • ${item['category'] ?? 'Other'}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Delete product',
                                onPressed: () => _deleteProduct(
                                  item['id'],
                                  item['title'] ?? 'this product',
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
      if (widget.currentUser!['role'] == 'driver') return true;
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchJobs),
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

                                  await http.put(
                                    Uri.parse(
                                        '$baseUrl/deliveries/${job['id']}/accept/${widget.currentUser!['id']}'),
                                    headers: {'x-api-key': apiKey},
                                  );
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
    final isRunner = user != null && user['role'] == 'driver';

    final String subtitle;
    if (isRunner) {
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
          colors: isRunner
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
                foregroundColor: isRunner
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFF0D47A1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(isRunner ? Icons.list_alt : Icons.directions_run),
              label: Text(
                isRunner ? 'View Available Jobs' : 'How to become a Runner',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (isRunner) {
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
                    );
                  },
                ),
    );
  }
}