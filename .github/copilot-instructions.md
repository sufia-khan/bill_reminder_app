# Copilot instructions for projeckt_k (Flutter + Firebase, offline-first)

This is a Flutter mobile app using Firebase Auth/Firestore with a strict offline-first data layer. Use these notes to follow the project’s patterns, avoid common pitfalls, and stay efficient.

## Big picture
- App entry: `lib/main.dart` initializes Firebase (`AuthService.initializeFirebase()`), creates a process-wide `SyncNotificationService`, and routes `AuthWrapper → MainNavigationWrapper`.
- Navigation: `lib/widgets/main_navigation_wrapper.dart` builds a custom bottom nav with a centered Add action. It holds a `GlobalKey<HomeScreenState>` to open Home’s add-bill bottom sheet from the nav.
- Screens: `lib/screens/` (notably `home_screen.dart`, `all_bills_screen.dart`, `analytics_screen.dart`, `settings_screen.dart`). Home displays stats, category tabs, and bill lists, and owns edit/mark-as-paid/delete flows.
- Services:
  - `AuthService`: wraps Firebase Auth and exposes `authStateChanges`.
  - `SubscriptionService`: Firestore + SharedPreferences cache for subscriptions. CRUD is offline-first and merges local + remote.
  - `LocalStorageService`: JSON store with `subscriptions[]`, each item has `localId` (and optional `firebaseId`), and `last_sync`.
  - `SyncNotificationService`: listens to connectivity, verifies true online via Firestore calls, triggers sync, and shows SnackBars when a context is set.
- Model: `Category` (`lib/models/category_model.dart`) centralizes icon/color palettes for UI consistency.

## Data & offline-first rules
- Firestore path: `users/{uid}/subscriptions`. On write, set `createdAt` and `updatedAt` to `FieldValue.serverTimestamp()`.
- Local storage: keep an array under key `subscriptions`. Items have a `localId`; when synced, a `firebaseId` is attached. Tag `source` as `local` or `firebase` when merging.
- Reads: `SubscriptionService.getSubscriptions()` fetches Firestore (when available) and merges in unsynced local items.
- Writes: add/update/delete try Firestore first, then mirror locally. On network failure, apply the local change and throw a friendly “Offline mode…” exception so UI can show a SnackBar.
- Sync: `SubscriptionService.syncLocalToFirebase()` pushes unsynced (no `firebaseId`), marks them synced, and updates `last_sync`.

## UI patterns (Home)
- Theming: Material 3 with blue seed in `main.dart`. Use subtle spacing (8–16 px) and rounded corners (12–20 px). Prefer HSL-based blue for accents used in nav and headers.
- Stats cards (top of Home): two white, elevated cards for “This Month” and “Next 7 Days” with clean typography—no grey (“ash”) backgrounds. Values and diffs are computed in `home_screen.dart`.
- Sensitive actions:
  - “Mark as paid” always shows a confirm dialog; on success, update local state immediately and then sync.
  - “Edit” opens a bottom sheet prefilled with the bill; apply changes instantly to UI and attempt remote update, falling back to local with an offline SnackBar.
  - Delete uses `Dismissible` + confirm dialog; mirror the offline-first flow.
- Add flow: `HomeScreenState.showAddBillBottomSheet(context)` for the create form; reflect locally first; show “saved locally, will sync” when offline.

## Connectivity & sync notifications
- Always update `SyncNotificationService` with the current BuildContext in `didChangeDependencies` (done in `AuthWrapper` and `MainNavigationWrapper`).
- On reconnect, call `SubscriptionService.syncLocalToFirebase()` and show “Syncing…” → “Synced” SnackBars via `SyncNotificationService`.
- Connectivity checks use `connectivity_plus` first; a lightweight Firestore ping confirms true online before sync.

## Performance: minimize Firebase reads/writes
- Do not touch Firebase at import time. Keep all initialization lazy and guarded.
- Prefer local state updates immediately; rely on background sync when online. Avoid extra reads—reuse results from `getSubscriptions()` in the current view rather than requerying.
- Only trigger sync on meaningful events (app resume, tab change, explicit user action, or connectivity regained)—not on every small change.

## Testing & local dev
- Commands:
  - `flutter pub get`
  - `flutter analyze`
  - `flutter test -r compact`
- Widget tests should avoid bootstrapping Firebase. Prefer isolated widgets and screens that don’t require Auth.
- If you must build `MainNavigationWrapper`, pass a `SyncNotificationService`:
  - Example: `MainNavigationWrapper(syncService: SyncNotificationService())`
- Don’t create code that performs Firestore calls during import or test setup. Keep `SyncNotificationService` safe to construct in tests.

## Key files to study
- App setup: `lib/main.dart`
- Navigation: `lib/widgets/main_navigation_wrapper.dart`
- Home & flows: `lib/screens/home_screen.dart`
- Offline core: `lib/services/subscription_service.dart`, `lib/services/local_storage_service.dart`
- Sync UX: `lib/services/sync_notification_service.dart`

## Quality gates after any code change
- Always check inline editor diagnostics (squiggles) and fix errors immediately before proceeding.
- Run `flutter analyze` and address all issues relevant to your change.
- Run fast tests: `flutter test -r compact` (or the focused file).
- If you modify navigation/context usage, verify `SyncNotificationService.setContext` is still called in `AuthWrapper`/`MainNavigationWrapper`.

Questions or unclear patterns? Open an issue and reference specific files. Mirror existing choices for timestamps, IDs, SnackBars, and bottom sheets for a consistent experience.
