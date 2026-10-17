import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:maa_messaging/maa_messaging.dart';

import 'firebase_options.dart';
import 'open_street_map.dart';

const navy = Color(0xFF142443);
const blue = Color(0xFF1E91C9);
const teal = Color(0xFF22C6C9);
const orange = Color(0xFFFF702E);
const pale = Color(0xFFF4F7FB);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  final options = maaFirebaseOptions();
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      firebaseReady = true;
      await MaaMessaging.initialize('driver', accent: orange);
    } catch (error) {
      debugPrint('Firebase is not configured yet: $error');
    }
  }
  runApp(MaaDriverApp(firebaseReady: firebaseReady));
}

class MaaDriverApp extends StatelessWidget {
  const MaaDriverApp({super.key, required this.firebaseReady});
  final bool firebaseReady;
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
            colorScheme: ColorScheme.fromSeed(
                seedColor: navy, primary: navy, secondary: orange),
            textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Tajawal'),
            appBarTheme: const AppBarTheme(
                backgroundColor: navy, foregroundColor: Colors.white)),
        home: MaaUpdateGate(
            role: 'driver',
            accent: orange,
            enabled: firebaseReady,
            child: const Directionality(
                textDirection: TextDirection.rtl, child: DriverShell())),
      );
}

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});
  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int tab = 0;
  bool available = true;
  bool accepted = false;
  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHome(
          available: available,
          accepted: accepted,
          onToggle: (v) => setState(() => available = v),
          onAccept: () => setState(() => accepted = true)),
      const DriverEarnings(),
      const DriverHistory(),
      const DriverProfile(),
    ];
    return Scaffold(
        body: SafeArea(child: IndexedStack(index: tab, children: pages)),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            indicatorColor: teal.withValues(alpha: .18),
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'موقعي'),
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'الأرباح'),
              NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'الطلبات'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'ملفي'),
            ]));
  }
}

class DriverHome extends StatelessWidget {
  const DriverHome(
      {super.key,
      required this.available,
      required this.accepted,
      required this.onToggle,
      required this.onAccept});
  final bool available, accepted;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAccept;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('معًا  •  السائق'), actions: [
        const MaaNotificationButton(role: 'driver', accent: orange)
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.circle,
                  color: available ? const Color(0xFF29B77B) : Colors.grey,
                  size: 13),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      available ? 'متاح لاستقبال الطلبات' : 'غير متاح الآن',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: navy))),
              Switch(
                  value: available,
                  activeThumbColor: orange,
                  onChanged: onToggle)
            ])),
        const SizedBox(height: 14),
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: navy, borderRadius: BorderRadius.circular(22)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('أرباح اليوم',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              const Text('125.50 ج.م',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 18),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Metric(label: 'الطلبات', value: '5'),
                    Metric(label: 'ساعات', value: '2.5'),
                    Metric(label: 'التقييم', value: '4.9')
                  ])
            ])),
        const SizedBox(height: 14),
        const OpenStreetMapPreview(height: 205),
        const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
                'خريطة تجريبية للقاهرة — علامات السائق والمطعم ثابتة وليست مواقع حية.',
                style: TextStyle(color: Colors.black54, fontSize: 12))),
        const SizedBox(height: 16),
        Text(accepted ? 'تم قبول الطلب' : 'طلب توصيل جديد',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: navy)),
        Card(
            color: Colors.white,
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('مطعم بيت الشامي',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Text('شارع النصر، المعادي، القاهرة  •  2.3 كم'),
                      const Divider(),
                      const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Metric(label: 'الوقت المتوقع', value: '25 دقيقة'),
                            Metric(label: 'مقابل التوصيل', value: '15 ج.م')
                          ]),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: accepted ? null : onAccept,
                              style: FilledButton.styleFrom(
                                  backgroundColor: orange),
                              child: Text(accepted
                                  ? 'في طريقك للمطعم'
                                  : 'قبول الطلب'))),
                      OutlinedButton(
                          onPressed: () {},
                          child: const SizedBox(
                              width: double.infinity,
                              child: Center(child: Text('رفض الطلب'))))
                    ]))),
      ]));
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w900, color: navy, fontSize: 17)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))
      ]);
}

class DriverEarnings extends StatelessWidget {
  const DriverEarnings({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('الأرباح')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: navy, borderRadius: BorderRadius.circular(22)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إجمالي الأرباح هذا الأسبوع',
                      style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 8),
                  Text('892.50 ج.م',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 18),
                  Text('الأحد  الاثنين  الثلاثاء  الأربعاء  الخميس  الجمعة',
                      style: TextStyle(color: Colors.white70))
                ])),
        const SizedBox(height: 18),
        const Row(children: [
          Expanded(child: SummaryCard(label: 'عدد الطلبات', value: '48')),
          SizedBox(width: 10),
          Expanded(child: SummaryCard(label: 'ساعات العمل', value: '18.6'))
        ]),
        const SizedBox(height: 14),
        const SummaryCard(label: 'متوسط التقييم', value: '4.8 ★'),
        const SizedBox(height: 18),
        const Text('ملخص الأرباح',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const ListTile(
            leading: Icon(Icons.bolt, color: orange),
            title: Text('حوافز التوصيل'),
            trailing: Text('+ 72 ج.م')),
        const ListTile(
            leading: Icon(Icons.delivery_dining, color: blue),
            title: Text('مكافآت الطلبات'),
            trailing: Text('+ 35 ج.م'))
      ]));
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
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: navy)),
            Text(label, style: const TextStyle(color: Colors.black54))
          ])));
}

class DriverHistory extends StatelessWidget {
  const DriverHistory({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('سجل التوصيل')),
      body: ListView(padding: const EdgeInsets.all(16), children: const [
        HistoryCard(
            restaurant: 'مطعم بيت الشام',
            date: 'اليوم • 14:32',
            amount: '15.00 ج.م'),
        HistoryCard(
            restaurant: 'مطعم مذاق الشرق',
            date: 'اليوم • 11:20',
            amount: '12.50 ج.م'),
        HistoryCard(
            restaurant: 'مطعم برجر لاند',
            date: 'أمس • 20:15',
            amount: '11.00 ج.م')
      ]));
}

class HistoryCard extends StatelessWidget {
  const HistoryCard(
      {super.key,
      required this.restaurant,
      required this.date,
      required this.amount});
  final String restaurant, date, amount;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
          leading: const CircleAvatar(
              backgroundColor: Color(0xFFE5F6EE),
              child: Icon(Icons.check, color: Color(0xFF29B77B))),
          title: Text(restaurant,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(date),
          trailing: Text(amount,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, color: navy))));
}

class DriverProfile extends StatelessWidget {
  const DriverProfile({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ملفي')),
      body: ListView(padding: const EdgeInsets.all(18), children: const [
        CircleAvatar(
            radius: 38,
            backgroundColor: Color(0xFFDCECF4),
            child: Icon(Icons.person, size: 42, color: navy)),
        SizedBox(height: 10),
        Center(
            child: Text('محمد علي  •  4.8 ★',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        Center(child: Text('مندوب توصيل')),
        SizedBox(height: 18),
        ProfileRow(
            icon: Icons.motorcycle,
            title: 'معلومات المركبة',
            value: 'دراجة نارية'),
        ProfileRow(
            icon: Icons.schedule,
            title: 'أوقات العمل والمناطق',
            value: 'القاهرة'),
        ProfileRow(
            icon: Icons.payments_outlined,
            title: 'المدفوعات',
            value: 'الحساب البنكي'),
        ProfileRow(
            icon: Icons.help_outline, title: 'المساعدة والدعم', value: ''),
        ProfileRow(icon: Icons.settings_outlined, title: 'الإعدادات', value: '')
      ]));
}

class ProfileRow extends StatelessWidget {
  const ProfileRow(
      {super.key,
      required this.icon,
      required this.title,
      required this.value});
  final IconData icon;
  final String title, value;
  @override
  Widget build(BuildContext context) => Card(
      color: Colors.white,
      elevation: 0,
      child: ListTile(
          leading: Icon(icon, color: navy),
          title: Text(title),
          subtitle: value.isEmpty ? null : Text(value),
          trailing: const Icon(Icons.chevron_left)));
}
