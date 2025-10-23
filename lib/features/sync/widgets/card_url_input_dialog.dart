import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog to prompt user for credit card product URL
class CardUrlInputDialog extends StatefulWidget {
  final String bankName;
  final String cardVariant;
  final String emailSubject;
  final String? suggestedUrl;

  const CardUrlInputDialog({
    Key? key,
    required this.bankName,
    required this.cardVariant,
    required this.emailSubject,
    this.suggestedUrl,
  }) : super(key: key);

  @override
  State<CardUrlInputDialog> createState() => _CardUrlInputDialogState();
}

class _CardUrlInputDialogState extends State<CardUrlInputDialog> {
  late TextEditingController _urlController;
  bool _isValidUrl = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.suggestedUrl ?? '');
    if (widget.suggestedUrl != null) {
      _validateUrl(widget.suggestedUrl!);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _validateUrl(String url) {
    setState(() {
      if (url.isEmpty) {
        _isValidUrl = false;
        _errorMessage = 'URL cannot be empty';
        return;
      }

      try {
        final uri = Uri.parse(url);
        if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
          _isValidUrl = false;
          _errorMessage = 'URL must start with http:// or https://';
          return;
        }
        if (!uri.hasAuthority || uri.host.isEmpty) {
          _isValidUrl = false;
          _errorMessage = 'Invalid URL format';
          return;
        }
        _isValidUrl = true;
        _errorMessage = null;
      } catch (e) {
        _isValidUrl = false;
        _errorMessage = 'Invalid URL format';
      }
    });
  }

  Future<void> _openSearchInBrowser() async {
    final searchQuery = Uri.encodeComponent('${widget.bankName} ${widget.cardVariant} credit card official');
    final searchUrl = Uri.parse('https://www.google.com/search?q=$searchQuery');
    
    if (await canLaunchUrl(searchUrl)) {
      await launchUrl(searchUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.credit_card, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Card URL Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info card with card details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.account_balance, 'Bank', widget.bankName),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.credit_card, 'Card', widget.cardVariant),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.email, 'Email', widget.emailSubject),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Explanation text
              const Text(
                'We need the official product page URL for this credit card to extract benefits and features.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              
              // Search button
              OutlinedButton.icon(
                onPressed: _openSearchInBrowser,
                icon: const Icon(Icons.search),
                label: const Text('Search on Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              
              // URL input field
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Product Page URL',
                  hintText: 'https://www.bankname.com/cards/card-name',
                  prefixIcon: const Icon(Icons.link),
                  errorText: _errorMessage,
                  border: const OutlineInputBorder(),
                  helperText: 'Paste the official credit card product page URL',
                ),
                onChanged: _validateUrl,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              
              // Example URLs
              const Text(
                'Examples:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              _buildExampleUrl('https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia-gold'),
              _buildExampleUrl('https://www.idfcfirstbank.com/credit-card/millennia-credit-card'),
              _buildExampleUrl('https://www.axisbank.com/retail/cards/credit-card/ace-credit-card'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null); // User cancelled
          },
          child: const Text('Skip for Now'),
        ),
        ElevatedButton(
          onPressed: _isValidUrl
              ? () {
                  Navigator.of(context).pop(_urlController.text.trim());
                }
              : null,
          child: const Text('Save URL'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExampleUrl(String url) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 2),
      child: Text(
        '• $url',
        style: const TextStyle(fontSize: 11, color: Colors.black45, fontFamily: 'monospace'),
      ),
    );
  }
}

/// Show the card URL input dialog
Future<String?> showCardUrlInputDialog({
  required BuildContext context,
  required String bankName,
  required String cardVariant,
  required String emailSubject,
  String? suggestedUrl,
}) async {
  print('🎯 showCardUrlInputDialog called!');
  print('   Bank: $bankName');
  print('   Card: $cardVariant');
  print('   Email: $emailSubject');
  print('   Context mounted: ${context.mounted}');
  
  if (!context.mounted) {
    print('   ❌ Context not mounted! Cannot show dialog.');
    return null;
  }
  
  print('   ✅ Showing dialog now...');
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false, // User must provide URL or skip
    builder: (context) => CardUrlInputDialog(
      bankName: bankName,
      cardVariant: cardVariant,
      emailSubject: emailSubject,
      suggestedUrl: suggestedUrl,
    ),
  );
  
  print('   📱 Dialog returned: $result');
  return result;
}
