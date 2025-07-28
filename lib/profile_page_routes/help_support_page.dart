// help_support_page.dart
import 'package:flutter/material.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Frequently Asked Questions', [
            _buildFAQTile(
              'How do I save a location?',
              'Use the favorite button in the speed dial on the map screen.',
            ),
            _buildFAQTile(
              'How does distance tracking work?',
              'The app automatically tracks your movement when location services are enabled.',
            ),
            _buildFAQTile(
              'Why is my location not accurate?',
              'Make sure location services are enabled and you have a good GPS signal.',
            ),
            _buildFAQTile(
              'How do I get directions?',
              'Use the directions button in the speed dial and search for your destination.',
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Contact Support', [
            _buildContactTile(
              'Email Support',
              'Get help via email',
              Icons.email,
              'support@yourapp.com',
            ),
            _buildContactTile(
              'Live Chat',
              'Chat with our support team',
              Icons.chat,
              'Available 9AM - 5PM',
            ),
            _buildContactTile(
              'Phone Support',
              'Call our support line',
              Icons.phone,
              '+1 (555) 123-4567',
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('App Information', [
            _buildInfoTile('Version', '1.0.0'),
            _buildInfoTile('Build', '123'),
            _buildInfoTile('Platform', 'Android'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        Card(child: Column(children: children)),
      ],
    );
  }

  Widget _buildFAQTile(String question, String answer) {
    return ExpansionTile(
      title: Text(question),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(answer, style: TextStyle(color: Colors.grey[600])),
        ),
      ],
    );
  }

  Widget _buildContactTile(
    String title,
    String subtitle,
    IconData icon,
    String detail,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[700]),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        detail,
        style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500),
      ),
      onTap: () {
        // Handle contact action
      },
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
      ),
    );
  }
}
