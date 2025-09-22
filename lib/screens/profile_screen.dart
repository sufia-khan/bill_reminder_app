import 'package:flutter/material.dart';
import 'package:projeckt_k/services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _hasError = false;
  bool _isEditing = false;

  // User data
  String _displayName = '';
  String _email = '';
  String _photoURL = '';
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;

  // Edit controllers
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final user = _authService.currentUser;
      if (user != null) {
        setState(() {
          _displayName = user.displayName ?? 'User';
          _email = user.email ?? '';
          _photoURL = user.photoURL ?? '';
          _nameController = TextEditingController(text: _displayName);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load user data: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateUserProfile() async {
    try {
      // Only update display name (email is read-only for security)
      await _authService.updateDisplayName(_nameController.text.trim());

      setState(() {
        _displayName = _nameController.text.trim();
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sign out: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isEditable,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        trailing: isEditable
            ? const Icon(Icons.chevron_right, color: Colors.grey)
            : null,
        onTap: isEditable ? onTap : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        color: const Color(0xFF1976D2),
        backgroundColor: Colors.white,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading profile...'),
                  ],
                ),
              )
            : _hasError
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load profile',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _loadUserData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Compact Profile Header
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: _photoURL.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(28),
                                      child: Image.network(
                                        _photoURL,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Icon(
                                            Icons.person,
                                            size: 30,
                                            color: Colors.blue.withOpacity(0.8),
                                          );
                                        },
                                      ),
                                    )
                                  : Icon(
                                      Icons.person,
                                      size: 30,
                                      color: Colors.blue.withOpacity(0.8),
                                    ),
                            ),
                            title: _isEditing
                                ? TextField(
                                    controller: _nameController,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Display Name',
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  )
                                : Text(
                                    _displayName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                            subtitle: Text(
                              _email,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: _isEditing
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _isEditing = false;
                                            _nameController.text = _displayName;
                                          });
                                        },
                                        icon: const Icon(Icons.close),
                                        color: Colors.grey,
                                      ),
                                      IconButton(
                                        onPressed: _updateUserProfile,
                                        icon: const Icon(Icons.check),
                                        color: Colors.green,
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = true;
                                      });
                                    },
                                    icon: const Icon(Icons.edit),
                                    color: Colors.blue,
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Profile Information Section
                        _buildSection('Profile Information', [
                          _buildProfileTile(
                            icon: Icons.account_circle_outlined,
                            iconColor: Colors.blue,
                            title: 'Account Status',
                            subtitle: 'Active',
                            isEditable: false,
                          ),
                          _buildProfileTile(
                            icon: Icons.calendar_today_outlined,
                            iconColor: Colors.green,
                            title: 'Member Since',
                            subtitle: 'January 2024',
                            isEditable: false,
                          ),
                          _buildProfileTile(
                            icon: Icons.email_outlined,
                            iconColor: Colors.orange,
                            title: 'Email',
                            subtitle: _email,
                            isEditable: false,
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // Account Actions Section
                        _buildSection('Account Actions', [
                          _buildProfileTile(
                            icon: Icons.lock_outlined,
                            iconColor: Colors.purple,
                            title: 'Change Password',
                            subtitle: 'Update your password',
                            isEditable: true,
                            onTap: () {
                              // Placeholder for password change
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Password change functionality coming soon!'),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            },
                          ),
                          _buildProfileTile(
                            icon: Icons.security_outlined,
                            iconColor: Colors.red,
                            title: 'Privacy Settings',
                            subtitle: 'Manage your privacy',
                            isEditable: true,
                            onTap: () {
                              // Placeholder for privacy settings
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Privacy settings coming soon!'),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            },
                          ),
                          _buildProfileTile(
                            icon: Icons.refresh_outlined,
                            iconColor: Colors.teal,
                            title: 'Refresh Profile',
                            subtitle: 'Reload profile information',
                            isEditable: true,
                            onTap: () async {
                              await _loadUserData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profile refreshed successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // Sign Out Button
                        Container(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _signOut,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Sign Out',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
      ),
    );
  }
}