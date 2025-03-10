import 'dart:collection';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger/logger.dart';

/// Utility class for managing persistent storage with reactive state
class RxStorageUtils {
  static final _logger = Logger();
  static final _storage = GetStorage();

  // Update lock to prevent infinite update loops
  static final Map<String, bool> _updateLocks = HashMap<String, bool>();

  // Optional debug mode to trace storage operations
  static bool _debugMode = false;

  // Track operation timing for performance analysis
  static bool _trackTiming = false;

  /// Enable or disable debug logging
  static void setDebugMode(bool enabled, {bool trackTiming = false}) {
    _debugMode = enabled;
    _trackTiming = trackTiming;
    _log(
        "Debug mode ${enabled ? 'enabled' : 'disabled'}, timing tracking ${trackTiming ? 'enabled' : 'disabled'}");
  }

  /// Initialize GetStorage at app startup
  static Future<void> initStorage() async {
    final stopwatch = Stopwatch()..start();
    _log("Storage initialization started");

    await GetStorage.init();

    stopwatch.stop();
    _log(
        "Storage initialization completed in ${stopwatch.elapsedMilliseconds}ms");
  }

  /// Initializes a reactive value with persistent storage
  ///
  /// [key]: Storage key for the data
  /// [rxValue]: Reactive value to be synced with storage
  /// [onUpdate]: Called when the value changes
  /// [onInitialLoadFromDb]: Called when a value is initially loaded from storage
  /// [toRawData]: Converts the typed value to storable format
  /// [fromRawData]: Converts stored data back to typed format
  /// [autoSync]: Whether to automatically sync changes to storage
  ///
  /// Example:
  /// ```dart
  /// final RxString name = RxString('');
  /// StorageUtil.bindReactiveValue<String>(
  ///   key: 'username',
  ///   rxValue: name,
  ///   onUpdate: (data) => print('Updated: $data'),
  ///   onInitialLoadFromDb: (data) => print('Loaded: $data'),
  ///   toRawData: (data) => data,
  ///   fromRawData: (data) => data.toString(),
  /// );
  /// ```
  static Future<void> bindReactiveValue<T>({
    required String key,
    required Rx<T> rxValue,
    required Function(T? data) onUpdate,
    required Function(T? data) onInitialLoadFromDb,
    required dynamic Function(T data) toRawData,
    required T Function(dynamic data) fromRawData,
    bool autoSync = true,
  }) async {
    final stopwatch = _trackTiming ? (Stopwatch()..start()) : null;
    _log("START bindReactiveValue for key '$key'");

    try {
      // Check if key exists, if not initialize with null
      if (!_storage.hasData(key)) {
        _log("Key '$key' does not exist, initializing with null");
        await _storage.write(key, jsonEncode({'data': null}));
      } else {
        _log("Key '$key' exists in storage");
      }

      // Read data without type constraint
      final dynamic rawData = _storage.read(key);
      _log("Reading value for key '$key': $rawData");

      if (rawData != null) {
        try {
          _log("Extracting data for key '$key'");
          // Handle both string and map formats for backward compatibility
          final dynamic decodedData = _safelyExtractData(rawData);
          _log("Decoded data for key '$key': $decodedData");

          if (decodedData != null) {
            _log("Converting data from raw format for key '$key'");
            final typedData = fromRawData(decodedData);
            _log("Data converted to typed format for key '$key': $typedData");

            // Set lock before updating reactive value to prevent loops
            _log("Setting update lock for key '$key'");
            _updateLocks[key] = true;

            if (autoSync) {
              // Only update if value is different to prevent needless notifications
              if (_isDifferent(rxValue.value, typedData)) {
                _log("Updating rxValue for key '$key' (values differ)");
                rxValue.value = typedData;
              } else {
                _log(
                    "Skipping rxValue update for key '$key' (values identical)");
              }
            } else {
              _log("Auto sync disabled for key '$key'");
            }

            // Release lock after update
            _log("Releasing update lock for key '$key'");
            _updateLocks[key] = false;

            // Notify on initial load from database
            _log("Calling onInitialLoadFromDb for key '$key'");
            onInitialLoadFromDb(typedData);
            _log("onInitialLoadFromDb completed for key '$key'");
          } else {
            _log("Data for key '$key' is null after extraction");
            onInitialLoadFromDb(null);
          }
        } catch (e) {
          _logger.e('Error loading data from storage for key "$key": $e');
          // Reset the storage for this key
          await _storage.write(key, jsonEncode({'data': null}));
          onInitialLoadFromDb(null);
        }
      } else {
        _log("No value found for key '$key'");
        onInitialLoadFromDb(null);
      }

      // Set up reactive listener with lock protection
      _log("Setting up reactive listener for key '$key'");
      rxValue.listen(
        (data) async {
          _log("Rx value changed for key '$key': $data");

          // Skip update if lock is active (we're updating from storage)
          if (_updateLocks[key] == true) {
            _log("Skipping update for locked key '$key'");
            return;
          }

          try {
            // Set lock to prevent recursive updates
            _log("Setting update lock for key '$key' during listener update");
            _updateLocks[key] = true;

            _log("Converting data to raw format for key '$key'");
            final rawData = toRawData(data);

            // Check if data has actually changed in storage
            final currentRawData = _storage.read(key);
            final currentData = currentRawData != null
                ? _safelyExtractData(currentRawData)
                : null;
            _log("Current data in storage for key '$key': $currentData");

            // Only write to storage if the data is different
            if (_isDifferent(currentData, rawData)) {
              _log("Writing updated data to storage for key '$key'");
              await _storage.write(key, jsonEncode({'data': rawData}));
              _log("Storage write completed for key '$key'");

              _log("Calling onUpdate for key '$key'");
              onUpdate(data);
              _log("onUpdate completed for key '$key'");
            } else {
              _log("Skipping storage update for key '$key' (no changes)");
            }
          } catch (e) {
            _logger.e("Failed to update storage for key '$key': $e");
          } finally {
            // Always release the lock
            _log("Releasing update lock for key '$key'");
            _updateLocks[key] = false;
          }
        },
      );
      _log("Reactive listener setup completed for key '$key'");

      if (stopwatch != null) {
        stopwatch.stop();
        _log(
            "COMPLETE bindReactiveValue for key '$key' in ${stopwatch.elapsedMilliseconds}ms");
      }
    } catch (e) {
      _logger.e("Storage initialization error for key '$key': $e");
      onInitialLoadFromDb(null);
      if (stopwatch != null) {
        stopwatch.stop();
        _log(
            "FAILED bindReactiveValue for key '$key' in ${stopwatch.elapsedMilliseconds}ms: $e");
      }
    }
  }

  /// Initializes a reactive list with persistent storage
  ///
  /// [key]: Storage key for the list data
  /// [rxList]: Reactive list to be synced with storage
  /// [onUpdate]: Called when the list changes
  /// [onInitialLoadFromDb]: Called when a list is initially loaded from storage
  /// [itemToRawData]: Converts each list item to storable format
  /// [itemFromRawData]: Converts stored data back to typed list items
  /// [autoSync]: Whether to automatically sync changes to storage
  static Future<void> bindReactiveListValue<T>({
    required String key,
    required RxList<T> rxList,
    required Function(List<T>? data) onUpdate,
    required Function(List<T>? data) onInitialLoadFromDb,
    required dynamic Function(T item) itemToRawData,
    required T Function(dynamic data) itemFromRawData,
    bool autoSync = true,
  }) async {
    final stopwatch = _trackTiming ? (Stopwatch()..start()) : null;
    _log("START bindReactiveListValue for key '$key'");

    try {
      // Check if key exists, if not initialize with empty list
      if (!_storage.hasData(key)) {
        await _storage.write(key, jsonEncode({'data': []}));
      }

      // Read data without type constraint
      final dynamic rawData = _storage.read(key);

      if (rawData != null) {
        try {
          final dynamic decodedData = _safelyExtractData(rawData);

          if (decodedData != null && decodedData is List) {
            final typedList = decodedData
                .map((item) => itemFromRawData(item))
                .toList()
                .cast<T>();

            // Set lock before updating reactive list
            _updateLocks[key] = true;

            if (autoSync) {
              // Only update if list content is different
              if (_isDifferentList(rxList, typedList)) {
                rxList.clear();
                rxList.addAll(typedList);
              }
            }

            // Release lock after update
            _updateLocks[key] = false;

            // Notify once on initial load from database
            onInitialLoadFromDb(typedList);
          } else {
            _logger.w("Data for key '$key' is not a list or is null");
            if (autoSync) {
              rxList.clear();
            }
            onInitialLoadFromDb([]);
          }
        } catch (e) {
          _logger.e('Error loading list data from storage for key "$key": $e');
          await _storage.write(key, jsonEncode({'data': []}));
          onInitialLoadFromDb([]);
        }
      } else {
        _logger.d("No list found for key '$key'");
        onInitialLoadFromDb([]);
      }

      // Set up reactive listener with lock protection
      rxList.listen(
        (data) async {
          // Skip update if lock is active
          if (_updateLocks[key] == true) {
            return;
          }

          try {
            // Set lock to prevent recursive updates
            _updateLocks[key] = true;

            final rawData = data.map((item) => itemToRawData(item)).toList();

            // Check if data has actually changed in storage
            final currentRawData = _storage.read(key);
            final currentData = currentRawData != null
                ? _safelyExtractData(currentRawData)
                : null;

            // Only write if different
            if (currentData == null ||
                !_isEqualListContent(currentData as List, rawData)) {
              await _storage.write(key, jsonEncode({'data': rawData}));
              onUpdate(data);
              _logger.d("Updated list storage for key '$key'");
            }
          } catch (e) {
            _logger.e("Failed to update list storage for key '$key': $e");
          } finally {
            // Always release the lock
            _updateLocks[key] = false;
          }
        },
      );
    } catch (e) {
      _logger.e("List storage initialization error for key '$key': $e");
      onInitialLoadFromDb([]);
    }
  }

  /// Get a value directly from storage without reactive binding
  ///
  /// [key]: Storage key
  /// [fromRawData]: Converter function from stored data to desired type
  /// [defaultValue]: Value to return if key doesn't exist or on error
  static T? getValue<T>({
    required String key,
    required T Function(dynamic data) fromRawData,
    T? defaultValue,
  }) {
    try {
      if (!_storage.hasData(key)) return defaultValue;

      final dynamic rawData = _storage.read(key);
      if (rawData == null) return defaultValue;

      final dynamic decodedData = _safelyExtractData(rawData);
      if (decodedData == null) return defaultValue;

      return fromRawData(decodedData);
    } catch (e) {
      _logger.e("Error getting value for key '$key': $e");
      return defaultValue;
    }
  }

  /// Set a value directly to storage without reactive binding
  ///
  /// [key]: Storage key
  /// [value]: Value to store
  /// [toRawData]: Converter function from value to storable format
  static Future<bool> setValue<T>({
    required String key,
    required T value,
    required dynamic Function(T data) toRawData,
  }) async {
    try {
      final rawData = toRawData(value);

      // Get current data to check if update is needed
      final dynamic currentRawData = _storage.read(key);
      final currentData =
          currentRawData != null ? _safelyExtractData(currentRawData) : null;

      // Only write if different
      if (_isDifferent(currentData, rawData)) {
        await _storage.write(key, jsonEncode({'data': rawData}));
        _logger.d("Set value for key '$key'");
      }
      return true;
    } catch (e) {
      _logger.e("Error setting value for key '$key': $e");
      return false;
    }
  }

  /// Clear a specific key from storage
  static Future<void> clearKey(String key) async {
    try {
      await _storage.remove(key);
      _logger.d("Cleared storage for key '$key'");
    } catch (e) {
      _logger.e("Error clearing key '$key': $e");
    }
  }

  /// Clear all storage data
  static Future<void> clearAll() async {
    try {
      await _storage.erase();
      _logger.d("Cleared all storage data");
    } catch (e) {
      _logger.e("Error clearing all storage: $e");
    }
  }

  /// Check if a key exists in storage
  static bool hasKey(String key) {
    return _storage.hasData(key);
  }

  /// Safely extracts data from either a JSON string or a map
  /// Handles both formats for backward compatibility
  static dynamic _safelyExtractData(dynamic rawValue) {
    try {
      if (rawValue is String) {
        // If it's a string, try to decode it as JSON
        final jsonData = jsonDecode(rawValue);
        return jsonData['data'];
      } else if (rawValue is Map) {
        // If it's already a map, extract the data field
        return rawValue['data'];
      }
      // If it's another type, return as-is (likely to fail later, but best effort)
      return rawValue;
    } catch (e) {
      throw FormatException('Invalid data format: $e');
    }
  }

  /// Determine if two values are different
  /// Used to prevent unnecessary updates
  static bool _isDifferent(dynamic a, dynamic b) {
    if (identical(a, b)) return false;
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;

    if (a is List && b is List) {
      return !_isEqualListContent(a, b);
    }

    if (a is Map && b is Map) {
      return !_isEqualMapContent(a, b);
    }

    return a != b;
  }

  /// Check if two lists have different content
  static bool _isDifferentList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return true;

    for (var i = 0; i < a.length; i++) {
      if (_isDifferent(a[i], b[i])) return true;
    }

    return false;
  }

  /// Check if two lists have equal content
  static bool _isEqualListContent(List a, List b) {
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      if (i >= b.length) return false;
      if (!_isEqual(a[i], b[i])) return false;
    }

    return true;
  }

  /// Check if two maps have equal content
  static bool _isEqualMapContent(Map a, Map b) {
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_isEqual(a[key], b[key])) return false;
    }

    return true;
  }

  /// Deep equality check for nested structures
  static bool _isEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;

    if (a is List && b is List) {
      return _isEqualListContent(a, b);
    }

    if (a is Map && b is Map) {
      return _isEqualMapContent(a, b);
    }

    return a == b;
  }

  /// Helper method for consistent logging
  static void _log(String message) {
    if (_debugMode) {
      _logger.d("📦 STORAGE: $message");
    }
  }
}
