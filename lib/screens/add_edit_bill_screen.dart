import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:intl/intl.dart';
import 'package:projeckt_k/services/subscription_service.dart';

class AddEditBillScreen extends StatefulWidget {
  final Map<String, dynamic>? bill;
  final int? editIndex;
  final Function(Map<String, dynamic>, int?) onBillSaved;
  final SubscriptionService subscriptionService;

  const AddEditBillScreen({
    Key? key,
    this.bill,
    this.editIndex,
    required this.onBillSaved,
    required this.subscriptionService,
  }) : super(key: key);

  @override
  _AddEditBillScreenState createState() => _AddEditBillScreenState();
}

class _AddEditBillScreenState extends State<AddEditBillScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _dueTimeController;
  late final TextEditingController _notesController;
  late final TextEditingController _paymentMethodController;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedFrequency = 'Monthly';
  String _selectedReminder = 'Same day';
  Category _selectedCategory = Category.defaultCategories[0];
  String _selectedPaymentMethod = 'Credit Card';

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();

    // Update time controller after the first frame when context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateTimeController();
      }
    });
  }

  void _initializeControllers() {
    // Initialize all controllers first
    _nameController = TextEditingController(
      text: widget.bill?['name']?.toString() ?? '',
    );
    _amountController = TextEditingController(
      text: widget.bill?['amount']?.toString() ?? '',
    );
    _dueDateController = TextEditingController();
    _dueTimeController = TextEditingController();
    _notesController = TextEditingController(
      text: widget.bill?['notes']?.toString() ?? '',
    );
    _paymentMethodController = TextEditingController(
      text: widget.bill?['paymentMethod']?.toString() ?? 'Credit Card',
    );

    // Parse existing date and time if editing
    if (widget.bill != null) {
      _parseExistingBillData();
    }

    _updateDateController();
    // Don't call _updateTimeController() here as it requires context
    // It will be called in the first build after initState completes
  }

  void _parseExistingBillData() {
    // Set defaults for new bills
    if (widget.bill == null) {
      _selectedDate = DateTime.now();
      _selectedTime = const TimeOfDay(hour: 9, minute: 0);
      _selectedFrequency = 'Monthly';
      _selectedReminder = 'Same day';
      _selectedPaymentMethod = 'Credit Card';
      return;
    }

    // Parse due date for existing bills
    if (widget.bill!['dueDate'] != null) {
      try {
        if (widget.bill!['dueDate'] is DateTime) {
          _selectedDate = widget.bill!['dueDate'];
        } else if (widget.bill!['dueDate'] is String) {
          final dateStr = widget.bill!['dueDate'].toString();
          try {
            // Try standard ISO format first
            _selectedDate = DateTime.parse(dateStr);
          } catch (e) {
            // Try different date formats
            final formats = ['MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd'];
            for (final format in formats) {
              try {
                _selectedDate = DateFormat(format).parse(dateStr);
                break;
              } catch (_) {
                continue;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error parsing due date: $e');
        // Default to today if parsing fails
        _selectedDate = DateTime.now();
      }
    } else {
      // Set default date for new bills
      _selectedDate = DateTime.now();
    }

    // Parse due time
    if (widget.bill!['dueTime'] != null) {
      try {
        final timeStr = widget.bill!['dueTime'].toString();
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          int hour = int.parse(parts[0]);
          int minute = int.parse(parts[1]);
          _selectedTime = TimeOfDay(hour: hour, minute: minute);
        }
      } catch (e) {
        debugPrint('Error parsing due time: $e');
        _selectedTime = const TimeOfDay(hour: 9, minute: 0); // Default to 9 AM
      }
    } else {
      // Set default time for new bills
      _selectedTime = const TimeOfDay(hour: 9, minute: 0); // Default to 9 AM
    }

    // Set other fields
    _selectedFrequency = widget.bill!['frequency']?.toString() ?? 'Monthly';
    _selectedReminder = widget.bill!['reminder']?.toString() ?? 'Same day';
    _selectedPaymentMethod = widget.bill!['paymentMethod']?.toString() ?? 'Credit Card';

    // Set category
    if (widget.bill!['category'] != null) {
      final category = Category.findById(widget.bill!['category'].toString());
      if (category != null) {
        _selectedCategory = category;
      }
    }
  }

  void _updateDateController() {
    if (_selectedDate != null) {
      _dueDateController.text = DateFormat('MM/dd/yyyy').format(_selectedDate!);
    } else {
      _dueDateController.text = '';
    }
  }

  void _updateTimeController() {
    if (_selectedTime != null) {
      _dueTimeController.text = _selectedTime!.format(context);
    } else {
      _dueTimeController.text = '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _dueTimeController.dispose();
    _notesController.dispose();
    _paymentMethodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.bill != null && widget.editIndex != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          isEditMode ? 'Edit Bill' : 'Add New Bill',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveBill,
            child: Text(
              'Save',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Basic Information Section
                _buildSectionHeader('Basic Information'),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _nameController,
                  label: 'Bill Name',
                  hint: 'Enter bill name',
                  icon: Icons.receipt,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a bill name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                _buildTextField(
                  controller: _amountController,
                  label: 'Amount',
                  hint: '0.00',
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an amount';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Please enter a valid amount';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Category & Schedule Section
                _buildSectionHeader('Category & Schedule'),
                const SizedBox(height: 16),

                _buildCategorySelector(),
                const SizedBox(height: 16),

                _buildFrequencySelector(),
                const SizedBox(height: 16),

                _buildDateSelector(),
                const SizedBox(height: 16),

                _buildTimeSelector(),

                const SizedBox(height: 24),

                // Additional Details Section
                _buildSectionHeader('Additional Details'),
                const SizedBox(height: 16),

                _buildPaymentMethodSelector(),
                const SizedBox(height: 16),

                _buildReminderSelector(),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _notesController,
                  label: 'Notes',
                  hint: 'Add any notes (optional)',
                  icon: Icons.note,
                  maxLines: 3,
                ),

                const SizedBox(height: 32),

                // Save Button
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveBill,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isEditMode ? 'Update Bill' : 'Add Bill',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.poppins(
        fontSize: 16,
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.grey[400],
        ),
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildCategorySelector() {
    return InkWell(
      onTap: _showCategorySelection,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getCategoryColor(_selectedCategory.id),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _selectedCategory.icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _selectedCategory.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return InkWell(
      onTap: _showFrequencySelection,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.repeat,
                color: Colors.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frequency',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _selectedFrequency,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return TextFormField(
      controller: _dueDateController,
      readOnly: true,
      onTap: _selectDate,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please select a due date';
        }
        return null;
      },
      style: GoogleFonts.poppins(
        fontSize: 16,
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: 'Due Date',
        hintText: 'Select date',
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.grey[400],
        ),
        prefixIcon: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.calendar_today,
            color: Colors.green,
            size: 20,
          ),
        ),
        suffixIcon: Icon(Icons.chevron_right, color: Colors.grey[400]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildTimeSelector() {
    return InkWell(
      onTap: _selectTime,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.access_time,
                color: Colors.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Due Time',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _dueTimeController.text.isEmpty ? 'Select time' : _dueTimeController.text,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _dueTimeController.text.isEmpty ? Colors.grey[400] : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return InkWell(
      onTap: _showPaymentMethodSelection,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.credit_card,
                color: Colors.purple,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Method',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _selectedPaymentMethod,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderSelector() {
    return InkWell(
      onTap: _showReminderSelection,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.notifications,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _selectedReminder,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String? categoryId) {
    switch (categoryId) {
      case 'utilities':
        return Colors.blue;
      case 'entertainment':
        return Colors.purple;
      case 'food':
        return Colors.orange;
      case 'transportation':
        return Colors.green;
      case 'healthcare':
        return Colors.red;
      case 'education':
        return Colors.indigo;
      case 'shopping':
        return Colors.pink;
      case 'insurance':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _updateDateController();
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _updateTimeController();
      });
    }
  }

  void _showCategorySelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Category',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: Category.defaultCategories.length,
                itemBuilder: (context, index) {
                  final category = Category.defaultCategories[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(category.id),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        category.icon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(category.name),
                    trailing: _selectedCategory.id == category.id
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedCategory = category;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFrequencySelection() {
    final frequencies = ['Weekly', 'Bi-weekly', 'Monthly', 'Quarterly', 'Yearly', 'One-time'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Frequency',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...frequencies.map((frequency) => ListTile(
              title: Text(frequency),
              trailing: _selectedFrequency == frequency
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedFrequency = frequency;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showPaymentMethodSelection() {
    final methods = ['Credit Card', 'Debit Card', 'Bank Transfer', 'Cash', 'PayPal', 'Other'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Method',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...methods.map((method) => ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(method),
              trailing: _selectedPaymentMethod == method
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedPaymentMethod = method;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showReminderSelection() {
    final reminders = ['No reminder', 'Same day', '1 day before', '2 days before', '3 days before', '1 week before'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reminder',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...reminders.map((reminder) => ListTile(
              leading: const Icon(Icons.notifications),
              title: Text(reminder),
              trailing: _selectedReminder == reminder
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedReminder = reminder;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  // Check for duplicate bills before saving
  Future<bool> _checkForDuplicateBill() async {
    final billName = _nameController.text.trim().toLowerCase();
    final billAmount = _amountController.text.trim();
    final billCategory = _selectedCategory.id;
    final billDueDate = _selectedDate;

    if (billName.isEmpty || billAmount.isEmpty) return false;

    // Get all existing bills to check for duplicates
    final existingBills = await widget.subscriptionService.getSubscriptions();

    // Check for duplicates (excluding current bill if editing)
    for (final bill in existingBills) {
      // Skip current bill if editing
      if (widget.bill != null &&
          (bill['id'] == widget.bill!['id'] ||
           bill['localId'] == widget.bill!['localId'] ||
           bill['firebaseId'] == widget.bill!['firebaseId'])) {
        continue;
      }

      final existingName = bill['name']?.toString().toLowerCase().trim() ?? '';
      final existingAmount = bill['amount']?.toString() ?? '';
      final existingCategory = bill['category']?.toString();
      final existingDueDate = bill['dueDate'] != null ? DateTime.tryParse(bill['dueDate']) : null;

      // Check if this is a potential duplicate
      bool isDuplicate = false;

      // Exact match: name + amount + category + due date
      if (existingName == billName &&
          existingAmount == billAmount &&
          existingCategory == billCategory &&
          _isSameDay(existingDueDate, billDueDate)) {
        isDuplicate = true;
      }
      // Partial match: name + amount (most common duplicate case)
      else if (existingName == billName && existingAmount == billAmount) {
        isDuplicate = true;
      }
      // Name + category match
      else if (existingName == billName && existingCategory == billCategory) {
        isDuplicate = true;
      }

      if (isDuplicate) {
        // Show duplicate warning dialog
        final shouldContinue = await _showDuplicateWarningDialog(
          existingName,
          existingAmount,
          existingCategory,
          existingDueDate,
        );

        if (shouldContinue == false) {
          return true; // User chose not to continue
        }
      }
    }

    return false; // No duplicates found or user chose to continue
  }

  // Helper method to check if two dates are the same day
  bool _isSameDay(DateTime? date1, DateTime? date2) {
    if (date1 == null || date2 == null) return date1 == null && date2 == null;
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  // Show duplicate warning dialog
  Future<bool?> _showDuplicateWarningDialog(
    String existingName,
    String existingAmount,
    String? existingCategory,
    DateTime? existingDueDate,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Duplicate Bill Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A similar bill already exists:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: $existingName', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('Amount: \$$existingAmount'),
                  if (existingCategory != null)
                    Text('Category: ${existingCategory}'),
                  if (existingDueDate != null)
                    Text('Due Date: ${existingDueDate.month}/${existingDueDate.day}/${existingDueDate.year}'),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Do you want to continue adding this bill anyway?',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text('Continue Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Check for duplicate bills before saving
      final isDuplicate = await _checkForDuplicateBill();
      if (isDuplicate) {
        setState(() {
          _isLoading = false;
        });
        return; // User cancelled due to duplicate
      }

      final billData = {
        'name': _nameController.text.trim(),
        'amount': double.tryParse(_amountController.text) ?? 0.0,
        'category': _selectedCategory.id,
        'frequency': _selectedFrequency,
        'dueDate': _selectedDate?.toIso8601String(),
        'dueTime': _selectedTime?.format(context),
        'reminder': _selectedReminder,
        'paymentMethod': _selectedPaymentMethod,
        'notes': _notesController.text.trim(),
        'status': widget.bill?['status'] ?? 'upcoming',
        'createdAt': widget.bill?['createdAt'] ?? DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Add existing bill ID if editing
      if (widget.bill != null) {
        billData['id'] = widget.bill!['id'];
        billData['firebaseId'] = widget.bill!['firebaseId'];
        billData['localId'] = widget.bill!['localId'];
      }

      widget.onBillSaved(billData, widget.editIndex);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.bill != null ? 'Bill updated successfully!' : 'Bill added successfully!',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Close screen after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving bill: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}