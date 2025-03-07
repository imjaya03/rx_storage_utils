// class LoggerService {
//   bool enableLogging = false;

//   void initLogger(bool enable) {
//     enableLogging = enable;
//   }

//   void log(String message, {bool isError = false}) {
//     if (!enableLogging) return;
//     if (isError) {
//       print('⚠️ [Storage] $message');
//     } else {
//       print('💾 [Storage] $message');
//     }
//   }
// }
