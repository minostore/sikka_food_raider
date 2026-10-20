import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// عنوان لوحة التحكم المنشورة (مثال: https://maa-admin.vercel.app).
/// يُمرَّر عند البناء: --dart-define=MAA_API_URL=https://...
const String _maaApiUrlEnv = String.fromEnvironment('MAA_API_URL');
const String _maaApiUrlDefault = 'https://sikka-food-admin.vercel.app';

/// يُستخدم العنوان الافتراضي إذا لم يُمرَّر MAA_API_URL (أو مُرّر فارغًا).
String get maaApiUrl => _maaApiUrlEnv.isEmpty ? _maaApiUrlDefault : _maaApiUrlEnv;

const statusActive = 'نشط';
const statusPending = 'بانتظار الموافقة';

/// حالات الطلب (نفس النصوص التي تعرضها لوحة التحكم).
const orderNew = 'جديد';
const orderPreparing = 'قيد التحضير';
const orderReady = 'جاهز للاستلام';
const orderDelivering = 'قيد التوصيل';
const orderDone = 'مكتمل';
const orderCancelled = 'ملغي';
const activeOrderStatuses = [orderNew, orderPreparing, orderReady, orderDelivering];

const maaGovernorates = [
  'القاهرة', 'الجيزة', 'الإسكندرية', 'القليوبية', 'الشرقية', 'الدقهلية', 'البحيرة',
  'المنوفية', 'الغربية', 'كفر الشيخ', 'دمياط', 'بورسعيد', 'الإسماعيلية', 'السويس',
  'شمال سيناء', 'جنوب سيناء', 'الفيوم', 'بني سويف', 'المنيا', 'أسيوط', 'سوهاج',
  'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر', 'الوادي الجديد', 'مطروح',
];

const roleCollections = {
  'customer': 'customers',
  'restaurant': 'restaurants',
  'driver': 'drivers',
};

String maaMoney(num value) =>
    '${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(2)} ج.م';

String maaNow() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String maaClock() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

num maaNum(dynamic v) =>
    v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

/// ترجمة أخطاء Firebase Auth إلى رسائل عربية.
String maaAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح.';
      case 'user-disabled':
        return 'هذا الحساب موقوف. تواصل مع الإدارة.';
      case 'too-many-requests':
        return 'محاولات كثيرة. انتظر قليلًا ثم أعد المحاولة.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت.';
    }
    return 'تعذر تسجيل الدخول (${error.code}).';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

enum MaaAuthState { loading, signedOut, active, pending, blocked, wrongRole }

/// جلسة المستخدم: تربط حساب Firebase Auth بوثيقة users/{uid} وملف الدور
/// (customers/restaurants/drivers) وتحمل الرقم التعريفي publicId.
class MaaSession extends ChangeNotifier {
  MaaSession(this.role);
  final String role;

  MaaAuthState state = MaaAuthState.loading;
  User? user;
  Map<String, dynamic> account = {}; // users/{uid}
  Map<String, dynamic> profile = {}; // customers|restaurants|drivers/{uid}

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _accountSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  FirebaseFirestore get db => FirebaseFirestore.instance;
  String get uid => user?.uid ?? '';
  String get publicId => (account['publicId'] ?? '').toString();
  String get name => (profile['name'] ?? account['name'] ?? '').toString();
  String get phone => (profile['phone'] ?? account['phone'] ?? '').toString();
  String get address => (profile['address'] ?? account['address'] ?? '').toString();
  DocumentReference<Map<String, dynamic>> get profileRef =>
      db.collection(roleCollections[role]!).doc(uid);

  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  void _onUser(User? next) {
    user = next;
    _accountSub?.cancel();
    _profileSub?.cancel();
    account = {};
    profile = {};
    if (next == null) {
      state = MaaAuthState.signedOut;
      notifyListeners();
      return;
    }
    state = MaaAuthState.loading;
    notifyListeners();
    _accountSub = db.collection('users').doc(next.uid).snapshots().listen((snap) {
      account = snap.data() ?? {};
      _recompute();
    }, onError: (_) {
      state = MaaAuthState.blocked;
      notifyListeners();
    });
    _profileSub = profileRef.snapshots().listen((snap) {
      profile = snap.data() ?? {};
      _recompute();
    }, onError: (_) {});
  }

  void _recompute() {
    if (account.isEmpty) {
      state = MaaAuthState.loading;
    } else if (account['role'] != role) {
      state = MaaAuthState.wrongRole;
    } else {
      final status = (account['accountStatus'] ?? '').toString();
      state = status == statusActive
          ? MaaAuthState.active
          : status == statusPending
              ? MaaAuthState.pending
              : MaaAuthState.blocked;
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  /// تسجيل ذاتي عبر لوحة التحكم (تُنشئ الحساب والرقم التعريفي)، ثم دخول مباشر.
  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String address = '',
    String vehicle = '',
    String owner = '',
    String governorate = '',
    String area = '',
  }) async {
    if (maaApiUrl.isEmpty) {
      throw Exception('لم يُضبط عنوان الخادم MAA_API_URL عند بناء التطبيق.');
    }
    final base = maaApiUrl.endsWith('/')
        ? maaApiUrl.substring(0, maaApiUrl.length - 1)
        : maaApiUrl;
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$base/api/auth/register'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'role': role,
              'name': name,
              'email': email.trim(),
              'phone': phone,
              'password': password,
              'address': address,
              'vehicle': vehicle,
              'owner': owner,
              'governorate': governorate,
              'area': area,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالخادم.');
    } catch (_) {
      throw Exception('تعذر الوصول إلى الخادم. تحقق من الإنترنت.');
    }
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode != 201) {
      throw Exception((body['error'] ?? 'تعذر إنشاء الحساب (${response.statusCode}).').toString());
    }
    await signIn(email, password);
  }

  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  /// رقم متسلسل للطلبات/التذاكر بمعاملة آمنة. يعيد مثل 1، 2، 3…
  Future<int> nextCounter(String name) {
    final ref = db.collection('counters').doc(name);
    return db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['value'] as num?)?.toInt() ?? 0) + 1;
      tx.set(ref, {'value': next});
      return next;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _accountSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}

/// يضيف سطرًا إلى سجل تغيّر حالة الطلب (يعرضه المدير في لوحة التحكم).
String maaAppendHistory(dynamic old, String line) {
  final current = (old ?? '').toString();
  return '${current.isEmpty ? '' : '$current\n'}${maaClock()} — $line';
}

int maaOrderSerial(Map<String, dynamic> order) =>
    int.tryParse((order['id'] ?? '').toString().replaceAll(RegExp(r'\D'), '')) ?? 0;

/// ترتيب الطلبات من الأحدث إلى الأقدم (بالرقم المتسلسل).
List<Map<String, dynamic>> maaSortedOrders(Iterable<Map<String, dynamic>> orders) =>
    orders.toList()..sort((a, b) => maaOrderSerial(b).compareTo(maaOrderSerial(a)));

/// نص الخطوات المقروء للعميل.
const maaOrderSteps = [orderNew, orderPreparing, orderReady, orderDelivering, orderDone];
