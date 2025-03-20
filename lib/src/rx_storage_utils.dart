import 'dart:async';
import 'dart:convert';
import 'dart:nativewrappers/_internal/vm/lib/mirrors_patch.dart';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger/logger.dart';

/// Data converter for standardizing storage format
class _UserDataConverter {
  /// Wraps data in a standard format before storing
  static Map<String, dynamic> userDataToJson(dynamic data) {
    return {
      "data": data,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Extracts data from standardized format when retrieving
  static dynamic jsonToUserData(Map<String, dynamic> json) {
    return json["data"];
  }
}

/// A utility class for binding GetX reactive types with persistent storage
class RxStorageUtils {
  static final GetStorage _storage = GetStorage();
  static final Logger _logger = Logger();
  static bool _debugMode = false;
  static bool _trackTiming = false;
  static final Map<String, bool> _updateLocks = {};
  static final Map<String, Worker> _workers = {}; // Track workers for unbinding

  /// Initialize the storage system
  static Future<void> initStorage() async {
    await GetStorage.init();
    if (_debugMode) {
      _logger.d('RxStorageUtils: Storage initialized');
    }
  }

  /// Enable or disable debug mode
  static void setDebugMode(bool enabled, {bool trackTiming = false}) {
    _debugMode = enabled;
    _trackTiming = trackTiming;
    if (_debugMode) {
      _logger.d('RxStorageUtils: Debug mode $_debugMode, timing $_trackTiming');
    }
  }

  /// Unbind a reactive value from storage (stops syncing)
  static void unbindReactive(String key) {
    if (_workers.containsKey(key)) {
      _workers[key]?.dispose();
      _workers.remove(key);
      if (_debugMode) {
        _logger.d('RxStorageUtils: Unbound reactive value for key $key');
      }
    }
  }

  /// Store data with standardized format
  static Future<void> _writeToStorage(String key, dynamic rawData) async {
    final wrappedData = _UserDataConverter.userDataToJson(rawData);
    await _storage.write(key, wrappedData);
    if (_debugMode) {
      _logger.d('RxStorageUtils: Stored wrapped data for $key');
    }
  }

  /// Read data and extract from standardized format
  static dynamic _readFromStorage(String key) {
    if (!_storage.hasData(key)) return null;

    final raw = _storage.read(key);
    if (raw == null) return null;

    try {
      if (raw is Map<String, dynamic>) {
        return _UserDataConverter.jsonToUserData(raw);
      } else if (_debugMode) {
        _logger.w(
            'RxStorageUtils: Data for key $key is not in expected format: ${raw.runtimeType}');
        // For backward compatibility, return raw data if not in expected format
        return raw;
      }
      return raw;
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error unwrapping data for $key: $e');
      }
      return raw; // Return raw data as fallback
    }
  }

  /// Bind a reactive value to persistent storage
  static Future<void> bindReactiveValue<T>({
    required String key,
    required Rx<T> rxValue,
    required Function(T? data) onUpdate,
    required Function(T? data) onInitialLoadFromDb,
    required dynamic Function(T data) toRawData,
    required T Function(dynamic data) fromRawData,
    T? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Unbind if already bound to prevent duplicate listeners
    unbindReactive(key);

    if (_debugMode) {
      _logger.d('RxStorageUtils: Binding $key with type $T');
    }

    // Check for existing data
    try {
      if (_storage.hasData(key)) {
        final dynamic rawData = _readFromStorage(key); // Use the wrapper method
        if (_debugMode) {
          _logger.d('RxStorageUtils: Read from storage $key: $rawData');
        }

        // Handle null data from storage
        if (rawData != null) {
          try {
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Attempting to convert raw data for $key using fromRawData');
            }

            final T typedData = fromRawData(rawData);

            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Successfully converted raw data for $key: $typedData');
            }

            // Update reactive value only if it's different
            if (rxValue.value != typedData) {
              if (_debugMode && verboseLogging) {
                _logger.d(
                    'RxStorageUtils: Updating rxValue for $key from ${rxValue.value} to $typedData');
              }
              rxValue.value = typedData;
            } else if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Value unchanged for $key, skipping update');
            }

            // Call the initial load callback with the loaded value
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Calling onInitialLoadFromDb for $key with typedData');
            }
            onInitialLoadFromDb(typedData);
          } catch (e) {
            if (_debugMode) {
              _logger.e('RxStorageUtils: Error parsing data for $key: $e');
              _logger.e(
                  'RxStorageUtils: Raw data that failed conversion: $rawData');
            }
            // If parsing fails but we have a default value, use it
            if (defaultValue != null) {
              if (_debugMode) {
                _logger.d(
                    'RxStorageUtils: Using default value for $key: $defaultValue');
              }
              rxValue.value = defaultValue;
              onInitialLoadFromDb(defaultValue);
              // Store the default value
              final processedData = toRawData(defaultValue);
              await _writeToStorage(
                  key, processedData); // Use the wrapper method
            } else {
              if (_debugMode) {
                _logger.d(
                    'RxStorageUtils: No default value for $key, calling onInitialLoadFromDb with null');
              }
              // Call with null if no default value provided
              onInitialLoadFromDb(null);
            }
            if (onError != null && e is Exception) {
              onError(e);
            }
          }
        } else {
          // Key exists but value is null, handle with default
          if (defaultValue != null) {
            rxValue.value = defaultValue;
            onInitialLoadFromDb(defaultValue);
            final processedData = toRawData(defaultValue);
            await _writeToStorage(key, processedData); // Use the wrapper method
          } else {
            // Call with null if no default is provided
            onInitialLoadFromDb(null);
          }
        }
      } else {
        // Key doesn't exist yet
        if (_debugMode) {
          _logger.d('RxStorageUtils: Key $key not found in storage');
        }

        // Use default value if provided
        if (defaultValue != null) {
          rxValue.value = defaultValue;
          onInitialLoadFromDb(defaultValue);
          final processedData = toRawData(defaultValue);
          await _writeToStorage(key, processedData); // Use the wrapper method
        } else {
          // Call with null when no default value and key doesn't exist
          onInitialLoadFromDb(null);
        }
      }
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error loading initial data for $key: $e');
        _logger.e('RxStorageUtils: Stack trace: ${StackTrace.current}');
      }
      onInitialLoadFromDb(null);
      if (onError != null && e is Exception) {
        onError(e);
      }
    }

    // Listen for changes
    if (autoSync) {
      final worker = ever(rxValue, (T newValue) async {
        // Prevent update loops with lock
        if (_updateLocks[key] == true) {
          return;
        }

        _updateLocks[key] = true;

        // Track timing if enabled
        Stopwatch? stopwatch;
        if (_debugMode && _trackTiming) {
          stopwatch = Stopwatch()..start();
        }

        try {
          final dynamic rawData = toRawData(newValue);
          await _writeToStorage(key, rawData); // Use the wrapper method
          onUpdate(newValue);

          if (_debugMode) {
            _logger.d('RxStorageUtils: Updated $key with value: $newValue');
            if (_trackTiming) {
              stopwatch!.stop();
              _logger.d(
                  'RxStorageUtils: Update operation took ${stopwatch.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_debugMode) {
            _logger.e('RxStorageUtils: Error updating value for $key: $e');
          }
          if (onError != null && e is Exception) {
            onError(e);
          }
        } finally {
          _updateLocks[key] = false;
        }
      });

      // Store worker for possible later unbinding
      _workers[key] = worker;
    }
  }

  /// Bind a reactive value with type inference and simplified conversion
  /// This version uses the type of rxValue to infer T automatically
  static Future<void> bind<T>({
    required String key,
    required Rx<T> rxValue,
    required Function(T? data) onUpdate,
    Function(T? data)? onInitialLoad,
    dynamic Function(T data)? toRawData,
    T Function(dynamic data)? fromRawData,
    T? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Create default converters based on type when not provided
    final actualToRawData = toRawData ?? _createDefaultToRawConverter<T>();
    final actualFromRawData =
        fromRawData ?? _createDefaultFromRawConverter<T>();
    final actualOnInitialLoad = onInitialLoad ?? onUpdate;

    await bindReactiveValue<T>(
      key: key,
      rxValue: rxValue,
      onUpdate: onUpdate,
      onInitialLoadFromDb: actualOnInitialLoad,
      toRawData: actualToRawData,
      fromRawData: actualFromRawData,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
      verboseLogging: verboseLogging,
    );
  }

  /// Bind a reactive list to persistent storage
  static Future<void> bindReactiveListValue<T>({
    required String key,
    required RxList<T> rxList,
    required Function(List<T>? data) onUpdate,
    required Function(List<T>? data) onInitialLoadFromDb,
    required dynamic Function(T item) itemToRawData,
    required T Function(dynamic data) itemFromRawData,
    List<T>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Unbind if already bound to prevent duplicate listeners
    unbindReactive(key);

    if (_debugMode) {
      _logger.d('RxStorageUtils: Binding list $key with type $T');
    }

    // Check for existing data
    try {
      if (_storage.hasData(key)) {
        final dynamic rawData = _readFromStorage(key); // Use the wrapper method
        if (_debugMode && verboseLogging) {
          _logger.d('RxStorageUtils: Read raw list data for $key: $rawData');
        }

        if (rawData != null) {
          try {
            if (rawData is! List && _debugMode) {
              _logger.e(
                  'RxStorageUtils: Data for $key is not a List: ${rawData.runtimeType}');
              throw FormatException('Data is not a List');
            }

            final List<dynamic> rawList = List.from(rawData);
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Processing ${rawList.length} items for $key');
            }

            final List<T> typedList = [];

            // Process items one by one for better error tracking
            for (int i = 0; i < rawList.length; i++) {
              try {
                if (_debugMode && verboseLogging) {
                  _logger.d('RxStorageUtils: Converting item $i for $key');
                }
                T convertedItem = itemFromRawData(rawList[i]);
                typedList.add(convertedItem);
              } catch (e) {
                if (_debugMode) {
                  _logger.e(
                      'RxStorageUtils: Error parsing list item $i for $key: $e');
                  _logger.e('RxStorageUtils: Raw item data: ${rawList[i]}');
                }
                if (onError != null && e is Exception) {
                  onError(e);
                }
                // Skip failed item and continue with the next one
                continue;
              }
            }

            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Successfully converted ${typedList.length} items for $key');
            }

            // Update list content
            rxList.clear();
            rxList.addAll(typedList);

            // Call with parsed data
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Calling onInitialLoadFromDb for $key with ${typedList.length} items');
            }
            onInitialLoadFromDb(typedList);
          } catch (e) {
            if (_debugMode) {
              _logger.e('RxStorageUtils: Error parsing list data for $key: $e');
              _logger.e('RxStorageUtils: Raw data that failed: $rawData');
            }

            // Use default if available
            if (defaultValue != null) {
              rxList.clear();
              rxList.addAll(defaultValue);
              onInitialLoadFromDb(defaultValue);

              // Store default value
              final List<dynamic> rawList =
                  defaultValue.map(itemToRawData).toList();
              await _writeToStorage(key, rawList); // Use the wrapper method
            } else {
              onInitialLoadFromDb(null);
            }
            if (onError != null && e is Exception) {
              onError(e);
            }
          }
        } else {
          // Handle null data
          if (defaultValue != null) {
            rxList.clear();
            rxList.addAll(defaultValue);
            onInitialLoadFromDb(defaultValue);

            // Store default value
            final List<dynamic> rawList =
                defaultValue.map(itemToRawData).toList();
            await _writeToStorage(key, rawList); // Use the wrapper method
          } else {
            onInitialLoadFromDb(null);
          }
        }
      } else {
        // No data exists yet
        if (_debugMode) {
          _logger.d('RxStorageUtils: List key $key not found in storage');
        }

        // Use default if available
        if (defaultValue != null) {
          rxList.clear();
          rxList.addAll(defaultValue);
          onInitialLoadFromDb(defaultValue);

          // Store default value
          final List<dynamic> rawList =
              defaultValue.map(itemToRawData).toList();
          await _writeToStorage(key, rawList); // Use the wrapper method
        } else {
          onInitialLoadFromDb(null);
        }
      }
    } catch (e) {
      if (_debugMode) {
        _logger
            .e('RxStorageUtils: Error loading initial list data for $key: $e');
        _logger.e('RxStorageUtils: Stack trace: ${StackTrace.current}');
      }
      onInitialLoadFromDb(null);
      if (onError != null && e is Exception) {
        onError(e);
      }
    }

    // Listen for changes
    if (autoSync) {
      final worker = ever(rxList, (List<T> newList) async {
        // Prevent update loops
        if (_updateLocks[key] == true) {
          return;
        }

        _updateLocks[key] = true;

        // Track timing if enabled
        Stopwatch? stopwatch;
        if (_debugMode && _trackTiming) {
          stopwatch = Stopwatch()..start();
        }

        try {
          final List<dynamic> rawList = newList.map(itemToRawData).toList();
          await _writeToStorage(key, rawList); // Use the wrapper method
          onUpdate(newList);

          if (_debugMode) {
            _logger.d(
                'RxStorageUtils: Updated list $key with ${newList.length} items');
            if (_trackTiming) {
              stopwatch!.stop();
              _logger.d(
                  'RxStorageUtils: Update operation took ${stopwatch.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_debugMode) {
            _logger.e('RxStorageUtils: Error updating list for $key: $e');
          }
          if (onError != null && e is Exception) {
            onError(e);
          }
        } finally {
          _updateLocks[key] = false;
        }
      });

      // Store worker for possible later unbinding
      _workers[key] = worker;
    }
  }

  /// Bind a list with simplified syntax and type inference
  static Future<void> bindList<T>({
    required String key,
    required RxList<T> rxList,
    required Function(List<T>? data) onUpdate,
    Function(List<T>? data)? onInitialLoad,
    dynamic Function(T item)? itemToRawData,
    T Function(dynamic data)? itemFromRawData,
    List<T>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Create default converters based on type when not provided
    final actualItemToRawData =
        itemToRawData ?? _createDefaultToRawConverter<T>();
    final actualItemFromRawData =
        itemFromRawData ?? _createDefaultFromRawConverter<T>();
    final actualOnInitialLoad = onInitialLoad ?? onUpdate;

    await bindReactiveListValue<T>(
      key: key,
      rxList: rxList,
      onUpdate: onUpdate,
      onInitialLoadFromDb: actualOnInitialLoad,
      itemToRawData: actualItemToRawData,
      itemFromRawData: actualItemFromRawData,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
      verboseLogging: verboseLogging,
    );
  }

  /// Bind a reactive Map to persistent storage
  static Future<void> bindReactiveMapValue<K, V>({
    required String key,
    required RxMap<K, V> rxMap,
    required Function(Map<K, V>? data) onUpdate,
    required Function(Map<K, V>? data) onInitialLoadFromDb,
    required dynamic Function(K key) keyToRawData,
    required dynamic Function(V value) valueToRawData,
    required K Function(dynamic data) keyFromRawData,
    required V Function(dynamic data) valueFromRawData,
    Map<K, V>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Unbind if already bound to prevent duplicate listeners
    unbindReactive(key);

    if (_debugMode) {
      _logger.d('RxStorageUtils: Binding map $key with types K=$K, V=$V');
    }

    // Check for existing data
    try {
      if (_storage.hasData(key)) {
        final dynamic rawData = _readFromStorage(key);
        if (_debugMode && verboseLogging) {
          _logger.d('RxStorageUtils: Read raw map data for $key: $rawData');
        }

        if (rawData != null) {
          try {
            // Verify the data is a map
            if (rawData is! Map && _debugMode) {
              _logger.e(
                  'RxStorageUtils: Data for $key is not a Map: ${rawData.runtimeType}');
              throw FormatException('Data is not a Map');
            }

            final Map<dynamic, dynamic> rawMap = Map.from(rawData);
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Processing ${rawMap.length} entries for $key');
            }

            // Convert keys and values to their proper types
            final Map<K, V> typedMap = {};
            for (var entry in rawMap.entries) {
              try {
                if (_debugMode && verboseLogging) {
                  _logger.d(
                      'RxStorageUtils: Converting map entry ${entry.key} for $key');
                }
                K convertedKey = keyFromRawData(entry.key);
                V convertedValue = valueFromRawData(entry.value);
                typedMap[convertedKey] = convertedValue;
              } catch (e) {
                if (_debugMode) {
                  _logger.e(
                      'RxStorageUtils: Error parsing map entry for $key: $e');
                  _logger.e(
                      'RxStorageUtils: Raw entry data: ${entry.key} => ${entry.value}');
                }
                if (onError != null && e is Exception) {
                  onError(e);
                }
                // Skip failed entry and continue with the next one
                continue;
              }
            }

            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Successfully converted ${typedMap.length} map entries for $key');
            }

            // Update map content
            rxMap.clear();
            rxMap.addAll(typedMap);

            // Call with parsed data
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Calling onInitialLoadFromDb for $key with ${typedMap.length} entries');
            }
            onInitialLoadFromDb(typedMap);
          } catch (e) {
            if (_debugMode) {
              _logger.e('RxStorageUtils: Error parsing map data for $key: $e');
              _logger.e('RxStorageUtils: Raw data that failed: $rawData');
            }

            // Use default if available
            if (defaultValue != null) {
              rxMap.clear();
              rxMap.addAll(defaultValue);
              onInitialLoadFromDb(defaultValue);

              // Store default value
              final Map<dynamic, dynamic> processedMap = {};
              defaultValue.forEach((k, v) {
                processedMap[keyToRawData(k)] = valueToRawData(v);
              });
              await _writeToStorage(key, processedMap);
            } else {
              onInitialLoadFromDb(null);
            }
            if (onError != null && e is Exception) {
              onError(e);
            }
          }
        } else {
          // Handle null data
          if (defaultValue != null) {
            rxMap.clear();
            rxMap.addAll(defaultValue);
            onInitialLoadFromDb(defaultValue);

            // Store default value
            final Map<dynamic, dynamic> processedMap = {};
            defaultValue.forEach((k, v) {
              processedMap[keyToRawData(k)] = valueToRawData(v);
            });
            await _writeToStorage(key, processedMap);
          } else {
            onInitialLoadFromDb(null);
          }
        }
      } else {
        // No data exists yet
        if (_debugMode) {
          _logger.d('RxStorageUtils: Map key $key not found in storage');
        }

        // Use default if available
        if (defaultValue != null) {
          rxMap.clear();
          rxMap.addAll(defaultValue);
          onInitialLoadFromDb(defaultValue);

          // Store default value
          final Map<dynamic, dynamic> processedMap = {};
          defaultValue.forEach((k, v) {
            processedMap[keyToRawData(k)] = valueToRawData(v);
          });
          await _writeToStorage(key, processedMap);
        } else {
          onInitialLoadFromDb(null);
        }
      }
    } catch (e) {
      if (_debugMode) {
        _logger
            .e('RxStorageUtils: Error loading initial map data for $key: $e');
        _logger.e('RxStorageUtils: Stack trace: ${StackTrace.current}');
      }
      onInitialLoadFromDb(null);
      if (onError != null && e is Exception) {
        onError(e);
      }
    }

    // Listen for changes
    if (autoSync) {
      final worker = ever(rxMap, (Map<K, V> newMap) async {
        // Prevent update loops
        if (_updateLocks[key] == true) {
          return;
        }

        _updateLocks[key] = true;

        // Track timing if enabled
        Stopwatch? stopwatch;
        if (_debugMode && _trackTiming) {
          stopwatch = Stopwatch()..start();
        }

        try {
          // Convert map to raw format
          final Map<dynamic, dynamic> processedMap = {};
          newMap.forEach((k, v) {
            processedMap[keyToRawData(k)] = valueToRawData(v);
          });

          await _writeToStorage(key, processedMap);
          onUpdate(newMap);

          if (_debugMode) {
            _logger.d(
                'RxStorageUtils: Updated map $key with ${newMap.length} entries');
            if (_trackTiming) {
              stopwatch!.stop();
              _logger.d(
                  'RxStorageUtils: Update operation took ${stopwatch.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_debugMode) {
            _logger.e('RxStorageUtils: Error updating map for $key: $e');
          }
          if (onError != null && e is Exception) {
            onError(e);
          }
        } finally {
          _updateLocks[key] = false;
        }
      });

      // Store worker for possible later unbinding
      _workers[key] = worker;
    }
  }

  /// Bind a map with simplified syntax and type inference
  static Future<void> bindMap<K, V>({
    required String key,
    required RxMap<K, V> rxMap,
    required Function(Map<K, V>? data) onUpdate,
    Function(Map<K, V>? data)? onInitialLoad,
    dynamic Function(K key)? keyToRawData,
    dynamic Function(V value)? valueToRawData,
    K Function(dynamic data)? keyFromRawData,
    V Function(dynamic data)? valueFromRawData,
    Map<K, V>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Create default converters based on type
    final actualKeyToRawData =
        keyToRawData ?? _createDefaultToRawConverter<K>();
    final actualValueToRawData =
        valueToRawData ?? _createDefaultToRawConverter<V>();
    final actualKeyFromRawData =
        keyFromRawData ?? _createDefaultFromRawConverter<K>();
    final actualValueFromRawData =
        valueFromRawData ?? _createDefaultFromRawConverter<V>();
    final actualOnInitialLoad = onInitialLoad ?? onUpdate;

    await bindReactiveMapValue<K, V>(
      key: key,
      rxMap: rxMap,
      onUpdate: onUpdate,
      onInitialLoadFromDb: actualOnInitialLoad,
      keyToRawData: actualKeyToRawData,
      valueToRawData: actualValueToRawData,
      keyFromRawData: actualKeyFromRawData,
      valueFromRawData: actualValueFromRawData,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
      verboseLogging: verboseLogging,
    );
  }

  /// Bind a reactive Set to persistent storage
  static Future<void> bindReactiveSetValue<T>({
    required String key,
    required RxSet<T> rxSet,
    required Function(Set<T>? data) onUpdate,
    required Function(Set<T>? data) onInitialLoadFromDb,
    required dynamic Function(T item) itemToRawData,
    required T Function(dynamic data) itemFromRawData,
    Set<T>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Unbind if already bound to prevent duplicate listeners
    unbindReactive(key);

    if (_debugMode) {
      _logger.d('RxStorageUtils: Binding set $key with type $T');
    }

    // Check for existing data
    try {
      if (_storage.hasData(key)) {
        final dynamic rawData = _readFromStorage(key);
        if (_debugMode && verboseLogging) {
          _logger.d('RxStorageUtils: Read raw set data for $key: $rawData');
        }

        if (rawData != null) {
          try {
            if (rawData is! List && _debugMode) {
              _logger.e(
                  'RxStorageUtils: Data for $key is not a List: ${rawData.runtimeType}');
              throw FormatException('Data for set should be stored as a List');
            }

            final List<dynamic> rawList = List.from(rawData);
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Processing ${rawList.length} items for set $key');
            }

            final Set<T> typedSet = {};

            // Process items one by one for better error tracking
            for (int i = 0; i < rawList.length; i++) {
              try {
                if (_debugMode && verboseLogging) {
                  _logger.d('RxStorageUtils: Converting set item $i for $key');
                }
                T convertedItem = itemFromRawData(rawList[i]);
                typedSet.add(convertedItem);
              } catch (e) {
                if (_debugMode) {
                  _logger.e(
                      'RxStorageUtils: Error parsing set item $i for $key: $e');
                  _logger.e('RxStorageUtils: Raw item data: ${rawList[i]}');
                }
                if (onError != null && e is Exception) {
                  onError(e);
                }
                // Skip failed item and continue with the next one
                continue;
              }
            }

            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Successfully converted ${typedSet.length} set items for $key');
            }

            // Update set content
            rxSet.clear();
            rxSet.addAll(typedSet);

            // Call with parsed data
            if (_debugMode && verboseLogging) {
              _logger.d(
                  'RxStorageUtils: Calling onInitialLoadFromDb for $key with ${typedSet.length} set items');
            }
            onInitialLoadFromDb(typedSet);
          } catch (e) {
            if (_debugMode) {
              _logger.e('RxStorageUtils: Error parsing set data for $key: $e');
              _logger.e('RxStorageUtils: Raw data that failed: $rawData');
            }

            // Use default if available
            if (defaultValue != null) {
              rxSet.clear();
              rxSet.addAll(defaultValue);
              onInitialLoadFromDb(defaultValue);

              // Store default value as list
              final List<dynamic> rawList =
                  defaultValue.map(itemToRawData).toList();
              await _writeToStorage(key, rawList);
            } else {
              onInitialLoadFromDb(null);
            }
            if (onError != null && e is Exception) {
              onError(e);
            }
          }
        } else {
          // Handle null data
          if (defaultValue != null) {
            rxSet.clear();
            rxSet.addAll(defaultValue);
            onInitialLoadFromDb(defaultValue);

            // Store default value
            final List<dynamic> rawList =
                defaultValue.map(itemToRawData).toList();
            await _writeToStorage(key, rawList);
          } else {
            onInitialLoadFromDb(null);
          }
        }
      } else {
        // No data exists yet
        if (_debugMode) {
          _logger.d('RxStorageUtils: Set key $key not found in storage');
        }

        // Use default if available
        if (defaultValue != null) {
          rxSet.clear();
          rxSet.addAll(defaultValue);
          onInitialLoadFromDb(defaultValue);

          // Store default value
          final List<dynamic> rawList =
              defaultValue.map(itemToRawData).toList();
          await _writeToStorage(key, rawList);
        } else {
          onInitialLoadFromDb(null);
        }
      }
    } catch (e) {
      if (_debugMode) {
        _logger
            .e('RxStorageUtils: Error loading initial set data for $key: $e');
        _logger.e('RxStorageUtils: Stack trace: ${StackTrace.current}');
      }
      onInitialLoadFromDb(null);
      if (onError != null && e is Exception) {
        onError(e);
      }
    }

    // Listen for changes
    if (autoSync) {
      final worker = ever(rxSet, (Set<T> newSet) async {
        // Prevent update loops
        if (_updateLocks[key] == true) {
          return;
        }

        _updateLocks[key] = true;

        // Track timing if enabled
        Stopwatch? stopwatch;
        if (_debugMode && _trackTiming) {
          stopwatch = Stopwatch()..start();
        }

        try {
          final List<dynamic> rawList = newSet.map(itemToRawData).toList();
          await _writeToStorage(key, rawList);
          onUpdate(newSet);

          if (_debugMode) {
            _logger.d(
                'RxStorageUtils: Updated set $key with ${newSet.length} items');
            if (_trackTiming) {
              stopwatch!.stop();
              _logger.d(
                  'RxStorageUtils: Update operation took ${stopwatch.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_debugMode) {
            _logger.e('RxStorageUtils: Error updating set for $key: $e');
          }
          if (onError != null && e is Exception) {
            onError(e);
          }
        } finally {
          _updateLocks[key] = false;
        }
      });

      // Store worker for possible later unbinding
      _workers[key] = worker;
    }
  }

  /// Bind a set with simplified syntax and type inference
  static Future<void> bindSet<T>({
    required String key,
    required RxSet<T> rxSet,
    required Function(Set<T>? data) onUpdate,
    Function(Set<T>? data)? onInitialLoad,
    dynamic Function(T item)? itemToRawData,
    T Function(dynamic data)? itemFromRawData,
    Set<T>? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Create default converters based on type
    final actualItemToRawData =
        itemToRawData ?? _createDefaultToRawConverter<T>();
    final actualItemFromRawData =
        itemFromRawData ?? _createDefaultFromRawConverter<T>();
    final actualOnInitialLoad = onInitialLoad ?? onUpdate;

    await bindReactiveSetValue<T>(
      key: key,
      rxSet: rxSet,
      onUpdate: onUpdate,
      onInitialLoadFromDb: actualOnInitialLoad,
      itemToRawData: actualItemToRawData,
      itemFromRawData: actualItemFromRawData,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
      verboseLogging: verboseLogging,
    );
  }

  /// Bind primitive reactive types (String, int, double, bool) with simpler syntax
  static Future<void> bindPrimitiveRx<T>({
    required String key,
    required Rx<T> rxValue,
    required Function(T? data) onUpdate,
    required Function(T? data) onInitialLoadFromDb,
    T? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
    bool verboseLogging = false,
  }) async {
    // Validate type is a primitive that can be directly stored
    if (T != String && T != int && T != double && T != bool && T != num) {
      throw ArgumentError(
          'Type $T is not supported by bindPrimitiveRx. Use bindReactiveValue instead.');
    }

    return bindReactiveValue<T>(
      key: key,
      rxValue: rxValue,
      onUpdate: onUpdate,
      onInitialLoadFromDb: onInitialLoadFromDb,
      toRawData: (T data) => data, // Direct storage for primitives
      fromRawData: (dynamic data) => data as T, // Direct cast for primitives
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
      verboseLogging: verboseLogging,
    );
  }

  /// Convenience method for RxString
  static Future<void> bindRxString({
    required String key,
    required RxString rxString,
    required Function(String? data) onUpdate,
    required Function(String? data) onInitialLoadFromDb,
    String? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
  }) async {
    return bindPrimitiveRx<String>(
      key: key,
      rxValue: rxString,
      onUpdate: onUpdate,
      onInitialLoadFromDb: onInitialLoadFromDb,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
    );
  }

  /// Convenience method for RxInt
  static Future<void> bindRxInt({
    required String key,
    required RxInt rxInt,
    required Function(int? data) onUpdate,
    required Function(int? data) onInitialLoadFromDb,
    int? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
  }) async {
    return bindPrimitiveRx<int>(
      key: key,
      rxValue: rxInt,
      onUpdate: onUpdate,
      onInitialLoadFromDb: onInitialLoadFromDb,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
    );
  }

  /// Convenience method for RxDouble
  static Future<void> bindRxDouble({
    required String key,
    required RxDouble rxDouble,
    required Function(double? data) onUpdate,
    required Function(double? data) onInitialLoadFromDb,
    double? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
  }) async {
    return bindPrimitiveRx<double>(
      key: key,
      rxValue: rxDouble,
      onUpdate: onUpdate,
      onInitialLoadFromDb: onInitialLoadFromDb,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
    );
  }

  /// Convenience method for RxBool
  static Future<void> bindRxBool({
    required String key,
    required RxBool rxBool,
    required Function(bool? data) onUpdate,
    required Function(bool? data) onInitialLoadFromDb,
    bool? defaultValue,
    bool autoSync = true,
    Function(Exception error)? onError,
  }) async {
    return bindPrimitiveRx<bool>(
      key: key,
      rxValue: rxBool,
      onUpdate: onUpdate,
      onInitialLoadFromDb: onInitialLoadFromDb,
      defaultValue: defaultValue,
      autoSync: autoSync,
      onError: onError,
    );
  }

  /// Get a value without reactive binding
  static T? getValue<T>({
    required String key,
    required T Function(dynamic data) fromRawData,
    T? defaultValue,
    Function(Exception error)? onError,
  }) {
    try {
      if (_storage.hasData(key)) {
        final dynamic data = _readFromStorage(key); // Use the wrapper method
        if (data != null) {
          return fromRawData(data);
        }
      }
      return defaultValue;
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error getting value for $key: $e');
      }
      if (onError != null && e is Exception) {
        onError(e);
      }
      return defaultValue;
    }
  }

  /// Set a value without reactive binding
  static Future<bool> setValue<T>({
    required String key,
    required T value,
    required dynamic Function(T data) toRawData,
    Function(Exception error)? onError,
  }) async {
    try {
      final dynamic rawData = toRawData(value);
      await _writeToStorage(key, rawData); // Use the wrapper method
      return true;
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error setting value for $key: $e');
      }
      if (onError != null && e is Exception) {
        onError(e);
      }
      return false;
    }
  }

  /// Check if a key exists in storage
  static bool hasKey(String key) {
    return _storage.hasData(key);
  }

  /// Clear a specific key from storage
  static Future<void> clearKey(String key) async {
    await _storage.remove(key);
    if (_debugMode) {
      _logger.d('RxStorageUtils: Cleared key $key from storage');
    }
  }

  /// Clear all storage
  static Future<void> clearAll() async {
    await _storage.erase();
    if (_debugMode) {
      _logger.d('RxStorageUtils: Cleared all storage');
    }
  }

  /// Quick debug test for fromRawData conversion
  static T? testFromRawData<T>({
    required dynamic rawData,
    required T Function(dynamic data) fromRawData,
    required String key,
  }) {
    try {
      _logger.d('RxStorageUtils: Testing conversion of raw data for $key');
      _logger.d('RxStorageUtils: Raw data: $rawData');
      final T result = fromRawData(rawData);
      _logger.d('RxStorageUtils: Conversion successful, result: $result');
      return result;
    } catch (e) {
      _logger.e('RxStorageUtils: Conversion failed for $key: $e');
      _logger.e('RxStorageUtils: Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Helper method to serialize objects to JSON
  static dynamic objectToJson<T>(T object,
      [List<Type> cyclicTypes = const []]) {
    try {
      if (object == null) return null;

      // Check if it's a primitive type that can be directly stored
      if (object is String || object is num || object is bool) {
        return object;
      }
      // Handle objects with toJson method
      else if (object is Map || object is Iterable) {
        return json.decode(json.encode(object));
      }
      // For other objects, check for a toJson method
      else {
        final mirror = reflect(object);
        final toJsonMethod = mirror.type.instanceMembers[Symbol('toJson')];

        if (toJsonMethod != null) {
          final result = mirror.invoke(Symbol('toJson'), []).reflectee;
          return result;
        } else {
          throw FormatException(
              'Object of type ${object.runtimeType} does not have a toJson method');
        }
      }
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error converting object to JSON: $e');
      }
      rethrow;
    }
  }

  /// Helper method to deserialize JSON to objects
  static T? jsonToObject<T>(
      dynamic data, T Function(Map<String, dynamic> json) fromJson) {
    try {
      if (data == null) return null;

      if (data is Map<String, dynamic>) {
        return fromJson(data);
      } else {
        throw FormatException(
            'Expected Map<String, dynamic>, got ${data.runtimeType}');
      }
    } catch (e) {
      if (_debugMode) {
        _logger.e('RxStorageUtils: Error converting JSON to object: $e');
      }
      rethrow;
    }
  }

  /// Create a default raw data converter based on the type
  static dynamic Function(T) _createDefaultToRawConverter<T>() {
    return (T value) {
      if (value == null) return null;

      // Handle primitive types directly
      if (value is String || value is num || value is bool) {
        return value;
      }

      // Handle lists
      if (value is List) {
        return value
            .map((item) => item is String || item is num || item is bool
                ? item
                : item?.toString() ?? "null")
            .toList();
      }

      // Handle maps
      if (value is Map) {
        final result = <String, dynamic>{};
        value.forEach((k, v) {
          final key = k is String ? k : k.toString();
          final val = v is String || v is num || v is bool
              ? v
              : v?.toString() ?? "null";
          result[key] = val;
        });
        return result;
      }

      // Handle objects with toJson method
      try {
        // Try to use dart:convert for JSON objects
        return json.decode(json.encode(value));
      } catch (e) {
        // Fallback to string representation
        return value.toString();
      }
    };
  }

  /// Create a default converter from raw data based on the type
  static T Function(dynamic) _createDefaultFromRawConverter<T>() {
    return (dynamic data) {
      if (data == null) {
        throw ArgumentError('Cannot convert null to type $T');
      }

      // Handle String
      if (T == String) {
        return data.toString() as T;
      }

      // Handle int
      if (T == int) {
        if (data is int) return data as T;
        if (data is num) return data.toInt() as T;
        if (data is String) return int.parse(data) as T;
        throw ArgumentError('Cannot convert ${data.runtimeType} to int');
      }

      // Handle double
      if (T == double) {
        if (data is double) return data as T;
        if (data is num) return data.toDouble() as T;
        if (data is String) return double.parse(data) as T;
        throw ArgumentError('Cannot convert ${data.runtimeType} to double');
      }

      // Handle bool
      if (T == bool) {
        if (data is bool) return data as T;
        if (data is String) {
          if (data.toLowerCase() == 'true') return true as T;
          if (data.toLowerCase() == 'false') return false as T;
        }
        if (data is num) return (data != 0) as T;
        throw ArgumentError('Cannot convert ${data.runtimeType} to bool');
      }

      // Direct cast if types match
      if (data is T) {
        return data;
      }

      throw ArgumentError(
          'No default conversion available from ${data.runtimeType} to $T');
    };
  }
}
