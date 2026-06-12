class InAppNotificationModel {
  const InAppNotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.isRead,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final String category;
  final bool isRead;
  final String? createdAt;

  factory InAppNotificationModel.fromJson(Map<String, dynamic> json) {
    return InAppNotificationModel(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'system',
      isRead: json['is_read'] == true,
      createdAt: json['created_at'] as String?,
    );
  }
}
