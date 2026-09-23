import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String baseUrl = 'https://random.taila91e03.ts.net';
const String apiKey = '3258852141263772bdc450e22e847032c586edd4692a56bf4c1d96208b0622aee3';

void main() {
  runApp(const NaYouGetApp());
}

class NaYouGetApp extends StatelessWidget {
  const NaYouGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Na You Get (NUG)',
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
// MAIN NAVIGATION
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const MarketplaceScreen(),
    const DriverDashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Marketplace'),
          NavigationDestination(icon: Icon(Icons.two_wheeler), label: 'Driver Jobs'),
        ],
      ),
    );
  }
}

// ==========================================
// 1. MARKETPLACE SCREEN
// ==========================================
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  List<dynamic> products = [];
  Map<String, dynamic>? myShop;
  bool isLoading = true;
  String selectedFilterCategory = 'All';

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
    if (selectedFilterCategory == 'All') return products;
    return products.where((p) => p['category'] == selectedFilterCategory).toList();
  }

  void _showCreateShopDialog() {
    final shopNameController = TextEditingController();
    final ownerNameController = TextEditingController();
    final phoneController = TextEditingController(text: '+232');
    final cityController = TextEditingController(text: 'Freetown');
    String selectedCategory = 'Fashion';

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
                    labelText: 'Shop Name (e.g. Salone Fashion Hub)',
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
                    labelText: 'Phone Number (+232...)',
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
                    if (value != null) setDialogState(() => selectedCategory = value);
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
                          content: Text('Failed to create shop. Try a different name.')),
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

  void _showCheckout(dynamic product) {
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
                    'customer_id': 1,
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
                    const SnackBar(content: Text('Order placed! Driver dispatched.')),
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

  Widget _buildMyShopCard() {
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
                : 'Create your own shop page and list your goods.',
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

    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 60),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEverything),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMyShopCard(),
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
                                selectedFilterCategory == 'All'
                                    ? 'No items listed yet in Sierra Leone.'
                                    : 'No items in "$selectedFilterCategory".',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap "Create My Shop" below to start selling.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(10),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (ctx, i) {
                            final item = visible[i];
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
                                      item['title'],
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text('SLE ${item['price_sle']}'),
                                    Text(
                                      '🏪 ${item['shop_name']} • ${item['shop_city']}',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () => _showCheckout(item),
                                        child: const Text('Buy'),
                                      ),
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
      floatingActionButton: myShop == null
          ? FloatingActionButton.extended(
              onPressed: _showCreateShopDialog,
              icon: const Icon(Icons.store),
              label: const Text('Create My Shop'),
            )
          : null,
    );
  }
}

// ==========================================
// 2. SHOP PROFILE PAGE
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
                    labelText: 'Item Title (e.g. Local Rice 50kg)',
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
                    if (value != null) setDialogState(() => selectedCategory = value);
                  },
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
                  if (response.statusCode >= 200 && response.statusCode < 300) {
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
          'You can create a new shop or sign in to a different one. Your products will stay on the marketplace.',
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
            child: const Text('Sign Out'),
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
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
// 3. DRIVER DASHBOARD
// ==========================================
class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  List<dynamic> jobs = [];

  @override
  void initState() {
    super.initState();
    fetchJobs();
  }

  Future<void> fetchJobs() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/deliveries/available/'));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => jobs = jsonDecode(res.body));
      }
    } catch (_) {}
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
      body: jobs.isEmpty
          ? const Center(child: Text('No delivery jobs available right now.'))
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (ctx, i) {
                final job = jobs[i];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text('Dropoff: ${job['delivery_address']}'),
                    subtitle: Text(
                        'Fee: SLE ${job['delivery_fee_sle']} | Payment: ${job['payment_method']}'),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        await http.put(
                          Uri.parse('$baseUrl/deliveries/${job['id']}/accept/99'),
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