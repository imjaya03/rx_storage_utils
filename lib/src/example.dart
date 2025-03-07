import 'package:get/get.dart';
import 'package:rx_storage_utils/rx_storage_utils.dart';

class ExampleService extends GetxController {
  // Example service to demonstrate the use of GetX
  var count = 0.obs;

  final _storage = RxStorageUtils();

  void aa() {}

  void increment() {
    count++;
  }

  void decrement() {
    count--;
  }
}
