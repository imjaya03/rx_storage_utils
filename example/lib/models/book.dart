class Book {
  final String id;
  final String title;
  final String author;
  final String publisher;
  final double price;
  final int pageCount;
  final String coverUrl;
  final bool isRead;
  final DateTime publishDate;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.publisher,
    required this.price,
    required this.pageCount,
    required this.coverUrl,
    this.isRead = false,
    required this.publishDate,
  });

  // Convert Book to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'publisher': publisher,
      'price': price,
      'pageCount': pageCount,
      'coverUrl': coverUrl,
      'isRead': isRead,
      'publishDate': publishDate.toIso8601String(),
    };
  }

  // Create Book from a JSON map
  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      publisher: json['publisher'] as String,
      price: json['price'] as double,
      pageCount: json['pageCount'] as int,
      coverUrl: json['coverUrl'] as String,
      isRead: json['isRead'] as bool,
      publishDate: DateTime.parse(json['publishDate'] as String),
    );
  }

  // Create a copy of this Book with some updated properties
  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? publisher,
    double? price,
    int? pageCount,
    String? coverUrl,
    bool? isRead,
    DateTime? publishDate,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      publisher: publisher ?? this.publisher,
      price: price ?? this.price,
      pageCount: pageCount ?? this.pageCount,
      coverUrl: coverUrl ?? this.coverUrl,
      isRead: isRead ?? this.isRead,
      publishDate: publishDate ?? this.publishDate,
    );
  }
}
