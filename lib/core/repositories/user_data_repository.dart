import 'package:supabase_flutter/supabase_flutter.dart';

class UserDataRepository {
  UserDataRepository(this._db);

  final SupabaseClient _db;

  Future<void> resetAll() async {
    await _db.rpc<void>('reset_my_cardcompass_data');
  }
}
