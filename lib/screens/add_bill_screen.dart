import 'package:flutter/material.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/dialog_service.dart';
import 'package:intl/intl.dart';

class AddBillScreen extends StatefulWidget {
  final Map<String, dynamic>? existingBill;
  final Function(Map<String, dynamic>)? onBillAdded;

  const AddBillScreen({
    super.key,
    this.existingBill,
    this.onBillAdded,
  });

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subscriptionService = SubscriptionService();

  bool _isLoading = false;
  bool _isEditing = false;

  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _dueDateController;
  late String _selectedCategory;
  late String _selectedFrequency;
  late String _selectedReminder;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingBill != null;

    _nameController = TextEditingController(text: widget.existingBill?['name'] ?? '');
    _amountController = TextEditingController(text: widget.existingBill?['amount']?.toString() ?? '');
    _dueDateController = TextEditingController(text: widget.existingBill?['dueDate'] ?? '');
    _selectedCategory = widget.existingBill?['category'] ?? 'other';
    _selectedFrequency = widget.existingBill?['frequency'] ?? 'monthly';
    _selectedReminder = widget.existingBill?['reminder'] ?? 'same day';
    _selectedStatus = widget.existingBill?['status'] ?? 'upcoming';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDateController.text.isNotEmpty
          ? DateTime.tryParse(_dueDateController.text) ?? DateTime.now()
          : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 2),
    );

    if (picked != null) {
      setState(() {
        _dueDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _saveBill() async {
    // Manual validation for due date since it's a read-only field
    if (_dueDateController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Due date is required'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validate form and show errors
    if (!_formKey.currentState!.validate()) {
      // Shake animation to indicate validation errors
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields marked with *'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final billData = {
        'name': _nameController.text.trim(),
        'amount': double.tryParse(_amountController.text) ?? 0.0,
        'dueDate': _dueDateController.text,
        'category': _selectedCategory,
        'frequency': _selectedFrequency,
        'reminder': _selectedReminder,
        'status': _selectedStatus,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (_isEditing && widget.existingBill != null) {
        // Update existing bill
        final billId = widget.existingBill!['id'] ?? '';
        if (billId.isNotEmpty) {
          await _subscriptionService.updateSubscription(billId, billData);
        }
      } else {
        // Add new bill
        await _subscriptionService.addSubscription(billData);
      }

      // Call callback if provided
      widget.onBillAdded?.call(billData);

      if (mounted) {
        DialogService.showSuccessSnackBar(
          context,
          _isEditing ? 'Bill updated successfully!' : 'Bill added successfully!',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to ${_isEditing ? 'update' : 'add'} bill. Please try again.';

        // Check for specific duplicate error
        if (e.toString().contains('already exists')) {
          errorMessage = 'A bill with the same name, amount, and due date already exists.';
        }

        DialogService.showErrorSnackBar(
          context,
          errorMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Bill' : 'Add New Bill'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Bill Name *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.description),
                  hintText: 'Enter bill name',
                  errorStyle: const TextStyle(color: Colors.red),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bill name is required';
                  }
                  if (value.trim().length < 2) {
                    return 'Bill name must be at least 2 characters';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 16),

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.attach_money),
                  hintText: 'Enter amount',
                  errorStyle: const TextStyle(color: Colors.red),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid amount';
                  }
                  final amount = double.tryParse(value);
                  if (amount != null && amount <= 0) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 16),

              // Due Date Field
              TextFormField(
                controller: _dueDateController,
                decoration: InputDecoration(
                  labelText: 'Due Date *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.calendar_today),
                  hintText: 'Select due date',
                  errorStyle: const TextStyle(color: Colors.red),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
                readOnly: true,
                onTap: _selectDueDate,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Due date is required';
                  }
                  try {
                    final selectedDate = DateTime.parse(value);
                    if (selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
                      return 'Due date cannot be in the past';
                    }
                  } catch (e) {
                    return 'Please select a valid due date';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.category),
                ),
                items: Category.defaultCategories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category.id,
                    child: Row(
                      children: [
                        Icon(category.icon, size: 20, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Text(category.name),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Frequency Dropdown
              DropdownButtonFormField<String>(
                value: _selectedFrequency,
                decoration: InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.repeat),
                ),
                items: const [
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'bi-weekly', child: Text('Bi-Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  DropdownMenuItem(value: 'one-time', child: Text('One Time')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedFrequency = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Status Dropdown (only for editing)
              if (_isEditing)
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.info),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
                    DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
                    DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    }
                  },
                ),
              if (_isEditing) const SizedBox(height: 16),

              // Reminder Dropdown
              DropdownButtonFormField<String>(
                value: _selectedReminder,
                decoration: InputDecoration(
                  labelText: 'Reminder',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.notifications),
                ),
                items: const [
                  DropdownMenuItem(value: 'same day', child: Text('Same day')),
                  DropdownMenuItem(value: '1 day before', child: Text('1 day before')),
                  DropdownMenuItem(value: '2 days before', child: Text('2 days before')),
                  DropdownMenuItem(value: '3 days before', child: Text('3 days before')),
                  DropdownMenuItem(value: '5 days before', child: Text('5 days before')),
                  DropdownMenuItem(value: '1 week before', child: Text('1 week before')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedReminder = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 32),

              // Save Button
              ElevatedButton(
                onPressed: _isLoading ? null : _saveBill,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
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
                          const SizedBox(width: 12),
                          Text(_isEditing ? 'Updating...' : 'Adding...'),
                        ],
                      )
                    : Text(_isEditing ? 'Update Bill' : 'Add Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}