import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A helper class for storing and retrieving complex objects
/// using JSON serialization.
class RxJsonStorage {
  // Save a complex object
  Future<bool> saveObject<T>(String key, dynamic object) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(object);
      return await prefs.setString(key, jsonString);
    } catch (e) {
      print('Error saving object: $e');
      return false;
    }
  }

  // Save a list of complex objects
  Future<bool> saveObjectList<T>(String key, List<dynamic> objects) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(objects);
      return await prefs.setString(key, jsonString);
    } catch (e) {
      print('Error saving object list: $e');
      return false;
    }
  }

  // Retrieve a complex object
  Future<T?> getObject<T>(
      String key, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(key);
      if (jsonString == null) return null;

      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return fromJson(jsonMap);
    } catch (e) {
      print('Error retrieving object: $e');
      return null;
    }
  }

  // Retrieve a list of complex objects
  Future<List<T>> getObjectList<T>(
      String key, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(key);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error retrieving object list: $e');
      return [];
    }
  }

  // Remove an object
  Future<bool> removeObject(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(key);
    } catch (e) {
      print('Error removing object: $e');
      return false;
    }
  }
}
