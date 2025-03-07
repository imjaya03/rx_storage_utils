import 'package:example/helpers/mock_rx_preferences.dart';
import 'package:example/screens/book_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'RxStorage Utils Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const StorageDemoPage(),
    );
  }
}

class StorageDemoPage extends StatefulWidget {
  const StorageDemoPage({super.key});

  @override
  State<StorageDemoPage> createState() => _StorageDemoPageState();
}

class _StorageDemoPageState extends State<StorageDemoPage> {
  // Initialize storage helper instance
  final _preferences = RxPreferences();

  // Define keys for storage
  static const _usernameKey = 'username';
  static const _isDarkModeKey = 'isDarkMode';
  static const _counterKey = 'counter';
  static const _favoritesKey = 'favorites';

  // UI state variables with default values
  String _username = 'Guest';
  bool _isDarkMode = false;
  int _counter = 0;
  List<String> _favorites = [];

  // Text controllers
  final _usernameController = TextEditingController();
  final _favoriteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _favoriteController.dispose();
    super.dispose();
  }

  // Load all stored data
  Future<void> _loadStoredData() async {
    // Load username with default value
    _username = await _preferences.getString(_usernameKey) ?? 'Guest';
    _usernameController.text = _username;

    // Load dark mode preference
    _isDarkMode = await _preferences.getBool(_isDarkModeKey) ?? false;

    // Load counter value
    _counter = await _preferences.getInt(_counterKey) ?? 0;

    // Load favorites list
    final List<String>? savedFavorites =
        await _preferences.getStringList(_favoritesKey);
    if (savedFavorites != null) {
      _favorites = savedFavorites;
    }

    setState(() {});
  }

  // Save username to storage
  Future<void> _saveUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isNotEmpty) {
      await _preferences.setString(_usernameKey, newUsername);
      setState(() {
        _username = newUsername;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username saved')),
        );
      }
    }
  }

  // Toggle dark mode and save preference
  Future<void> _toggleDarkMode(bool value) async {
    await _preferences.setBool(_isDarkModeKey, value);
    setState(() {
      _isDarkMode = value;
    });
  }

  // Increment counter and save
  Future<void> _incrementCounter() async {
    final newValue = _counter + 1;
    await _preferences.setInt(_counterKey, newValue);
    setState(() {
      _counter = newValue;
    });
  }

  // Add item to favorites
  Future<void> _addFavorite() async {
    final newItem = _favoriteController.text.trim();
    if (newItem.isNotEmpty && !_favorites.contains(newItem)) {
      final updatedList = [..._favorites, newItem];
      await _preferences.setStringList(_favoritesKey, updatedList);
      setState(() {
        _favorites = updatedList;
        _favoriteController.clear();
      });
    }
  }

  // Remove item from favorites
  Future<void> _removeFavorite(String item) async {
    final updatedList = _favorites.where((i) => i != item).toList();
    await _preferences.setStringList(_favoritesKey, updatedList);
    setState(() {
      _favorites = updatedList;
    });
  }

  // Clear all stored data
  Future<void> _clearAllData() async {
    await _preferences.clear();
    setState(() {
      _username = 'Guest';
      _usernameController.text = _username;
      _isDarkMode = false;
      _counter = 0;
      _favorites = [];
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data cleared')),
      );
    }
  }

  // Navigate to the book management screen
  void _navigateToBookManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BookManagementScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RxStorage Utils Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAllData,
            tooltip: 'Clear all stored data',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Complex Data Demo Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Complex Data Management',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This demo shows how to store and manage complex data types like Books using JSON serialization.',
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _navigateToBookManagement,
                      icon: const Icon(Icons.library_books),
                      label: const Text('Open Book Library'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Welcome card with username
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, $_username!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Change Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _saveUsername,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Username'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Settings section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Dark Mode'),
                    subtitle: Text(_isDarkMode ? 'Enabled' : 'Disabled'),
                    value: _isDarkMode,
                    onChanged: _toggleDarkMode,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Counter section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Persistent Counter',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_counter',
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _incrementCounter,
                          icon: const Icon(Icons.add),
                          label: const Text('Increment'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Favorites section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Favorites List',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _favoriteController,
                          decoration: const InputDecoration(
                            labelText: 'Add a favorite item',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: _addFavorite,
                        tooltip: 'Add to favorites',
                        iconSize: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_favorites.isEmpty)
                    const Center(
                      child: Text('No favorites added yet'),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _favorites.length,
                      itemBuilder: (context, index) {
                        final item = _favorites[index];
                        return ListTile(
                          leading: const Icon(Icons.favorite),
                          title: Text(item),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeFavorite(item),
                            tooltip: 'Remove from favorites',
                          ),
                        );
                      },
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
