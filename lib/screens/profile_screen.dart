import 'package:flutter/material.dart';
import 'package:projeckt_k/services/auth_service.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _isLoading = true;
  bool _hasError = false;
  bool _isEditing = false;

  // User data
  String _displayName = '';
  String _email = '';
  String _photoURL = '';

  // Bill statistics
  int _totalBills = 0;
  int _paidBills = 0;
  int _upcomingBills = 0;
  int _overdueBills = 0;
  double _totalAmount = 0.0;

  // Edit controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadBillStatistics();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
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
          _emailController = TextEditingController(text: _email);
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

  Future<void> _loadBillStatistics() async {
    try {
      final subscriptions = await _subscriptionService.getSubscriptions();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int paid = 0;
      int upcoming = 0;
      int overdue = 0;
      double total = 0.0;

      for (var bill in subscriptions) {
        total += (bill['amount'] ?? 0);

        if (bill['status'] == 'paid') {
          paid++;
        } else {
          try {
            final dueDate = DateTime.parse(bill['dueDate']);
            final due = DateTime(dueDate.year, dueDate.month, dueDate.day);

            if (due.isBefore(today)) {
              overdue++;
            } else {
              upcoming++;
            }
          } catch (e) {
            upcoming++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalBills = subscriptions.length;
          _paidBills = paid;
          _upcomingBills = upcoming;
          _overdueBills = overdue;
          _totalAmount = total;
        });
      }
    } catch (e) {
      debugPrint('Failed to load bill statistics: $e');
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

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                if (_isEditing) {
                  _nameController.text = _displayName;
                  _emailController.text = _email;
                }
              });
            },
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            tooltip: _isEditing ? 'Cancel Edit' : 'Edit Profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserData();
          await _loadBillStatistics();
        },
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
                          onPressed: () {
                            _loadUserData();
                            _loadBillStatistics();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Profile Header Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1976D2), Color(0xFF1565C0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1976D2).withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Profile Picture
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: _photoURL.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(37),
                                        child: Image.network(
                                          _photoURL,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Icon(
                                              Icons.person,
                                              size: 40,
                                              color: Colors.white.withOpacity(0.8),
                                            );
                                          },
                                        ),
                                      )
                                    : Icon(
                                        Icons.person,
                                        size: 40,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                              ),
                              const SizedBox(height: 16),

                              // User Info
                              if (_isEditing) ...[
                                TextField(
                                  controller: _nameController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Display Name',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                    focusedBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  _displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Edit/Save Button
                              if (_isEditing)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _updateUserProfile,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(0xFF1976D2),
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      ),
                                      child: const Text('Save Changes'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Bill Statistics Grid
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bill Overview',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your subscription management summary',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),

                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.1,
                              children: [
                                _buildStatCard(
                                  'Total Bills',
                                  '$_totalBills',
                                  const Color(0xFF1976D2),
                                  Icons.receipt_long,
                                ),
                                _buildStatCard(
                                  'Total Amount',
                                  '\$${_totalAmount.toStringAsFixed(2)}',
                                  const Color(0xFF2E7D32),
                                  Icons.attach_money,
                                ),
                                _buildStatCard(
                                  'Paid',
                                  '$_paidBills',
                                  const Color(0xFF2E7D32),
                                  Icons.payments_rounded,
                                ),
                                _buildStatCard(
                                  'Upcoming',
                                  '$_upcomingBills',
                                  const Color(0xFFD4A017),
                                  Icons.calendar_month,
                                ),
                                _buildStatCard(
                                  'Overdue',
                                  '$_overdueBills',
                                  const Color(0xFFC62828),
                                  Icons.hourglass_top_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Account Actions
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account Actions',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.refresh,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    title: const Text('Refresh Data'),
                                    subtitle: const Text('Update profile and bill statistics'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () async {
                                      await _loadUserData();
                                      await _loadBillStatistics();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Data refreshed successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    },
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.logout,
                                        color: Colors.red,
                                      ),
                                    ),
                                    title: const Text('Sign Out'),
                                    subtitle: const Text('Sign out from your account'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: _signOut,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // App Info
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                'SubManager',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Version 1.0.0',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Manage your subscriptions with ease',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}