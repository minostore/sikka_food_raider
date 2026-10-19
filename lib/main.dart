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

  @override
  void dispose() {
    publisher.stop();
    // يُصبح السائق غير متصل عند إغلاق التطبيق قدر الإمكان
    widget.session.profileRef
        .update({'online': 'غير متصل', 'availability': 'غير متاح'}).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      DriverHome(session: s, publisher: publisher),
      DriverEarnings(session: s),
      DriverHistory(session: s),
      DriverProfile(session: s),
    ];
    return Scaffold(
        body: SafeArea(child: IndexedStack(index: tab, children: pages)),
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

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, required this.session, required this.publisher});
  final MaaSession session;
  final MaaLocationPublisher publisher;
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
  }

  Future<void> _accept(Map<String, dynamic> o) async {
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
    } catch (e) {
      if (mounted) setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _advance(Map<String, dynamic> o) async {
    final s = widget.session;
    final next = o['status'] == orderReady ? orderDelivering : orderDone;
    final patch = <String, dynamic>{
      'status': next,
      'updated': maaNow(),
      'history': maaAppendHistory(o['history'], next == orderDelivering ? 'استلم السائق الطلب' : 'تم التسليم للعميل'),
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
          final available = s.profile['online'] == 'متصل';
          return Scaffold(
              appBar: AppBar(title: Text('معًا  •  ${s.publicId}'), actions: const [MaaNotificationButton(role: 'driver', accent: orange)]),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Icon(Icons.circle, color: available ? okGreen : Colors.grey, size: 13),
                      const SizedBox(width: 8),
                      Expanded(child: Text(available ? 'متصل — يُرسل موقعك للإدارة' : 'غير متاح الآن', style: const TextStyle(fontWeight: FontWeight.bold, color: navy))),
                      Switch(value: available, activeThumbColor: orange, onChanged: _toggle)
                    ])),
                if (message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message!, style: const TextStyle(color: Color(0xFFC62828)))),
                const SizedBox(height: 14),
                StreamBuilder<List<Map<String, dynamic>>>(
                    stream: myOrders(s),
                    builder: (context, mine) {
                      final current = (mine.data ?? const <Map<String, dynamic>>[]).where((o) => activeOrderStatuses.contains(o['status'])).toList();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(current.isEmpty ? 'لا يوجد طلب حالي' : 'طلباتي الحالية', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: navy)),
                        ...current.map((o) => _CurrentOrder(session: s, order: o, onAdvance: () => _advance(o))),
                        const SizedBox(height: 16),
                        const Text('طلبات متاحة للتوصيل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: navy)),
                        if (!available) const Padding(padding: EdgeInsets.all(14), child: Text('فعّل «متصل» لترى الطلبات المتاحة.', style: TextStyle(color: Colors.black54))),
                        if (available)
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: s.db.collection('orders').where('driverUid', isEqualTo: '').snapshots(),
                              builder: (context, open) {
                                if (open.hasError) return const Padding(padding: EdgeInsets.all(14), child: Text('تعذر تحميل الطلبات المتاحة.'));
                                final list = maaSortedOrders((open.data?.docs ?? []).map((d) => d.data()).where((o) => o['status'] == orderPreparing || o['status'] == orderReady));
                                if (list.isEmpty) return const Padding(padding: EdgeInsets.all(14), child: Text('لا توجد طلبات متاحة الآن.', style: TextStyle(color: Colors.black54)));
                                return Column(
                                    children: list
                                        .map((o) => Card(
                                            color: Colors.white,
                                            elevation: 0,
                                            child: Padding(
                                                padding: const EdgeInsets.all(15),
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text('${o['restaurant']}  •  ${o['order']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                                  Text('إلى: ${o['address']}'),
                                                  Text('الحالة: ${o['status']}'),
                                                  const Divider(),
                                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                                    Metric(label: 'مقابل التوصيل', value: maaMoney(maaNum(o['deliveryFee']))),
                                                    Metric(label: 'قيمة الطلب', value: maaMoney(maaNum(o['total']))),
                                                  ]),
                                                  const SizedBox(height: 10),
                                                  SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _accept(o), style: FilledButton.styleFrom(backgroundColor: orange), child: const Text('قبول الطلب'))),
                                                ]))))
                                        .toList());
                              }),
                      ]);
                    }),
              ]));
        });
  }
}

class _CurrentOrder extends StatelessWidget {
  const _CurrentOrder({required this.session, required this.order, required this.onAdvance});
  final MaaSession session;
  final Map<String, dynamic> order;
  final VoidCallback onAdvance;
  @override
  Widget build(BuildContext context) {
    final status = '${order['status']}';
    final coords = order['coordinates'];
    final label = status == orderReady ? 'تم استلام الطلب من المطعم' : status == orderDelivering ? 'تم التسليم للعميل' : null;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: session.db.collection('restaurants').doc('${order['restaurantUid']}').snapshots(),
        builder: (context, snap) {
          final r = snap.data?.data();
          final me = session.profile;
          final pins = <MapPin>[
            if (coords is List && coords.length == 2) MapPin(maaNum(coords[0]).toDouble(), maaNum(coords[1]).toDouble(), Icons.home, orange),
            if (r != null && r['lat'] is num) MapPin((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble(), Icons.restaurant, navy),
            if (me['lat'] is num) MapPin((me['lat'] as num).toDouble(), (me['lng'] as num).toDouble(), Icons.delivery_dining, okGreen),
          ];
          return Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (pins.isNotEmpty) ...[OpenStreetMapPreview(height: 170, pins: pins), const SizedBox(height: 10)],
                    Text('${order['restaurant']}  •  ${order['order']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('المطعم: ${r?['address'] ?? ''}  ${r?['phone'] ?? ''}'),
                    Text('العميل: ${order['customer']}  ${order['customerPhone'] ?? ''}'),
                    Text('العنوان: ${order['address']}'),
                    Text('الطلب: ${order['items']}'),
                    Text('الحالة: $status', style: const TextStyle(fontWeight: FontWeight.bold, color: orange)),
                    if (order['paymentMethod'] == 'نقدًا عند الاستلام') Text('حصّل من العميل: ${maaMoney(maaNum(order['total']))}'),
                    const SizedBox(height: 8),
                    if (label != null) SizedBox(width: double.infinity, child: FilledButton(onPressed: onAdvance, style: FilledButton.styleFrom(backgroundColor: orange), child: Text(label)))
                    else const Text('بانتظار أن يجهّز المطعم الطلب…', style: TextStyle(color: Colors.black54)),
                  ])));
        });
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
