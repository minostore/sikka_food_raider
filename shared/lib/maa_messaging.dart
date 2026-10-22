import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:cloud_firestore/cloud_firestore.dart';
export 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
export 'maa_auth_ui.dart';
export 'maa_core.dart';
export 'maa_support.dart';
export 'maa_location.dart';
export 'maa_widgets.dart';

const _roles = {'customer', 'driver', 'restaurant'};

class MaaMessaging {
  MaaMessaging._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static bool _initialized = false;
  static String? _role;
  static Color? _accent;
  static bool _pendingInbox = false;

  static Future<void> initialize(String role, {required Color accent}) async {
    if (!_roles.contains(role) || _initialized) return;
    _role = role;
    _accent = accent;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    try {
      await _local.initialize(settings);
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'maa_announcements',
              'إشعارات معًا',
              description: 'إشعارات الطلبات والإعلانات وتحديثات التطبيق',
              importance: Importance.high,
            ),
          );
    } catch (error) {
      debugPrint('Local notifications are not ready: $error');
    }

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: true,
      );
    } catch (error) {
      debugPrint('Notification permission is not ready: $error');
    }
    for (final topic in ['all_apps', 'app_$role']) {
      try {
        await messaging.subscribeToTopic(topic);
      } catch (error) {
        debugPrint('Could not subscribe to FCM topic $topic: $error');
      }
    }
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openInbox());
    try {
      if (await messaging.getInitialMessage() != null) _pendingInbox = true;
    } catch (error) {
      debugPrint('Could not inspect the launch notification: $error');
    }
    _initialized = true;
  }

  /// إشعار محلي فوري (مثل: وصول طلب جديد للمطعم أثناء فتح التطبيق).
  static Future<void> showLocal(String title, String body) async {
    try {
      await _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'maa_announcements',
            'إشعارات معًا',
            channelDescription: 'إشعارات الطلبات والإعلانات وتحديثات التطبيق',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
        ),
      );
    } catch (error) {
      debugPrint('Local notification failed: $error');
    }
  }

  static void openPendingInbox() {
    if (_pendingInbox) _openInbox();
  }

  static void _openInbox() {
    final navigator = navigatorKey.currentState;
    final role = _role;
    final accent = _accent;
    if (navigator == null || role == null || accent == null) {
      _pendingInbox = true;
      return;
    }
    _pendingInbox = false;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => MaaInboxPage(role: role, accent: accent),
    ));
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'معًا';
    final body =
        message.notification?.body ?? message.data['description'] ?? '';
    await _local.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'maa_announcements',
          'إشعارات معًا',
          channelDescription: 'إشعارات الطلبات والإعلانات وتحديثات التطبيق',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> loadInbox(String role) async {
    if (!_roles.contains(role)) return const [];
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      // شرط واحد فقط (بدون فهرس مركّب)، والتصفية والترتيب يتمان هنا
      db
          .collection('broadcastMessages')
          .where('audienceIds', arrayContains: role)
          .limit(100)
          .get(),
      db
          .collection('appUpdates')
          .where('audienceIds', arrayContains: role)
          .limit(60)
          .get(),
    ]);
    final messages = <Map<String, dynamic>>[];
    for (final document in results[0].docs.where((d) => d.data()['published'] == true && d.data()['inAppEnabled'] == true)) {
      messages.add({
        'id': document.id,
        'kind': 'notification',
        ...document.data(),
      });
    }
    for (final document in results[1].docs.where((d) => d.data()['published'] == true)) {
      messages.add({
        'id': document.id,
        'kind': 'appUpdate',
        ...document.data(),
      });
    }
    messages.sort(
      (a, b) => _date(b['createdAt']).compareTo(_date(a['createdAt'])),
    );
    return messages;
  }

  static Future<void> showUpdateIfNeeded({
    required BuildContext context,
    required String role,
    required Color accent,
  }) async {
    if (!_roles.contains(role)) return;
    try {
      final latest = await FirebaseFirestore.instance
          .collection('appUpdates')
          .where('audienceIds', arrayContains: role)
          .limit(30)
          .get();
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final updates = (latest.docs.map((document) => document.data()).where((u) => u['published'] == true).toList()
        ..sort((a, b) => _date(b['createdAt']).compareTo(_date(a['createdAt']))))
        .where((
        update,
      ) {
        final targetBuild = _number(update['minBuildNumber']);
        return targetBuild > currentBuild;
      }).toList();
      if (updates.isEmpty || !context.mounted) return;
      final update = updates.first;
      final mandatory = update['mandatory'] == true;
      final versionKey = _number(update['minBuildNumber']);
      final preferences = await SharedPreferences.getInstance();
      if (!mandatory &&
          preferences.getInt('maa_dismissed_update_$role') == versionKey)
        return;
      if (!context.mounted) return;
      final storeUrl = Platform.isIOS
          ? update['iosStoreUrl']?.toString()
          : update['androidStoreUrl']?.toString();
      final uri = storeUrl == null ? null : Uri.tryParse(storeUrl);

      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (dialogContext) => PopScope(
          canPop: !mandatory,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: CircleAvatar(
              radius: 30,
              backgroundColor: accent.withValues(alpha: .13),
              child: Text('م',
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 28)),
            ),
            title: Text(
              update['title']?.toString() ?? 'تحديث جديد لتطبيق معًا',
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((update['imageUrl'] ?? '').toString().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        update['imageUrl'].toString(),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    update['description']?.toString() ?? '',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الإصدار ${update['versionName'] ?? ''}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (mandatory)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'هذا التحديث مطلوب لمتابعة استخدام التطبيق.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              if (!mandatory)
                TextButton(
                  onPressed: () async {
                    await preferences.setInt(
                      'maa_dismissed_update_$role',
                      versionKey,
                    );
                    if (dialogContext.mounted)
                      Navigator.of(dialogContext).pop();
                  },
                  child: const Text('لاحقًا'),
                ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: uri == null || !uri.hasScheme
                    ? null
                    : () =>
                        launchUrl(uri, mode: LaunchMode.externalApplication),
                child: const Text('التحديث الآن'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      debugPrint('Maa update check skipped: $error');
    }
  }
}

class MaaUpdateGate extends StatefulWidget {
  const MaaUpdateGate({
    super.key,
    required this.role,
    required this.accent,
    required this.enabled,
    required this.child,
  });
  final String role;
  final Color accent;
  final bool enabled;
  final Widget child;

  @override
  State<MaaUpdateGate> createState() => _MaaUpdateGateState();
}

class _MaaUpdateGateState extends State<MaaUpdateGate> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MaaMessaging.openPendingInbox();
        MaaMessaging.showUpdateIfNeeded(
          context: context,
          role: widget.role,
          accent: widget.accent,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MaaNotificationButton extends StatelessWidget {
  const MaaNotificationButton({
    super.key,
    required this.role,
    required this.accent,
  });
  final String role;
  final Color accent;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'الإشعارات والتحديثات',
        icon: Icon(Icons.notifications_none, color: accent),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MaaInboxPage(role: role, accent: accent),
          ),
        ),
      );
}

class MaaInboxPage extends StatefulWidget {
  const MaaInboxPage({super.key, required this.role, required this.accent});
  final String role;
  final Color accent;

  @override
  State<MaaInboxPage> createState() => _MaaInboxPageState();
}

class _MaaInboxPageState extends State<MaaInboxPage> {
  late Future<List<Map<String, dynamic>>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = MaaMessaging.loadInbox(widget.role);
  }

  Future<void> _refresh() async {
    final next = MaaMessaging.loadInbox(widget.role);
    setState(() => _messages = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإشعارات والتحديثات')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _messages,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذر تحميل الرسائل. تأكد من إعداد Firebase والاتصال بالإنترنت.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final messages = snapshot.data ?? const [];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: messages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 180),
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 52,
                          color: Colors.black38,
                        ),
                        SizedBox(height: 12),
                        Center(child: Text('لا توجد إشعارات جديدة')),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _MessageCard(
                        message: messages[index],
                        accent: widget.accent,
                      ),
                    ),
            );
          },
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.accent});
  final Map<String, dynamic> message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final update = message['kind'] == 'appUpdate';
    final mandatory = message['mandatory'] == true;
    final imageUrl = message['imageUrl']?.toString() ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(height: 8),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: accent.withValues(alpha: .13),
                      child: Icon(
                        update
                            ? Icons.system_update_alt
                            : Icons.notifications_active_outlined,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message['title']?.toString() ??
                            (update ? 'تحديث تطبيق' : 'إشعار'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (update)
                      Chip(
                        label: Text(mandatory ? 'إجباري' : 'اختياري'),
                        backgroundColor: mandatory
                            ? const Color(0xFFFFECE8)
                            : const Color(0xFFE9F6EF),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  message['description']?.toString() ?? '',
                  style: const TextStyle(height: 1.5),
                ),
                if (update &&
                    (message['versionName'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'الإصدار ${message['versionName']}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _formatDate(message['createdAt']),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
DateTime _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
        ? value
        : DateTime.fromMillisecondsSinceEpoch(0);
String _formatDate(dynamic value) {
  final date = _date(value).toLocal();
  if (date.millisecondsSinceEpoch == 0) return '';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
