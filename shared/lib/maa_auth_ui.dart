import 'package:flutter/material.dart';

import 'maa_core.dart';

/// بوابة الدخول: تعرض شاشة الدخول/التسجيل حتى يصبح الحساب نشطًا،
/// ثم تبني واجهة التطبيق عبر [builder].
class MaaAuthGate extends StatelessWidget {
  const MaaAuthGate({
    super.key,
    required this.session,
    required this.accent,
    required this.appTitle,
    required this.builder,
  });
  final MaaSession session;
  final Color accent;
  final String appTitle;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            switch (session.state) {
              case MaaAuthState.loading:
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              case MaaAuthState.signedOut:
                return MaaLoginPage(
                    session: session, accent: accent, appTitle: appTitle);
              case MaaAuthState.pending:
                return _Notice(
                    session: session,
                    accent: accent,
                    icon: Icons.hourglass_top,
                    title: 'حسابك بانتظار الموافقة',
                    text:
                        'تم استلام طلب التسجيل برقمك التعريفي ${session.publicId}. ستفعّل الإدارة الحساب قريبًا ثم يمكنك البدء.');
              case MaaAuthState.blocked:
                return _Notice(
                    session: session,
                    accent: accent,
                    icon: Icons.block,
                    title: 'الحساب غير متاح',
                    text: 'هذا الحساب موقوف أو مقيّد. تواصل مع إدارة منصة معًا.');
              case MaaAuthState.wrongRole:
                return _Notice(
                    session: session,
                    accent: accent,
                    icon: Icons.swap_horiz,
                    title: 'هذا الحساب لتطبيق آخر',
                    text:
                        'سجّل الخروج ثم ادخل بحساب مناسب لهذا التطبيق ($appTitle).');
              case MaaAuthState.active:
                return builder(context);
            }
          },
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(
      {required this.session,
      required this.accent,
      required this.icon,
      required this.title,
      required this.text});
  final MaaSession session;
  final Color accent;
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 64, color: accent),
                      const SizedBox(height: 18),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Text(text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(height: 1.6)),
                      const SizedBox(height: 24),
                      OutlinedButton(
                          onPressed: session.signOut,
                          child: const Text('تسجيل الخروج')),
                    ]))),
      );
}

class MaaLoginPage extends StatefulWidget {
  const MaaLoginPage(
      {super.key,
      required this.session,
      required this.accent,
      required this.appTitle});
  final MaaSession session;
  final Color accent;
  final String appTitle;
  @override
  State<MaaLoginPage> createState() => _MaaLoginPageState();
}

class _MaaLoginPageState extends State<MaaLoginPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  final _vehicle = TextEditingController();
  final _owner = TextEditingController();
  final _area = TextEditingController();
  String _governorate = '';
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String _error = '';
  String _info = '';

  String get role => widget.session.role;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _address, _vehicle, _owner, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });
    try {
      if (_register) {
        await widget.session.register(
            name: _name.text.trim(),
            email: _email.text,
            phone: _phone.text.trim(),
            password: _password.text,
            address: _address.text.trim(),
            vehicle: _vehicle.text.trim(),
            owner: _owner.text.trim(),
            governorate: _governorate,
            area: _area.text.trim());
      } else {
        await widget.session.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = maaAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'اكتب بريدك الإلكتروني أولًا ثم اضغط «نسيت كلمة المرور».');
      return;
    }
    try {
      await widget.session.sendPasswordReset(_email.text);
      if (mounted) setState(() { _error = ''; _info = 'أرسلنا رابط إعادة التعيين إلى بريدك.'; });
    } catch (e) {
      if (mounted) setState(() => _error = maaAuthError(e));
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final restaurant = role == 'restaurant';
    final driver = role == 'driver';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CircleAvatar(
                      radius: 34,
                      backgroundColor: accent.withValues(alpha: .14),
                      child: Text('م',
                          style: TextStyle(
                              color: accent,
                              fontSize: 34,
                              fontWeight: FontWeight.w900))),
                  const SizedBox(height: 12),
                  Text(widget.appTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 20),
                  if (_register) ...[
                    _field(_name, restaurant ? 'اسم المطعم' : 'الاسم الكامل',
                        validator: _required, icon: Icons.person_outline),
                    if (restaurant)
                      _field(_owner, 'اسم المسؤول', icon: Icons.badge_outlined),
                    _field(_phone, 'رقم الهاتف',
                        keyboard: TextInputType.phone,
                        validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                            ? 'أدخل رقم هاتف صحيحًا'
                            : null,
                        icon: Icons.phone_outlined),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        initialValue: _governorate.isEmpty ? null : _governorate,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: role == 'customer' ? 'المحافظة' : 'المحافظة (مطلوبة)',
                            prefixIcon: const Icon(Icons.map_outlined),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none)),
                        items: [
                          for (final g in maaGovernorates)
                            DropdownMenuItem(value: g, child: Text(g))
                        ],
                        validator: (v) => role != 'customer' && (v == null || v.isEmpty)
                            ? 'اختر المحافظة'
                            : null,
                        onChanged: (v) => setState(() => _governorate = v ?? ''),
                      ),
                    ),
                    _field(_area, role == 'customer' ? 'المنطقة' : 'المنطقة (مطلوبة)',
                        icon: Icons.place_outlined,
                        validator: role == 'customer' ? null : _required),
                    _field(_address, restaurant ? 'عنوان المطعم' : 'العنوان',
                        icon: Icons.location_on_outlined,
                        validator: role == 'driver' ? null : _required),
                    if (driver)
                      _field(_vehicle, 'المركبة (دراجة / سيارة)',
                          icon: Icons.two_wheeler_outlined, validator: _required),
                  ],
                  _field(_email, 'البريد الإلكتروني',
                      keyboard: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@') || !v.contains('.'))
                          ? 'أدخل بريدًا صحيحًا'
                          : null,
                      icon: Icons.email_outlined),
                  _field(_password, 'كلمة المرور',
                      obscure: _hide,
                      validator: (v) => (v ?? '').length < 8
                          ? 'كلمة المرور 8 أحرف على الأقل'
                          : null,
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                          icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _hide = !_hide))),
                  if (_error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(_error,
                            style: const TextStyle(color: Color(0xFFC62828)))),
                  if (_info.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(_info,
                            style: const TextStyle(color: Color(0xFF2E7D32)))),
                  if (_register && (restaurant || driver))
                    const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                            'بعد التسجيل يراجع فريق الإدارة طلبك ويفعّل الحساب.',
                            style: TextStyle(color: Colors.black54, fontSize: 13))),
                  FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          minimumSize: const Size.fromHeight(52)),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : Text(_register ? 'إنشاء الحساب' : 'دخول')),
                  const SizedBox(height: 8),
                  if (!_register)
                    TextButton(
                        onPressed: _reset,
                        child: const Text('نسيت كلمة المرور؟')),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = '';
                                _info = '';
                              }),
                      child: Text(_register
                          ? 'لديك حساب؟ سجّل الدخول'
                          : 'ليس لديك حساب؟ أنشئ حسابًا')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {String? Function(String?)? validator,
          TextInputType? keyboard,
          bool obscure = false,
          IconData? icon,
          Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          validator: validator,
          keyboardType: keyboard,
          obscureText: obscure,
          autocorrect: false,
          decoration: InputDecoration(
              labelText: label,
              prefixIcon: icon == null ? null : Icon(icon),
              suffixIcon: suffix,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none)),
        ),
      );
}
