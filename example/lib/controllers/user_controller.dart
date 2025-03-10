import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class UserController extends GetxController {
  //
  @override
  void onInit() {
    super.onInit();
    // Load user data if needed
    _initStorage<UserModel?>(
      key: "user",
      rxValue: _user,
      onUpdate: (T) {},
      onLoad: (T) {},
      autoSync: true,
    );
  }

  //
  void _initStorage<T>({
    required String key,
    required Rx<T> rxValue,
    required Function(T) onUpdate,
    required Function(T) onLoad,
    bool autoSync = true,
  }) async {
    final storage = GetStorage();

    await storage.writeIfNull(key, dataToString(data: null));

    final readValue = storage.read<String>(key);

    if (readValue == null) {
    } else {
      final storedData = dataFromString(value: readValue);
      onLoad(storedData);
    }

    rxValue.listen(
      (data) async {
        if (autoSync) {
          await storage.write(key, dataToString(data: data));
        }
        onUpdate(data);
      },
    );
    //
  }

  String dataToString({required dynamic data}) {
    Map<String, dynamic> json = {'data': data};
    return jsonEncode(json);
  }

  dynamic dataFromString({required String value}) {
    final json = jsonDecode(value);
    final data = json['data'];
    return data;
  }

  //
  final Rx<UserModel?> _user = Rx<UserModel?>(null);
  Rx<UserModel?> get user => _user;

  //
  void login(String username, String password) {
    // Logic for user login
    final credential = UserModel(
      username: username,
      password: password,
    );
    _user.value = credential;
  }

  void logout() {
    // Logic for user logout
    _user.value = null;
  }

  void register(String username, String password) {
    // Logic for user registration
  }
  //
}

class UserModel {
  final String username;
  final String password;

  UserModel({required this.username, required this.password});

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      username: json['username'],
      password: json['password'],
    );
  }
}
