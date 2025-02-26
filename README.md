# rx_storage_utils

A powerful Flutter utility package for seamless persistent storage with reactive (Rx) variable integration.

[![pub package](https://img.shields.io/pub/v/rx_storage_utils.svg)](https://pub.dev/packages/rx_storage_utils)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- 🔄 **Reactive Storage**: Two-way synchronization between Rx variables and persistent storage
- 🔒 **Optional Encryption**: Built-in protection for sensitive data
- 📋 **Type-Safe**: Generic methods for storing primitive types and complex objects
- ⏱️ **Expiring Data**: Set expiration times for temporary values
- 📱 **Simple API**: Intuitive methods for common storage operations
- 🔍 **Debugging**: Tools to inspect stored values during development

## Installation

Add `rx_storage_utils` to your `pubspec.yaml`:

```yaml
dependencies:
  rx_storage_utils: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Getting Started

### Initialize Storage

Initialize the storage system in your app's startup code:

```dart
import 'package:rx_storage_utils/rx_storage_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with default settings
  await StorageUtils.init();

  // Or with custom settings
  await StorageUtils.init(
    enableLogging: true,
    enableEncryption: true,
    customEncryptionKey: 'your-secure-key', // Optional
  );

  runApp(MyApp());
}
```

### Basic Usage

#### Store and Retrieve Simple Values

```dart
// Store values
await StorageUtils().setValue('username', 'JohnDoe');
await StorageUtils().setValue('age', 25);
await StorageUtils().setValue('isLoggedIn', true);
await StorageUtils().setValue('score', 95.5);

// Retrieve values (with type safety)
String? username = await StorageUtils().getValue<String>('username');
int? age = await StorageUtils().getValue<int>('age');
bool? isLoggedIn = await StorageUtils().getValue<bool>('isLoggedIn');
double? score = await StorageUtils().getValue<double>('score');
```

#### Store and Retrieve JSON Objects

```dart
// Store an object
final user = User(id: 1, name: 'John Doe', email: 'john@example.com');
await StorageUtils().writeToStorage('currentUser', user.toJson());

// Retrieve an object
final userData = await StorageUtils().readFromStorage('currentUser');
if (userData != null) {
  final user = User.fromJson(userData);
  print('User: ${user.name}');
}
```

### Reactive Storage with Automatic Synchronization

#### Link a Single Object to Storage

```dart
// Create a reactive variable
final Rx<UserProfile?> userProfileRx = Rx<UserProfile?>(null);

// Link it to persistent storage
await StorageUtils().initializeStorageWithListener<UserProfile>(
  key: 'userProfile',
  rxValue: userProfileRx,
  fromJson: UserProfile.fromJson,
  toJson: (profile) => profile.toJson(),
  onInitialValue: (profile) {
    print('Loaded profile for: ${profile.username}');
  },
);

// Now any changes to userProfileRx will automatically save to storage!
userProfileRx.value = UserProfile(username: 'jane_doe', email: 'jane@example.com');

// And when your app restarts, the value will be loaded automatically
```

#### Link a List to Storage

```dart
// Create a reactive list
final RxList<Task> tasksRx = <Task>[].obs;

// Link it to persistent storage
await StorageUtils().initializeListStorageWithListener<Task>(
  key: 'tasks',
  rxList: tasksRx,
  fromJson: Task.fromJson,
  toJson: (task) => task.toJson(),
);

// Now any changes to the list will persist automatically!
tasksRx.add(Task(id: 1, title: 'Buy groceries'));
tasksRx.add(Task(id: 2, title: 'Write report'));

// Items can be removed, replaced, etc., and storage stays in sync
tasksRx.removeAt(0);
```

### Working with Lists Manually

If you prefer to manage storage timing manually:

```dart
// Save a list
final taskList = [Task(id: 1, title: 'First task'), Task(id: 2, title: 'Second task')];
await StorageUtils().saveList(
  key: 'tasks',
  list: taskList,
  toJson: (task) => task.toJson(),
);

// Load a list
final loadedTasks = await StorageUtils().loadList<Task>(
  key: 'tasks',
  fromJson: Task.fromJson,
);

// Add an item to a stored list
await StorageUtils().addItemToList<Task>(
  key: 'tasks',
  item: Task(id: 3, title: 'New task'),
  toJson: (task) => task.toJson(),
  fromJson: Task.fromJson,
);

// Update an item by index
await StorageUtils().updateItemInList<Task>(
  key: 'tasks',
  index: 0,
  updatedItem: Task(id: 1, title: 'Updated task'),
  toJson: (task) => task.toJson(),
  fromJson: Task.fromJson,
);

// Remove an item by index
await StorageUtils().removeItemFromList<Task>(
  key: 'tasks',
  index: 1,
  toJson: (task) => task.toJson(),
  fromJson: Task.fromJson,
);
```

### Expiring Data

Store values that automatically expire after a specified duration:

```dart
// Store a temporary authentication token
await StorageUtils().setValueWithExpiration<String>(
  'authToken',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  Duration(hours: 1), // Expires after 1 hour
);

// Retrieve the value (returns null if expired)
String? token = await StorageUtils().getValueWithExpiration<String>('authToken');
```

### Debugging Tools

Print all stored values for debugging:

```dart
// In your debug/development code
await StorageUtils().printAllStoredValues();
```

## Advanced Usage

### Manual Synchronization

Force a sync from memory to storage:

```dart
// For single objects
await StorageUtils().syncRxValueToStorage<UserProfile>(
  key: 'userProfile',
  value: userProfileRx.value,
  toJson: (profile) => profile.toJson(),
);

// For lists
await StorageUtils().syncRxListToStorage<Task>(
  key: 'tasks',
  list: tasksRx,
  toJson: (task) => task.toJson(),
);
```

### Storage Management

Check, remove, and clear storage:

```dart
// Check if a key exists
bool exists = await StorageUtils().hasKey('username');

// Remove a specific value
await StorageUtils().removeFromStorage('username');

// Clear all stored data
await StorageUtils().clearStorage();
```

## Models Example

Example of model classes for use with rx_storage_utils:

```dart
class User {
  final int id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    name: json['name'],
    email: json['email'],
  );
}

class Task {
  final int id;
  final String title;
  bool completed;

  Task({required this.id, required this.title, this.completed = false});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    title: json['title'],
    completed: json['completed'] ?? false,
  );
}
```

## Theme and Dark Mode Compatibility

rx_storage_utils works seamlessly with theme changes, including dark mode. Here's an example of storing theme preferences:

```dart
// Create a reactive variable for theme mode
final Rx<ThemeMode> themeModeRx = Rx<ThemeMode>(ThemeMode.system);

// Link it to storage
await StorageUtils().initializeStorageWithListener<ThemeMode>(
  key: 'themeMode',
  rxValue: themeModeRx,
  fromJson: (data) => ThemeMode.values[data as int],
  toJson: (mode) => mode.index,
);

// In your MaterialApp
MaterialApp(
  theme: ThemeData.light(),
  darkTheme: ThemeData.dark(),
  themeMode: themeModeRx.value,
  // ...
)

// Change theme and it's automatically persisted
void toggleTheme() {
  themeModeRx.value = themeModeRx.value == ThemeMode.dark
    ? ThemeMode.light
    : ThemeMode.dark;
}
```

## Security Notes

- When `enableEncryption` is true, data is encrypted before storage
- For highly sensitive data, consider using dedicated security packages
- The default encryption is suitable for most applications but may not meet specific regulatory requirements

## Dependencies

This package is built on top of:

- [get](https://pub.dev/packages/get) - For reactive state management
- [get_storage](https://pub.dev/packages/get_storage) - For persistent storage
- [crypto](https://pub.dev/packages/crypto) - For encryption support
- [package_info_plus](https://pub.dev/packages/package_info_plus) - For auto-generating secure keys

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
# rx_storage_utils
