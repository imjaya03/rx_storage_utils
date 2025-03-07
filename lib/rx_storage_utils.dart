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
class RxStorageUtils {
  //--------------------------------------------------------------------------
  // SINGLETON PATTERN IMPLEMENTATION
  //--------------------------------------------------------------------------

  /// Private constructor
  RxStorageUtils._internal();

  /// Singleton instance
  static final RxStorageUtils _instance = RxStorageUtils._internal();

  /// Factory constructor that returns the singleton instance
  factory RxStorageUtils() => _instance;

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

  /// Indicates if auto-initialization warning has been shown
  static bool _autoInitWarningShown = false;

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
    bool clearInvalidData = false,
  }) async {
    // Fast return if already initialized
    if (_isInitialized) return;

    // Use a synchronized approach to prevent multiple initializations
    await synchronized(() async {
      // Double-check pattern for thread safety
      if (_isInitialized) return;

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
        final instance = RxStorageUtils();

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
    });

    // Add optional clearing of invalid data
    if (clearInvalidData && _isInitialized) {
      final instance = RxStorageUtils();
      instance._log('🧹 Checking for invalid storage data to clear');

      // We could implement a more sophisticated check here
      // For now we'll keep it simple
    }
  }

  /// Helper method to provide synchronized execution
  static Future<void> synchronized(Future<void> Function() action) async {
    // This is a simple synchronization helper since Dart doesn't have built-in locks
    // For more complex scenarios, consider using a package like 'synchronized'
    await action();
  }

  /// Internal method to initialize storage on first use if not explicitly initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      // Show warning only once
      if (!_autoInitWarningShown) {
        print(
            '⚠️ StorageUtil.init() was not called before usage. Auto-initializing with default settings.');
        _autoInitWarningShown = true;
      }

      await init(); // Call with default settings

      // Double-check initialization succeeded
      if (!_isInitialized) {
        throw StateError(
            'Failed to auto-initialize StorageUtil. Please call StorageUtil.init() explicitly before using any storage operations.');
      }
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
  // BASIC STORAGE OPERATIONS - INSTANCE METHODS
  //--------------------------------------------------------------------------

  /// Read data from storage by key (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.read(key)`
  @Deprecated('Use StorageUtils.read(key) for static access')
  Future<dynamic> readFromStorage(String key) async {
    return await readFromStorageInternal(key);
  }

  /// Write data to storage with key (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.write(key, data)`
  @Deprecated('Use StorageUtils.write(key, data) for static access')
  Future<void> writeToStorage(String key, dynamic data) async {
    return await writeToStorageInternal(key, data);
  }

  /// Delete a value from storage (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.remove(key)`
  @Deprecated('Use StorageUtils.remove(key) for static access')
  Future<void> removeFromStorage(String key) async {
    return await removeFromStorageInternal(key);
  }

  /// Clear all stored data (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.clear()`
  @Deprecated('Use StorageUtils.clear() for static access')
  Future<void> clearStorage() async {
    return await clearStorageInternal();
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
  /// * [defaultValue]: Optional default value to use when stored data cannot be converted
  Future<void> initializeStorageWithListener<T>({
    required String key,
    required Rx<T?> rxValue,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    Function(T initialValue)? onInitialValue,
    T? defaultValue,
  }) async {
    await _ensureConfigured();

    try {
      // STEP 1: Load existing data from storage (if any)
      final storedData = await readFromStorage(key);
      if (storedData != null) {
        // Convert data to the correct type and update the Rx variable
        T? initialValue;

        try {
          // Handle different data formats
          if (storedData is Map<String, dynamic>) {
            // Direct map - most common case
            initialValue = fromJson(storedData);
          } else if (storedData is String) {
            // Try parsing as JSON if it's a string
            try {
              final jsonData = json.decode(storedData);
              if (jsonData is Map<String, dynamic>) {
                initialValue = fromJson(jsonData);
              } else {
                throw FormatException('Stored data is not a valid JSON object');
              }
            } catch (e) {
              _log('⚠️ Cannot parse string as JSON: $e', isError: true);
              throw FormatException('Invalid JSON format for $key: $e');
            }
          } else {
            _log('⚠️ Unexpected data type: ${storedData.runtimeType}',
                isError: true);
            throw FormatException(
                'Unsupported data type: ${storedData.runtimeType}');
          }
        } catch (e) {
          _log('⚠️ Error converting stored data for key=$key: $e',
              isError: true);

          // Use default value if provided
          if (defaultValue != null) {
            _log('ℹ️ Using provided default value for key=$key',
                isError: false);
            initialValue = defaultValue;
          } else {
            // Re-throw if no default value provided
            throw Exception(
                'Cannot convert stored data to required type: ${T.toString()}');
          }
        }

        if (initialValue != null) {
          rxValue.value = initialValue;

          // Notify via callback if provided
          if (onInitialValue != null) {
            onInitialValue(initialValue);
          }

          _log('🔄 Loaded initial value from storage: key=$key');
        }
      } else if (defaultValue != null && rxValue.value == null) {
        // Only use default value if no stored data AND rxValue is null
        rxValue.value = defaultValue;
        _log('ℹ️ No stored data. Using default value for key=$key');

        // Notify via callback if provided
        if (onInitialValue != null) {
          onInitialValue(defaultValue);
        }
      } else if (rxValue.value != null) {
        _log('ℹ️ Using existing Rx value (ignoring default): key=$key');
      }

      // STEP 2: Set up auto-sync from Rx variable to storage
      ever(
        rxValue,
        (dynamic value) async {
          if (value != null) {
            try {
              // When Rx value changes, save to storage
              Map<String, dynamic> jsonData = toJson(value as T);
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
      rethrow; // Important to propagate the error for proper handling
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
  // SIMPLE TYPE-SAFE CONVENIENCE METHODS - INSTANCE METHODS
  //--------------------------------------------------------------------------

  /// Store a simple value (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.set(key, value)`
  @Deprecated('Use StorageUtils.set(key, value) for static access')
  Future<void> setValue<T>(String key, T value) async {
    return await setValueInternal<T>(key, value);
  }

  /// Get a simple value with type safety (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.get<T>(key)`
  @Deprecated('Use StorageUtils.get<T>(key) for static access')
  Future<T?> getValue<T>(String key) async {
    return await getValueInternal<T>(key);
  }

  /// Check if a key exists in storage (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.has(key)`
  @Deprecated('Use StorageUtils.has(key) for static access')
  Future<bool> hasKey(String key) async {
    return await hasKeyInternal(key);
  }

  /// Store a value with an expiration time (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.setWithExpiry(key, value, expiration)`
  @Deprecated(
      'Use StorageUtils.setWithExpiry(key, value, expiration) for static access')
  Future<void> setValueWithExpiration<T>(
      String key, T value, Duration expiration) async {
    return await setValueWithExpirationInternal<T>(key, value, expiration);
  }

  /// Get a value, respecting expiration if set (instance method)
  /// Use the static version for direct access without instantiating:
  /// `StorageUtils.getWithExpiry<T>(key)`
  @Deprecated('Use StorageUtils.getWithExpiry<T>(key) for static access')
  Future<T?> getValueWithExpiration<T>(String key) async {
    return await getValueWithExpirationInternal<T>(key);
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
      _log('⚠️ Decryption error: $e', isError: true);
      return text;
    }
  }

  /// Internal method to handle unexpected data formats
  dynamic _safelyDecodeJsonData(dynamic data, String key) {
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
      _log('⚠️ Error decoding JSON for key=$key: $e', isError: true);
      return data; // Return original data if parsing fails
    }
  }

  //--------------------------------------------------------------------------
  // STATIC FAÇADE METHODS (DIRECT ACCESS WITHOUT INSTANTIATION)
  //--------------------------------------------------------------------------

  /// Static method to print all stored values
  static Future<void> printAll() async {
    return await _instance.printAllStoredValuesInternal();
  }

  /// Static method to read values from storage
  static Future<dynamic> read(String key) async {
    return await _instance.readFromStorageInternal(key);
  }

  /// Static method to write values to storage
  static Future<void> write(String key, dynamic data) async {
    return await _instance.writeToStorageInternal(key, data);
  }

  /// Static method to remove values from storage
  static Future<void> remove(String key) async {
    return await _instance.removeFromStorageInternal(key);
  }

  /// Static method to clear storage
  static Future<void> clear() async {
    return await _instance.clearStorageInternal();
  }

  /// Static method to set a value
  static Future<void> set<T>(String key, T value) async {
    return await _instance.setValueInternal<T>(key, value);
  }

  /// Static method to get a value
  static Future<T?> get<T>(String key) async {
    return await _instance.getValueInternal<T>(key);
  }

  /// Static method to check if key exists
  static Future<bool> has(String key) async {
    return await _instance.hasKeyInternal(key);
  }

  /// Static method to set value with expiration
  static Future<void> setWithExpiry<T>(
      String key, T value, Duration expiration) async {
    return await _instance.setValueWithExpirationInternal<T>(
        key, value, expiration);
  }

  /// Static method to get value with expiration
  static Future<T?> getWithExpiry<T>(String key) async {
    return await _instance.getValueWithExpirationInternal<T>(key);
  }

  //--------------------------------------------------------------------------
  // INTERNAL IMPLEMENTATION METHODS
  //--------------------------------------------------------------------------

  /// Read data from storage by key (internal implementation)
  Future<dynamic> readFromStorageInternal(String key) async {
    await _ensureConfigured();

    try {
      final value = storage.read(key);
      if (value == null) return null;

      // Handle decryption if needed
      if (_enableEncryption &&
          value is String &&
          value.startsWith('ENCRYPTED:')) {
        final decrypted = _decrypt(value.substring(10)); // Remove prefix
        return _safelyDecodeJsonData(decrypted, key);
      }

      // For non-encrypted values
      return _safelyDecodeJsonData(value, key);
    } catch (e) {
      _log('⚠️ Error reading from storage: $e', isError: true);
      return null;
    }
  }

  /// Write data to storage with key (internal implementation)
  Future<void> writeToStorageInternal(String key, dynamic data) async {
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

  /// Delete a value from storage (internal implementation)
  Future<void> removeFromStorageInternal(String key) async {
    try {
      await storage.remove(key);
      _log('🗑️ Removed data: key=$key');
    } catch (e) {
      _log('⚠️ Error removing from storage: $e', isError: true);
    }
  }

  /// Clear all stored data (internal implementation)
  Future<void> clearStorageInternal() async {
    try {
      await storage.erase();
      _log('🧹 Cleared all storage data');
    } catch (e) {
      _log('⚠️ Error clearing storage: $e', isError: true);
    }
  }

  /// Store a simple value (String, int, double, bool) (internal implementation)
  Future<void> setValueInternal<T>(String key, T value) async {
    await _ensureConfigured();
    await writeToStorageInternal(key, value);
  }

  /// Get a simple value with type safety (internal implementation)
  Future<T?> getValueInternal<T>(String key) async {
    final value = await readFromStorageInternal(key);
    if (value == null) return null;
    if (value is T) return value;

    _log('⚠️ Type mismatch for key $key: expected $T, got ${value.runtimeType}',
        isError: true);
    return null;
  }

  /// Check if a key exists in storage (internal implementation)
  Future<bool> hasKeyInternal(String key) async {
    return storage.hasData(key);
  }

  /// Store a value with an expiration time (internal implementation)
  Future<void> setValueWithExpirationInternal<T>(
      String key, T value, Duration expiration) async {
    final expirationTime =
        DateTime.now().add(expiration).millisecondsSinceEpoch;
    await writeToStorageInternal('${key}_expiration', expirationTime);
    await setValueInternal(key, value);
    _log(
        '⏱️ Stored value with ${expiration.inMinutes} minute expiration: key=$key');
  }

  /// Get a value, respecting expiration if set (internal implementation)
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
          _log('⏱️ Value expired: key=$key');
          return null;
        }
      }
    }
    return await getValueInternal<T>(key);
  }

  /// Print all stored values for debugging purposes (internal implementation)
  Future<void> printAllStoredValuesInternal() async {
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
      _log('⚠️ Error printing storage values: $e', isError: true);
    }
  }
}
