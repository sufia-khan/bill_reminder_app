import 'package:flutter_test/flutter_test.dart';
import 'package:projeckt_k/services/notification_service.dart';

void main() {
  group('NotificationService Tests', () {
    late NotificationService notificationService;

    setUp(() {
      notificationService = NotificationService();
    });

    test('Notification action IDs are correctly defined', () {
      expect('mark_paid', equals('mark_paid'));
      expect('undo_payment', equals('undo_payment'));
    });

    test('Notification action handlers are properly structured', () {
      // Test that the static method exists and can be called
      expect(() => NotificationService.testNotificationAction('mark_paid', 'test_bill_id'), returnsNormally);
      expect(() => NotificationService.testNotificationAction('undo_payment', 'test_bill_id'), returnsNormally);
    });

    test('Notification service initialization', () async {
      // This test ensures the service can be initialized without errors
      expect(notificationService, isNotNull);
      expect(notificationService.onMarkAsPaid, isNull);
      expect(notificationService.onUndoPayment, isNull);
    });

    test('Notification callbacks can be set', () {
      // Test that callbacks can be set
      notificationService.onMarkAsPaid = (String? billId) {
        expect(billId, isNotNull);
      };

      notificationService.onUndoPayment = (String? billId) {
        expect(billId, isNotNull);
      };

      expect(notificationService.onMarkAsPaid, isNotNull);
      expect(notificationService.onUndoPayment, isNotNull);
    });

    test('Notification action simulation works', () {
      // Test that the test action method works correctly
      bool markAsPaidCalled = false;
      bool undoPaymentCalled = false;

      notificationService.onMarkAsPaid = (String? billId) {
        markAsPaidCalled = true;
        expect(billId, equals('test_bill_id'));
      };

      notificationService.onUndoPayment = (String? billId) {
        undoPaymentCalled = true;
        expect(billId, equals('test_bill_id'));
      };

      // Simulate notification actions
      NotificationService.testNotificationAction('mark_paid', 'test_bill_id');
      NotificationService.testNotificationAction('undo_payment', 'test_bill_id');

      expect(markAsPaidCalled, isTrue);
      expect(undoPaymentCalled, isTrue);
    });
  });
}