import 'package:example/controllers/book_controller.dart';
import 'package:example/models/book.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BookManagementScreen extends StatefulWidget {
  const BookManagementScreen({super.key});

  @override
  State<BookManagementScreen> createState() => _BookManagementScreenState();
}

class _BookManagementScreenState extends State<BookManagementScreen> {
  // Access the controller through GetX
  final BookController _bookController = Get.put(BookController());

  // Form controllers
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherController = TextEditingController();
  final _priceController = TextEditingController();
  final _pageCountController = TextEditingController();
  final _coverUrlController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _priceController.dispose();
    _pageCountController.dispose();
    _coverUrlController.dispose();
    super.dispose();
  }

  // Add a new book
  Future<void> _addBook() async {
    // Validate form
    if (_titleController.text.isEmpty || _authorController.text.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Title and author are required',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // Try to parse numeric values
    double price;
    int pageCount;

    try {
      price = double.parse(_priceController.text);
      pageCount = int.parse(_pageCountController.text);
    } catch (e) {
      Get.snackbar(
        'Validation Error',
        'Price and page count must be valid numbers',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    // Add book using controller
    final success = await _bookController.addBook(
      title: _titleController.text,
      author: _authorController.text,
      publisher: _publisherController.text,
      price: price,
      pageCount: pageCount,
      coverUrl: _coverUrlController.text,
    );

    if (success) {
      // Clear form
      _titleController.clear();
      _authorController.clear();
      _publisherController.clear();
      _priceController.clear();
      _pageCountController.clear();
      _coverUrlController.clear();

      // Show confirmation
      Get.snackbar(
        'Success',
        'Book added successfully',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      Get.snackbar(
        'Error',
        'Failed to add book',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // Show book details dialog
  void _showBookDetails(Book book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(book.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    book.coverUrl,
                    height: 150,
                    width: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 150,
                      width: 100,
                      color: Colors.grey[300],
                      child: const Icon(Icons.book, size: 50),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Author', book.author),
              _buildDetailRow('Publisher', book.publisher),
              _buildDetailRow('Price', '\$${book.price.toStringAsFixed(2)}'),
              _buildDetailRow('Pages', book.pageCount.toString()),
              _buildDetailRow('Published',
                  '${book.publishDate.month}/${book.publishDate.day}/${book.publishDate.year}'),
              _buildDetailRow('Status', book.isRead ? 'Read' : 'Unread'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper for building detail rows
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  // Show add book form
  void _showAddBookForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add New Book',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: 'Author *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _publisherController,
                decoration: const InputDecoration(
                  labelText: 'Publisher',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _pageCountController,
                      decoration: const InputDecoration(
                        labelText: 'Pages *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _coverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Cover URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _addBook();
                },
                child: const Text('Add Book'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Library'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Obx(() {
        if (_bookController.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        } else if (_bookController.books.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Your library is empty',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _showAddBookForm,
                  child: const Text('Add Your First Book'),
                ),
              ],
            ),
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _bookController.books.length,
            itemBuilder: (context, index) {
              final book = _bookController.books[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      book.coverUrl,
                      width: 40,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 60,
                        color: Colors.grey[300],
                        child: const Icon(Icons.book, size: 24),
                      ),
                    ),
                  ),
                  title: Text(book.title),
                  subtitle: Text(
                    '${book.author} • \$${book.price.toStringAsFixed(2)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          book.isRead ? Icons.bookmark : Icons.bookmark_border,
                          color: book.isRead ? Colors.green : null,
                        ),
                        onPressed: () =>
                            _bookController.toggleBookReadStatus(book.id),
                        tooltip:
                            book.isRead ? 'Mark as unread' : 'Mark as read',
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _bookController.deleteBook(book.id),
                        tooltip: 'Delete book',
                      ),
                    ],
                  ),
                  onTap: () => _showBookDetails(book),
                ),
              );
            },
          );
        }
      }),
      floatingActionButton: Obx(
        () => _bookController.books.isNotEmpty
            ? FloatingActionButton(
                onPressed: _showAddBookForm,
                tooltip: 'Add Book',
                child: const Icon(Icons.add),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
