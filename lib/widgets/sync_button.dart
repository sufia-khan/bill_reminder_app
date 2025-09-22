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
        await syncService.immediateSync();
      },
      child: const Icon(Icons.sync),
      tooltip: 'Sync Now',
    );
  }
}