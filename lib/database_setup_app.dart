import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/app_config.dart';

/// Database setup app to create benefit tables
class DatabaseSetupApp extends StatelessWidget {
  const DatabaseSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Database Setup',
      home: const DatabaseSetupScreen(),
    );
  }
}

class DatabaseSetupScreen extends StatefulWidget {
  const DatabaseSetupScreen({super.key});

  @override
  State<DatabaseSetupScreen> createState() => _DatabaseSetupScreenState();
}

class _DatabaseSetupScreenState extends State<DatabaseSetupScreen> {
  bool _isLoading = false;
  String _status = 'Ready to set up database tables';
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initializeSupabase();
  }

  Future<void> _initializeSupabase() async {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      setState(() {
        _status = 'Supabase initialized. Ready to create tables.';
      });
    } catch (e) {
      setState(() {
        _status = 'Supabase initialization failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Setup'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database Setup Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _status.contains('Error') || _status.contains('failed')
                            ? Colors.red
                            : _status.contains('success') || _status.contains('completed')
                            ? Colors.green
                            : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _setupDatabase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Setting up...'),
                      ],
                    )
                  : const Text(
                      'Create Benefit Tables',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
            const SizedBox(height: 24),
            if (_logs.isNotEmpty) ...[
              const Text(
                'Setup Logs:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _logs.map((log) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          log,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setupDatabase() async {
    setState(() {
      _isLoading = true;
      _status = 'Creating database tables...';
      _logs.clear();
    });

    try {
      final supabase = Supabase.instance.client;
      
      _addLog('🔄 Starting database setup...');
      
      // Create benefit_categories table
      _addLog('📊 Creating benefit_categories table...');
      await supabase.rpc('sql', params: {
        'query': '''
          CREATE TABLE IF NOT EXISTS benefit_categories (
            category_code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );
        '''
      });
      _addLog('✅ benefit_categories table created');

      // Create benefits table
      _addLog('📊 Creating benefits table...');
      await supabase.rpc('sql', params: {
        'query': '''
          CREATE TABLE IF NOT EXISTS benefits (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            category_code TEXT REFERENCES benefit_categories(category_code),
            name TEXT NOT NULL,
            description TEXT,
            calculation_method TEXT NOT NULL,
            default_value DECIMAL(10, 2),
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );
        '''
      });
      _addLog('✅ benefits table created');

      // Create card_catalog table if not exists
      _addLog('📊 Creating card_catalog table...');
      await supabase.rpc('sql', params: {
        'query': '''
          CREATE TABLE IF NOT EXISTS card_catalog (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            bank TEXT NOT NULL,
            card_name TEXT NOT NULL,
            card_type TEXT DEFAULT 'standard',
            network TEXT DEFAULT 'VISA',
            annual_fee DECIMAL(10, 2) DEFAULT 0,
            features JSONB DEFAULT '{}',
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );
        '''
      });
      _addLog('✅ card_catalog table created');

      // Create card_benefits table
      _addLog('📊 Creating card_benefits table...');
      await supabase.rpc('sql', params: {
        'query': '''
          CREATE TABLE IF NOT EXISTS card_benefits (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            card_id UUID,
            benefit_id UUID REFERENCES benefits(id) NOT NULL,
            value DECIMAL(10, 2),
            spending_categories TEXT[],
            monthly_cap DECIMAL(10, 2),
            annual_cap DECIMAL(10, 2),
            valid_from TIMESTAMP WITH TIME ZONE,
            valid_to TIMESTAMP WITH TIME ZONE,
            configuration JSONB DEFAULT '{}',
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );
        '''
      });
      _addLog('✅ card_benefits table created');

      // Insert sample cards
      _addLog('📊 Inserting sample cards...');
      await supabase.from('card_catalog').upsert([
        {
          'bank': 'HDFC Bank',
          'card_name': 'Regalia Credit Card',
          'card_type': 'premium',
          'annual_fee': 2500,
        },
        {
          'bank': 'ICICI Bank',
          'card_name': 'Amazon Pay Credit Card',
          'card_type': 'standard',
          'annual_fee': 0,
        },
        {
          'bank': 'SBI Card',
          'card_name': 'SimplyCLICK Credit Card',
          'card_type': 'standard',
          'annual_fee': 499,
        },
        {
          'bank': 'Axis Bank',
          'card_name': 'Flipkart Credit Card',
          'card_type': 'standard',
          'annual_fee': 500,
        },
      ], onConflict: 'bank,card_name');
      _addLog('✅ Sample cards inserted');

      _addLog('🎉 Database setup completed successfully!');
      
      setState(() {
        _status = 'Database setup completed! You can now run the benefit import.';
      });
      
    } catch (e) {
      _addLog('❌ Error during setup: $e');
      setState(() {
        _status = 'Database setup failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toLocal().toString().substring(11, 19)} - $message');
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DatabaseSetupApp());
}
