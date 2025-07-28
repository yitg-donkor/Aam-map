import 'package:flutter/material.dart';
import 'package:map/data/user_stats.dart';

// settings_page.dart
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _distanceTracking = true;
  bool _notifications = true;
  bool _locationServices = true;
  String _mapStyle = 'Streets';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Location & Tracking', [
            _buildSwitchTile(
              'Distance Tracking',
              'Track your walking distance',
              Icons.directions_walk,
              _distanceTracking,
              (value) => setState(() => _distanceTracking = value),
            ),
            _buildSwitchTile(
              'Location Services',
              'Allow app to access your location',
              Icons.location_on,
              _locationServices,
              (value) => setState(() => _locationServices = value),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Map Preferences', [
            _buildDropdownTile(
              'Map Style',
              'Choose your preferred map style',
              Icons.map,
              _mapStyle,
              ['Streets', 'Satellite', 'Dark', 'Light'],
              (value) => setState(() => _mapStyle = value!),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Notifications', [
            _buildSwitchTile(
              'Push Notifications',
              'Receive app notifications',
              Icons.notifications,
              _notifications,
              (value) => setState(() => _notifications = value),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Data Management', [
            _buildActionTile(
              'Clear Cache',
              'Free up storage space',
              Icons.storage,
              () => _showClearCacheDialog(),
            ),
            _buildActionTile(
              'Reset Distance',
              'Reset total distance to zero',
              Icons.refresh,
              () => _showResetDistanceDialog(),
              isDestructive: true,
            ),
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

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[700]),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.blue,
      ),
    );
  }

  Widget _buildDropdownTile(
    String title,
    String subtitle,
    IconData icon,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[700]),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        items:
            options.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red[700] : Colors.blue[700],
      ),
      title: Text(
        title,
        style: TextStyle(color: isDestructive ? Colors.red[700] : null),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Cache'),
            content: const Text(
              'This will clear temporary files and free up storage space. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared successfully')),
                  );
                },
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  void _showResetDistanceDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reset Distance'),
            content: const Text(
              'This will reset your total distance to zero. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await UserStatsService.resetUserTotalDistance();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Distance reset successfully'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Reset'),
              ),
            ],
          ),
    );
  }
}
