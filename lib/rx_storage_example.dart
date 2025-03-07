import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rx_storage_utils/rx_storage_utils.dart';

void main() async {
  // Initialize Flutter binding
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RxStorageUtils before using it (typically in main.dart)
  await RxStorageUtils.init(
    enableLogging: true, // Enable logging for development
    enableEncryption: false, // Disable encryption for this example
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'RxStorage Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RxStorageDemo(),
    );
  }
}

// Example model class for storage demonstrations
class UserProfile {
  final String id;
  final String name;
  final int age;
  final List<String> interests;

  UserProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.interests,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'interests': interests,
    };
  }

  // Create from JSON for retrieval
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      interests: List<String>.from(json['interests']),
    );
  }
}

// Another example model
class TodoItem {
  final String id;
  final String title;
  final bool completed;
  final DateTime createdAt;

  TodoItem({
    required this.id,
    required this.title,
    this.completed = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class RxStorageDemo extends StatefulWidget {
  const RxStorageDemo({super.key});

  @override
  State<RxStorageDemo> createState() => _RxStorageDemoState();
}

class _RxStorageDemoState extends State<RxStorageDemo> {
  // ======================================================================
  // BASIC REACTIVE VARIABLES FOR STORAGE DEMONSTRATION
  // ======================================================================

  // Simple reactive variables for primitive types
  final RxString usernameRx = RxString('');
  final RxBool isDarkModeRx = RxBool(false);
  final RxInt counterRx = RxInt(0);
  final RxDouble scoreRx = RxDouble(0.0);

  // Complex object storage with Rx
  final Rx<UserProfile?> currentUserRx = Rx<UserProfile?>(null);

  // List storage with RxList
  final RxList<TodoItem> todosRx = RxList<TodoItem>([]);

  // Status variables for UI feedback
  final RxString statusMessage = RxString('');
  final RxBool isBusy = RxBool(false);

  @override
  void initState() {
    super.initState();
    _initializeStorage();
  }

  Future<void> _initializeStorage() async {
    setState(() => isBusy.value = true);
    try {
      // =================================================================
      // EXAMPLE 1: LINKING SIMPLE RX VARIABLES WITH STORAGE
      // =================================================================

      // Link a String Rx variable with storage
      // This creates two-way sync: changes to the Rx variable are saved to storage
      // and external changes to storage update the Rx variable
      await RxStorageUtils().linkWithStorage(
        key: 'username',
        rxValue: usernameRx,
        fromData: (data) => data as String,
        toData: (value) => value,
        defaultValue: 'Guest User', // Used if no stored value exists
        onChange: (oldValue, newValue) {
          // Optional callback when value changes
          statusMessage.value = 'Username changed: $oldValue → $newValue';
        },
      );

      // Link a Boolean Rx variable with storage
      await RxStorageUtils().linkWithStorage(
        key: 'dark_mode',
        rxValue: isDarkModeRx,
        fromData: (data) => data as bool,
        toData: (value) => value,
        defaultValue: false,
      );

      // Link numeric values with storage
      await RxStorageUtils().linkWithStorage(
        key: 'counter',
        rxValue: counterRx,
        fromData: (data) => data as int,
        toData: (value) => value,
        defaultValue: 0,
      );

      await RxStorageUtils().linkWithStorage(
        key: 'score',
        rxValue: scoreRx,
        fromData: (data) => data as double,
        toData: (value) => value,
        defaultValue: 0.0,
      );

      // =================================================================
      // EXAMPLE 2: LINKING COMPLEX OBJECTS WITH STORAGE
      // =================================================================

      // Link a complex object (UserProfile) with storage
      await RxStorageUtils().linkWithStorage<UserProfile, dynamic, dynamic>(
        key: 'current_user',
        rxValue: currentUserRx,
        fromData: (data) => UserProfile.fromJson(data),
        toData: (user) => user.toJson(),
        defaultValue: UserProfile(
          id: 'default-id',
          name: 'New User',
          age: 30,
          interests: ['Flutter', 'Dart'],
        ),
        onInitialValue: (user) {
          // Called when initial value is loaded or default is set
          statusMessage.value = 'User profile loaded: ${user.name}';
        },
      );

      // =================================================================
      // EXAMPLE 3: LINKING LISTS WITH STORAGE
      // =================================================================

      // Link a list of objects with storage
      await RxStorageUtils().linkListWithStorage<dynamic, dynamic, dynamic>(
        key: 'todos',
        rxList: todosRx,
        fromData: (data) => TodoItem.fromJson(data),
        toData: (item) => item.toJson(),
        onInitialValue: (items) {
          statusMessage.value = 'Loaded ${items.length} todo items';
        },
      );

      // If we don't have any todos yet, add some example items
      if (todosRx.isEmpty) {
        todosRx.addAll([
          TodoItem(
            id: '1',
            title: 'Learn RxStorageUtils',
            completed: false,
          ),
          TodoItem(
            id: '2',
            title: 'Build awesome Flutter app',
            completed: false,
          ),
        ]);
        statusMessage.value = 'Added sample todo items';
      }

      // =================================================================
      // EXAMPLE 4: TEMPORARY STORAGE WITH EXPIRATION
      // =================================================================

      // Store a value that expires after 1 minute
      await RxStorageUtils().setValueWithExpirationInternal(
        'temporary_message',
        'This message will expire in 1 minute!',
        const Duration(minutes: 1),
      );

      // Get it back
      final tempMessage = await RxStorageUtils()
          .getValueWithExpirationInternal<String>('temporary_message');

      print('Temporary message: $tempMessage');

      // After 1 minute, this will return null
    } catch (e) {
      statusMessage.value = 'Error initializing storage: $e';
      print('Error in storage initialization: $e');
    } finally {
      setState(() => isBusy.value = false);
    }
  }

  // =================================================================
  // EXAMPLE METHODS FOR MANIPULATING STORAGE VALUES
  // =================================================================

  // Update the username (both Rx and storage)
  void _updateUsername(String newName) {
    // Simply update the Rx value - storage is automatically updated
    usernameRx.value = newName;

    // The linkWithStorage setup handles the persistence automatically!
    statusMessage.value = 'Username updated to: $newName';
  }

  // Toggle dark mode setting
  void _toggleDarkMode() {
    // Toggle the value
    isDarkModeRx.value = !isDarkModeRx.value;
    statusMessage.value = 'Dark mode: ${isDarkModeRx.value}';
  }

  // Increment counter
  void _incrementCounter() {
    // Directly modify the Rx value
    counterRx.value++;
    statusMessage.value = 'Counter incremented to: ${counterRx.value}';
  }

  // Update the user profile
  void _updateUserProfile() {
    if (currentUserRx.value != null) {
      // Create a new profile (objects should be treated as immutable)
      final updatedUser = UserProfile(
        id: currentUserRx.value!.id,
        name: '${currentUserRx.value!.name} (Updated)',
        age: currentUserRx.value!.age + 1,
        interests: [...currentUserRx.value!.interests, 'Storage APIs'],
      );

      // Update the Rx value - storage sync happens automatically
      currentUserRx.value = updatedUser;
      statusMessage.value = 'Updated user profile';
    }
  }

  // Add a new todo item
  void _addTodoItem() {
    final newItem = TodoItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New task ${todosRx.length + 1}',
    );

    // Add to the RxList - storage sync happens automatically
    todosRx.add(newItem);
    statusMessage.value = 'Added new todo item';
  }

  // Toggle completion status of a todo item
  void _toggleTodoCompletion(int index) {
    if (index >= 0 && index < todosRx.length) {
      final item = todosRx[index];
      final updatedItem = TodoItem(
        id: item.id,
        title: item.title,
        completed: !item.completed,
        createdAt: item.createdAt,
      );

      // Update the item in the RxList
      todosRx[index] = updatedItem;
      statusMessage.value = 'Updated todo completion status';
    }
  }

  // Remove a todo item
  void _removeTodoItem(int index) {
    if (index >= 0 && index < todosRx.length) {
      todosRx.removeAt(index);
      statusMessage.value = 'Removed todo item';
    }
  }

  // =================================================================
  // EXAMPLE OF MANUAL SYNCHRONIZATION (WITHOUT AUTO-SYNC)
  // =================================================================

  Future<void> _demonstrateManualSync() async {
    // Create a separate list not linked to storage
    final manualTodos = <TodoItem>[
      TodoItem(id: 'manual-1', title: 'Manual Item 1'),
      TodoItem(id: 'manual-2', title: 'Manual Item 2'),
    ];

    // Manually save this list to storage
    await RxStorageUtils().saveList(
      key: 'manual_todos',
      list: manualTodos,
      toData: (item) => item.toJson(),
    );

    // Later, load the list from storage
    final loadedTodos =
        await RxStorageUtils().loadList<TodoItem, Map<String, dynamic>>(
      key: 'manual_todos',
      fromData: (data) => TodoItem.fromJson(data),
    );

    statusMessage.value = 'Manually synced ${loadedTodos.length} items';
  }

  // =================================================================
  // DEMONSTRATE CHANGE LISTENERS
  // =================================================================

  void _demonstrateChangeListeners() {
    // Register a change listener for the username
    final dispose =
        RxStorageUtils().onDataChange('username', (oldValue, newValue) {
      print('Username changed: $oldValue → $newValue');
      // Show a snackbar with the change
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Username changed: $oldValue → $newValue')),
      );
    });

    // In a real app, you would store the dispose function and call it when no longer needed
    // For example in dispose() method of your widget

    // For this demo, we'll just dispose it after a delay
    Future.delayed(const Duration(seconds: 30), dispose);
  }

  // =================================================================
  // DEMONSTRATE BATCH OPERATIONS WITHOUT NOTIFICATIONS
  // =================================================================

  Future<void> _performBatchUpdates() async {
    statusMessage.value = 'Starting batch update...';

    // Perform multiple updates without triggering individual notifications
    await RxStorageUtils().withoutNotifications(() async {
      // Update multiple values in a batch
      // await RxStorageUtils.write('batch_value1', 'Value 1');
      // await RxStorageUtils.write('batch_value2', 'Value 2');
      // await RxStorageUtils.write('batch_value3', 'Value 3');

      // Updating reactive values would still work
      counterRx.value += 10;
      usernameRx.value = 'Batch Updated User';
    }, notifyKeysAfter: ['username', 'counter']);

    statusMessage.value = 'Batch update completed';
  }

  // =================================================================
  // DEBUG PRINTING
  // =================================================================

  Future<void> _printAllStoredValues() async {
    // This will print all stored values to the console for debugging
    await RxStorageUtils().printAllStoredValuesInternal();
    statusMessage.value = 'Printed storage values to console';
  }

  // =================================================================
  // UI FOR DEMONSTRATION
  // =================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RxStorageUtils Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printAllStoredValues,
            tooltip: 'Print all stored values',
          ),
        ],
      ),
      body: Obx(() => isBusy.value
          ? const Center(child: CircularProgressIndicator())
          : _buildDemoContent()),
      floatingActionButton: FloatingActionButton(
        onPressed: _demonstrateChangeListeners,
        tooltip: 'Setup change listeners',
        child: const Icon(Icons.notifications_active),
      ),
    );
  }

  Widget _buildDemoContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status message
          if (statusMessage.value.isNotEmpty)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  statusMessage.value,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Basic value storage examples
          _buildSection(
            'Simple Values',
            [
              // Username (String)
              _buildSimpleValueCard(
                'Username',
                usernameRx.value,
                onEdit: () {
                  _showEditDialog(
                    'Edit Username',
                    initialValue: usernameRx.value,
                    onSave: _updateUsername,
                  );
                },
              ),

              // Dark Mode (boolean)
              _buildToggleCard(
                'Dark Mode',
                isDarkModeRx.value,
                onToggle: _toggleDarkMode,
              ),

              // Counter (int)
              _buildCounterCard(
                'Counter',
                counterRx.value,
                onIncrement: _incrementCounter,
              ),

              // Score (double)
              _buildSimpleValueCard(
                'Score',
                scoreRx.value.toStringAsFixed(1),
                onEdit: () {
                  _showEditDialog(
                    'Edit Score',
                    initialValue: scoreRx.value.toString(),
                    onSave: (value) {
                      scoreRx.value = double.tryParse(value) ?? scoreRx.value;
                    },
                  );
                },
              ),
            ],
          ),

          // Complex object storage
          _buildSection(
            'Complex Object',
            [
              _buildProfileCard(currentUserRx.value,
                  onUpdate: _updateUserProfile),
            ],
          ),

          // List storage
          _buildSection(
            'List Storage',
            [
              _buildTodoListCard(
                todosRx,
                onAddItem: _addTodoItem,
                onToggleItem: _toggleTodoCompletion,
                onDeleteItem: _removeTodoItem,
              ),
            ],
          ),

          // Additional advanced demos
          _buildSection(
            'Advanced Features',
            [
              Card(
                child: ListTile(
                  title: const Text('Manual Synchronization'),
                  subtitle:
                      const Text('Demonstrate manual save and load operations'),
                  trailing: const Icon(Icons.sync),
                  onTap: _demonstrateManualSync,
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Batch Updates'),
                  subtitle: const Text(
                      'Perform multiple storage operations as a batch'),
                  trailing: const Icon(Icons.batch_prediction),
                  onTap: _performBatchUpdates,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSimpleValueCard(String label, String value,
      {VoidCallback? onEdit}) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: onEdit,
        ),
      ),
    );
  }

  Widget _buildToggleCard(String label, bool value, {VoidCallback? onToggle}) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Switch(
          value: value,
          onChanged: (_) => onToggle?.call(),
        ),
      ),
    );
  }

  Widget _buildCounterCard(String label, int value,
      {VoidCallback? onIncrement}) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text('Current value: $value'),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: onIncrement,
        ),
      ),
    );
  }

  Widget _buildProfileCard(UserProfile? profile, {VoidCallback? onUpdate}) {
    if (profile == null) {
      return const Card(
        child: ListTile(
          title: Text('No Profile'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${profile.name}', style: const TextStyle(fontSize: 16)),
            Text('Age: ${profile.age}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Interests:', style: TextStyle(fontSize: 16)),
            Wrap(
              spacing: 8,
              children: profile.interests
                  .map((interest) => Chip(label: Text(interest)))
                  .toList(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onUpdate,
              child: const Text('Update Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoListCard(
    List<TodoItem> todos, {
    VoidCallback? onAddItem,
    Function(int)? onToggleItem,
    Function(int)? onDeleteItem,
  }) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Todo Items',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                  onPressed: onAddItem,
                ),
              ],
            ),
          ),
          const Divider(),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final item = todos[index];
              return ListTile(
                leading: Checkbox(
                  value: item.completed,
                  onChanged: (_) => onToggleItem?.call(index),
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    decoration:
                        item.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  'Created: ${_formatDate(item.createdAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => onDeleteItem?.call(index),
                ),
                onTap: () => onToggleItem?.call(index),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showEditDialog(
    String title, {
    required String initialValue,
    required Function(String) onSave,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
