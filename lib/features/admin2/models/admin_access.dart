class AdminAccess {
  const AdminAccess({required this.isAdmin});

  final bool isAdmin;

  factory AdminAccess.fromJson(Map<String, dynamic> json) {
    final isAdmin = json['is_admin'];
    if (isAdmin is! bool) {
      throw const FormatException('is_admin must be a boolean');
    }
    return AdminAccess(isAdmin: isAdmin);
  }
}
