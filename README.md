# RxStorageUtils

[![pub package](https://img.shields.io/pub/v/rx_storage_utils.svg)](https://pub.dev/packages/rx_storage_utils)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Platform-Flutter-02569B?logo=flutter)](https://flutter.dev)

A powerful Flutter utility that seamlessly binds GetX reactive state with persistent storage, ensuring your UI state and device storage remain perfectly synchronized.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Getting Started](#getting-started)
  - [Initialization](#initialization)
  - [Basic Usage](#basic-usage)
- [API Reference](#api-reference)
- [Advanced Examples](#advanced-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- 🔄 **Reactive State Binding** - Automatically sync GetX reactive variables with persistent storage
- 📦 **Type-Safe Storage** - Strongly typed data persistence with custom converters
- 📋 **List Support** - Special handling for reactive lists
- 🔒 **Update Protection** - Prevents infinite update loops with intelligent locking
- 🐞 **Debug Mode** - Detailed logging and performance tracking for troubleshooting
- ⚡ **Performance Optimization** - Minimizes storage writes by tracking actual changes

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  rx_storage_utils: ^1.0.0
  get: ^4.6.5
  get_storage: ^2.1.1
```

## Getting Started

### Initialization

Initialize the storage system in your app's `main()` method:

```dart
import 'package:rx_storage_utils/rx_storage_utils.dart';

void main() async {
  // Initialize storage before runApp
  await RxStorageUtils.initStorage();

  // Enable debug mode during development
  RxStorageUtils.setDebugMode(true, trackTiming: true);

  runApp(MyApp());
}
```

### Basic Usage

#### Binding a Simple Reactive Value

```dart
// Create a reactive variable
final RxString username = ''.obs;

// Bind it to persistent storage
await RxStorageUtils.bindReactiveValue<String>(
  key: 'username',
  rxValue: username,
  onUpdate: (data) => print('Username updated: $data'),
  onInitialLoadFromDb: (data) => print('Username loaded: $data'),
  toRawData: (data) => data, // String can be stored directly
  fromRawData: (data) => data.toString(),
  autoSync: true, // automatically sync changes to storage
);

// Use the reactive value normally in your UI
// Any changes will be automatically persisted
username.value = 'JohnDoe';
```

#### Binding Complex Objects

```dart
class User {
  final String name;
  final int age;

  User({required this.name, required this.age});

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
  };

  // Create from JSON
  factory User.fromJson(Map<String, dynamic> json) => User(
    name: json['name'] ?? '',
    age: json['age'] ?? 0,
  );
}

// Create a reactive user
final Rx<User> currentUser = User(name: '', age: 0).obs;

// Bind to storage with converters
await RxStorageUtils.bindReactiveValue<User>(
  key: 'current_user',
  rxValue: currentUser,
  onUpdate: (data) => print('User updated'),
  onInitialLoadFromDb: (data) => print('User loaded'),
  toRawData: (data) => data.toJson(), // Convert to storable format
  fromRawData: (data) => User.fromJson(data), // Convert back to User
);
```

#### Binding Lists

```dart
// Create a reactive list of strings
final RxList<String> todoItems = <String>[].obs;

// Bind the list to storage
await RxStorageUtils.bindReactiveListValue<String>(
  key: 'todo_items',
  rxList: todoItems,
  onUpdate: (data) => print('Todo list updated'),
  onInitialLoadFromDb: (data) => print('Todo list loaded with ${data?.length} items'),
  itemToRawData: (item) => item, // String items can be stored directly
  itemFromRawData: (data) => data.toString(),
);

// Use the list normally - changes are automatically persisted
todoItems.add('Buy groceries');
todoItems.add('Walk the dog');
```

## API Reference

### Initialization

```dart
// Initialize storage
static Future<void> initStorage() async

// Enable or disable debug mode
static void setDebugMode(bool enabled, {bool trackTiming = false})
```

### Binding Reactive Values

```dart
static Future<void> bindReactiveValue<T>({
  required String key,
  required Rx<T> rxValue,
  required Function(T? data) onUpdate,
  required Function(T? data) onInitialLoadFromDb,
  required dynamic Function(T data) toRawData,
  required T Function(dynamic data) fromRawData,
  bool autoSync = true,
})
```

### Binding Reactive Lists

```dart
static Future<void> bindReactiveListValue<T>({
  required String key,
  required RxList<T> rxList,
  required Function(List<T>? data) onUpdate,
  required Function(List<T>? data) onInitialLoadFromDb,
  required dynamic Function(T item) itemToRawData,
  required T Function(dynamic data) itemFromRawData,
  bool autoSync = true,
})
```

### Direct Storage Access

```dart
// Get a value without reactive binding
static T? getValue<T>({
  required String key,
  required T Function(dynamic data) fromRawData,
  T? defaultValue,
})

// Set a value without reactive binding
static Future<bool> setValue<T>({
  required String key,
  required T value,
  required dynamic Function(T data) toRawData,
})

// Check if a key exists
static bool hasKey(String key)

// Clear a specific key
static Future<void> clearKey(String key)

// Clear all storage
static Future<void> clearAll()
```

## Advanced Examples

### Custom Objects with List Binding

```dart
class Task {
  final String id;
  final String title;
  final bool completed;

  Task({required this.id, required this.title, this.completed = false});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    completed: json['completed'] ?? false,
  );
}

// Reactive list of Task objects
final RxList<Task> tasks = <Task>[].obs;

// Bind to storage
await RxStorageUtils.bindReactiveListValue<Task>(
  key: 'tasks',
  rxList: tasks,
  onUpdate: (data) => updateUI(),
  onInitialLoadFromDb: (data) => initializeUI(),
  itemToRawData: (task) => task.toJson(),
  itemFromRawData: (data) => Task.fromJson(data),
);
```

## Best Practices

1. **Initialize Early**: Call `initStorage()` before your app rendering starts
2. **Use Strong Types**: Always use properly typed converters (toRawData/fromRawData)
3. **Error Handling**: Add try/catch blocks in your converters for resilience
4. **Debug First**: Enable debug mode during development with `setDebugMode(true)`
5. **Key Naming**: Use consistent, descriptive key names with potential for namespacing
6. **Minimal Updates**: Only modify the values that actually change to minimize storage writes

## Troubleshooting

- If you experience update loops, check your `onUpdate` handlers for code that might modify the same value
- For slow performance, consider using `trackTiming: true` to identify bottlenecks
- Clear problematic keys using `clearKey()` if data becomes corrupted

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details
