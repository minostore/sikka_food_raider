import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'maa_core.dart';

/// يختار صورة من المعرض ويضغطها ويعيدها Base64 (تُخزَّن داخل وثيقة Firestore).
Future<String?> maaPickImageB64({int maxSide = 600, int quality = 60}) async {
  final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      imageQuality: quality);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 300 * 1024) {
    throw Exception('الصورة كبيرة بعد الضغط. اختر صورة أصغر.');
  }
  return base64Encode(bytes);
}

/// يعرض صورة Base64 أو أيقونة بديلة.
class MaaImage extends StatelessWidget {
  const MaaImage(
      {super.key,
      required this.b64,
      this.width = 64,
      this.height = 64,
      this.radius = 14,
      this.fallback = Icons.restaurant,
      this.color = Colors.grey});
  final String? b64;
  final double width, height, radius;
  final IconData fallback;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (b64 != null && b64!.isNotEmpty) {
      try {
        child = Image.memory(base64Decode(b64!),
            width: width, height: height, fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        child = _placeholder();
      }
    } else {
      child = _placeholder();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  Widget _placeholder() => Container(
      width: width,
      height: height,
      color: color.withValues(alpha: .12),
      child: Icon(fallback, color: color, size: (width < height ? width : height) * .5));
}

/// دردشة داخل الطلب بين العميل والسائق.
class MaaOrderChatPage extends StatefulWidget {
  const MaaOrderChatPage(
      {super.key,
      required this.session,
      required this.orderId,
      required this.title,
      required this.accent});
  final MaaSession session;
  final String orderId;
  final String title;
  final Color accent;
  @override
  State<MaaOrderChatPage> createState() => _MaaOrderChatPageState();
}

class _MaaOrderChatPageState extends State<MaaOrderChatPage> {
  final _text = TextEditingController();
  bool _sending = false;

  CollectionReference<Map<String, dynamic>> get _col =>
      widget.session.db.collection('orders').doc(widget.orderId).collection('messages');

  Future<void> _send() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _col.add({
        'uid': widget.session.uid,
        'role': widget.session.role,
        'name': widget.session.name,
        'text': value,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر إرسال الرسالة.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Column(children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _col.orderBy('ts').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(child: Text('تعذر تحميل المحادثة.'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('ابدأ المحادثة…'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final m = docs[i].data();
                      final mine = m['uid'] == widget.session.uid;
                      return Align(
                        alignment: mine
                            ? AlignmentDirectional.centerStart
                            : AlignmentDirectional.centerEnd,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 290),
                          decoration: BoxDecoration(
                              color: mine
                                  ? widget.accent.withValues(alpha: .16)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine)
                                  Text('${m['name']}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54)),
                                Text('${m['text']}'),
                              ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _text,
                          decoration: InputDecoration(
                              hintText: 'اكتب رسالتك…',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none)))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: widget.accent),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

/// شكوى مرتبطة بطلب: تُنشأ كتذكرة دعم تظهر للإدارة في لوحة التحكم.
Future<void> maaFileComplaint(
    BuildContext context, MaaSession session, Map<String, dynamic> order) async {
  final text = TextEditingController();
  final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('شكوى على الطلب ${order['order']}'),
            content: TextField(
                controller: text,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'اكتب تفاصيل الشكوى')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('إرسال')),
            ],
          )));
  if (ok != true || text.text.trim().isEmpty) return;
  final label = {'customer': 'عميل', 'restaurant': 'مطعم', 'driver': 'مندوب'}[session.role]!;
  final from = {'customer': 'العميل', 'restaurant': 'المطعم', 'driver': 'المندوب'}[session.role]!;
  try {
    final number = await session.nextCounter('support');
    final id = 'SUP-${number.toString().padLeft(4, '0')}';
    await session.db.collection('supportTickets').doc(id).set({
      'id': id,
      'requesterUid': session.uid,
      'requesterRole': session.role,
      'customer': session.name,
      'customerId': session.publicId,
      'subject': 'شكوى على الطلب ${order['order']}',
      'category': 'شكوى $label',
      'orderId': order['id'],
      'orderRestaurantId': order['restaurantId'],
      'orderCustomerId': order['customerId'],
      'orderDriverId': order['driverId'],
      'status': 'مفتوحة',
      'updated': maaNow(),
      'messages': [
        {'from': from, 'text': text.text.trim(), 'at': maaClock(), 'ts': DateTime.now().millisecondsSinceEpoch}
      ],
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الشكوى ($id). ستراجعها الإدارة.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر إرسال الشكوى.')));
    }
  }
}
