import 'package:flutter/material.dart';
import 'core/services/advanced_benefit_calculation_service.dart';

/// Demo app to test the new ML-powered benefit extraction
class MLBenefitExtractionDemo extends StatefulWidget {
  @override
  _MLBenefitExtractionDemoState createState() => _MLBenefitExtractionDemoState();
}

class _MLBenefitExtractionDemoState extends State<MLBenefitExtractionDemo> {
  final TextEditingController _cardNameController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  bool _isExtracting = false;
  Map<String, dynamic>? _extractionResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Set some default values for testing
    _cardNameController.text = 'Regalia Credit Card';
    _bankNameController.text = 'HDFC Bank';
  }

  Future<void> _extractBenefits() async {
    setState(() {
      _isExtracting = true;
      _extractionResult = null;
      _errorMessage = null;
    });

    try {
      final cardName = _cardNameController.text.trim();
      final bankName = _bankNameController.text.trim();

      if (cardName.isEmpty || bankName.isEmpty) {
        throw Exception('Card name and bank name are required');
      }

      print('🚀 DEMO: Starting benefit extraction for $bankName $cardName');

      // Use the new AI benefit extraction service
      final benefitService = AdvancedBenefitCalculationService();
      
      // For demo purposes, we'll use a dummy card ID
      final dummyCardId = 'demo-card-${DateTime.now().millisecondsSinceEpoch}';
      
      final result = await benefitService.extractAndUpdateBenefits(
        cardId: dummyCardId,
        cardName: cardName,
        bankName: bankName,
      );

      setState(() {
        _extractionResult = result;
        _isExtracting = false;
      });

      if (result['success'] == true) {
        print('✅ DEMO: Extraction successful!');
        _showSuccessSnackBar('Benefits extracted successfully!');
      } else {
        print('❌ DEMO: Extraction failed: ${result['error']}');
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Unknown error';
        });
      }

    } catch (e) {
      print('❌ DEMO: Exception during extraction: $e');
      setState(() {
        _errorMessage = e.toString();
        _isExtracting = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🤖 ML Benefit Extraction Demo'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.smart_toy, size: 48, color: Colors.blue[800]),
                    SizedBox(height: 8),
                    Text(
                      'AI-Powered Benefit Extraction',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Extract real benefit data from bank websites using Gemini AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 20),
            
            // Input fields
            TextField(
              controller: _bankNameController,
              decoration: InputDecoration(
                labelText: 'Bank Name',
                hintText: 'e.g., HDFC Bank, ICICI Bank, SBI Card',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
            ),
            
            SizedBox(height: 16),
            
            TextField(
              controller: _cardNameController,
              decoration: InputDecoration(
                labelText: 'Card Name',
                hintText: 'e.g., Regalia Credit Card, Amazon Pay Card',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.credit_card),
              ),
            ),
            
            SizedBox(height: 20),
            
            // Extract button
            ElevatedButton(
              onPressed: _isExtracting ? null : _extractBenefits,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isExtracting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Extracting Benefits...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome),
                        SizedBox(width: 8),
                        Text('Extract Benefits with AI'),
                      ],
                    ),
            ),
            
            SizedBox(height: 20),
            
            // Results section
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extraction Results',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      
                      if (_errorMessage != null)
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            border: Border.all(color: Colors.red[200]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red[600]),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Error: $_errorMessage',
                                  style: TextStyle(color: Colors.red[800]),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_extractionResult != null)
                        Expanded(
                          child: SingleChildScrollView(
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _extractionResult!['success'] == true 
                                    ? Colors.green[50] 
                                    : Colors.red[50],
                                border: Border.all(
                                  color: _extractionResult!['success'] == true 
                                      ? Colors.green[200]! 
                                      : Colors.red[200]!
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _extractionResult!['success'] == true 
                                            ? Icons.check_circle_outline 
                                            : Icons.error_outline,
                                        color: _extractionResult!['success'] == true 
                                            ? Colors.green[600] 
                                            : Colors.red[600],
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        _extractionResult!['success'] == true 
                                            ? 'Extraction Successful!' 
                                            : 'Extraction Failed',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _extractionResult!['success'] == true 
                                              ? Colors.green[800] 
                                              : Colors.red[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    _extractionResult!.toString(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Enter card details and click "Extract Benefits" to see AI-powered extraction in action!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cardNameController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase (you'll need to provide your credentials)
  // await Supabase.initialize(
  //   url: 'YOUR_SUPABASE_URL',
  //   anonKey: 'YOUR_SUPABASE_ANON_KEY',
  // );
  
  runApp(MaterialApp(
    title: 'ML Benefit Extraction Demo',
    theme: ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ),
    home: MLBenefitExtractionDemo(),
    debugShowCheckedModeBanner: false,
  ));
}
