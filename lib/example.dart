import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rx_storage_utils/rx_storage_utils.dart';

// Example of a model class
class LoginCredentialModel {
  final String username;
  final String? token;

  LoginCredentialModel({
    required this.username,
    this.token,
  });

  // Convert from JSON map
  factory LoginCredentialModel.fromJson(Map<String, dynamic> json) {
    return LoginCredentialModel(
      username: json['username'] ?? '',
      token: json['token'],
    );
  }

  // Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'token': token,
    };
  }
}

class ExampleUsage {
  // Reactive variable to store login credentials
  final Rx<LoginCredentialModel?> loginCredentials =
      Rx<LoginCredentialModel?>(null);

  // Proper initialization with error handling
  Future<void> initializeStorage() async {
    // Initialize the storage
    await StorageUtils.init(
      enableLogging: true,
      enableEncryption: false,
      clearInvalidData: false, // Set to true to clear problematic data
    );

    try {
      // Initialize with a default value to handle conversion errors gracefully
      await StorageUtils().initializeStorageWithListener<LoginCredentialModel>(
        key: 'login_credentials',
        rxValue: loginCredentials,
        fromJson: LoginCredentialModel.fromJson,
        toJson: (model) => model.toJson(),
        defaultValue: LoginCredentialModel(username: 'default_user'),
        onInitialValue: (value) {
          print('Loaded login credentials: ${value.username}');
        },
      );
    } catch (e) {
      print('Error initializing storage: $e');
      // Handle initialization error - could reset the problematic storage key
      await StorageUtils.remove('login_credentials');

      // Try again with a clean slate
      loginCredentials.value = LoginCredentialModel(username: 'default_user');
    }
  }

  // Example of saving new credentials
  void updateCredentials(String username, String token) {
    loginCredentials.value = LoginCredentialModel(
      username: username,
      token: token,
    );
    // Storage is automatically updated via the listener
  }

  // Example of clearing credentials
  void logout() {
    loginCredentials.value = null;
    // Key is automatically removed from storage via the listener
  }

  // Example of manually checking for issues
  Future<void> checkStorageHealth() async {
    await StorageUtils.printAll();
  }
}

// Example app showing usage
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageUtils.init();

  runApp(
    GetMaterialApp(
      home: ExampleScreen(),
    ),
  );
}

class ExampleScreen extends StatelessWidget {
  final ExampleUsage example = ExampleUsage();

  ExampleScreen({super.key}) {
    // Initialize when the screen is created
    example.initializeStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Storage Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display the stored username
            Obx(() => Text(
                  'Current user: ${example.loginCredentials.value?.username ?? "Not logged in"}',
                  style: TextStyle(fontSize: 18),
                )),
            SizedBox(height: 20),
            // Login button
            ElevatedButton(
              onPressed: () => example.updateCredentials('test_user', 'abc123'),
              child: Text('Login as test_user'),
            ),
            SizedBox(height: 10),
            // Logout button
            ElevatedButton(
              onPressed: () => example.logout(),
              child: Text('Logout'),
            ),
            SizedBox(height: 10),
            // Health check button
            ElevatedButton(
              onPressed: () => example.checkStorageHealth(),
              child: Text('Check Storage Health'),
            ),
          ],
        ),
      ),
    );
  }
}
