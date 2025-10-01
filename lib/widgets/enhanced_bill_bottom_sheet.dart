import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/services/bottom_sheet_service.dart';

class EnhancedBillBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? bill;
  final Function(Map<String, dynamic>) onSave;
  final Function() onCancel;

  const EnhancedBillBottomSheet({
    Key? key,
    this.bill,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<EnhancedBillBottomSheet> createState() =>
      _EnhancedBillBottomSheetState();
}

class _EnhancedBillBottomSheetState extends State<EnhancedBillBottomSheet>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _reminderController = TextEditingController();

  Category? _selectedCategory;
  String _selectedFrequency = 'Monthly';
  String _selectedReminder = '3 days before';
  bool _isEdit = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _isEdit = widget.bill != null;

    if (_isEdit) {
      _populateForm();
    }

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _animationController.forward();
    _fadeController.forward();
  }

  void _populateForm() {
    if (widget.bill != null) {
      _nameController.text = widget.bill!['name'] ?? '';
      _amountController.text = widget.bill!['amount'] ?? '';
      _dueDateController.text = widget.bill!['dueDate'] ?? '';
      _frequencyController.text = widget.bill!['frequency'] ?? 'Monthly';
      _reminderController.text = widget.bill!['reminder'] ?? '3 days before';
      _selectedFrequency = widget.bill!['frequency'] ?? 'Monthly';
      _selectedReminder = widget.bill!['reminder'] ?? '3 days before';

      final categoryId = widget.bill!['category'];
      if (categoryId != null) {
        _selectedCategory = Category.findById(categoryId);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _frequencyController.dispose();
    _reminderController.dispose();
    super.dispose();
  }

  void _closeBottomSheet() {
    HapticFeedback.lightImpact();
    _animationController.reverse().then((_) {
      _fadeController.reverse().then((_) {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onCancel();
        }
      });
    });
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isLoading = true;
    });

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));

    final billData = {
      'name': _nameController.text,
      'amount': _amountController.text,
      'dueDate': _dueDateController.text,
      'frequency': _selectedFrequency,
      'reminder': _selectedReminder,
      'category': _selectedCategory?.id ?? 'other',
      'status': widget.bill?['status'] ?? 'unpaid',
    };

    if (_isEdit && widget.bill != null) {
      billData['id'] = widget.bill!['id'];
    }

    setState(() {
      _isLoading = false;
    });

    _closeBottomSheet();
    widget.onSave(billData);
  }

  void _showFrequencyBottomSheet() {
    BottomSheetService.showFrequencyBottomSheet(context, _selectedFrequency, (
      frequency,
    ) {
      setState(() {
        _selectedFrequency = frequency;
        _frequencyController.text = frequency;
      });
    });
  }

  void _showReminderBottomSheet() {
    BottomSheetService.showReminderBottomSheet(context, _selectedReminder, (
      reminder,
    ) {
      setState(() {
        _selectedReminder = reminder;
        _reminderController.text = reminder;
      });
    });
  }

  void _showCategoryBottomSheet() {
    BottomSheetService.showCategoryBottomSheet(context, (category) {
      setState(() {
        _selectedCategory = category;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animationController, _fadeController]),
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with cross icon
                  _buildHeader(),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 20,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildNameField(),
                            const SizedBox(height: 16),
                            _buildAmountField(),
                            const SizedBox(height: 16),
                            _buildDueDateField(),
                            const SizedBox(height: 16),
                            _buildCategoryField(),
                            const SizedBox(height: 16),
                            _buildFrequencyField(),
                            const SizedBox(height: 16),
                            _buildReminderField(),
                            const SizedBox(height: 24),
                            _buildActionButtons(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Text(
            _isEdit ? 'Edit Bill' : 'Add Bill',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          // Cross icon
          GestureDetector(
            onTap: _closeBottomSheet,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.close, size: 18, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Bill Name',
        hintText: 'Enter bill name',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter bill name';
        }
        return null;
      },
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      decoration: InputDecoration(
        labelText: 'Amount',
        hintText: '0.00',
        prefixText: '\$ ',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter amount';
        }
        if (double.tryParse(value) == null) {
          return 'Please enter valid amount';
        }
        return null;
      },
    );
  }

  Widget _buildDueDateField() {
    return TextFormField(
      controller: _dueDateController,
      decoration: InputDecoration(
        labelText: 'Due Date',
        hintText: 'Select due date',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
        suffixIcon: const Icon(Icons.calendar_today),
      ),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          setState(() {
            _dueDateController.text = date.toIso8601String().split('T')[0];
          });
        }
      },
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please select due date';
        }
        return null;
      },
    );
  }

  Widget _buildCategoryField() {
    return InkWell(
      onTap: _showCategoryBottomSheet,
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
            Expanded(
              child: Text(
                _selectedCategory?.name ?? 'Select Category',
                style: TextStyle(
                  color: _selectedCategory != null
                      ? Colors.black87
                      : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ),
            if (_selectedCategory != null)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _selectedCategory!.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _selectedCategory!.icon,
                  color: _selectedCategory!.color,
                  size: 14,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyField() {
    return InkWell(
      onTap: _showFrequencyBottomSheet,
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
            Expanded(
              child: Text(
                'Frequency: $_selectedFrequency',
                style: const TextStyle(color: Colors.black87, fontSize: 16),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderField() {
    return InkWell(
      onTap: _showReminderBottomSheet,
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
            Expanded(
              child: Text(
                'Reminder: $_selectedReminder',
                style: const TextStyle(color: Colors.black87, fontSize: 16),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _closeBottomSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[200],
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveBill,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isEdit ? 'Update' : 'Add',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
