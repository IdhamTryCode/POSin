import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/database_helper.dart';

final supabaseAuthProvider =
    StreamProvider<User?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map((event) {
    final user = event.session?.user;
    if (user != null) {
      DatabaseHelper.setUser(user.id);
    } else {
      DatabaseHelper.clearUser();
    }
    return user;
  });
});
