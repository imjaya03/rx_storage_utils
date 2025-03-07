import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// # RxStorageUtils
///
/// A powerful utility for persistent data storage in Flutter applications with
/// reactive (Rx) variable synchronization support.
///
/// ## Key Features:
///
/// * Type-safe data persistence with GetStorage backend
/// * Automatic two-way synchronization with reactive (Rx) variables
/// * Support for individual values, objects, and collections
/// * Optional data encryption for sensitive information
/// * Expiration support for temporary data storage
/// * Change listeners for monitoring data updates
///
/// ## Basic Usage Examples:
///
/// ```dart
/// // Initialize in your main.dart
/// await RxStorageUtils.init();
///
/// // Store a simple value
/// await RxStorageUtils.write('username', 'john_doe');
///
/// // Retrieve a value with type safety
/// String? username = await RxStorageUtils.get<String>('username');
///
/// // Link a reactive variable to storage
/// await RxStorageUtils().linkWithStorage(
///   key: 'user_profile',
///   rxValue: userProfileRx,
///   fromJson: UserProfile.fromJson,
///   toJson: (profile) => profile.toJson(),
/// );
///
/// // Link a reactive list to storage
/// await RxStorageUtils().linkListWithStorage(
///   key: 'todo_items',
///   rxList: todoItemsRx,
///   fromJson: TodoItem.fromJson,
///   toJson: (item) => item.toJson(),
/// );
/// ```
class RxStorageUtils {
  //--------------------------------------------------------------------------
  // SINGLETON PATTERN & INITIALIZATION
  //--------------------------------------------------------------------------

  /// Private constructor
  RxStorageUtils._internal();

  /// Singleton instance
  static final RxStorageUtils _instance = RxStorageUtils._internal();

  /// Factory constructor that returns the singleton instance
  factory RxStorageUtils() => _instance;

  /// The underlying storage instance
  GetStorage? _storage;

  /// Configuration properties
  bool _enableLogging = kDebugMode;
  bool _enableEncryption = !kDebugMode;
  String _encryptionKey = '';
  bool _autoConfigured = false;

  /// Initialization state tracking
  static bool _isInitialized = false;
  static bool _autoInitWarningShown = false;
  static final _initLock = Object();
  static bool _initializationInProgress = false;

  /// Listener management
  final Map<String, List<Function(dynamic oldValue, dynamic newValue)>>
      _changeListeners = {};
  bool _notifyListeners = true;

  /// Initialize the storage system
  ///
  /// Should be called early in app lifecycle (before using storage operations)
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await RxStorageUtils.init();
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> init({
    bool enableLogging = kDebugMode,
    bool enableEncryption = !kDebugMode,
    String? customEncryptionKey,
    bool clearInvalidData = false,
  }) async {
    // Fast return if already initialized
    if (_isInitialized) return;

    // Prevent multiple simultaneous initializations
    await _synchronizedInit(() async {
      // Double-check pattern for thread safety
      if (_isInitialized) return;

      _initializationInProgress = true;

      try {
        // Initialize GetStorage
        await GetStorage.init();

        // Configure the singleton instance
        final instance = RxStorageUtils._instance;
        instance._storage = GetStorage();
        instance._enableLogging = enableLogging;
        instance._enableEncryption = enableEncryption;

        if (customEncryptionKey != null && customEncryptionKey.isNotEmpty) {
          instance._encryptionKey = customEncryptionKey;
        }

        // Auto-configure encryption key if needed
        await instance._configureSecurity();

        _isInitialized = true;
        instance._log('RxStorageUtils initialized successfully');
      } catch (e) {
        print('Error initializing RxStorageUtils: $e');
        rethrow; // Critical initialization error
      } finally {
        _initializationInProgress = false;
      }
    });

    // Optional data validation
    if (clearInvalidData && _isInitialized) {
      RxStorageUtils()._log('Checking for invalid storage data');
      await _instance._cleanupInvalidData();
    }
  }

  /// Helper method to synchronize initialization
  static Future<void> _synchronizedInit(Future<void> Function() action) async {
    if (_initializationInProgress) {
      // Wait for existing initialization to complete
      while (_initializationInProgress) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    await action();
  }

  /// Internal method to ensure storage is initialized before use
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      if (!_autoInitWarningShown) {
        print(
            'WARNING: RxStorageUtils.init() was not called. Auto-initializing with default settings.');
        _autoInitWarningShown = true;
      }

      await init();

      if (!_isInitialized) {
        throw StateError(
            'Failed to initialize RxStorageUtils. Call RxStorageUtils.init() explicitly.');
      }
    }
  }

  /// Configure security settings including encryption key generation
  Future<void> _configureSecurity() async {
    if (_autoConfigured) return;

    try {
      // Generate encryption key if not provided and encryption is enabled
      if (_enableEncryption && _encryptionKey.isEmpty) {
        // Get app package info for generating a unique key
        final packageInfo = await PackageInfo.fromPlatform();
        final appId = packageInfo.packageName;
        final appVersion = packageInfo.version;
        final buildNumber = packageInfo.buildNumber;

        // Create a secure key based on app identity
        final baseKey = '$appId-$appVersion-$buildNumber-SecureStorageSalt';
        final keyBytes = utf8.encode(baseKey);
        final digest = sha256.convert(keyBytes);
        _encryptionKey = digest.toString();

        _log('Generated secure app-specific encryption key');
      }

      _autoConfigured = true;
      _log('Security configuration complete: encryption=$_enableEncryption');
    } catch (e) {
      _log('Security auto-configuration failed: $e. Using fallback settings.',
          isError: true);

      // Fallback configuration
      _enableEncryption = false;
      _encryptionKey = '';
    }
  }

  /// Get the storage instance safely
  GetStorage get storage {
    if (_storage == null) {
      throw StateError(
          'Storage not initialized. Call RxStorageUtils.init() before using storage.');
    }
    return _storage!;
  }

  /// Clean up invalid data in storage
  Future<void> _cleanupInvalidData() async {
    try {
      final keys = storage.getKeys();
      int cleanedCount = 0;

      for (final key in keys) {
        // Check for expired values
        if (key.endsWith('_expiration')) {
          final baseKey = key.substring(0, key.length - 11);
          final expiryTime = await getValueInternal<int>(key);

          if (expiryTime != null &&
              DateTime.now().millisecondsSinceEpoch > expiryTime) {
            await removeFromStorageInternal(baseKey);
            await removeFromStorageInternal(key);
            cleanedCount++;
          }
        }

        // More validation could be added here
      }

      if (cleanedCount > 0) {
        _log('Cleaned up $cleanedCount expired items');
      }
    } catch (e) {
      _log('Error during data cleanup: $e', isError: true);
    }
  }

  //--------------------------------------------------------------------------
  // CHANGE LISTENERS
  //--------------------------------------------------------------------------

  /// Register a listener for data changes for a specific key
  ///
  /// Returns a dispose function to unregister the listener
  ///
  /// ```dart
  /// final dispose = RxStorageUtils.onChange('settings', (oldValue, newValue) {
  ///   print('Settings changed from $oldValue to $newValue');
  /// });
  ///
  /// // Later when no longer needed:
  /// dispose();
  /// ```
  Function() onDataChange(
      String key, Function(dynamic oldValue, dynamic newValue) listener) {
    _changeListeners[key] ??= [];
    _changeListeners[key]!.add(listener);

    return () {
      if (_changeListeners.containsKey(key)) {
        _changeListeners[key]!.remove(listener);
        if (_changeListeners[key]!.isEmpty) {
          _changeListeners.remove(key);
        }
      }
    };
  }

  /// Temporarily suspend notifications to change listeners
  ///
  /// Useful for batch operations to avoid excessive notifications
  ///
  /// ```dart
  /// await RxStorageUtils.withoutNotifications(() async {
  ///   await RxStorageUtils.write('key1', value1);
  ///   await RxStorageUtils.write('key2', value2);
  ///   await RxStorageUtils.write('key3', value3);
  /// }, notifyKeysAfter: ['key1', 'key3']);
  /// ```
  Future<T> withoutNotifications<T>(
    Future<T> Function() action, {
    List<String>? notifyKeysAfter,
  }) async {
    final previousState = _notifyListeners;
    _notifyListeners = false;

    try {
      // Capture old values for keys that will be notified
      final oldValues = <String, dynamic>{};
      if (notifyKeysAfter != null) {
        for (final key in notifyKeysAfter) {
          oldValues[key] = await readFromStorageInternal(key);
        }
      }

      // Execute the action with notifications disabled
      final result = await action();

      // Process manual notifications if needed
      if (previousState && notifyKeysAfter != null) {
        for (final key in notifyKeysAfter) {
          final newValue = await readFromStorageInternal(key);
          _notifyListenersForKey(key, oldValues[key], newValue);
        }
      }

      return result;
    } finally {
      // Restore previous notification state
      _notifyListeners = previousState;
    }
  }

  /// Notify listeners for a specific key
  void _notifyListenersForKey(String key, dynamic oldValue, dynamic newValue) {
    if (!_notifyListeners || oldValue == newValue) return;

    if (_changeListeners.containsKey(key)) {
      // Create a copy of the listeners list to safely iterate
      final listeners = List.from(_changeListeners[key]!);
      for (final listener in listeners) {
        try {
          listener(oldValue, newValue);
        } catch (e) {
          _log('Error in data change listener for key=$key: $e', isError: true);
        }
      }
    }
  }

  //--------------------------------------------------------------------------
  // REACTIVE VARIABLE SYNCHRONIZATION
  //--------------------------------------------------------------------------

  /// Link a reactive variable to storage with two-way synchronization
  ///
  /// Creates a binding where the Rx variable stays in sync with stored data
  ///
  /// ```dart
  /// // Define a reactive variable
  /// final userRx = Rx<User?>(null);
  ///
  /// // Link it with storage
  /// await RxStorageUtils().linkWithStorage(
  ///   key: 'current_user',
  ///   rxValue: userRx,
  ///   fromJson: User.fromJson,
  ///   toJson: (user) => user.toJson(),
  /// );
  /// ```
  Future<void> linkWithStorage<T, S, D>({
    required String key,
    required Rx<T?> rxValue,
    required T Function(S) fromJson,
    required D Function(T) toJson,
    Function(T initialValue)? onInitialValue,
    T? defaultValue,
    bool autoSync = true,
  }) async {
    await _ensureInitialized();

    try {
      // STEP 1: Load existing data from storage
      final storedData = await readFromStorageInternal(key);
      T? initialValue;

      if (storedData != null) {
        try {
          initialValue = _convertStoredData<T, S>(storedData, fromJson, key);
        } catch (e) {
          _log('Error converting stored data for key=$key: $e', isError: true);
          initialValue = defaultValue;
        }
      }

      // STEP 2: Initialize Rx value
      if (initialValue != null) {
        rxValue.value = initialValue;

        if (onInitialValue != null) {
          onInitialValue(initialValue);
        }

        _log('Loaded initial value from storage: key=$key');
      } else if (defaultValue != null && rxValue.value == null) {
        // Use default only if no stored data AND rxValue is null
        rxValue.value = defaultValue;
        _log('Using default value for key=$key');

        if (onInitialValue != null) {
          onInitialValue(defaultValue);
        }
      } else if (rxValue.value != null) {
        _log('Using existing Rx value for key=$key');
      }

      // STEP 3: Set up auto-sync if enabled
      if (autoSync) {
        ever(
          rxValue,
          (dynamic value) async {
            if (value != null) {
              try {
                // Save to storage when Rx value changes
                await writeToStorageInternal(key, toJson(value as T));
                _log('Auto-synced value to storage: key=$key');
              } catch (e) {
                _log('Error during auto-sync: $e', isError: true);
              }
            } else {
              // Remove from storage when value becomes null
              await removeFromStorageInternal(key);
              _log('Auto-removed value from storage: key=$key');
            }
          },
        );
        _log('Auto-sync enabled for key=$key');
      }
    } catch (e) {
      _log('Error linking Rx value with storage: $e', isError: true);
      rethrow;
    }
  }

  /// Link a reactive list to storage with two-way synchronization
  ///
  /// Creates a binding where the RxList stays in sync with stored data
  ///
  /// ```dart
  /// // Define a reactive list
  /// final todoItemsRx = RxList<TodoItem>([]);
  ///
  /// // Link it with storage
  /// await RxStorageUtils().linkListWithStorage(
  ///   key: 'todo_items',
  ///   rxList: todoItemsRx,
  ///   fromJson: TodoItem.fromJson,
  ///   toJson: (item) => item.toJson(),
  /// );
  /// ```
  Future<void> linkListWithStorage<T, S, D>({
    required String key,
    required RxList<T> rxList,
    required T Function(S) fromJson,
    required D Function(T) toJson,
    Function(List<T> initialList)? onInitialValue,
    bool autoSync = true,
  }) async {
    await _ensureInitialized();

    try {
      // STEP 1: Load existing list from storage
      final storedData = await readFromStorageInternal(key);

      if (storedData != null) {
        List<T> loadedList = [];

        try {
          if (storedData is List) {
            loadedList = _convertStoredList<T, S>(storedData, fromJson);
          } else if (storedData is String) {
            final decoded = json.decode(storedData);
            if (decoded is List) {
              loadedList = _convertStoredList<T, S>(decoded, fromJson);
            }
          }
        } catch (e) {
          _log('Error loading list from storage: $e', isError: true);
        }

        if (loadedList.isNotEmpty) {
          rxList.assignAll(loadedList);

          if (onInitialValue != null) {
            onInitialValue(loadedList);
          }

          _log('Loaded ${loadedList.length} items from storage: key=$key');
        }
      }

      // STEP 2: Set up auto-sync if enabled
      if (autoSync) {
        ever(
          rxList,
          (List<T> list) async {
            try {
              if (list.isNotEmpty) {
                final storableList = list.map((item) => toJson(item)).toList();
                await writeToStorageInternal(key, storableList);
                _log('Auto-synced ${list.length} items to storage: key=$key');
              } else {
                await removeFromStorageInternal(key);
                _log('Auto-removed empty list from storage: key=$key');
              }
            } catch (e) {
              _log('Error in list auto-sync: $e', isError: true);
            }
          },
        );
        _log('List auto-sync enabled for key=$key');
      }
    } catch (e) {
      _log('Error linking RxList with storage: $e', isError: true);
    }
  }

  /// Safely convert stored data to the target type
  T? _convertStoredData<T, S>(
      dynamic storedData, T Function(S) fromJson, String key) {
    if (storedData is S) {
      // Direct compatible type
      return fromJson(storedData);
    } else if (storedData is String && S != String) {
      // Try parsing as JSON
      try {
        final jsonData = json.decode(storedData);
        if (jsonData is S) {
          return fromJson(jsonData);
        }
      } catch (e) {
        _log('Cannot parse JSON data for key=$key: $e', isError: true);
      }
    } else if (storedData is Map) {
      // Handle Map type conversions (common case)
      try {
        return fromJson(storedData as S);
      } catch (e) {
        _log('Type conversion failed for key=$key: $e', isError: true);
      }
    }

    throw FormatException('Cannot convert ${storedData.runtimeType} to $S');
  }

  /// Convert a stored list to a list of target type objects
  List<T> _convertStoredList<T, S>(List sourceList, T Function(S) fromJson) {
    return sourceList.map((item) {
      if (item is S) {
        return fromJson(item);
      } else {
        try {
          return fromJson(item as S);
        } catch (e) {
          throw FormatException('Cannot convert ${item.runtimeType} to $S');
        }
      }
    }).toList();
  }

  //--------------------------------------------------------------------------
  // LIST OPERATIONS
  //--------------------------------------------------------------------------

  /// Save a list of objects to storage
  ///
  /// ```dart
  /// await RxStorageUtils().saveList(
  ///   key: 'contacts',
  ///   list: contactsList,
  ///   toJson: (contact) => contact.toJson(),
  /// );
  /// ```
  Future<void> saveList<T, D>({
    required String key,
    required List<T> list,
    required D Function(T) toJson,
  }) async {
    await _ensureInitialized();

    try {
      if (list.isEmpty) {
        await removeFromStorageInternal(key);
        _log('Saved empty list (removed): key=$key');
        return;
      }

      final storableList = list.map((item) => toJson(item)).toList();
      await writeToStorageInternal(key, storableList);
      _log('Saved list with ${list.length} items: key=$key');
    } catch (e) {
      _log('Error saving list: $e', isError: true);
      rethrow;
    }
  }

  /// Load a list of objects from storage
  ///
  /// ```dart
  /// final contacts = await RxStorageUtils().loadList(
  ///   key: 'contacts',
  ///   fromJson: Contact.fromJson,
  /// );
  /// ```
  Future<List<T>> loadList<T, S>({
    required String key,
    required T Function(S) fromJson,
  }) async {
    try {
      final storedData = await readFromStorageInternal(key);
      if (storedData != null && storedData is List) {
        try {
          return _convertStoredList<T, S>(storedData, fromJson);
        } catch (e) {
          _log('Error converting list items: $e', isError: true);
        }
      }
    } catch (e) {
      _log('Error loading list: $e', isError: true);
    }
    return [];
  }

  /// Add an item to a stored list
  Future<bool> addItemToList<T, S, D>({
    required String key,
    required T item,
    required D Function(T) toJson,
    required T Function(S) fromJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      existingList.add(item);
      await saveList(key: key, list: existingList, toJson: toJson);
      _log('Added item to list (now ${existingList.length} items): key=$key');
      return true;
    } catch (e) {
      _log('Error adding item to list: $e', isError: true);
      return false;
    }
  }

  /// Update an item in a stored list by index
  Future<bool> updateItemInList<T, S, D>({
    required String key,
    required int index,
    required T updatedItem,
    required T Function(S) fromJson,
    required D Function(T) toJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      if (index >= 0 && index < existingList.length) {
        existingList[index] = updatedItem;
        await saveList(key: key, list: existingList, toJson: toJson);
        _log('Updated item at index $index in list: key=$key');
        return true;
      } else {
        _log('Invalid index $index for list with ${existingList.length} items',
            isError: true);
        return false;
      }
    } catch (e) {
      _log('Error updating item in list: $e', isError: true);
      return false;
    }
  }

  /// Remove an item from a stored list by index
  Future<bool> removeItemFromList<T, S, D>({
    required String key,
    required int index,
    required T Function(S) fromJson,
    required D Function(T) toJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      if (index >= 0 && index < existingList.length) {
        existingList.removeAt(index);
        if (existingList.isEmpty) {
          await removeFromStorageInternal(key);
        } else {
          await saveList(key: key, list: existingList, toJson: toJson);
        }
        _log('Removed item at index $index from list: key=$key');
        return true;
      } else {
        _log('Invalid index $index for list with ${existingList.length} items',
            isError: true);
        return false;
      }
    } catch (e) {
      _log('Error removing item from list: $e', isError: true);
      return false;
    }
  }

  //--------------------------------------------------------------------------
  // MANUAL SYNCHRONIZATION
  //--------------------------------------------------------------------------

  /// Manually sync an Rx value to storage
  Future<void> syncToStorage<T, D>({
    required String key,
    required T value,
    required D Function(T) toJson,
  }) async {
    try {
      if (value != null) {
        await writeToStorageInternal(key, toJson(value));
        _log('Manually synced value to storage: key=$key');
      } else {
        await removeFromStorageInternal(key);
        _log('Manually removed value from storage: key=$key');
      }
    } catch (e) {
      _log('Error in manual sync: $e', isError: true);
      rethrow;
    }
  }

  /// Manually sync an RxList to storage
  Future<void> syncListToStorage<T, D>({
    required String key,
    required List<T> list,
    required D Function(T) toJson,
  }) async {
    try {
      if (list.isNotEmpty) {
        final storableList = list.map((item) => toJson(item)).toList();
        await writeToStorageInternal(key, storableList);
        _log('Manually synced list with ${list.length} items: key=$key');
      } else {
        await removeFromStorageInternal(key);
        _log('Manually removed empty list from storage: key=$key');
      }
    } catch (e) {
      _log('Error in manual list sync: $e', isError: true);
      rethrow;
    }
  }

  /// Update a value in an Rx variable and optionally sync to storage
  Future<void> updateRx<T, D>({
    required String key,
    required Rx<T?> rxValue,
    required T newValue,
    required D Function(T) toJson,
    bool syncToStorage = true,
  }) async {
    rxValue.value = newValue;
    _log('Updated Rx value: key=$key');

    if (syncToStorage) {
      await this.syncToStorage(
        key: key,
        value: newValue,
        toJson: toJson,
      );
    }
  }

  /// Update an item in an RxList and optionally sync to storage
  Future<bool> updateRxListItem<T, D>({
    required String key,
    required RxList<T> rxList,
    required int index,
    required T newValue,
    required D Function(T) toJson,
    bool syncToStorage = true,
  }) async {
    if (index < 0 || index >= rxList.length) {
      _log('Invalid index $index for list with ${rxList.length} items',
          isError: true);
      return false;
    }

    rxList[index] = newValue;
    _log('Updated item at index $index in RxList: key=$key');

    if (syncToStorage) {
      await syncListToStorage(
        key: key,
        list: rxList,
        toJson: toJson,
      );
    }

    return true;
  }

  /// Add an item to an RxList and optionally sync to storage
  Future<void> addRxListItem<T, D>({
    required String key,
    required RxList<T> rxList,
    required T item,
    required D Function(T) toJson,
    bool syncToStorage = true,
  }) async {
    rxList.add(item);
    _log('Added item to RxList (now ${rxList.length} items): key=$key');

    if (syncToStorage) {
      await syncListToStorage(
        key: key,
        list: rxList,
        toJson: toJson,
      );
    }
  }

  /// Remove an item from an RxList and optionally sync to storage
  Future<bool> removeRxListItem<T, D>({
    required String key,
    required RxList<T> rxList,
    required int index,
    required D Function(T) toJson,
    bool syncToStorage = true,
  }) async {
    if (index < 0 || index >= rxList.length) {
      _log('Invalid index $index for list with ${rxList.length} items',
          isError: true);
      return false;
    }

    rxList.removeAt(index);
    _log('Removed item at index $index from RxList: key=$key');

    if (syncToStorage) {
      if (rxList.isEmpty) {
        await removeFromStorageInternal(key);
        _log('Removed empty list from storage: key=$key');
      } else {
        await syncListToStorage(
          key: key,
          list: rxList,
          toJson: toJson,
        );
      }
    }

    return true;
  }

  //--------------------------------------------------------------------------
  // CORE STORAGE OPERATIONS
  //--------------------------------------------------------------------------

  /// Read data from storage
  Future<dynamic> readFromStorageInternal(String key) async {
    await _ensureInitialized();

    try {
      final value = storage.read(key);
      if (value == null) return null;

      // Handle decryption if needed
      if (_enableEncryption &&
          value is String &&
          value.startsWith('ENCRYPTED:')) {
        final decrypted = _decrypt(value.substring(10)); // Remove prefix
        return _safelyDecodeJson(decrypted, key);
      }

      // For non-encrypted values
      return _safelyDecodeJson(value, key);
    } catch (e) {
      _log('Error reading from storage: $e', isError: true);
      return null;
    }
  }

  /// Write data to storage
  Future<void> writeToStorageInternal(String key, dynamic data) async {
    await _ensureInitialized();

    try {
      // Get old value before updating (for change notification)
      final oldValue =
          _notifyListeners ? await readFromStorageInternal(key) : null;

      // Handle encryption if enabled
      final valueToStore = (_enableEncryption && data != null)
          ? 'ENCRYPTED:${_encrypt(data is String ? data : json.encode(data))}'
          : data;

      await storage.write(key, valueToStore);
      _log('Saved data: key=$key');

      // Notify listeners after successful write
      if (_notifyListeners) {
        _notifyListenersForKey(key, oldValue, data);
      }
    } catch (e) {
      _log('Error writing to storage: $e', isError: true);
      rethrow;
    }
  }

  /// Remove data from storage
  Future<void> removeFromStorageInternal(String key) async {
    try {
      // Get old value before removing (for change notification)
      final oldValue =
          _notifyListeners ? await readFromStorageInternal(key) : null;
      await storage.remove(key);
      _log('Removed data: key=$key');

      // Notify listeners that the value was removed (is now null)
      if (_notifyListeners) {
        _notifyListenersForKey(key, oldValue, null);
      }
    } catch (e) {
      _log('Error removing from storage: $e', isError: true);
    }
  }

  /// Clear all stored data
  Future<void> clearStorageInternal() async {
    try {
      // If notifications are enabled, capture all keys that have listeners
      final keysWithListeners =
          _notifyListeners ? _changeListeners.keys.toList() : <String>[];

      // Get current values for those keys
      final oldValues = <String, dynamic>{};
      for (final key in keysWithListeners) {
        oldValues[key] = await readFromStorageInternal(key);
      }

      // Clear the storage
      await storage.erase();
      _log('Cleared all storage data');

      // Notify listeners for each key that had a value and a listener
      if (_notifyListeners) {
        for (final key in keysWithListeners) {
          if (oldValues[key] != null) {
            _notifyListenersForKey(key, oldValues[key], null);
          }
        }
      }
    } catch (e) {
      _log('Error clearing storage: $e', isError: true);
    }
  }

  /// Store a simple value (String, int, double, bool)
  Future<void> setValueInternal<T>(String key, T value) async {
    await _ensureInitialized();
    await writeToStorageInternal(key, value);
  }

  /// Get a simple value with type safety
  Future<T?> getValueInternal<T>(String key) async {
    final value = await readFromStorageInternal(key);
    if (value == null) return null;
    if (value is T) return value;

    _log('Type mismatch for key $key: expected $T, got ${value.runtimeType}',
        isError: true);
    return null;
  }

  /// Check if a key exists in storage
  Future<bool> hasKeyInternal(String key) async {
    return storage.hasData(key);
  }

  /// Store a value with an expiration time
  Future<void> setValueWithExpirationInternal<T>(
      String key, T value, Duration expiration) async {
    final expirationTime =
        DateTime.now().add(expiration).millisecondsSinceEpoch;
    await writeToStorageInternal('${key}_expiration', expirationTime);
    await setValueInternal(key, value);
    _log(
        'Stored value with ${expiration.inMinutes} minute expiration: key=$key');
  }

  /// Get a value, respecting expiration if set
  Future<T?> getValueWithExpirationInternal<T>(String key) async {
    final expirationKey = '${key}_expiration';
    if (storage.hasData(expirationKey)) {
      final expirationTime = await getValueInternal<int>(expirationKey);
      if (expirationTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > expirationTime) {
          // Value has expired, remove both value and expiration
          await removeFromStorageInternal(key);
          await removeFromStorageInternal(expirationKey);
          _log('Value expired: key=$key');
          return null;
        }
      }
    }
    return await getValueInternal<T>(key);
  }

  /// Print all stored values for debugging purposes
  Future<void> printAllStoredValuesInternal() async {
    await _ensureInitialized();

    try {
      // Get all keys from storage
      final keys = storage.getKeys();

      if (keys.isEmpty) {
        _log('Storage is empty. No values to print.');
        return;
      }

      _log('Storage contains ${keys.length} keys:');
      _log('======================================');

      // Print each key-value pair
      for (final key in keys) {
        // Skip expiration keys for cleaner output
        if (key.endsWith('_expiration')) continue;

        var value = await readFromStorageInternal(key);
        String valueType = value?.runtimeType.toString() ?? 'null';
        String valuePreview;

        if (value == null) {
          valuePreview = 'null';
        } else if (value is Map || value is List) {
          // Format JSON objects for readability
          valuePreview =
              '${jsonEncode(value).substring(0, min(50, jsonEncode(value).length))}${jsonEncode(value).length > 50 ? '...' : ''}';
        } else {
          valuePreview = '$value';
          if (valuePreview.length > 50) {
            valuePreview = '${valuePreview.substring(0, 50)}...';
          }
        }

        // Check for expiration
        final expirationKey = '${key}_expiration';
        String expirationInfo = '';
        if (storage.hasData(expirationKey)) {
          final expiryTimestamp = storage.read(expirationKey) as int?;
          if (expiryTimestamp != null) {
            final expiryDate =
                DateTime.fromMillisecondsSinceEpoch(expiryTimestamp);
            final now = DateTime.now();
            if (expiryDate.isAfter(now)) {
              final remaining = expiryDate.difference(now);
              expirationInfo = ' (expires in ${_formatDuration(remaining)})';
            } else {
              expirationInfo = ' (EXPIRED)';
            }
          }
        }

        _log('🔑 $key:');
        _log('   Type: $valueType$expirationInfo');
        _log('   Value: $valuePreview');
        _log('--------------------------------------');
      }
      _log('======================================');
    } catch (e) {
      _log('Error printing storage values: $e', isError: true);
    }
  }

  //--------------------------------------------------------------------------
  // DEBUGGING & INSPECTION - INSTANCE METHODS
  //--------------------------------------------------------------------------

  /// Print all stored values for debugging purposes (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.printAll()`
  @Deprecated('Use StorageUtils.printAll() for static access')
  Future<void> printAllStoredValues() async {
    return await printAllStoredValuesInternal();
  }

  /// Format a duration in a human-readable format
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  //--------------------------------------------------------------------------
  // HELPER METHODS
  //--------------------------------------------------------------------------

  /// Print logs if logging is enabled
  void _log(String message, {bool isError = false}) {
    if (_enableLogging) {
      if (isError) {
        print('⚠️ [Storage] $message');
      } else {
        print('💾 [Storage] $message');
      }
    }
  }

  /// Basic encryption function
  ///
  /// NOTE: This is a simple implementation for demonstration.
  /// Use a proper encryption library for production.
  String _encrypt(String text) {
    if (_encryptionKey.isEmpty) return text;

    final bytes = utf8.encode(text);
    final key = utf8.encode(_encryptionKey);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);

    // Simple XOR encryption
    final encrypted = List<int>.from(bytes);
    for (var i = 0; i < encrypted.length; i++) {
      encrypted[i] = encrypted[i] ^ key[i % key.length];
    }

    return '${base64Encode(encrypted)}.$digest';
  }

  /// Basic decryption function
  String _decrypt(String text) {
    if (_encryptionKey.isEmpty) return text;

    try {
      final parts = text.split('.');
      if (parts.length != 2) return text; // Not properly encrypted

      final encrypted = base64Decode(parts[0]);
      final key = utf8.encode(_encryptionKey);

      // Reverse XOR operation
      final decrypted = List<int>.from(encrypted);
      for (var i = 0; i < decrypted.length; i++) {
        decrypted[i] = decrypted[i] ^ key[i % key.length];
      }

      return utf8.decode(decrypted);
    } catch (e) {
      _log('Decryption error: $e', isError: true);
      return text;
    }
  }

  /// Internal method to handle unexpected data formats
  dynamic _safelyDecodeJson(dynamic data, String key) {
    if (data == null) return null;

    try {
      if (data is String) {
        // Check if string looks like JSON
        if ((data.startsWith('{') && data.endsWith('}')) ||
            (data.startsWith('[') && data.endsWith(']'))) {
          return json.decode(data);
        }
      }
      return data;
    } catch (e) {
      _log('Error decoding JSON for key=$key: $e', isError: true);
      return data; // Return original data if parsing fails
    }
  }

  /// Get count of listeners for a specific key (useful for testing)
  int getListenerCount(String key) {
    return _changeListeners[key]?.length ?? 0;
  }

  /// Get total count of registered listeners (useful for testing)
  int get totalListenerCount {
    int count = 0;
    for (final listeners in _changeListeners.values) {
      count += listeners.length;
    }
    return count;
  }
}
