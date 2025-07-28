import 'package:flutter/material.dart';
// privacy_policy_page.dart

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy Policy',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Information We Collect',
              'We collect location data to provide mapping and navigation services. This includes your current location, saved places, and navigation history.',
            ),
            _buildSection(
              'How We Use Your Information',
              'Your location data is used to provide core app functionality including navigation, distance tracking, and saving favorite places. We do not share your personal location data with third parties.',
            ),
            _buildSection(
              'Data Storage',
              'Your data is securely stored and encrypted. You have full control over your data and can delete it at any time through the app settings.',
            ),
            _buildSection(
              'Location Services',
              'The app requires location services to function properly. You can control location permissions through your device settings. Disabling location services will limit app functionality.',
            ),
            _buildSection(
              'Your Rights',
              'You have the right to access, modify, or delete your personal data. You can also request a copy of your data or withdraw consent at any time.',
            ),
            _buildSection(
              'Contact Us',
              'If you have questions about this privacy policy, please contact us at privacy@yourapp.com',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
