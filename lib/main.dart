import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/providers/service_providers.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();
  
  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Hive Adapters
  // Hive.registerAdapter(UserAdapter());
  // Hive.registerAdapter(CreditCardAdapter());
  // Hive.registerAdapter(TransactionAdapter());
  // Hive.registerAdapter(BenefitAdapter());
  // Hive.registerAdapter(CardNetworkAdapter());
  // Hive.registerAdapter(CardTypeAdapter());
  // Hive.registerAdapter(TransactionTypeAdapter());
  // Hive.registerAdapter(TransactionCategoryAdapter());
  // Hive.registerAdapter(BenefitTypeAdapter());  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // Initialize GoogleSignIn singleton exactly once (required by google_sign_in 7.x)
  await GoogleSignIn.instance.initialize(
    clientId: AppConfig.googleClientId,
  );
  
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const CardCompassApp(),
    ),
  );
}
