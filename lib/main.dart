import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:maa_messaging/maa_messaging.dart';

import 'firebase_options.dart';
import 'open_street_map.dart';

const navy = Color(0xFF142443);
const blue = Color(0xFF1E91C9);
const teal = Color(0xFF22C6C9);
const orange = Color(0xFFFF702E);
const pale = Color(0xFFF4F7FB);
const okGreen = Color(0xFF29B77B);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MaaSession? session;
  final options = maaFirebaseOptions();
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      session = MaaSession('driver')..start();
      await MaaMessaging.initialize('driver', accent: orange);
    } catch (error) {
      debugPrint('Firebase is not configured yet: $error');
    }
  }
  runApp(MaaDriverApp(session: session));
}

class MaaDriverApp extends StatelessWidget {
  const MaaDriverApp({super.key, required this.session});
  final MaaSession? session;
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: MaaMessaging.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'معًا - السائق',
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: pale,
            colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: orange),
            textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Tajawal'),
            appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white)),
        home: session == null
            ? const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                    body: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                            child: Text(
                                'لم يُربط التطبيق بمشروع Firebase بعد.\nابنِ التطبيق مع قيم FIREBASE_* و MAA_API_URL كما في ملف README.',
                                textAlign: TextAlign.center)))))
            : MaaAuthGate(
                session: session!,
                accent: orange,
                appTitle: 'معًا — تطبيق السائق',
                builder: (_) => MaaUpdateGate(
                    role: 'driver',
                    accent: orange,
                    enabled: true,
                    child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: DriverShell(session: session!)))),
      );
}

Stream<List<Map<String, dynamic>>> myOrders(MaaSession s) => s.db
    .collection('orders')
    .where('driverUid', isEqualTo: s.uid)
    .snapshots()
    .map((q) => maaSortedOrders(q.docs.map((d) => d.data())));

class DriverShell extends StatefulWidget {
  const DriverShell({super.key, required this.session});
  final MaaSession session;
  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int tab = 0;
  late final MaaLocationPublisher publisher = MaaLocationPublisher(widget.session);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _openSub;
  StreamSubscription<List<Map<String, dynamic>>>? _mineSub;
  Timer? _timer;
  Map<String, dynamic>? incoming;
  int secondsLeft = 0;
  bool busy = false;
  List<Map<String, dynamic>> open = [];
  final Set<String> _declined = {};

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _mineSub = myOrders(s).listen((list) {
      busy = list.any((o) => activeOrderStatuses.contains(o['status']));
      if (busy && incoming != null) _dismiss();
    }, onError: (_) {});
    _openSub = s.db.collection('orders').where('driverUid', isEqualTo: '').snapshots().listen((snap) {
      final gov = '${s.profile['governorate'] ?? ''}';
      open = maaSortedOrders(snap.docs.map((d) => d.data()).where((o) =>
          (o['status'] == orderPreparing || o['status'] == orderReady) &&
          (gov.isEmpty || '${o['governorate'] ?? ''}'.isEmpty || o['governorate'] == gov)));
      _maybeAlert();
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  void _maybeAlert() {
    final s = widget.session;
    if (incoming != null || busy || s.profile['online'] != 'متصل') return;
    for (final o in open) {
      if (_declined.contains('${o['id']}')) continue;
      incoming = o;
      secondsLeft = 30;
      MaaMessaging.showLocal('طلب جديد ${o['order']}', '${o['restaurant']} ← ${o['address']}');
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        secondsLeft--;
        if (secondsLeft <= 0) {
          _decline();
        } else if (mounted) {
          setState(() {});
        }
      });
      break;
    }
  }

  void _dismiss() {
    _timer?.cancel();
    incoming = null;
    if (mounted) setState(() {});
  }

  void _decline() {
    if (incoming != null) _declined.add('${incoming!['id']}');
    _dismiss();
    _maybeAlert();
  }

  Future<String?> accept(Map<String, dynamic> o) async {
    final s = widget.session;
    final ref = s.db.collection('orders').doc('${o['id']}');
    try {
      await s.db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null || '${data['driverUid'] ?? ''}'.isNotEmpty) {
          throw Exception('سبقك سائق آخر إلى هذا الطلب.');
        }
        tx.update(ref, {
          'driverUid': s.uid,
          'driverId': s.publicId,
          'driver': s.name,
          'updated': maaNow(),
          'history': maaAppendHistory(data['history'], 'قبل السائق ${s.name} الطلب'),
        });
      });
      await s.profileRef.update({'availability': 'مشغول بطلب'});
      _dismiss();
      if (mounted) setState(() => tab = 0);
      return null;
    } catch (e) {
      _dismiss();
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _openSub?.cancel();
    _mineSub?.cancel();
    publisher.stop();
    widget.session.profileRef.update({'online': 'غير متصل', 'availability': 'غير متاح'}).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      DriverHome(session: s, publisher: publisher, available: open, onAccept: accept, onGoOnline: _maybeAlert),
      DriverEarnings(session: s),
      DriverHistory(session: s),
      DriverProfile(session: s),
    ];
    return Scaffold(
        body: Stack(children: [
          SafeArea(child: IndexedStack(index: tab, children: pages)),
          if (incoming != null)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                    child: _IncomingBanner(
                        order: incoming!,
                        seconds: secondsLeft,
                        onAccept: () async {
                          final err = await accept(incoming!);
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                          }
                        },
                        onDecline: _decline))),
        ]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            indicatorColor: teal.withValues(alpha: .18),
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الطلبات'),
              NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'الأرباح'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'السجل'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'ملفي'),
            ]));
  }
}

/// إشعار علوي بطلب جديد مع عدّاد وقبول/رفض (مثل تطبيقات التوصيل).
class _IncomingBanner extends StatelessWidget {
  const _IncomingBanner({required this.order, required this.seconds, required this.onAccept, required this.onDecline});
  final Map<String, dynamic> order;
  final int seconds;
  final VoidCallback onAccept, onDecline;
  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
          color: Colors.transparent,
          child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(blurRadius: 24, color: Color(0x55000000))]),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.notifications_active, color: orange),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('طلب توصيل جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: navy))),
                  Text('$seconds ث', style: const TextStyle(fontWeight: FontWeight.bold, color: orange)),
                ]),
                const SizedBox(height: 6),
                Text(maaMoney(maaNum(order['deliveryFee'])), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: okGreen)),
                const Text('مقابل التوصيل', style: TextStyle(color: Colors.black54, fontSize: 12)),
                const Divider(),
                Row(children: [const Icon(Icons.storefront, size: 18), const SizedBox(width: 6), Expanded(child: Text('استلام: ${order['restaurant']}'))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.person_pin_circle, size: 18), const SizedBox(width: 6), Expanded(child: Text('تسليم: ${order['address']}'))]),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: seconds / 30, color: orange, backgroundColor: const Color(0xFFFFE0D2)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: onAccept, style: FilledButton.styleFrom(backgroundColor: navy, minimumSize: const Size.fromHeight(48)), child: const Text('قبول'))),
                  const SizedBox(width: 10),
                  OutlinedButton(onPressed: onDecline, style: OutlinedButton.styleFrom(minimumSize: const Size(90, 48), foregroundColor: const Color(0xFFC62828)), child: const Text('رفض')),
                ]),
              ]))));
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, required this.session, required this.publisher, required this.available, required this.onAccept, required this.onGoOnline});
  final MaaSession session;
  final MaaLocationPublisher publisher;
  final List<Map<String, dynamic>> available;
  final Future<String?> Function(Map<String, dynamic>) onAccept;
  final VoidCallback onGoOnline;
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  String? message;

  Future<void> _toggle(bool on) async {
    final s = widget.session;
    if (on) {
      final ok = await widget.publisher.start();
      if (!ok) {
        setState(() => message = 'فعّل خدمة الموقع وامنح التطبيق الإذن لتصبح متاحًا.');
        return;
      }
    } else {
      await widget.publisher.stop();
    }
    setState(() => message = null);
    await s.profileRef.update({
      'online': on ? 'متصل' : 'غير متصل',
      'availability': on ? 'متاح' : 'غير متاح',
      'lastSeen': maaNow(),
    });
    if (on) widget.onGoOnline();
  }

  Future<void> _advance(Map<String, dynamic> o) async {
    final s = widget.session;
    final next = o['status'] == orderDelivering ? orderDone : orderDelivering;
    final patch = <String, dynamic>{
      'status': next,
      'updated': maaNow(),
      'history': maaAppendHistory(o['history'], next == orderDelivering ? 'استلم السائق الطلب من المطعم' : 'تم التسليم للعميل'),
    };
    if (next == orderDone && o['paymentMethod'] == 'نقدًا عند الاستلام') patch['paymentStatus'] = 'مدفوع';
    try {
      await s.db.collection('orders').doc('${o['id']}').update(patch);
      if (next == orderDone) await s.profileRef.update({'availability': 'متاح'});
    } catch (_) {
      if (mounted) setState(() => message = 'تعذر تحديث الطلب.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final online = s.profile['online'] == 'متصل';
          return StreamBuilder<List<Map<String, dynamic>>>(
              stream: myOrders(s),
              builder: (context, mine) {
                final current = (mine.data ?? const <Map<String, dynamic>>[]).where((o) => activeOrderStatuses.contains(o['status'])).toList();
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: current.isEmpty ? const Stream.empty() : s.db.collection('restaurants').doc('${current.first['restaurantUid']}').snapshots(),
                    builder: (context, restSnap) {
                      final rest = restSnap.data?.data();
                      final first = current.isEmpty ? null : current.first;
                      final pickedUp = first != null && first['status'] == orderDelivering;
                      final c = first?['coordinates'];
                      final pins = <MapPin>[
                        if (s.profile['lat'] is num) MapPin((s.profile['lat'] as num).toDouble(), (s.profile['lng'] as num).toDouble(), Icons.delivery_dining, okGreen),
                        if (first != null && !pickedUp && rest != null && rest['lat'] is num) MapPin((rest['lat'] as num).toDouble(), (rest['lng'] as num).toDouble(), Icons.storefront, orange),
                        if (first != null && pickedUp && c is List && c.length == 2) MapPin(maaNum(c[0]).toDouble(), maaNum(c[1]).toDouble(), Icons.person_pin_circle, navy),
                      ];
                      return Scaffold(
                          appBar: AppBar(title: Text('معًا  •  ${s.publicId}'), actions: const [MaaNotificationButton(role: 'driver', accent: orange)]),
                          body: ListView(padding: const EdgeInsets.all(14), children: [
                            OpenStreetMapPreview(height: 250, pins: pins, zoom: 14),
                            const SizedBox(height: 10),
                            Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                                child: Row(children: [
                                  Icon(Icons.circle, color: online ? okGreen : Colors.grey, size: 13),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(online ? 'متصل — تصلك الطلبات الجديدة' : 'غير متاح الآن', style: const TextStyle(fontWeight: FontWeight.bold, color: navy))),
                                  Switch(value: online, activeThumbColor: orange, onChanged: _toggle)
                                ])),
                            if (message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message!, style: const TextStyle(color: Color(0xFFC62828)))),
                            const SizedBox(height: 12),
                            if (first != null)
                              _OrderPanel(session: s, order: first, restaurant: rest, pickedUp: pickedUp, onAdvance: () => _advance(first))
                            else ...[
                              const Text('طلبات متاحة للتوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: navy)),
                              if (!online) const Padding(padding: EdgeInsets.all(14), child: Text('فعّل «متصل» لتستقبل الطلبات.', style: TextStyle(color: Colors.black54))),
                              if (online && widget.available.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('لا توجد طلبات متاحة الآن. سيصلك إشعار عند وصول طلب.', style: TextStyle(color: Colors.black54))),
                              if (online)
                                for (final o in widget.available)
                                  Card(
                                      color: Colors.white,
                                      elevation: 0,
                                      child: ListTile(
                                          title: Text('${o['restaurant']}  •  ${o['order']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: Text('إلى: ${o['address']}\nمقابل التوصيل ${maaMoney(maaNum(o['deliveryFee']))}'),
                                          isThreeLine: true,
                                          trailing: FilledButton(
                                              onPressed: () async {
                                                final err = await widget.onAccept(o);
                                                if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                                              },
                                              style: FilledButton.styleFrom(backgroundColor: orange),
                                              child: const Text('قبول')))),
                            ],
                          ]));
                    });
              });
        });
  }
}

/// تفاصيل الطلب: قبل الاستلام (المطعم + اسم العميل)، وبعده (بيانات العميل كاملة + دردشة).
class _OrderPanel extends StatelessWidget {
  const _OrderPanel({required this.session, required this.order, required this.restaurant, required this.pickedUp, required this.onAdvance});
  final MaaSession session;
  final Map<String, dynamic> order;
  final Map<String, dynamic>? restaurant;
  final bool pickedUp;
  final VoidCallback onAdvance;

  Widget _row(IconData icon, String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 18, color: navy), const SizedBox(width: 8), Expanded(child: Text(text))]));

  @override
  Widget build(BuildContext context) {
    final c = order['coordinates'];
    final hasCustomerPoint = c is List && c.length == 2;
    final hasRestPoint = restaurant != null && restaurant!['lat'] is num;
    return Card(
        color: Colors.white,
        elevation: 0,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(pickedUp ? 'توصيل إلى العميل' : 'التوجه إلى المطعم', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: navy))),
                Text('${order['order']}', style: const TextStyle(color: Colors.black54)),
              ]),
              const Divider(),
              if (!pickedUp) ...[
                _row(Icons.storefront, 'المطعم: ${order['restaurant']}'),
                if ('${restaurant?['address'] ?? ''}'.isNotEmpty) _row(Icons.place, '${restaurant!['address']}'),
                _row(Icons.person_outline, 'العميل: ${order['customer']}'),
                _row(Icons.receipt_long, '${order['items']}'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: hasRestPoint ? () => maaOpenMaps((restaurant!['lat'] as num).toDouble(), (restaurant!['lng'] as num).toDouble()) : null, icon: const Icon(Icons.navigation), label: Text(hasRestPoint ? 'توجه إلى المطعم' : 'موقع المطعم غير محدد'))),
                  if ('${restaurant?['phone'] ?? ''}'.isNotEmpty) ...[const SizedBox(width: 8), IconButton.outlined(onPressed: () => maaCall('${restaurant!['phone']}'), icon: const Icon(Icons.call))],
                ]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: onAdvance, style: FilledButton.styleFrom(backgroundColor: orange, minimumSize: const Size.fromHeight(50)), child: const Text('استلمت الطلب من المطعم'))),
              ] else ...[
                _row(Icons.person, 'العميل: ${order['customer']}'),
                _row(Icons.phone, '${order['customerPhone'] ?? ''}'),
                _row(Icons.place, 'العنوان: ${order['address']}'),
                if ('${order['notes'] ?? ''}'.isNotEmpty) _row(Icons.sticky_note_2_outlined, 'ملاحظات: ${order['notes']}'),
                _row(Icons.receipt_long, '${order['items']}'),
                if (order['paymentMethod'] == 'نقدًا عند الاستلام') _row(Icons.payments_outlined, 'حصّل من العميل: ${maaMoney(maaNum(order['total']))}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: hasCustomerPoint ? () => maaOpenMaps(maaNum(c[0]).toDouble(), maaNum(c[1]).toDouble()) : null, icon: const Icon(Icons.navigation), label: Text(hasCustomerPoint ? 'توجه إلى العميل' : 'لا يوجد موقع محدد')),
                  if ('${order['customerPhone'] ?? ''}'.isNotEmpty) OutlinedButton.icon(onPressed: () => maaCall('${order['customerPhone']}'), icon: const Icon(Icons.call), label: const Text('اتصال')),
                  FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MaaOrderChatPage(session: session, orderId: '${order['id']}', title: 'محادثة مع ${order['customer']}', accent: orange))),
                      style: FilledButton.styleFrom(backgroundColor: navy),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('دردشة العميل')),
                ]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: onAdvance, style: FilledButton.styleFrom(backgroundColor: okGreen, minimumSize: const Size.fromHeight(50)), child: const Text('تم التسليم للعميل'))),
              ],
              TextButton.icon(onPressed: () => maaFileComplaint(context, session, order), icon: const Icon(Icons.report_gmailerrorred, size: 18), label: const Text('تقديم شكوى')),
            ])));
  }
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: navy, fontSize: 17)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))
      ]);
}

class DriverEarnings extends StatelessWidget {
  const DriverEarnings({super.key, required this.session});
  final MaaSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('الأرباح')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: myOrders(session),
          builder: (context, snap) {
            final done = (snap.data ?? const <Map<String, dynamic>>[]).where((o) => o['status'] == orderDone).toList();
            final today = maaNow().substring(0, 10);
            final weekAgo = DateTime.now().subtract(const Duration(days: 7));
            bool inWeek(Map<String, dynamic> o) => (DateTime.tryParse('${o['date']}'.replaceFirst(' ', 'T')) ?? DateTime(2000)).isAfter(weekAgo);
            num sum(Iterable<Map<String, dynamic>> l) => l.fold<num>(0, (n, o) => n + maaNum(o['deliveryFee']));
            final todays = done.where((o) => '${o['date']}'.startsWith(today));
            final week = done.where(inWeek);
            return ListView(padding: const EdgeInsets.all(18), children: [
              Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(22)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('أرباح هذا الأسبوع', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(maaMoney(sum(week)), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                  ])),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: SummaryCard(label: 'أرباح اليوم', value: maaMoney(sum(todays)))),
                const SizedBox(width: 10),
                Expanded(child: SummaryCard(label: 'طلبات الأسبوع', value: '${week.length}'))
              ]),
              const SizedBox(height: 14),
              SummaryCard(label: 'إجمالي الأرباح', value: maaMoney(sum(done))),
              const SizedBox(height: 6),
              const Text('الأرباح = مقابل التوصيل للطلبات المكتملة.', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ]);
          }));
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Center(child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: navy)),
            Text(label, style: const TextStyle(color: Colors.black54))
          ]))));
}

class DriverHistory extends StatelessWidget {
  const DriverHistory({super.key, required this.session});
  final MaaSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('سجل التوصيل')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: myOrders(session),
          builder: (context, snap) {
            final list = (snap.data ?? const <Map<String, dynamic>>[]).where((o) => o['status'] == orderDone || o['status'] == orderCancelled).toList();
            if (list.isEmpty) return const Center(child: Text('لا يوجد سجل بعد.'));
            return ListView(
                padding: const EdgeInsets.all(16),
                children: list
                    .map((o) => Card(
                        color: Colors.white,
                        elevation: 0,
                        child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: o['status'] == orderDone ? const Color(0xFFE5F6EE) : const Color(0xFFFDE8E8),
                                child: Icon(o['status'] == orderDone ? Icons.check : Icons.close, color: o['status'] == orderDone ? okGreen : const Color(0xFFC62828))),
                            title: Text('${o['restaurant']}  •  ${o['order']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${o['date']}'),
                            trailing: Text(maaMoney(maaNum(o['deliveryFee'])), style: const TextStyle(fontWeight: FontWeight.bold, color: navy)))))
                    .toList());
          }));
}

class DriverProfile extends StatelessWidget {
  const DriverProfile({super.key, required this.session});
  final MaaSession session;

  Future<void> _edit(BuildContext context) async {
    final name = TextEditingController(text: session.name);
    final phone = TextEditingController(text: session.phone);
    final vehicle = TextEditingController(text: '${session.profile['vehicle'] ?? ''}');
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('بياناتي'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
                TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'المركبة')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            )));
    if (ok == true) {
      await session.profileRef.update({'name': name.text.trim(), 'phone': phone.text.trim(), 'vehicle': vehicle.text.trim()});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('ملفي')),
          body: ListView(padding: const EdgeInsets.all(18), children: [
            const CircleAvatar(radius: 38, backgroundColor: Color(0xFFDCECF4), child: Icon(Icons.person, size: 42, color: navy)),
            const SizedBox(height: 10),
            Center(child: Text(session.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            Center(child: Text('الرقم التعريفي: ${session.publicId}', style: const TextStyle(color: Colors.black54))),
            const SizedBox(height: 18),
            ProfileRow(icon: Icons.motorcycle, title: 'معلومات المركبة', value: '${session.profile['vehicle'] ?? ''}', onTap: () => _edit(context)),
            ProfileRow(icon: Icons.phone_outlined, title: 'الهاتف', value: session.phone, onTap: () => _edit(context)),
            ProfileRow(icon: Icons.verified_outlined, title: 'المستندات', value: '${session.profile['documents'] ?? ''}', onTap: () {}),
            ProfileRow(icon: Icons.help_outline, title: 'المساعدة والدعم', value: '', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MaaSupportPage(session: session, accent: orange)))),
            ProfileRow(icon: Icons.logout, title: 'تسجيل الخروج', value: '', onTap: session.signOut),
          ])));
}

class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key, required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title, value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(onTap: onTap, leading: Icon(icon, color: navy), title: Text(title), subtitle: value.isEmpty ? null : Text(value), trailing: const Icon(Icons.chevron_left)));
}
