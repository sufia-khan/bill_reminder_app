import 'package:flutter/material.dart';
import 'package:projeckt_k/services/sync_notification_service.dart';

class SyncButton extends StatelessWidget {
  final SyncNotificationService syncService;

  const SyncButton({Key? key, required this.syncService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () async {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manual sync triggered...'),
            backgroundColor: Colors.blue,
          ),
        );

        try {
          // Trigger batch sync immediately
          final syncResult = await syncService.triggerImmediateBatchSync();

          // Show result message
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(syncResult
                  ? 'Sync completed successfully!'
                  : 'No pending changes to sync'),
                backgroundColor: syncResult ? Colors.green : Colors.blue,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sync failed: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      child: const Icon(Icons.sync),
      tooltip: 'Sync Now',
    );
  }
}