import 'package:shared_preferences/shared_preferences.dart';

/// A simple implementation of RxPreferences that can be used in the example app
/// if the actual package implementation isn't ready yet.
class RxPreferences {
  // Internal storage
  Map<String, dynamic> _memoryCache = {};

  // Get a string value
  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    _memoryCache[key] = value;
    return value;
  }

  // Set a string value
  Future<bool> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    _memoryCache[key] = value;
    return prefs.setString(key, value);
  }

  // Get a bool value
  Future<bool?> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(key);
    _memoryCache[key] = value;
    return value;
  }

  // Set a bool value
  Future<bool> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _memoryCache[key] = value;
    return prefs.setBool(key, value);
  }

  // Get an int value
  Future<int?> getInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(key);
    _memoryCache[key] = value;
    return value;
  }

  // Set an int value
  Future<bool> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    _memoryCache[key] = value;
    return prefs.setInt(key, value);
  }

  // Get a string list
  Future<List<String>?> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getStringList(key);
    _memoryCache[key] = value;
    return value;
  }

  // Set a string list
  Future<bool> setStringList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    _memoryCache[key] = value;
    return prefs.setStringList(key, value);
  }

  // Clear all data
  Future<bool> clear() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryCache = {};
    return prefs.clear();
  }
}
