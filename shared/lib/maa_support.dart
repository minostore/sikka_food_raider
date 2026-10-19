import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'maa_core.dart';

const _roleLabels = {'customer': 'عميل', 'restaurant': 'مطعم', 'driver': 'مندوب'};
const _fromLabels = {'customer': 'العميل', 'restaurant': 'المطعم', 'driver': 'المندوب'};

/// صندوق الدعم: تذاكر مرتبطة برقم المستخدم التعريفي وتظهر للإدارة في لوحة التحكم.
class MaaSupportPage extends StatelessWidget {
  const MaaSupportPage({super.key, required this.session, required this.accent});
  final MaaSession session;
  final Color accent;

  Future<void> _create(BuildContext context) async {
    final subject = TextEditingController();
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تذكرة دعم جديدة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: subject, decoration: const InputDecoration(labelText: 'الموضوع')),
            const SizedBox(height: 8),
            TextField(controller: text, maxLines: 4, decoration: const InputDecoration(labelText: 'اشرح المشكلة')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إرسال')),
          ],
        ),
      ),
    );
    if (ok != true || subject.text.trim().isEmpty || text.text.trim().isEmpty) return;
    try {
      final number = await session.nextCounter('support');
      final id = 'SUP-${number.toString().padLeft(4, '0')}';
      await session.db.collection('supportTickets').doc(id).set({
        'id': id,
        'requesterUid': session.uid,
        'requesterRole': session.role,
        'customer': session.name,
        'customerId': session.publicId,
        'subject': subject.text.trim(),
        'category': _roleLabels[session.role],
        'status': 'مفتوحة',
        'updated': maaNow(),
        'messages': [
          {'from': _fromLabels[session.role], 'text': text.text.trim(), 'at': maaClock(), 'ts': DateTime.now().millisecondsSinceEpoch}
        ],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال التذكرة. حاول مجددًا.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المساعدة والدعم')),
          floatingActionButton: FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              onPressed: () => _create(context),
              icon: const Icon(Icons.add_comment),
              label: const Text('تذكرة جديدة')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: session.db.collection('supportTickets').where('requesterUid', isEqualTo: session.uid).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return const Center(child: Text('تعذر تحميل التذاكر.'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.toList()
                ..sort((a, b) => (b.data()['updated'] ?? '').toString().compareTo((a.data()['updated'] ?? '').toString()));
              if (docs.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('لا توجد تذاكر. اضغط «تذكرة جديدة» للتواصل مع الدعم.', textAlign: TextAlign.center)));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = docs[i].data();
                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: accent.withValues(alpha: .13), child: Icon(Icons.support_agent, color: accent)),
                      title: Text('${t['subject']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${t['id']} • ${t['status']}'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _TicketChat(session: session, ticketId: docs[i].id, accent: accent))),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
}

class _TicketChat extends StatefulWidget {
  const _TicketChat({required this.session, required this.ticketId, required this.accent});
  final MaaSession session;
  final String ticketId;
  final Color accent;
  @override
  State<_TicketChat> createState() => _TicketChatState();
}

class _TicketChatState extends State<_TicketChat> {
  final _text = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.session.db.collection('supportTickets').doc(widget.ticketId).update({
        'messages': FieldValue.arrayUnion([
          {'from': _fromLabels[widget.session.role], 'text': value, 'at': maaClock(), 'ts': DateTime.now().millisecondsSinceEpoch}
        ]),
        'updated': maaNow(),
        'status': 'مفتوحة',
      });
      _text.clear();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال الرسالة.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: Text('تذكرة ${widget.ticketId}')),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: widget.session.db.collection('supportTickets').doc(widget.ticketId).snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              if (data == null) return const Center(child: CircularProgressIndicator());
              final messages = ((data['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
              return Column(children: [
                Padding(padding: const EdgeInsets.all(12), child: Text('${data['subject']} • ${data['status']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      final mine = m['from'] != 'الدعم' && m['from'] != 'الإدارة';
                      return Align(
                        alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(color: mine ? widget.accent.withValues(alpha: .14) : Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${m['from']} • ${m['at'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text('${m['text']}'),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(children: [
                      Expanded(child: TextField(controller: _text, decoration: InputDecoration(hintText: 'اكتب رسالتك…', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
                      const SizedBox(width: 8),
                      IconButton.filled(style: IconButton.styleFrom(backgroundColor: widget.accent), onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                    ]),
                  ),
                ),
              ]);
            },
          ),
        ),
      );
}
