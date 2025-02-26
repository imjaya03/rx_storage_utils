import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// # StorageUtil
///
/// A utility class that simplifies persistent data storage in Flutter applications.
/// Provides methods for storing, retrieving, and managing data with optional encryption.
///
/// ## Key Features:
///
/// * Easy data persistence with type safety
/// * Automatic real-time synchronization with reactive (Rx) variables
/// * Support for both individual values and lists of objects
/// * Optional data encryption for sensitive information
/// * Expiration support for temporary data storage
///
/// ## Basic Usage Examples:
///
/// ```dart
/// // Store a simple value
/// await StorageUtil().setValue('username', 'john_doe');
///
/// // Retrieve a simple value
/// String? username = await StorageUtil().getValue<String>('username');
///
/// // Store an object
/// await StorageUtil().writeToStorage('user', userModel.toJson());
///
/// // Link a reactive variable to persistent storage (auto-sync)
/// await StorageUtil().initializeStorageWithListener(
///   key: 'user_profile',
///   rxValue: userProfileRx,
///   fromJson: UserProfile.fromJson,
///   toJson: (profile) => profile.toJson(),
/// );
/// ```
class StorageUtils {
  //--------------------------------------------------------------------------
  // SINGLETON PATTERN IMPLEMENTATION
  //--------------------------------------------------------------------------

  /// Private constructor
  StorageUtils._internal();

  /// Singleton instance
  static final StorageUtils _instance = StorageUtils._internal();

  /// Factory constructor that returns the singleton instance
  factory StorageUtils() => _instance;

  //--------------------------------------------------------------------------
  // PROPERTIES
  //--------------------------------------------------------------------------

  /// The underlying storage instance
  GetStorage? _storage;

  /// Whether to show debug logs (default: true in debug mode, false in release)
  bool _enableLogging = kDebugMode;

  /// Whether to encrypt stored data (default: true)
  bool _enableEncryption = !kDebugMode;

  /// Encryption key when encryption is enabled (auto-generated based on app package)
  String _encryptionKey = '<WRITE_YOUR_KEY>';

  /// Indicates if auto-configuration has completed
  bool _autoConfigured = false;

  /// Indicates if storage has been initialized
  static bool _isInitialized = false;

  /// Lock for thread-safe initialization
  static final _initLock = Object();

  /// Initialization in progress flag
  static bool _initializationInProgress = false;

  //--------------------------------------------------------------------------
  // INITIALIZATION & CONFIGURATION
  //--------------------------------------------------------------------------

  /// Initialize the storage system
  /// This should be called from main.dart before runApp() or during app bootstrap
  ///
  /// Example:
  /// ```dart
  /// Future<void> main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await StorageUtil.init();
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> init({
    bool enableLogging = kDebugMode,
    bool enableEncryption = !kDebugMode,
    String? customEncryptionKey,
  }) async {
    // Fast return if already initialized
    if (_isInitialized) return;

    // Use lock to prevent multiple simultaneous initializations
    synchronized() async {
      // Double-check pattern
      if (_isInitialized) return;

      // Set flag to indicate initialization is in progress
      if (_initializationInProgress) {
        // Wait for initialization to complete if another thread is already doing it
        while (_initializationInProgress) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        return;
      }

      _initializationInProgress = true;

      try {
        // Initialize GetStorage
        await GetStorage.init();

        // Initialize the singleton instance
        final instance = StorageUtils();

        // Configure with provided settings
        instance._enableLogging = enableLogging;
        instance._enableEncryption = enableEncryption;

        if (customEncryptionKey != null && customEncryptionKey.isNotEmpty) {
          instance._encryptionKey = customEncryptionKey;
        }

        // Initialize storage only if not already initialized
        instance._storage ??= GetStorage();

        // Auto-configure securely to generate default encryption key if needed
        await instance._autoConfigureSecurely();

        _isInitialized = true;
        instance._log('📦 StorageUtil initialized successfully');
      } catch (e) {
        print('⚠️ Error initializing StorageUtil: $e');
        rethrow; // Propagate error to caller since this is a critical initialization
      } finally {
        _initializationInProgress = false;
      }
    }

    // Execute the synchronized function
    await synchronized();
  }

  /// Internal method to initialize storage on first use if not explicitly initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      print(
          '⚠️ StorageUtil.init() was not called before usage. Auto-initializing with default settings.');
      await init();
    }
  }

  /// Initialize the storage system (legacy method, use static init() instead)
  @Deprecated('Use static StorageUtil.init() method instead')
  Future<void> _initStorage() async {
    try {
      await _ensureInitialized();
    } catch (e) {
      _log('⚠️ Error initializing storage: $e', isError: true);
    }
  }

  /// Automatically configure storage with secure defaults
  /// This generates an encryption key based on the app's package info
  Future<void> _autoConfigureSecurely() async {
    if (_autoConfigured) return;

    try {
      // Only generate encryption key if not custom provided
      if (_encryptionKey == '<WRITE_YOUR_KEY>') {
        // Get app package info for generating a unique encryption key
        final packageInfo = await PackageInfo.fromPlatform();
        final appId = packageInfo.packageName;
        final appVersion = packageInfo.version;
        final buildNumber = packageInfo.buildNumber;

        // Create a reasonably secure default encryption key based on app identity
        final baseKey =
            '$appId-$appVersion-$buildNumber-PiTaskWatchSecureStorage';
        final keyBytes = utf8.encode(baseKey);
        final digest = sha256.convert(keyBytes);
        _encryptionKey = digest.toString();

        _log('🔐 Generated secure app-specific encryption key');
      }

      _autoConfigured = true;
      _log(
          '🔐 Auto-configured securely: logging=$_enableLogging, encryption=$_enableEncryption');
    } catch (e) {
      _log('⚠️ Auto-configuration failed: $e. Using fallback configuration.',
          isError: true);

      // Fallback to basic configuration
      _enableLogging = kDebugMode;
      _enableEncryption = false;
      _encryptionKey = '';
    }
  }

  /// Ensure auto-configuration has completed
  /// This is called internally before any storage operation
  Future<void> _ensureConfigured() async {
    await _ensureInitialized();
    if (!_autoConfigured) {
      await _autoConfigureSecurely();
    }
  }

  /// Get the storage instance safely
  GetStorage get storage {
    if (_storage == null) {
      throw StateError(
          'Storage not initialized. Call StorageUtil.init() before using storage.');
    }
    return _storage!;
  }

  //--------------------------------------------------------------------------
  // BASIC STORAGE OPERATIONS
  //--------------------------------------------------------------------------

  /// Read data from storage by key
  ///
  /// * [key]: The identifier to retrieve the data
  /// * Returns: The stored data, or null if not found
  Future<dynamic> readFromStorage(String key) async {
    await _ensureConfigured();

    try {
      final value = await storage.read(key);
      if (value == null) return null;

      // Handle decryption if needed
      if (_enableEncryption &&
          value is String &&
          value.startsWith('ENCRYPTED:')) {
        final decrypted =
            _decrypt(value.substring(10)); // Remove the 'ENCRYPTED:' prefix

        // Try to parse as JSON if it's a string that looks like JSON
        if ((decrypted.startsWith('{') || decrypted.startsWith('['))) {
          try {
            return json.decode(decrypted);
          } catch (_) {
            // If parsing fails, return the raw decrypted string
            return decrypted;
          }
        }
        return decrypted;
      }

      // For non-encrypted values, also try to parse JSON strings
      if (value is String && (value.startsWith('{') || value.startsWith('['))) {
        try {
          return json.decode(value);
        } catch (_) {
          // If parsing fails, return the raw string
          return value;
        }
      }

      return value;
    } catch (e) {
      _log('⚠️ Error reading from storage: $e', isError: true);
      return null;
    }
  }

  /// Write data to storage with key
  ///
  /// * [key]: The identifier for storing the data
  /// * [data]: The data to store
  Future<void> writeToStorage(String key, dynamic data) async {
    await _ensureConfigured();

    try {
      // Handle encryption if needed
      final valueToStore = (_enableEncryption && data != null)
          ? 'ENCRYPTED:${_encrypt(data is String ? data : json.encode(data))}'
          : data;

      await storage.write(key, valueToStore);
      _log('📝 Saved data: key=$key');
    } catch (e) {
      _log('⚠️ Error writing to storage: $e', isError: true);
    }
  }

  /// Delete a value from storage
  ///
  /// * [key]: The identifier of the data to remove
  Future<void> removeFromStorage(String key) async {
    try {
      await storage.remove(key);
      _log('🗑️ Removed data: key=$key');
    } catch (e) {
      _log('⚠️ Error removing from storage: $e', isError: true);
    }
  }

  /// Clear all stored data
  Future<void> clearStorage() async {
    try {
      await storage.erase();
      _log('🧹 Cleared all storage data');
    } catch (e) {
      _log('⚠️ Error clearing storage: $e', isError: true);
    }
  }

  //--------------------------------------------------------------------------
  // REACTIVE STORAGE METHODS (AUTO-SYNC WITH RX VARIABLES)
  //--------------------------------------------------------------------------

  /// Link a reactive variable to persistent storage with automatic synchronization
  ///
  /// This creates a two-way binding where:
  /// * When the app starts, the stored value is loaded into the reactive variable
  /// * When the reactive variable changes, storage is automatically updated
  ///
  /// Parameters:
  /// * [key]: Storage key
  /// * [rxValue]: Reactive variable to link with storage
  /// * [fromJson]: Function to convert storage data to object type
  /// * [toJson]: Function to convert object to storable format
  /// * [onInitialValue]: Optional callback when initial value is loaded
  Future<void> initializeStorageWithListener<T>({
    required String key,
    required Rx<T?> rxValue,
    required T Function(dynamic) fromJson,
    required dynamic Function(T) toJson,
    Function(T initialValue)? onInitialValue,
  }) async {
    await _ensureConfigured();

    try {
      // STEP 1: Load existing data from storage (if any)
      final storedData = await readFromStorage(key);
      if (storedData != null) {
        // Convert data to the correct type and update the Rx variable
        T initialValue;

        try {
          initialValue = fromJson(storedData);
        } catch (e) {
          _log('⚠️ Error converting stored data: $e. Using safe approach.',
              isError: true);

          // Try alternate approaches if direct conversion fails
          if (storedData is String) {
            try {
              // Try parsing as JSON if it's a string
              final jsonData = json.decode(storedData);
              initialValue = fromJson(jsonData);
            } catch (_) {
              // If specific conversions fail, use a more generic approach
              throw Exception(
                  'Cannot convert stored data to required type: ${T.toString()}');
            }
          } else {
            throw Exception(
                'Cannot convert stored data to required type: ${T.toString()}');
          }
        }

        rxValue.value = initialValue;

        // Notify via callback if provided
        if (onInitialValue != null) {
          onInitialValue(initialValue);
        }

        _log('🔄 Loaded initial value from storage: key=$key');
      }

      // STEP 2: Set up auto-sync from Rx variable to storage
      ever(
        rxValue,
        (dynamic value) async {
          if (value != null) {
            try {
              // When Rx value changes, save to storage
              dynamic jsonData = toJson(value as T);
              await writeToStorage(key, jsonData);
              _log('🔄 Auto-saved value to storage: key=$key');
            } catch (e) {
              _log('⚠️ Error saving value to storage: $e', isError: true);
            }
          } else {
            // When Rx value is null, remove from storage
            await removeFromStorage(key);
            _log('🔄 Auto-removed value from storage: key=$key');
          }
        },
      );

      _log('🔄 Auto-sync enabled for: key=$key');
    } catch (e) {
      _log('⚠️ Error setting up auto-sync: $e', isError: true);
    }
  }

  /// Link a reactive list to persistent storage with automatic synchronization
  ///
  /// This creates a two-way binding where:
  /// * When the app starts, stored list items are loaded into the reactive list
  /// * When the reactive list changes, storage is automatically updated
  ///
  /// Parameters:
  /// * [key]: Storage key
  /// * [rxList]: Reactive list to link with storage
  /// * [fromJson]: Function to convert storage data to list item type
  /// * [toJson]: Function to convert list item to storable format
  /// * [onInitialValue]: Optional callback when initial list is loaded
  Future<void> initializeListStorageWithListener<T>({
    required String key,
    required RxList<T> rxList,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    Function(List<T> initialList)? onInitialValue,
  }) async {
    await _ensureConfigured();

    try {
      // STEP 1: Load existing list from storage (if any)
      final storedData = await readFromStorage(key);

      if (storedData != null) {
        List<T> loadedList = [];

        // Handle different types of stored data
        if (storedData is List) {
          loadedList = storedData.map((item) {
            // Make sure each item is a Map before conversion
            if (item is Map<String, dynamic>) {
              return fromJson(item);
            } else if (item is String) {
              // Try to parse string items as JSON
              try {
                final Map<String, dynamic> jsonMap = json.decode(item);
                return fromJson(jsonMap);
              } catch (_) {
                _log('⚠️ Could not parse list item as JSON: $item',
                    isError: true);
                throw Exception('Invalid list item format');
              }
            } else {
              _log('⚠️ Invalid list item type: ${item.runtimeType}',
                  isError: true);
              throw Exception('Invalid list item type');
            }
          }).toList();
        } else if (storedData is String) {
          // Try to parse the entire string as a JSON array
          try {
            final List<dynamic> jsonList = json.decode(storedData);
            loadedList = jsonList.map((item) {
              if (item is Map<String, dynamic>) {
                return fromJson(item);
              } else {
                throw Exception('Invalid item type in JSON list');
              }
            }).toList();
          } catch (e) {
            _log('⚠️ Could not parse stored data as JSON list: $e',
                isError: true);
            throw Exception('Invalid list format in storage');
          }
        }

        // Update the list and notify
        if (loadedList.isNotEmpty) {
          rxList.assignAll(loadedList);

          if (onInitialValue != null) {
            onInitialValue(loadedList);
          }

          _log('🔄 Loaded ${loadedList.length} items from storage: key=$key');
        }
      }

      // STEP 2: Set up auto-sync from Rx list to storage
      ever(
        rxList,
        (List<T> list) async {
          try {
            if (list.isNotEmpty) {
              // When list has items, save to storage
              final List<Map<String, dynamic>> jsonList =
                  list.map((item) => toJson(item)).toList();
              await writeToStorage(key, jsonList);
              _log('🔄 Auto-saved ${list.length} items to storage: key=$key');
            } else {
              // When list is empty, remove from storage
              await removeFromStorage(key);
              _log('🔄 Auto-removed empty list from storage: key=$key');
            }
          } catch (e) {
            _log('⚠️ Error in list auto-sync: $e', isError: true);
          }
        },
      );

      _log('🔄 Auto-sync enabled for list: key=$key');
    } catch (e) {
      _log('⚠️ Error setting up list auto-sync: $e', isError: true);
    }
  }

  //--------------------------------------------------------------------------
  // LIST OPERATIONS (MANUAL METHODS)
  //--------------------------------------------------------------------------

  /// Save a list of objects to storage
  ///
  /// * [key]: Storage key for the list
  /// * [list]: List of items to save
  /// * [toJson]: Function to convert each item to JSON format
  Future<void> saveList<T>({
    required String key,
    required List<T> list,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    await _ensureConfigured();

    try {
      if (list.isEmpty) {
        await removeFromStorage(key);
        _log('📝 Saved empty list (removed): key=$key');
        return;
      }

      final List<Map<String, dynamic>> jsonList =
          list.map((item) => toJson(item)).toList();
      await writeToStorage(key, jsonList);
      _log('📝 Saved list with ${list.length} items: key=$key');
    } catch (e) {
      _log('⚠️ Error saving list: $e', isError: true);
    }
  }

  /// Load a list of objects from storage
  ///
  /// * [key]: Storage key for the list
  /// * [fromJson]: Function to convert JSON to item type
  /// * Returns: List of items (empty list if not found)
  Future<List<T>> loadList<T>({
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final storedData = await readFromStorage(key);
      if (storedData != null && storedData is List) {
        final list = storedData
            .map((item) => fromJson(item as Map<String, dynamic>))
            .toList();
        _log('📋 Loaded list with ${list.length} items: key=$key');
        return list;
      }
    } catch (e) {
      _log('⚠️ Error loading list: $e', isError: true);
    }
    return [];
  }

  /// Add an item to a stored list
  ///
  /// * [key]: Storage key for the list
  /// * [item]: Item to add
  /// * [fromJson]/[toJson]: Conversion functions
  /// * Returns: true if successful
  Future<bool> addItemToList<T>({
    required String key,
    required T item,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      existingList.add(item);
      await saveList(key: key, list: existingList, toJson: toJson);
      _log('➕ Added item to list (now ${existingList.length} items): key=$key');
      return true;
    } catch (e) {
      _log('⚠️ Error adding item to list: $e', isError: true);
      return false;
    }
  }

  /// Remove an item from a stored list by index
  ///
  /// * [key]: Storage key for the list
  /// * [index]: Position to remove (0-based)
  /// * [fromJson]/[toJson]: Conversion functions
  /// * Returns: true if successful
  Future<bool> removeItemFromList<T>({
    required String key,
    required int index,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      if (index >= 0 && index < existingList.length) {
        existingList.removeAt(index);
        await saveList(key: key, list: existingList, toJson: toJson);
        _log('➖ Removed item at index $index from list: key=$key');
        return true;
      } else {
        _log(
            '⚠️ Invalid index $index for list with ${existingList.length} items: key=$key',
            isError: true);
        return false;
      }
    } catch (e) {
      _log('⚠️ Error removing item from list: $e', isError: true);
      return false;
    }
  }

  /// Update an item in a stored list by index
  ///
  /// * [key]: Storage key for the list
  /// * [index]: Position to update (0-based)
  /// * [updatedItem]: New item value
  /// * [fromJson]/[toJson]: Conversion functions
  /// * Returns: true if successful
  Future<bool> updateItemInList<T>({
    required String key,
    required int index,
    required T updatedItem,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    try {
      List<T> existingList = await loadList(key: key, fromJson: fromJson);
      if (index >= 0 && index < existingList.length) {
        existingList[index] = updatedItem;
        await saveList(key: key, list: existingList, toJson: toJson);
        _log('✏️ Updated item at index $index in list: key=$key');
        return true;
      } else {
        _log(
            '⚠️ Invalid index $index for list with ${existingList.length} items: key=$key',
            isError: true);
        return false;
      }
    } catch (e) {
      _log('⚠️ Error updating item in list: $e', isError: true);
      return false;
    }
  }

  //--------------------------------------------------------------------------
  // SIMPLE TYPE-SAFE CONVENIENCE METHODS
  //--------------------------------------------------------------------------

  /// Store a simple value (String, int, double, bool)
  ///
  /// * [key]: Storage key
  /// * [value]: Value to store
  Future<void> setValue<T>(String key, T value) async {
    await _ensureConfigured();
    await writeToStorage(key, value);
  }

  /// Get a simple value with type safety
  ///
  /// * [key]: Storage key
  /// * Returns: Value of type T, or null if not found
  Future<T?> getValue<T>(String key) async {
    final value = await readFromStorage(key);
    if (value == null) return null;
    if (value is T) return value;

    _log('⚠️ Type mismatch for key $key: expected $T, got ${value.runtimeType}',
        isError: true);
    return null;
  }

  /// Check if a key exists in storage
  Future<bool> hasKey(String key) async {
    return storage.hasData(key);
  }

  /// Store a value with an expiration time
  Future<void> setValueWithExpiration<T>(
      String key, T value, Duration expiration) async {
    final expirationTime =
        DateTime.now().add(expiration).millisecondsSinceEpoch;
    await writeToStorage('${key}_expiration', expirationTime);
    await setValue(key, value);
    _log(
        '⏱️ Stored value with ${expiration.inMinutes} minute expiration: key=$key');
  }

  /// Get a value, respecting expiration if set
  ///
  /// Returns null if the value has expired
  Future<T?> getValueWithExpiration<T>(String key) async {
    final expirationKey = '${key}_expiration';
    if (storage.hasData(expirationKey)) {
      final expirationTime = await getValue<int>(expirationKey);
      if (expirationTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > expirationTime) {
          // Value has expired, remove both value and expiration
          await removeFromStorage(key);
          await removeFromStorage(expirationKey);
          _log('⏱️ Value expired: key=$key');
          return null;
        }
      }
    }
    return await getValue<T>(key);
  }

  //--------------------------------------------------------------------------
  // MANUAL SYNC METHODS
  //--------------------------------------------------------------------------

  /// Manually sync an Rx value to storage
  ///
  /// Useful for forcing an immediate update
  Future<void> syncRxValueToStorage<T>({
    required String key,
    required T value,
    required dynamic Function(T) toJson,
  }) async {
    try {
      if (value != null) {
        await writeToStorage(key, toJson(value));
        _log('🔄 Manually synced value to storage: key=$key');
      } else {
        await removeFromStorage(key);
        _log('🔄 Manually removed value from storage: key=$key');
      }
    } catch (e) {
      _log('⚠️ Error in manual sync: $e', isError: true);
    }
  }

  /// Manually sync an RxList to storage
  ///
  /// Useful for forcing an immediate update
  Future<void> syncRxListToStorage<T>({
    required String key,
    required List<T> list,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    try {
      if (list.isNotEmpty) {
        final List<Map<String, dynamic>> jsonList =
            list.map((item) => toJson(item)).toList();
        await writeToStorage(key, jsonList);
        _log('🔄 Manually synced list with ${list.length} items: key=$key');
      } else {
        await removeFromStorage(key);
        _log('🔄 Manually removed empty list from storage: key=$key');
      }
    } catch (e) {
      _log('⚠️ Error in manual list sync: $e', isError: true);
    }
  }

  //--------------------------------------------------------------------------
  // DEBUGGING & INSPECTION
  //--------------------------------------------------------------------------

  /// Print all stored values for debugging purposes
  ///
  /// This method retrieves and prints all key-value pairs from storage
  /// Useful for debugging and initial app state inspection
  Future<void> printAllStoredValues() async {
    await _ensureConfigured();

    try {
      // Get all keys from storage
      final keys = storage.getKeys();

      if (keys.isEmpty) {
        _log('📦 Storage is empty. No values to print.');
        return;
      }

      _log('📦 Storage contains ${keys.length} keys:');
      _log('======================================');

      // Print each key-value pair
      for (final key in keys) {
        // Skip expiration keys for cleaner output
        if (key.endsWith('_expiration')) continue;

        var value = await readFromStorage(key);
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
      _log('⚠️ Error printing storage values: $e', isError: true);
    }
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
      _log('⚠️ Decryption error: $e', isError: true);
      return text;
    }
  }
}
