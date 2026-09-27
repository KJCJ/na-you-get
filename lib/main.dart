import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

const String baseUrl = 'https://random.taila91e03.ts.net';
const String apiKey = '3269e65be9a1970f8dc3874d4da06407e19e12d63427e75213bff1785acabfd295';
const String appVersion = '1.0.0';
const String apkDownloadUrl = 'https://github.com/KJCJ/na-you-get/raw/main/apk/NaYouGet.apk';

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
    request.files.add(await http.MultipartFile.fromPath('file', picked.path));

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
    return null;
  }
}

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

  static Future<void> save(Map<String, dynamic> user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, user['id']);
    await prefs.setString(_nameKey, user['name']);
    await prefs.setString(_phoneKey, user['phone_number']);
    await prefs.setString(_roleKey, user['role']);
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

  static Future<void> save(Map<String, dynamic> merchant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idKey, merchant['id']);
    await prefs.setString(_nameKey, merchant['shop_name']);
    await prefs.setString(_ownerKey, merchant['owner_name']);
    await prefs.setString(_phoneKey, merchant['phone_number']);
    await prefs.setString(_cityKey, merchant['city'] ?? 'Freetown');
    await prefs.setString(_categoryKey, merchant['category'] ?? 'Other');
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
    if (_phoneController.text.trim().length < 8) {
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
            'phone_number': _phoneController.text.trim(),
            'password': _passwordController.text,
          }
        : {
            'phone_number': _phoneController.text.trim(),
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
    if (mounted) {
      setState(() {
        _currentUser = user;
        _loadingUser = false;
      });
    }
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
      const MarketplaceLocationsScreen(),
      RunnerDashboardScreen(
          currentUser: _currentUser, onUserChanged: _refreshUser),
    ];

    return Scaffold(
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
    );
  }
}

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
    request.files.add(await http.MultipartFile.fromPath('file', picked.path));

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
    return null;
  }
}

// ==========================================
// REUSABLE: SHOP PRODUCT GRID
// ==========================================
class ShopProductGrid extends StatelessWidget {
  final List<dynamic> products;
  final void Function(dynamic product) onBuy;
  final VoidCallback? onRefresh;

  const ShopProductGrid({
    super.key,
    required this.products,
    required this.onBuy,
    this.onRefresh,
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    color: Colors.green.shade100,
                    width: double.infinity,
                    child: item['image_url'] != null &&
                            item['image_url'].toString().isNotEmpty
                        ? Image.network(
                            item['image_url'],
                            fit: BoxFit.cover,
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => onBuy(item),
                    child: const Text('Buy'),
                  ),
                ),
              ],
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
class MarketplaceLocationsScreen extends StatelessWidget {
  const MarketplaceLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No markets yet.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Markets like Lumley, Bo Central, and Freetown Central will appear here once sellers add their locations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
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
// SHOP PAGE — VIEWING A SHOP
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

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${widget.shop['id']}/products/'),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as List;
        final enriched = data.map((p) {
          return {
            ...p,
            'shop_name': widget.shop['shop_name'],
            'shop_city': widget.shop['city'],
            'shop_category': widget.shop['category'],
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
                await http.post(
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
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Order placed! Runner will be assigned.')),
                  );
                }
              },
              child: const Text('Confirm Order'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;

    return Scaffold(
      appBar: AppBar(
        title: Text(shop['shop_name'] ?? 'Shop'),
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
                      child: Text(
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

  @override
  void initState() {
    super.initState();
    _fetchShops();
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchShops,
          ),
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
                                      child: Text(
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

  void _showAccountSheet() {
    final user = widget.currentUser;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
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
                      final ok = await _ensureLoggedIn();
                      if (ok && mounted) setState(() {});
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
                      final ok = await _ensureLoggedIn();
                      if (ok && mounted) setState(() {});
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
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
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
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Sign Out',
                    style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await UserSession.clear();
                  await ShopSession.clear();
                  widget.onUserChanged();
                  if (mounted) setState(() => myShop = null);
                },
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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
                await http.post(
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
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Order placed! Runner will be assigned.')),
                  );
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
    final visible = filteredProducts;
    final isLoggedIn = widget.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEverything,
          ),
          IconButton(
            icon: Icon(isLoggedIn ? Icons.account_circle : Icons.login),
            tooltip: isLoggedIn ? 'My Account' : 'Sign In',
            onPressed: _showAccountSheet,
          ),
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
                        ),
                ),
              ],
            ),
    );
  }
}

// ==========================================
// SHOP PROFILE (SELLER'S OWN VIEW)
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

  @override
  void initState() {
    super.initState();
    fetchShopProducts();
  }

  Future<void> fetchShopProducts() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/merchants/${widget.merchant['id']}/products/'),
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
          title: Text('Add Item to ${widget.merchant['shop_name']}'),
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
                    'merchant_id': widget.merchant['id'],
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

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of this shop?'),
        content: const Text(
          'Your products will stay on the marketplace. You can always sign back in later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ShopSession.clear();
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            child: const Text('Sign Out of Shop'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.merchant['shop_name']),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out of shop',
            onPressed: _confirmLogout,
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
                Text(
                  widget.merchant['shop_name'],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Owner: ${widget.merchant['owner_name']}'),
                Text('Location: ${widget.merchant['city']}, Sierra Leone'),
                Text('Category: ${widget.merchant['category'] ?? 'Other'}'),
                Text('Contact: ${widget.merchant['phone_number']}'),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchJobs),
        ],
      ),
      body: _loadingJobs
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}