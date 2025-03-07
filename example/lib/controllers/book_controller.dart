import 'package:example/helpers/mock_rx_json_storage.dart';
import 'package:example/models/book.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

class BookController extends GetxController {
  final RxJsonStorage _jsonStorage = RxJsonStorage();
  static const _booksStorageKey = 'user_books_library';

  // Observable state
  final RxList<Book> books = <Book>[].obs;
  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadBooks();
  }

  // Load books from storage
  Future<void> loadBooks() async {
    isLoading.value = true;

    final loadedBooks = await _jsonStorage.getObjectList<Book>(
      _booksStorageKey,
      (json) => Book.fromJson(json),
    );

    books.value = loadedBooks;
    isLoading.value = false;
  }

  // Save books to storage
  Future<void> saveBooks() async {
    await _jsonStorage.saveObjectList(
      _booksStorageKey,
      books.map((book) => book.toJson()).toList(),
    );
  }

  // Add a new book
  Future<bool> addBook({
    required String title,
    required String author,
    required String publisher,
    required double price,
    required int pageCount,
    required String coverUrl,
  }) async {
    try {
      final newBook = Book(
        id: const Uuid().v4(),
        title: title,
        author: author,
        publisher: publisher.isEmpty ? 'Unknown' : publisher,
        price: price,
        pageCount: pageCount,
        coverUrl: coverUrl.isEmpty
            ? 'https://via.placeholder.com/150x200?text=No+Cover'
            : coverUrl,
        publishDate: DateTime.now(),
      );

      books.add(newBook);
      await saveBooks();
      return true;
    } catch (e) {
      print('Error adding book: $e');
      return false;
    }
  }

  // Toggle read status for a book
  Future<void> toggleBookReadStatus(String bookId) async {
    final index = books.indexWhere((book) => book.id == bookId);
    if (index != -1) {
      final book = books[index];
      final updatedBook = book.copyWith(isRead: !book.isRead);
      books[index] = updatedBook;
      await saveBooks();
    }
  }

  // Delete a book
  Future<void> deleteBook(String bookId) async {
    books.removeWhere((book) => book.id == bookId);
    await saveBooks();
  }

  // Get a book by ID
  Book? getBookById(String bookId) {
    try {
      return books.firstWhere((book) => book.id == bookId);
    } catch (e) {
      return null;
    }
  }

  // Clear all books
  Future<void> clearAllBooks() async {
    books.clear();
    await saveBooks();
  }
}
