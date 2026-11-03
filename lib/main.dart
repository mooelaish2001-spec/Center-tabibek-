import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════ طبيبك — تطبيق المركز (Center app) ═══════════════
// يستخدم نفس تصميم تطبيق المستخدمين. البيانات في الذاكرة (Db) وتتحدّث لحظياً بين الشاشات.
//
// الدخول والتسجيل: برقم الهاتف + رمز تحقق OTP (بدون بريد إلكتروني ولا كلمة مرور).
//   • مدير المركز يسجّل المركز ويتحقق من هاتفه، ثم يضيف حساب الاستقبال (دخوله أيضاً برقمه + OTP).
//   • إضافة أخصائي: يُبحث برقم تسجيله في المجلس الطبي؛ إن كان مسجّلاً في طبيبك يظهر ملفه مباشرة
//     ويُضاف بشروط المركز، وإلا يُسجَّل كأخصائي جديد (قيد التحقق).
//
// تنبيه: هذه نسخة واجهة تجريبية. ما يلي يحتاج خادماً حقيقياً في النسخة الإنتاجية:
//   1) إرسال/التحقق من OTP عبر بوابة SMS (الكود هنا يُعرض على الشاشة للتجربة فقط — OtpService).
//   2) سجلّ الأخصائيين (Db.registry) وقرار اعتماد المراكز (لوحة إدارة طبيبك).
//   3) رفع صورة الترخيص، الإشعارات، الصلاحيات، وحذف الحساب (كلها يجب أن تُنفَّذ وتُفرَض من الخادم).

const kRed = Color(0xFFD9141E), kInk = Color(0xFF1B2A4A), kGrey = Color(0xFF7B8494), kLine = Color(0xFFE9EDF2);
const kBg = Color(0xFFF7F8FB), kChip = Color(0xFFF1F3F7), kGreen = Color(0xFF2A8F4F), kAmber = Color(0xFFB7791F);
const kGrad = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE0161F), Color(0xFFB30B15)]);
const kAmberBg = Color(0xFFFFF1D6), kGreenBg = Color(0xFFD9F3E1);

TextStyle t(double s, {FontWeight w = FontWeight.w700, Color c = kInk, double? h}) => GoogleFonts.cairo(fontSize: s, fontWeight: w, color: c, height: h);
void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));
Icon chev([Color c = kRed, double s = 24]) => Icon(Icons.chevron_left_rounded, color: c, size: s, textDirection: TextDirection.ltr);
BoxDecoration card([double r = 18]) => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r), border: Border.all(color: const Color(0xFFF0F2F6)), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6))]);
Widget gap([double h = 12]) => SizedBox(height: h);
Widget pill(String s, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Text(s, style: t(11.5, c: fg)));
Widget sec(String s) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 10), child: Text(s, style: t(15.5, w: FontWeight.w800)));
String money(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m, style: t(13, c: Colors.white))));

/// يحوّل الأرقام العربية (٠-٩) والفارسية (۰-۹) إلى لاتينية حتى تعمل كل الحقول مع لوحة المفاتيح العربية.
String latin(String s) => String.fromCharCodes(s.runes.map((r) => r >= 0x660 && r <= 0x669 ? r - 0x660 + 48 : r >= 0x6F0 && r <= 0x6F9 ? r - 0x6F0 + 48 : r));
int num(String s) => int.tryParse(latin(s).replaceAll(',', '').trim()) ?? 0;

/// يقبل الأرقام اللاتينية والعربية فقط.
final digitsFmt = FilteringTextInputFormatter.allow(RegExp('[0-9\u0660-\u0669\u06F0-\u06F9]'));

/// يوحّد رقم الهاتف السوداني إلى الصيغة الدولية +249XXXXXXXXX، ويرجع null إن لم يكن صالحاً.
/// يقبل: 912345678 · 0912345678 · +249912345678 · 00249912345678 (وبالأرقام العربية).
String? normPhone(String raw) {
  var s = latin(raw).replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.startsWith('00')) {
    s = '+${s.substring(2)}';
  } else if (s.startsWith('+')) {
    // جاهز
  } else if (s.startsWith('249')) {
    s = '+$s';
  } else if (s.startsWith('0')) {
    s = '+249${s.substring(1)}';
  } else {
    s = '+249$s';
  }
  return RegExp(r'^\+249[19]\d{8}$').hasMatch(s) ? s : null;
}

String fmtPhone(String p) => p.length == 13 && p.startsWith('+249') ? '${p.substring(0, 4)} ${p.substring(4, 7)} ${p.substring(7, 10)} ${p.substring(10)}' : p;
String centersTxt(int n) => n <= 0 ? 'لا مراكز أخرى' : n == 1 ? 'مركز واحد' : n == 2 ? 'مركزان' : n <= 10 ? '$n مراكز' : '$n مركزاً';

Widget badge(String s) {
  const m = {'جديد': (Color(0xFFFDE8EA), kRed), 'مؤكد': (Color(0xFFD9F3E1), kGreen), 'مكتمل': (kChip, kInk), 'مرفوض': (Color(0xFFFFF1D6), kAmber)};
  final x = m[s] ?? (kChip, kGrey);
  return pill(s, x.$1, x.$2);
}

Widget tile(IconData i, {double size = 44, bool dark = false}) => Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(gradient: dark ? kGrad : null, color: dark ? null : const Color(0xFFFDE8EA), borderRadius: BorderRadius.circular(size / 3.2)),
      child: Icon(i, color: dark ? Colors.white : kRed, size: size * .52),
    );

Widget btn(String text, VoidCallback onTap, {bool outline = false, double h = 50}) => Semantics(
      button: true,
      label: text,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(h / 2),
          child: Container(
        height: h, width: double.infinity, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: outline ? null : kGrad, color: outline ? Colors.white : null, borderRadius: BorderRadius.circular(h / 2),
          border: outline ? Border.all(color: kRed, width: 1.6) : null,
          boxShadow: outline ? null : const [BoxShadow(color: Color(0x4DD9141E), blurRadius: 14, offset: Offset(0, 7))],
        ),
        child: Text(text, style: t(16, w: FontWeight.w800, c: outline ? kRed : Colors.white)),
          ),
        ),
      ),
    );

Widget bar(BuildContext c, List<Widget> ch) => Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(c).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [for (final w in ch) Padding(padding: const EdgeInsets.only(top: 8), child: w)]),
    );

Widget panel(List<Widget> ch) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: ch));
Widget kv(String k, String v, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Expanded(child: Text(k, style: t(13, w: FontWeight.w500, c: kGrey))), Flexible(child: Text(v, textAlign: TextAlign.end, style: t(13.5, c: bold ? kRed : kInk)))]));
Widget two(String a, String b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: t(14.5, w: FontWeight.w800)), Text(b, style: t(12, w: FontWeight.w500, c: kGrey))]);

/// حقل نصي. ltr: للأرقام (هاتف/ترخيص). prefix: عنصر ثابت في بداية الحقل (مثل +249). enabled=false: حقل للقراءة فقط.
Widget fld(String l, TextEditingController c, {String? hint, int lines = 1, TextInputType? kb, bool obscure = false, bool enabled = true, bool ltr = false, Widget? prefix, List<TextInputFormatter>? fmt, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmit, TextStyle? style, TextAlign align = TextAlign.start}) {
  Widget f = TextField(
    controller: c, enabled: enabled, maxLines: lines, keyboardType: kb, obscureText: obscure, inputFormatters: fmt, onChanged: onChanged, onSubmitted: onSubmit, textAlign: align,
    style: style ?? t(14, w: FontWeight.w600, c: enabled ? kInk : kGrey),
    decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: t(13, w: FontWeight.w500, c: kGrey), prefixIcon: prefix, prefixIconConstraints: const BoxConstraints(), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
  );
  if (ltr) f = Directionality(textDirection: TextDirection.ltr, child: f);
  return Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: t(12.5)),
      gap(6),
      Container(
        decoration: BoxDecoration(color: enabled ? Colors.white : kChip, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
        child: f,
      ),
    ]),
  );
}

/// حقل هاتف سوداني: يعرض +249 ثابتاً ويقبل 9XXXXXXXX أو 09XXXXXXXX. استخدم normPhone للتحقق.
Widget phoneFld(String l, TextEditingController c, {bool enabled = true}) => fld(l, c,
    hint: '9XX XXX XXX', kb: TextInputType.phone, enabled: enabled, ltr: true,
    fmt: [digitsFmt, LengthLimitingTextInputFormatter(10)],
    prefix: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('+249', style: t(14, w: FontWeight.w700, c: kGrey))));

/// صف للقراءة فقط (قيمة مقفلة) بنفس شكل الحقول.
Widget lockedRow(String l, String v, {Widget? tail}) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: t(12.5)),
        gap(6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
          child: Row(children: [Expanded(child: Text(v, textDirection: TextDirection.ltr, style: t(14, w: FontWeight.w600, c: kGrey))), if (tail != null) tail]),
        ),
      ]),
    );

/// قائمة منسدلة بقيم مرقّمة.
Widget dd(int v, List<String> items, ValueChanged<int> on) => Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
      child: DropdownButton<int>(
        value: v, isExpanded: true, underline: const SizedBox(),
        items: [for (var i = 0; i < items.length; i++) DropdownMenuItem(value: i, child: Text(items[i], style: t(13.5, w: FontWeight.w600)))],
        onChanged: (x) {
          if (x != null) on(x);
        },
      ),
    );

Widget switchRow(String s, bool v, ValueChanged<bool> on) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [Expanded(child: Text(s, style: t(13.5))), Switch(value: v, onChanged: on)]));

/// مؤشّر خطوات (للتسجيل متعدد الخطوات).
Widget stepper(int cur, List<String> names) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < names.length; i++)
        Expanded(
          child: Column(children: [
            Container(
              width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(gradient: i <= cur ? kGrad : null, color: i <= cur ? null : kChip, shape: BoxShape.circle),
              child: i < cur ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : Text('${i + 1}', style: t(13, c: i <= cur ? Colors.white : kGrey)),
            ),
            gap(4),
            Text(names[i], textAlign: TextAlign.center, style: t(11, w: i == cur ? FontWeight.w800 : FontWeight.w500, c: i == cur ? kRed : kGrey)),
          ]),
        ),
    ]);

/// Chips bound to a Set<int> owned by the parent State (call setState via [refresh]).
Widget chips(List<String> items, Set<int> sel, VoidCallback refresh, {bool multi = false}) => Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < items.length; i++)
        GestureDetector(
          onTap: () {
            if (multi) {
              sel.contains(i) ? sel.remove(i) : sel.add(i);
            } else {
              sel..clear()..add(i);
            }
            refresh();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(gradient: sel.contains(i) ? kGrad : null, color: sel.contains(i) ? null : kChip, borderRadius: BorderRadius.circular(20)),
            child: Text(items[i], style: t(13, c: sel.contains(i) ? Colors.white : const Color(0xFF4B5873))),
          ),
        ),
    ]);

Widget empty(IconData i, String s) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [tile(i, size: 84), gap(14), Text(s, textAlign: TextAlign.center, style: t(14, c: kGrey))])));

/// نافذة تأكيد لإجراء لا رجعة فيه.
void confirm(BuildContext c, String title, String msg, String okText, VoidCallback onYes) => showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: t(15)),
        content: Text(msg, style: t(13, w: FontWeight.w500, c: kGrey, h: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: t(14, c: kGrey))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onYes();
            },
            child: Text(okText, style: t(14, c: kRed)),
          ),
        ],
      ),
    );

// ═══════════════ Constants ═══════════════
const kDays = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];
const kSpecs = ['باطنية', 'أطفال', 'نساء وتوليد', 'جراحة عامة', 'قلب', 'عظام', 'جلدية', 'أنف وأذن'];
const kCenterKinds = ['مستشفى', 'مجمع طبي', 'عيادات تخصصية', 'مركز تشخيصي ومختبر'];
const kStates = ['الخرطوم', 'الجزيرة', 'البحر الأحمر', 'كسلا', 'القضارف', 'سنار', 'النيل الأبيض', 'النيل الأزرق', 'نهر النيل', 'الشمالية', 'شمال كردفان', 'جنوب كردفان', 'غرب كردفان', 'شمال دارفور', 'جنوب دارفور', 'غرب دارفور', 'وسط دارفور', 'شرق دارفور'];
const kRoles = ['مدير المركز', 'استقبال']; // الفهرس = Member.role
const kPerms = ['الحجوزات: قبول ورفض وإنهاء', 'الأسرّة', 'الأخصائيون والخدمات المنزلية', 'التقارير والإيرادات']; // الفهرس = رقم الصلاحية في Db.can
const kSupportPhone = '+249 900 000 000'; // TODO: استبدله برقم الدعم الحقيقي
const kDemoManager = '+249912000111', kDemoReception = '+249923000222';

// ═══════════════ Data ═══════════════
class Booking {
  Booking(this.id, this.type, this.patient, this.phone, this.title, this.when, this.price, this.extra, {this.status = 'جديد', this.svc = 0});
  final int id, type, svc; // type: 0 طبيب · 1 سرير · 2 خدمة منزلية — svc (للخدمة المنزلية فقط): 0 زيارة طبيب · 1 تمريض · 2 سحب عينات
  final String patient, phone, title, when, price, extra;
  String status, note = '', assigned = '';
}

/// الملف العام للأخصائي في طبيبك (مشترك بين كل المراكز). يُعثر عليه برقم التسجيل في المجلس الطبي.
class DocProfile {
  DocProfile(this.lic, this.name, this.spec, this.quals, this.exp, {this.gender = 0, this.phone = '', this.verified = true, this.mine = false, this.others = 0});
  String lic, name, spec, quals, exp, phone;
  int gender, others; // gender: 0 ذكر · 1 أنثى — others: عدد المراكز الأخرى (غير هذا المركز) التي يعمل بها
  bool verified, mine; // verified: وثّقه فريق طبيبك — mine: سجّله هذا المركز (يعدّل بياناته إلى أن يُوثَّق)
}

/// ارتباط أخصائي بهذا المركز: ملفه العام + شروط عمله هنا (السعر والدوام والزيارات المنزلية).
class Doc {
  Doc(this.p, {this.price = '', Set<int>? wd, this.from = '8:00 ص', this.to = '6:00 م', this.on = true, this.home = false, this.homePrice = ''}) : wd = wd ?? {0, 1, 2, 3, 4};
  final DocProfile p;
  String price, from, to, homePrice; // homePrice فارغ = استخدم السعر الافتراضي للزيارة المنزلية
  Set<int> wd; // أيام العمل (فهرس kDays)
  bool on, home; // home: يقدّم زيارات منزلية
  String get name => p.name;
  String get spec => p.spec;
  String get quals => p.quals;
  String get lic => p.lic;
  String get exp => p.exp;
  String get hours => '$from - $to';
  String get days {
    final s = wd.toList()..sort();
    if (s.isEmpty) return '—';
    if (s.length == 1) return kDays[s.first];
    return s.last - s.first == s.length - 1 ? '${kDays[s.first]} - ${kDays[s.last]}' : s.map((i) => kDays[i]).join('، ');
  }
}

class Bed {
  Bed(this.type, this.no, this.floor, this.price, this.equip, {this.free = true});
  String type, no, floor, price, equip;
  bool free;
}

class Svc {
  Svc(this.name, this.price, {this.on = true});
  String name, price;
  bool on;
}

/// بيانات المركز. status: 0 قيد المراجعة · 1 معتمد · 2 مرفوض.
class CenterProfile {
  CenterProfile({this.name = '', this.kind = 1, this.lic = '', this.state = 0, this.locality = '', this.address = '', this.phone = '', this.from = '8:00 ص', this.to = '10:00 م', Set<int>? svc, this.status = 0, this.reqNo = '', this.reason = '', this.docAttached = false}) : svc = svc ?? {0, 1, 2};
  String name, lic, locality, address, phone, from, to, reqNo, reason;
  int kind, state, status;
  bool docAttached;
  Set<int> svc;
}

/// مستخدم للمركز. role: 0 مدير · 1 استقبال. perms: أرقام الصلاحيات (kPerms) — للمدير كلها.
class Member {
  Member(this.name, this.phone, this.role, {Set<int>? perms, this.active = true}) : perms = perms ?? (role == 0 ? {0, 1, 2, 3} : {0, 1});
  String name, phone; // phone بصيغة +249XXXXXXXXX
  int role;
  bool active;
  Set<int> perms;
}

class Db extends ChangeNotifier {
  Db() {
    loadDemo();
  }

  CenterProfile center = CenterProfile();
  Member? me; // المستخدم المسجّل دخوله
  bool notifyNew = true;
  final members = <Member>[];

  /// سجل الأخصائيين في طبيبك (على مستوى المنصة — في الإنتاج يأتي من الخادم).
  final registry = <DocProfile>[
    DocProfile('12345', 'د. أحمد محمد علي', 'باطنية', 'ماجستير + دكتوراه باطنية - جامعة الخرطوم', '10', others: 1),
    DocProfile('23456', 'د. سارة عبد الله', 'نساء وتوليد', 'بكالوريوس الطب + دبلوم نساء وتوليد', '7', gender: 1, others: 2),
    DocProfile('34567', 'د. حسن محمود', 'أطفال', 'ماجستير طب الأطفال', '9'),
    DocProfile('45678', 'د. منى الطيب', 'جلدية', 'ماجستير الأمراض الجلدية - جامعة النيلين', '8', gender: 1, others: 2),
    DocProfile('56789', 'د. عثمان صالح', 'عظام', 'بورد جراحة العظام - المجلس السوداني للتخصصات الطبية', '14', others: 1),
    DocProfile('67890', 'د. ياسر إبراهيم', 'قلب', 'دكتوراه أمراض القلب - جامعة أم درمان الإسلامية', '11', others: 3),
    DocProfile('78901', 'د. إيمان حسن', 'أنف وأذن', 'بكالوريوس الطب والجراحة + دبلوم أنف وأذن', '4', gender: 1, verified: false, others: 1),
  ];

  final bookings = <Booking>[];
  final docs = <Doc>[];
  final beds = <Bed>[];
  final svcs = <Svc>[Svc('زيارة طبيب للمنزل', '8,000'), Svc('تمريض منزلي', '3,000'), Svc('سحب عينات المعمل', '500', on: false)];
  final staff = <String>[];
  // كتالوج التمريض المنزلي (سعر كل خدمة كامل) وكتالوج التحاليل (يُضاف إليها رسوم السحب = svcs[2])
  final nursing = <Svc>[Svc('حقن عضلية', '1,500'), Svc('حقن وريدي ومحاليل', '3,000'), Svc('تغيير جروح وضمادات', '2,500'), Svc('قياس ضغط وسكر', '1,000'), Svc('رعاية كبار السن (ساعة)', '2,000', on: false)];
  final tests = <Svc>[Svc('صورة دم كاملة (CBC)', '150'), Svc('سكر صائم', '80'), Svc('سكر تراكمي HbA1c', '250'), Svc('وظائف كبد', '300'), Svc('وظائف كلى', '280'), Svc('فحص ملاريا', '120', on: false)];
  final visitSlots = <int>{0, 2}, labSlots = <int>{0, 1};

  DocProfile _p(String lic) => registry.firstWhere((p) => p.lic == lic);

  /// يحمّل مركزاً تجريبياً كاملاً (حجوزات وأخصائيون وأسرّة ومستخدمون).
  void loadDemo() {
    center = CenterProfile(name: 'مركز المسباح الطبي', kind: 1, lic: '8841', state: 0, locality: 'بحري', address: 'المسبح، شارع 15', phone: '+249 912 000 111', status: 1, reqNo: '20260001', docAttached: true);
    members
      ..clear()
      ..addAll([Member('إبراهيم الحاج', kDemoManager, 0), Member('منى عثمان', kDemoReception, 1)]);
    me = null;
    bookings
      ..clear()
      ..addAll([
        Booking(1, 0, 'محمد عبد الرحيم', '+249 912 345 678', 'كشف · د. أحمد محمد علي (باطنية)', 'السبت 18 أكتوبر · 4:30 م', '10,000', ''),
        Booking(2, 0, 'آمنة إبراهيم', '+249 923 111 222', 'كشف · د. سارة عبد الله (نساء وتوليد)', 'الأحد 19 أكتوبر · 6:00 م', '8,000', ''),
        Booking(3, 1, 'خالد يوسف', '+249 91 555 0101', 'حجز سرير ICU · 3 أيام', 'دخول السبت 18 أكتوبر', '45,000', 'ICU'),
        Booking(4, 2, 'فاطمة أحمد', '+249 99 888 7766', 'تمريض منزلي · حقن وريدي', 'الاثنين 20 أكتوبر · 9:00 ص', '3,000', 'الخرطوم - بحري - المسبح', svc: 1),
        Booking(5, 2, 'عمر حسن', '+249 90 321 4455', 'سحب عينات · صورة دم + سكر', 'الثلاثاء 21 أكتوبر · 8:00 ص', '730', 'أم درمان - الثورة', status: 'مؤكد', svc: 2),
        Booking(6, 0, 'ليلى محمود', '+249 92 444 3322', 'كشف · د. حسن محمود (أطفال)', 'الأحد 19 أكتوبر · 5:00 م', '7,500', '', status: 'مؤكد'),
        Booking(7, 1, 'سمير علي', '+249 91 777 6655', 'حجز سرير HDU · 2 أيام', 'دخول 12 أكتوبر', '24,000', 'HDU', status: 'مكتمل'),
        Booking(8, 2, 'نجلاء إبراهيم', '+249 91 222 3344', 'زيارة طبيب · د. أحمد محمد علي (باطنية)', 'الأربعاء 22 أكتوبر · 5:00 م', '15,000', 'الخرطوم - شرق النيل - الرياض', svc: 0),
      ]);
    docs
      ..clear()
      ..addAll([
        Doc(_p('12345'), price: '10,000', wd: {0, 1, 2, 3, 4, 5}, from: '8:00 ص', to: '6:00 م', home: true, homePrice: '15,000'),
        Doc(_p('23456'), price: '8,000', wd: {1, 2, 3, 4, 5}, from: '9:00 ص', to: '5:00 م', home: true),
        Doc(_p('34567'), price: '7,500', wd: {0, 1, 2, 3, 4}, from: '10:00 ص', to: '6:00 م', on: false),
      ]);
    beds
      ..clear()
      ..addAll([
        Bed('ICU', '101', '1', '15,000', 'جهاز تنفس · مونيتور'), Bed('ICU', '102', '1', '15,000', 'جهاز تنفس · مونيتور', free: false), Bed('ICU', '103', '1', '15,000', 'مونيتور'),
        Bed('HDU', '201', '2', '12,000', 'مونيتور · أكسجين'), Bed('HDU', '202', '2', '12,000', 'أكسجين'), Bed('CCU', '301', '3', '18,000', 'مونيتور قلب', free: false),
        Bed('عادية', '401', '4', '6,000', 'تكييف'), Bed('عادية', '402', '4', '6,000', 'تكييف'), Bed('عادية', '403', '4', '6,000', '', free: false),
      ]);
    staff
      ..clear()
      ..addAll(['أحمد عثمان · ممرض', 'هالة محمد · ممرضة', 'معتز علي · فني مختبر']);
    notifyListeners();
  }

  void set(Booking b, String s, {String note = '', String who = ''}) {
    b.status = s;
    b.note = note;
    b.assigned = who;
    notifyListeners();
  }

  void ping() => notifyListeners();

  // ── الحساب والصلاحيات ──
  Member? memberByPhone(String phone) {
    for (final m in members) {
      if (m.phone == phone) return m;
    }
    return null;
  }

  Member? get manager {
    for (final m in members) {
      if (m.role == 0) return m;
    }
    return null;
  }

  Member? get reception {
    for (final m in members) {
      if (m.role == 1) return m;
    }
    return null;
  }

  bool get isManager => me == null || me!.role == 0;

  /// صلاحية المستخدم الحالي: 0 حجوزات · 1 أسرّة · 2 أخصائيون وخدمات · 3 تقارير. المدير يملك الكل.
  bool can(int perm) {
    final m = me;
    return m == null || m.role == 0 || m.perms.contains(perm);
  }

  String newReq() => '${DateTime.now().year}${1000 + Random().nextInt(9000)}';

  /// تسجيل مركز جديد: يبدأ بلا حجوزات ولا أخصائيين ولا أسرّة. (في الإنتاج: طلب إلى الخادم.)
  void register(CenterProfile c, Member mgr, Member? rec) {
    bookings.clear();
    docs.clear();
    beds.clear();
    staff.clear();
    members
      ..clear()
      ..add(mgr);
    if (rec != null) members.add(rec);
    center = c;
    me = mgr;
    notifyListeners();
  }

  /// إعادة إرسال طلب مرفوض بعد تعديل بياناته.
  void resubmit(CenterProfile c, String mgrName, Member? rec) {
    center = c;
    final m = manager;
    if (m != null) m.name = mgrName;
    members.removeWhere((x) => x.role == 1);
    if (rec != null) members.add(rec);
    notifyListeners();
  }

  /// حذف حساب المركز وكل بياناته (متطلب متاجر التطبيقات). في الإنتاج يُنفَّذ على الخادم.
  void deleteAccount() {
    bookings.clear();
    docs.clear();
    beds.clear();
    staff.clear();
    members.clear();
    center = CenterProfile();
    me = null;
    notifyListeners();
  }

  // ── سجل الأخصائيين ──
  /// يبحث برقم التسجيل في المجلس الطبي. يرجع null إن لم يكن مسجّلاً في طبيبك.
  DocProfile? lookup(String raw) {
    final n = latin(raw).replaceAll(RegExp(r'\D'), '');
    for (final p in registry) {
      if (p.lic == n) return p;
    }
    return null;
  }

  /// ارتباط هذا المركز بالأخصائي إن كان مضافاً.
  Doc? linked(DocProfile p) {
    for (final d in docs) {
      if (identical(d.p, p)) return d;
    }
    return null;
  }

  /// الفريق المتاح لتكليفه بطلب خدمة منزلية: 0 أطباء يقدّمون زيارات · 1 ممرضون · 2 فنيو مختبر
  List<String> team(int svc) => svc == 0 ? [for (final d in docs) if (d.on && d.home) d.name] : staff.where((x) => x.contains(svc == 1 ? 'ممرض' : 'مختبر')).toList();
  int get fresh => bookings.where((b) => b.status == 'جديد').length;
  int get freeBeds => beds.where((b) => b.free).length;
  int get revenue => bookings.where((b) => b.status == 'مؤكد' || b.status == 'مكتمل').fold<int>(0, (a, b) => a + num(b.price));
}

final db = Db();
const kTypes = ['حجز طبيب', 'حجز سرير', 'خدمة منزلية'];
const kTypeIcons = [Icons.medical_services_rounded, Icons.bed_rounded, Icons.home_rounded];
const kBedTypes = ['ICU', 'HDU', 'CCU', 'عادية'];
const kHomeNames = ['زيارة طبيب', 'تمريض منزلي', 'سحب عينات'];
const kHomeIcons = [Icons.medical_services_rounded, Icons.vaccines_rounded, Icons.bloodtype_rounded];
const kWho = ['طبيب', 'ممرض', 'فني مختبر'];

// ═══════════════ OTP (رمز التحقق) ═══════════════
class _OtpEntry {
  _OtpEntry(this.code) : at = DateTime.now();
  final String code;
  final DateTime at;
  int tries = 0;
}

/// نموذج تجريبي محلي لرمز التحقق.
/// في الإنتاج: الخادم يولّد الرمز ويرسله بـ SMS ولا يعيده للتطبيق أبداً، ويتحقق منه ويحدّ المحاولات وعدد الإرسال لكل رقم.
/// هنا send() يرجع الرمز ليُعرض على الشاشة (للتجربة فقط).
class OtpService {
  final _m = <String, _OtpEntry>{};
  static const maxTries = 5;
  static const ttl = Duration(minutes: 5);

  String send(String phone) {
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    _m[phone] = _OtpEntry(code);
    return code;
  }

  /// يرجع null عند النجاح، وإلا رسالة الخطأ.
  String? check(String phone, String code) {
    final o = _m[phone];
    if (o == null) return 'اطلب رمزاً جديداً أولاً';
    if (DateTime.now().difference(o.at) > ttl) {
      _m.remove(phone);
      return 'انتهت صلاحية الرمز، اطلب رمزاً جديداً';
    }
    o.tries++;
    if (o.code != code) {
      if (o.tries >= maxTries) {
        _m.remove(phone);
        return 'تجاوزت عدد المحاولات، اطلب رمزاً جديداً';
      }
      return 'الرمز غير صحيح (${maxTries - o.tries} محاولات متبقية)';
    }
    _m.remove(phone);
    return null;
  }
}

final otp = OtpService();

// ═══════════════ Shell ═══════════════
void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'طبيبك للمراكز',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: kRed, scaffoldBackgroundColor: Colors.white, textTheme: GoogleFonts.cairoTextTheme(ThemeData.light().textTheme)),
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const LoginScreen(),
    ));

const roots = <Widget>[HomeScreen(), BookingsScreen(), ManageScreen(), AccountScreen()];

class Nav extends StatelessWidget {
  const Nav(this.i, {super.key});
  final int i;
  static const items = [(Icons.dashboard_rounded, 'الرئيسية'), (Icons.event_note_rounded, 'الحجوزات'), (Icons.apps_rounded, 'الإدارة'), (Icons.person_rounded, 'حسابي')];
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4))]),
        child: SafeArea(
          top: false,
          child: Row(children: [
            for (var k = 0; k < items.length; k++)
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (k != i) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => roots[k]), (r) => false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(items[k].$1, color: k == i ? kRed : kGrey),
                      Text(items[k].$2, style: t(10.5, w: k == i ? FontWeight.w800 : FontWeight.w500, c: k == i ? kRed : kGrey)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
}

/// Red header + rounded sheet. [nav] != null => root page (no back arrow, bottom nav).
class RPage extends StatelessWidget {
  const RPage(this.title, {super.key, required this.body, this.nav, this.action, this.bottom});
  final String title;
  final Widget body;
  final int? nav;
  final Widget? action, bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: Column(children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 60,
                child: Row(children: [
                  SizedBox(width: 56, child: action),
                  Expanded(child: Text(title, textAlign: TextAlign.center, style: t(20, w: FontWeight.w800, c: Colors.white))),
                  SizedBox(
                    width: 56,
                    child: nav != null ? null : IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 36, textDirection: TextDirection.ltr)),
                  ),
                ]),
              ),
            ),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(color: kBg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                child: Column(children: [Expanded(child: body), if (bottom != null) bottom!, if (nav != null) Nav(nav!)]),
              ),
            ),
          ]),
        ),
      );
}

// ═══════════════ 1. Auth — Login · OTP · Register · Pending ═══════════════
Widget authHeader(String sub, {IconData icon = Icons.local_hospital_rounded, String title = 'طبيبك', double size = 34, double h = 250}) => Container(
      height: h, width: double.infinity,
      decoration: const BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.vertical(bottom: Radius.circular(80))),
      child: SafeArea(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 58),
          Text(title, style: t(size, w: FontWeight.w900, c: Colors.white)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(sub, textAlign: TextAlign.center, style: t(13, w: FontWeight.w500, c: Colors.white))),
        ]),
      ),
    );

/// بعد نجاح الدخول: المركز المعتمد → الرئيسية، وإلا شاشة حالة الطلب.
void enterApp(BuildContext c, Member m) {
  db.me = m;
  final Widget w = db.center.status == 1 ? const HomeScreen() : const PendingScreen();
  Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => w), (r) => false);
}

void logout(BuildContext c) {
  db.me = null;
  Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
}

// ── Login ──
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final u = TextEditingController();

  @override
  void dispose() {
    u.dispose();
    super.dispose();
  }

  void next() {
    final ph = normPhone(u.text);
    if (ph == null) return snack(context, 'أدخل رقم هاتف سوداني صحيحاً (مثال: 912345678)');
    // ملاحظة: في الإنتاج لا يكشف الخادم هل الرقم مسجّل أم لا (منعاً لتعداد الأرقام)؛ هنا نوضّح للمستخدم لأنها نسخة تجريبية.
    final m = db.memberByPhone(ph);
    if (m == null) {
      confirm(context, 'هذا الرقم غير مسجّل', 'لا يوجد حساب مركز بهذا الرقم. تأكد من الرقم أو سجّل مركزك الآن.', 'تسجيل مركز جديد', () => go(context, RegisterPhoneScreen(initial: u.text)));
      return;
    }
    if (!m.active) return snack(context, 'تم إيقاف هذا الحساب من مدير المركز');
    go(context, OtpScreen(ph, (c) => enterApp(c, m)));
  }

  void demo(String ph) {
    if (db.memberByPhone(ph) == null) db.loadDemo();
    u.text = ph.replaceFirst('+249', '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          authHeader('بوابة المراكز الطبية'),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 16), children: [
              Center(child: Text('تسجيل دخول المركز', style: t(21, w: FontWeight.w800))),
              gap(4),
              Center(child: Text('ندخلك برقم هاتفك ورمز تحقق يصلك برسالة — بدون بريد إلكتروني أو كلمة مرور', textAlign: TextAlign.center, style: t(12, w: FontWeight.w500, c: kGrey, h: 1.6))),
              phoneFld('رقم الهاتف', u),
              gap(18),
              btn('إرسال رمز التحقق', next),
              gap(10),
              btn('تسجيل مركز جديد', () => go(context, RegisterPhoneScreen(initial: u.text)), outline: true, h: 46),
              gap(18),
              panel([
                Text('حسابات تجريبية (بيانات نموذجية)', style: t(12.5, c: kAmber)),
                gap(8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  GestureDetector(onTap: () => demo(kDemoManager), child: pill('مدير المركز', kChip, kInk)),
                  GestureDetector(onTap: () => demo(kDemoReception), child: pill('موظفة الاستقبال', kChip, kInk)),
                ]),
              ]),
              Center(child: Text('حساب المركز يُفعَّل بعد مراجعة الترخيص من إدارة طبيبك', textAlign: TextAlign.center, style: t(11.5, w: FontWeight.w500, c: kGrey, h: 1.6))),
            ]),
          ),
        ]),
      );
}

// ── OTP (شاشة مشتركة: الدخول والتسجيل) ──
class OtpScreen extends StatefulWidget {
  const OtpScreen(this.phone, this.onVerified, {super.key});
  final String phone;
  final void Function(BuildContext) onVerified; // تُستدعى بعد نجاح التحقق
  @override
  State<OtpScreen> createState() => _OtpState();
}

class _OtpState extends State<OtpScreen> {
  final ctl = TextEditingController();
  Timer? timer;
  int left = 0;
  String demoCode = '';
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    send();
  }

  @override
  void dispose() {
    timer?.cancel();
    ctl.dispose();
    super.dispose();
  }

  void send() {
    demoCode = otp.send(widget.phone);
    ctl.clear();
    err = null;
    left = 60;
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) {
        tm.cancel();
        return;
      }
      setState(() => left--);
      if (left <= 0) tm.cancel();
    });
  }

  void verify() {
    if (busy) return;
    final code = latin(ctl.text).trim();
    if (code.length != 6) {
      setState(() => err = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }
    final e = otp.check(widget.phone, code);
    if (e != null) {
      setState(() => err = e);
      return;
    }
    busy = true;
    widget.onVerified(context);
  }

  @override
  Widget build(BuildContext context) => RPage(
        'التحقق من الرقم',
        bottom: bar(context, [btn('تحقق', verify)]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          gap(10),
          Center(child: tile(Icons.sms_rounded, size: 76, dark: true)),
          gap(16),
          Center(child: Text('أدخل رمز التحقق', style: t(19, w: FontWeight.w800))),
          gap(6),
          Center(child: Text('أرسلنا رمزاً من 6 أرقام إلى', style: t(12.5, w: FontWeight.w500, c: kGrey))),
          Center(child: Text(fmtPhone(widget.phone), textDirection: TextDirection.ltr, style: t(15))),
          gap(14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kAmberBg, borderRadius: BorderRadius.circular(14)),
            child: Text('وضع تجريبي: لا تُرسَل رسالة SMS فعلية في هذا النموذج.\nرمز التحقق: $demoCode', style: t(12.5, c: kAmber, h: 1.7)),
          ),
          gap(6),
          fld('رمز التحقق', ctl,
              kb: TextInputType.number, ltr: true, hint: '------', align: TextAlign.center,
              fmt: [digitsFmt, LengthLimitingTextInputFormatter(6)],
              style: t(24, w: FontWeight.w800).copyWith(letterSpacing: 10),
              onChanged: (v) {
                if (err != null) setState(() => err = null);
                if (latin(v).length == 6) verify();
              }),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: t(12, c: kRed))),
          gap(16),
          Center(
            child: left > 0
                ? Text('إعادة الإرسال بعد $left ثانية', style: t(12.5, w: FontWeight.w500, c: kGrey))
                : GestureDetector(onTap: () => setState(send), child: Text('إعادة إرسال الرمز', style: t(13.5, c: kRed))),
          ),
        ]),
      );
}

// ── Register 1/2: رقم هاتف المدير + OTP ──
class RegisterPhoneScreen extends StatefulWidget {
  const RegisterPhoneScreen({super.key, this.initial = ''});
  final String initial;
  @override
  State<RegisterPhoneScreen> createState() => _RegPhoneState();
}

class _RegPhoneState extends State<RegisterPhoneScreen> {
  late final p = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    p.dispose();
    super.dispose();
  }

  void next() {
    final ph = normPhone(p.text);
    if (ph == null) return snack(context, 'أدخل رقم هاتف سوداني صحيحاً (مثال: 912345678)');
    if (db.memberByPhone(ph) != null) return snack(context, 'هذا الرقم مسجّل مسبقاً — سجّل الدخول بدلاً من ذلك');
    go(context, OtpScreen(ph, (c) => Navigator.pushReplacement(c, MaterialPageRoute(builder: (_) => RegisterWizard(ph)))));
  }

  Widget stepRow(IconData i, String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [tile(i, size: 38), const SizedBox(width: 12), Expanded(child: two(a, b))]),
      );

  @override
  Widget build(BuildContext context) => RPage(
        'تسجيل مركز جديد',
        bottom: bar(context, [btn('إرسال رمز التحقق', next)]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          panel([
            Text('ابدأ برقم هاتف مدير المركز', style: t(15.5, w: FontWeight.w800)),
            gap(4),
            Text('نرسل إليه رمز تحقق لإثبات ملكية الرقم. لا نحتاج بريداً إلكترونياً، وبه يدخل المدير إلى حسابه لاحقاً.', style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.6)),
          ]),
          phoneFld('رقم هاتف مدير المركز', p),
          sec('ما الذي سيأتي بعد ذلك؟'),
          panel([
            stepRow(Icons.local_hospital_rounded, 'بيانات المركز', 'الاسم والنوع والترخيص'),
            stepRow(Icons.place_rounded, 'الموقع والخدمات', 'الولاية والعنوان وساعات الدوام'),
            stepRow(Icons.support_agent_rounded, 'الاستقبال والترخيص', 'موظف الاستقبال وصورة الترخيص'),
          ]),
        ]),
      );
}

// ── Register 2/2: نموذج التسجيل (3 خطوات) ──
class RegisterWizard extends StatefulWidget {
  const RegisterWizard(this.phone, {super.key, this.again = false});
  final String phone; // رقم المدير الذي تم التحقق منه
  final bool again; // إعادة إرسال طلب مرفوض (الحقول معبّأة من بيانات الطلب السابق)
  @override
  State<RegisterWizard> createState() => _WizardState();
}

class _WizardState extends State<RegisterWizard> {
  static const names = ['المركز', 'الموقع والخدمات', 'الاستقبال والترخيص'];
  int step = 0;
  final sc = ScrollController();
  CenterProfile? get pre => widget.again ? db.center : null;
  Member? get rec0 => widget.again ? db.reception : null;

  late final n = TextEditingController(text: pre?.name), lic = TextEditingController(text: pre?.lic), cph = TextEditingController(text: pre?.phone);
  late final mgr = TextEditingController(text: widget.again ? db.manager?.name : '');
  late final loc = TextEditingController(text: pre?.locality), adr = TextEditingController(text: pre?.address);
  late final from = TextEditingController(text: pre?.from ?? '8:00 ص'), to = TextEditingController(text: pre?.to ?? '10:00 م');
  late final rn = TextEditingController(text: rec0?.name), rp = TextEditingController(text: rec0?.phone.replaceFirst('+249', ''));
  late final kind = {pre?.kind ?? 1}, svc = {...(pre?.svc ?? {0, 1, 2})};
  late int state = pre?.state ?? 0;
  late bool self = widget.again && db.reception == null;
  bool docOk = false, agree = false;

  @override
  void dispose() {
    for (final c in [n, lic, cph, mgr, loc, adr, from, to, rn, rp]) {
      c.dispose();
    }
    sc.dispose();
    super.dispose();
  }

  void toTop() {
    if (sc.hasClients) sc.jumpTo(0);
  }

  String? check() {
    if (step == 0) {
      if (n.text.trim().length < 3) return 'أدخل اسم المركز';
      if (lic.text.trim().length < 3) return 'أدخل رقم ترخيص المركز';
      if (latin(cph.text).replaceAll(RegExp(r'\D'), '').length < 9) return 'أدخل هاتف المركز';
      if (mgr.text.trim().length < 3) return 'أدخل اسم مدير المركز';
    } else if (step == 1) {
      if (loc.text.trim().length < 2) return 'أدخل المحلية أو الحي';
      if (from.text.trim().isEmpty || to.text.trim().isEmpty) return 'حدّد ساعات الدوام';
      if (svc.isEmpty) return 'اختر خدمة واحدة على الأقل';
    } else {
      if (!self) {
        if (rn.text.trim().length < 3) return 'أدخل اسم موظف الاستقبال';
        final rp2 = normPhone(rp.text);
        if (rp2 == null) return 'أدخل هاتف موظف الاستقبال صحيحاً';
        if (rp2 == widget.phone) return 'هاتف الاستقبال يجب أن يختلف عن هاتف المدير';
      }
      if (!docOk) return 'أرفق صورة ترخيص المركز';
      if (!agree) return 'يجب الموافقة على الشروط وسياسة الخصوصية';
    }
    return null;
  }

  void next() {
    final e = check();
    if (e != null) return snack(context, e);
    if (step < 2) {
      setState(() => step++);
      toTop();
    } else {
      submit();
    }
  }

  void submit() {
    final c = CenterProfile(
      name: n.text.trim(), kind: kind.first, lic: lic.text.trim(), state: state, locality: loc.text.trim(), address: adr.text.trim(),
      phone: cph.text.trim(), from: from.text.trim(), to: to.text.trim(), svc: {...svc}, status: 0, reqNo: db.newReq(), docAttached: docOk,
    );
    final rec = self ? null : Member(rn.text.trim(), normPhone(rp.text)!, 1);
    if (widget.again) {
      db.resubmit(c, mgr.text.trim(), rec);
    } else {
      db.register(c, Member(mgr.text.trim(), widget.phone, 0), rec);
    }
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PendingScreen()), (r) => false);
  }

  List<Widget> s0() => [
        fld('اسم المركز', n, hint: 'مثال: مركز المسباح الطبي'),
        sec('نوع المركز'),
        chips(kCenterKinds, kind, () => setState(() {})),
        fld('رقم ترخيص المركز', lic, ltr: true, hint: 'كما في شهادة الترخيص'),
        fld('هاتف المركز', cph, kb: TextInputType.phone, ltr: true, hint: 'رقم يتواصل عليه المرضى', fmt: [FilteringTextInputFormatter.allow(RegExp('[0-9+\u0660-\u0669\u06F0-\u06F9 ]'))]),
        fld('اسم مدير المركز', mgr, hint: 'الاسم الثلاثي'),
        lockedRow('هاتف مدير المركز (حساب الدخول)', fmtPhone(widget.phone), tail: pill('تم التحقق', kGreenBg, kGreen)),
      ];

  List<Widget> s1() => [
        sec('الولاية'),
        dd(state, kStates, (v) => setState(() => state = v)),
        fld('المحلية / الحي', loc, hint: 'مثال: بحري - المسبح'),
        fld('العنوان التفصيلي (اختياري)', adr, lines: 2, hint: 'الشارع وأقرب معلم'),
        Row(children: [Expanded(child: fld('بداية الدوام', from)), const SizedBox(width: 12), Expanded(child: fld('نهاية الدوام', to))]),
        sec('الخدمات التي يقدّمها المركز'),
        chips(kTypes, svc, () => setState(() {}), multi: true),
      ];

  List<Widget> s2() => [
        panel([
          switchRow('أتولى استقبال الحجوزات بنفسي', self, (v) => setState(() => self = v)),
          Text('موظف الاستقبال يستلم طلبات الحجز ويقبلها أو يرفضها، ويدخل بهاتفه ورمز تحقق. يمكنك إضافة غيره لاحقاً من «مستخدمو المركز».', style: t(11.5, w: FontWeight.w500, c: kGrey, h: 1.6)),
        ]),
        if (!self) ...[
          fld('اسم موظف الاستقبال', rn, hint: 'الاسم الثلاثي'),
          phoneFld('هاتف موظف الاستقبال', rp),
        ],
        sec('ترخيص المركز'),
        Container(
          padding: const EdgeInsets.all(12), decoration: card(16),
          child: Row(children: [
            tile(docOk ? Icons.check_circle_rounded : Icons.upload_file_rounded, size: 40),
            const SizedBox(width: 12),
            Expanded(child: two('صورة شهادة الترخيص', docOk ? 'ترخيص_المركز.jpg' : 'صورة واضحة وسارية المفعول')),
            GestureDetector(
              onTap: () {
                setState(() => docOk = !docOk);
                if (docOk) snack(context, 'نموذج تجريبي: في النسخة الفعلية يُفتح معرض الصور أو الكاميرا');
              },
              child: Text(docOk ? 'إزالة' : 'إرفاق', style: t(13, c: kRed)),
            ),
          ]),
        ),
        gap(12),
        Row(children: [
          Checkbox(value: agree, activeColor: kRed, onChanged: (v) => setState(() => agree = v ?? false)),
          Expanded(
            child: Wrap(children: [
              Text('أوافق على ', style: t(12.5, w: FontWeight.w500)),
              GestureDetector(onTap: () => go(context, const TermsScreen()), child: Text('شروط الاستخدام وسياسة الخصوصية', style: t(12.5, c: kRed))),
            ]),
          ),
        ]),
      ];

  @override
  Widget build(BuildContext context) => RPage(
        widget.again ? 'تعديل طلب التسجيل' : 'تسجيل مركز جديد',
        bottom: bar(context, [
          btn(step == 2 ? (widget.again ? 'إعادة إرسال الطلب' : 'إرسال طلب التسجيل') : 'التالي', next),
          if (step > 0)
            btn('السابق', () {
              setState(() => step--);
              toTop();
            }, outline: true, h: 44),
        ]),
        body: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          stepper(step, names),
          ...(step == 0 ? s0() : step == 1 ? s1() : s2()),
        ]),
      );
}

// ── Pending: حالة طلب التسجيل (قيد المراجعة / معتمد / مرفوض) ──
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) {
          final cn = db.center;
          final info = switch (cn.status) {
            0 => (Icons.hourglass_top_rounded, 'طلبك قيد المراجعة', 'نراجع ترخيص المركز وبياناته قبل تفعيل الحساب'),
            1 => (Icons.verified_rounded, 'تم اعتماد مركزك', 'يمكنك الآن استقبال الحجوزات وإدارة مركزك'),
            _ => (Icons.error_outline_rounded, 'تعذّر اعتماد الطلب', 'راجع السبب أدناه ثم عدّل بياناتك وأعد الإرسال'),
          };
          final rec = db.reception;
          return Scaffold(
            body: Column(children: [
              authHeader(info.$3, icon: info.$1, title: info.$2, size: 26),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), children: [
                  panel([
                    kv('رقم الطلب', cn.reqNo),
                    kv('المركز', cn.name),
                    kv('رقم الترخيص', cn.lic),
                    kv('هاتف المدير', fmtPhone(db.manager?.phone ?? '')),
                    if (rec != null) kv('الاستقبال', '${rec.name} · ${fmtPhone(rec.phone)}'),
                  ]),
                  if (cn.status == 2) panel([Text('سبب الرفض', style: t(13, c: kAmber)), gap(4), Text(cn.reason, style: t(13, w: FontWeight.w500, h: 1.6))]),
                  if (cn.status == 0)
                    panel([
                      Text('وضع تجريبي', style: t(12.5, c: kAmber)),
                      gap(4),
                      Text('قرار الاعتماد يصدر من لوحة إدارة طبيبك. استخدم الزرين التاليين لمحاكاته:', style: t(12, w: FontWeight.w500, c: kGrey, h: 1.6)),
                      gap(10),
                      btn('محاكاة: اعتماد المركز', () {
                        cn.status = 1;
                        db.ping();
                      }, h: 44),
                      gap(8),
                      btn('محاكاة: رفض الطلب', () {
                        cn.status = 2;
                        cn.reason = 'صورة شهادة الترخيص غير واضحة، أعد رفعها.';
                        db.ping();
                      }, outline: true, h: 44),
                    ]),
                  if (cn.status == 1) btn('ابدأ الآن', () => Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false)),
                  if (cn.status == 2) ...[
                    btn('تعديل البيانات وإعادة الإرسال', () => go(c, RegisterWizard(db.manager?.phone ?? '', again: true))),
                    gap(8),
                    btn('المساعدة والدعم', () => go(c, const HelpScreen()), outline: true, h: 44),
                  ],
                  gap(16),
                  Center(child: GestureDetector(onTap: () => logout(c), child: Text('تسجيل الخروج', style: t(13.5, c: kRed)))),
                ]),
              ),
            ]),
          );
        },
      );
}

// ═══════════════ 2. Dashboard ═══════════════
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  Widget stat(IconData i, String v, String l) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(5), padding: const EdgeInsets.all(14), decoration: card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [tile(i), gap(8), Text(v, style: t(21, w: FontWeight.w800)), Text(l, style: t(11.5, w: FontWeight.w500, c: kGrey))]),
        ),
      );
  Widget quick(BuildContext c, IconData i, String s, Widget to) => Expanded(
        child: GestureDetector(
          onTap: () => go(c, to),
          child: Container(margin: const EdgeInsets.all(5), padding: const EdgeInsets.symmetric(vertical: 12), decoration: card(), child: Column(children: [tile(i, dark: true), gap(6), Text(s, textAlign: TextAlign.center, style: t(11.5))])),
        ),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) {
          final fresh = db.bookings.where((b) => b.status == 'جديد').toList();
          // الإجراءات السريعة تظهر حسب صلاحيات المستخدم (الاستقبال لا يرى التقارير مثلاً).
          final acts = <Widget>[
            if (db.can(2)) quick(c, Icons.person_add_alt_1_rounded, 'إضافة أخصائي', const DoctorLookupScreen()),
            if (db.can(1)) quick(c, Icons.add_box_rounded, 'إضافة سرير', const BedForm()),
            if (db.can(3)) quick(c, Icons.bar_chart_rounded, 'التقارير', const ReportsScreen()),
          ];
          return RPage(
            db.center.name.isEmpty ? 'طبيبك' : db.center.name,
            nav: 0,
            action: IconButton(onPressed: () => go(c, const NotifsScreen()), icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 28)),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [stat(Icons.mark_email_unread_rounded, '${db.fresh}', 'طلبات جديدة'), stat(Icons.event_available_rounded, '${db.bookings.where((b) => b.status == 'مؤكد').length}', 'حجوزات مؤكدة')]),
              Row(children: [
                stat(Icons.bed_rounded, '${db.freeBeds}/${db.beds.length}', 'أسرّة متاحة'),
                db.can(3) ? stat(Icons.payments_rounded, '${money(db.revenue)} ج.س', 'الإيرادات') : stat(Icons.event_note_rounded, '${db.bookings.length}', 'إجمالي الحجوزات'),
              ]),
              if (acts.isNotEmpty) Row(children: [...acts, for (var i = acts.length; i < 3; i++) const Expanded(child: SizedBox())]),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                child: Row(children: [Expanded(child: sec('طلبات تنتظر ردّك')), GestureDetector(onTap: () => go(c, const BookingsScreen()), child: Text('عرض الكل', style: t(12.5, c: kRed)))]),
              ),
              if (fresh.isEmpty) SizedBox(height: 160, child: empty(Icons.done_all_rounded, 'لا توجد طلبات جديدة')),
              for (final b in fresh.take(4)) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: BookingCard(b)),
            ]),
          );
        },
      );
}

// ═══════════════ 3. Bookings inbox ═══════════════
class BookingCard extends StatelessWidget {
  const BookingCard(this.b, {super.key});
  final Booking b;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => go(context, BookingDetails(b)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(),
          child: Column(children: [
            Row(children: [tile(b.type == 2 ? kHomeIcons[b.svc] : kTypeIcons[b.type]), const SizedBox(width: 12), Expanded(child: two(b.patient, b.title)), badge(b.status)]),
            gap(8),
            Row(children: [
              const Icon(Icons.access_time_rounded, size: 16, color: kGrey),
              const SizedBox(width: 6),
              Expanded(child: Text(b.when, style: t(12, w: FontWeight.w600, c: const Color(0xFF4B5873)))),
              Text('${b.price} ج.س', style: t(13.5)),
            ]),
          ]),
        ),
      );
}

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsState();
}

class _BookingsState extends State<BookingsScreen> {
  final type = {0}, st = {0};
  static const sts = ['الكل', 'جديد', 'مؤكد', 'مكتمل', 'مرفوض'];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) {
          final list = db.bookings.where((b) => (type.first == 0 || b.type == type.first - 1) && (st.first == 0 || b.status == sts[st.first])).toList();
          return RPage(
            'الحجوزات',
            nav: 1,
            body: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: chips(['الكل', ...kTypes], type, () => setState(() {}))),
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: chips(sts, st, () => setState(() {}))),
              Expanded(child: list.isEmpty ? empty(Icons.inbox_rounded, 'لا توجد حجوزات مطابقة') : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [for (final b in list) BookingCard(b)])),
            ]),
          );
        },
      );
}

// ═══════════════ 4. Booking details + accept / reject / complete ═══════════════
class BookingDetails extends StatefulWidget {
  const BookingDetails(this.b, {super.key});
  final Booking b;
  @override
  State<BookingDetails> createState() => _BookingDetailsState();
}

class _BookingDetailsState extends State<BookingDetails> {
  String? sel;
  Booking get b => widget.b;

  List<String> get options => b.type == 1 ? [for (final x in db.beds.where((x) => x.free && x.type == b.extra)) 'سرير ${x.no}'] : db.team(b.svc);

  void accept() {
    if (b.type != 0 && sel == null) return snack(context, b.type == 1 ? 'اختر السرير أولاً' : 'اختر ${kWho[b.svc]} أولاً');
    if (b.type == 1) db.beds.firstWhere((x) => 'سرير ${x.no}' == sel).free = false;
    db.set(b, 'مؤكد', who: sel ?? '');
    snack(context, 'تم قبول الحجز داخل التطبيق؛ إشعار المريض يحتاج ربط خادم');
    Navigator.pop(context);
  }

  void reject() {
    const reasons = ['الطبيب غير متاح في هذا الموعد', 'لا توجد أسرّة متاحة', 'خارج نطاق التغطية', 'سبب آخر'];
    var r = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('سبب الرفض', style: t(17, w: FontWeight.w800)),
            gap(8),
            for (var i = 0; i < reasons.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => set(() => r = i),
                leading: Icon(r == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: r == i ? kRed : kGrey),
                title: Text(reasons[i], style: t(13.5, w: FontWeight.w600)),
              ),
            gap(8),
            btn('تأكيد الرفض', () {
              db.set(b, 'مرفوض', note: reasons[r]);
              Navigator.pop(ctx);
              Navigator.pop(context);
            }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'تفاصيل الحجز',
          bottom: !db.can(0)
              ? null
              : b.status == 'جديد'
              ? bar(c, [btn('قبول الحجز', accept), btn('رفض الحجز', reject, outline: true, h: 44)])
              : b.status == 'مؤكد'
                  ? bar(c, [btn('تم إنهاء الخدمة', () {
                      if (b.type == 1) {
                        for (final bed in db.beds.where((x) => 'سرير ${x.no}' == b.assigned)) {
                          bed.free = true;
                        }
                      }
                      db.set(b, 'مكتمل', who: b.assigned);
                      Navigator.pop(c);
                    })])
                  : null,
          body: ListView(padding: const EdgeInsets.all(16), children: [
            panel([
              Row(children: [
                tile(Icons.person_rounded, size: 52, dark: true),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b.patient, style: t(16, w: FontWeight.w800)), Directionality(textDirection: TextDirection.ltr, child: Text(b.phone, style: t(12.5, w: FontWeight.w500, c: kGrey)))])),
                const CircleAvatar(backgroundColor: kRed, child: Icon(Icons.phone_rounded, color: Colors.white)),
              ]),
            ]),
            panel([
              Row(children: [Expanded(child: Text(b.type == 2 ? 'خدمة منزلية · ${kHomeNames[b.svc]}' : kTypes[b.type], style: t(15))), badge(b.status)]),
              const Divider(color: kLine, height: 22),
              kv('الخدمة', b.title),
              kv('الموعد', b.when),
              if (b.type == 1) kv('نوع السرير', b.extra),
              if (b.type == 2) kv('العنوان', b.extra),
              kv('المبلغ', '${b.price} ج.س', bold: true),
              kv('طريقة الدفع', b.type == 2 ? 'نقداً عند الزيارة' : 'مدفوع عبر التطبيق'),
              if (b.assigned.isNotEmpty) kv(b.type == 1 ? 'السرير المخصص' : 'المكلّف', b.assigned),
              if (b.note.isNotEmpty) kv('سبب الرفض', b.note),
            ]),
            if (b.status == 'جديد' && b.type != 0 && db.can(0)) ...[
              sec(b.type == 1 ? 'تخصيص سرير' : 'تكليف ${kWho[b.svc]}'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
                child: DropdownButton<String>(
                  value: sel, isExpanded: true, underline: const SizedBox(), hint: Text(options.isEmpty ? (b.type == 1 ? 'لا توجد أسرّة متاحة من هذا النوع' : 'لا يوجد ${kWho[b.svc]} متاح — أضفه من صفحة الخدمة') : 'اختر', style: t(13, w: FontWeight.w500, c: kGrey)),
                  items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o, style: t(13.5, w: FontWeight.w600)))],
                  onChanged: (v) => setState(() => sel = v),
                ),
              ),
            ],
          ]),
        ),
      );
}

// ═══════════════ 5. Management hub ═══════════════
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});
  Widget item(BuildContext c, IconData i, String s, String sub, Widget to) => GestureDetector(
        onTap: () => go(c, to),
        child: Container(padding: const EdgeInsets.all(14), decoration: card(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [tile(i, dark: true, size: 50), const Spacer(), Text(s, style: t(15, w: FontWeight.w800)), Text(sub, style: t(11.5, w: FontWeight.w500, c: kGrey))])),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'الإدارة',
          nav: 2,
          body: GridView.count(crossAxisCount: 2, padding: const EdgeInsets.all(16), mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.05, children: [
            if (db.can(2)) item(c, Icons.medical_services_rounded, 'الأخصائيون', '${db.docs.length} أخصائي', const DoctorsScreen()),
            if (db.can(1)) item(c, Icons.bed_rounded, 'الأسرّة', '${db.freeBeds} متاح من ${db.beds.length}', const BedsScreen()),
            if (db.can(2)) item(c, Icons.home_rounded, 'الخدمات المنزلية', '${db.svcs.where((s) => s.on).length} خدمة مفعّلة', const HomeSvcScreen()),
            if (db.can(3)) item(c, Icons.bar_chart_rounded, 'التقارير', 'الإيرادات والحجوزات', const ReportsScreen()),
            item(c, Icons.notifications_rounded, 'الإشعارات', '${db.fresh} جديد', const NotifsScreen()),
            if (db.isManager) item(c, Icons.group_rounded, 'المستخدمون', '${db.members.length} مستخدم', const UsersScreen()),
          ]),
        ),
      );
}

// ═══════════════ 6. Doctors ═══════════════
class DoctorsScreen extends StatelessWidget {
  const DoctorsScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'الأخصائيون',
          bottom: bar(c, [btn('+ إضافة أخصائي', () => go(c, const DoctorLookupScreen()))]),
          body: db.docs.isEmpty
              ? empty(Icons.person_off_rounded, 'لم تضف أي أخصائي بعد')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final d in db.docs)
                    GestureDetector(
                      onTap: () => go(c, DoctorForm(d: d)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(),
                        child: Column(children: [
                          Row(children: [
                            tile(Icons.person_rounded, size: 52),
                            const SizedBox(width: 12),
                            Expanded(child: two(d.name, '${d.spec} · ${d.exp} سنوات خبرة')),
                            if (!d.p.verified) ...[pill('قيد التحقق', kAmberBg, kAmber), const SizedBox(width: 6)],
                            Switch(value: d.on, onChanged: (v) { d.on = v; db.ping(); }),
                          ]),
                          gap(6),
                          kv('المؤهلات', d.quals),
                          kv('الدوام', '${d.days} · ${d.hours}'),
                          kv('سعر الكشف', '${d.price} ج.س', bold: true),
                        ]),
                      ),
                    ),
                ]),
        ),
      );
}

/// بطاقة الملف العام للأخصائي (للقراءة فقط) — تُعرض عند العثور عليه برقم التسجيل وعند فتح بياناته.
Widget profileCard(DocProfile p) => panel([
      Row(children: [
        tile(Icons.person_rounded, size: 60, dark: true),
        const SizedBox(width: 12),
        Expanded(child: two(p.name, '${p.spec} · ${p.exp} سنوات خبرة')),
        p.verified ? pill('موثّق', kGreenBg, kGreen) : pill('قيد التحقق', kAmberBg, kAmber),
      ]),
      const Divider(color: kLine, height: 22),
      kv('رقم التسجيل', p.lic),
      kv('الجنس', p.gender == 0 ? 'ذكر' : 'أنثى'),
      kv('المؤهلات', p.quals),
      kv('يعمل في', centersTxt(p.others + (db.linked(p) != null ? 1 : 0))),
      if (!p.verified) Padding(padding: const EdgeInsets.only(top: 6), child: Text('لن يظهر للمرضى حتى يوثّقه فريق طبيبك.', style: t(11.5, w: FontWeight.w500, c: kAmber))),
    ]);

/// شروط عمل الأخصائي في هذا المركز (السعر والدوام والزيارات المنزلية). تُستخدم في البحث وفي نموذج الأخصائي.
class Terms {
  final price = TextEditingController(), from = TextEditingController(), to = TextEditingController(), homePrice = TextEditingController();
  final wd = <int>{};
  bool home = false;

  void load([Doc? d]) {
    price.text = d?.price.replaceAll(',', '') ?? '';
    from.text = d?.from ?? '8:00 ص';
    to.text = d?.to ?? '6:00 م';
    homePrice.text = d?.homePrice.replaceAll(',', '') ?? '';
    wd
      ..clear()
      ..addAll(d?.wd ?? const {0, 1, 2, 3, 4});
    home = d?.home ?? false;
  }

  void dispose() {
    price.dispose();
    from.dispose();
    to.dispose();
    homePrice.dispose();
  }

  /// يرجع رسالة الخطأ أو null إن كانت الشروط صالحة.
  String? check() {
    if (num(price.text) <= 0) return 'أدخل سعر الكشف';
    if (wd.isEmpty) return 'اختر يوم عمل واحداً على الأقل';
    if (from.text.trim().isEmpty || to.text.trim().isEmpty) return 'حدّد ساعات الدوام';
    return null;
  }

  void fill(Doc d) {
    d.price = money(num(price.text));
    d.wd = {...wd};
    d.from = from.text.trim();
    d.to = to.text.trim();
    d.home = home;
    d.homePrice = home && num(homePrice.text) > 0 ? money(num(homePrice.text)) : '';
  }

  List<Widget> view(VoidCallback refresh) => [
        sec('شروط العمل في مركزك'),
        fld('سعر الكشف (ج.س)', price, kb: TextInputType.number, fmt: [digitsFmt]),
        sec('أيام العمل'),
        chips(kDays, wd, refresh, multi: true),
        Row(children: [Expanded(child: fld('من', from)), const SizedBox(width: 12), Expanded(child: fld('إلى', to))]),
        gap(8),
        switchRow('يقدّم زيارات منزلية', home, (v) {
          home = v;
          refresh();
        }),
        if (home) fld('سعر الزيارة المنزلية (اختياري)', homePrice, kb: TextInputType.number, fmt: [digitsFmt], hint: 'يُستخدم السعر الافتراضي إن تُرك فارغاً'),
      ];
}

// ── إضافة أخصائي: البحث برقم التسجيل في المجلس الطبي ──
enum Look { idle, busy, found, already, none }

class DoctorLookupScreen extends StatefulWidget {
  const DoctorLookupScreen({super.key});
  @override
  State<DoctorLookupScreen> createState() => _LookupState();
}

class _LookupState extends State<DoctorLookupScreen> {
  final lic = TextEditingController();
  final tm = Terms();
  Look st = Look.idle;
  DocProfile? prof;
  String searched = '';

  @override
  void dispose() {
    lic.dispose();
    tm.dispose();
    super.dispose();
  }

  String get digits => latin(lic.text).replaceAll(RegExp(r'\D'), '');

  Future<void> search() async {
    final n = digits;
    if (n.length < 3) {
      snack(context, 'أدخل رقم التسجيل (3 أرقام على الأقل)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => st = Look.busy);
    await Future<void>.delayed(const Duration(milliseconds: 500)); // يحاكي طلب الشبكة — اربطه بواجهة البحث في سجل الأخصائيين
    if (!mounted) return;
    if (digits != n) {
      setState(() => st = Look.idle); // غيّر المستخدم الرقم أثناء البحث
      return;
    }
    final p = db.lookup(n);
    setState(() {
      searched = n;
      prof = p;
      if (p == null) {
        st = Look.none;
      } else if (db.linked(p) != null) {
        st = Look.already;
      } else {
        st = Look.found;
        tm.load();
      }
    });
  }

  /// أي تعديل على الرقم بعد ظهور نتيجة يعيد الصفحة إلى حالة البحث.
  void edited(String v) {
    if (st != Look.idle && latin(v).replaceAll(RegExp(r'\D'), '') != searched) {
      setState(() {
        st = Look.idle;
        prof = null;
      });
    }
  }

  void add() {
    final e = tm.check();
    if (e != null) {
      snack(context, e);
      return;
    }
    final d = Doc(prof!);
    tm.fill(d);
    db.docs.add(d);
    db.ping();
    snack(context, 'تمت إضافة ${prof!.name} إلى مركزك');
    Navigator.pop(context);
  }

  void openExisting() {
    final d = db.linked(prof!);
    if (d == null) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DoctorForm(d: d)));
  }

  void registerNew() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DoctorForm(lic: searched)));

  @override
  Widget build(BuildContext context) {
    final bottom = switch (st) {
      Look.found => bar(context, [btn('إضافة إلى المركز', add)]),
      Look.already => bar(context, [btn('فتح بياناته في المركز', openExisting)]),
      Look.none => bar(context, [btn('تسجيل أخصائي جديد', registerNew)]),
      Look.busy => bar(context, [btn('جارٍ البحث...', () {})]),
      Look.idle => bar(context, [btn('بحث', search)]),
    };
    return RPage(
      'إضافة أخصائي',
      bottom: bottom,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        gap(10),
        panel([
          Row(children: [
            tile(Icons.badge_rounded, dark: true),
            const SizedBox(width: 12),
            Expanded(child: Text('أدخل رقم تسجيل الأخصائي في المجلس الطبي. إن كان مسجّلاً لدينا يظهر ملفه مباشرة لتضيفه إلى مركزك، وإلا تسجّله كأخصائي جديد.', style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.6))),
          ]),
        ]),
        fld('رقم التسجيل (المجلس الطبي)', lic, kb: TextInputType.number, ltr: true, hint: 'مثال: 12345', fmt: [digitsFmt], onChanged: edited, onSubmit: (_) => search()),
        gap(14),
        if (st == Look.busy) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: kRed))),
        if (st == Look.found) ...[
          panel([Row(children: [const Icon(Icons.check_circle_rounded, color: kGreen), const SizedBox(width: 8), Expanded(child: Text('تم العثور على الأخصائي في طبيبك', style: t(13.5, c: kGreen)))])]),
          profileCard(prof!),
          ...tm.view(() => setState(() {})),
        ],
        if (st == Look.already) ...[
          profileCard(prof!),
          panel([Text('هذا الأخصائي مضاف مسبقاً إلى مركزك. يمكنك فتح بياناته لتعديل شروط عمله.', style: t(12.5, w: FontWeight.w600, c: kAmber, h: 1.6))]),
        ],
        if (st == Look.none)
          panel([
            Row(children: [tile(Icons.person_search_rounded, size: 48), const SizedBox(width: 12), Expanded(child: two('لا يوجد أخصائي بهذا الرقم', 'رقم التسجيل: $searched'))]),
            gap(8),
            Text('يبدو أنه غير مسجّل في طبيبك بعد. سجّله الآن ببياناته الأساسية وشروط عمله في مركزك، وسيراجع فريق طبيبك بياناته للتحقق من تسجيله المهني.', style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.6)),
          ]),
      ]),
    );
  }
}

// ── نموذج الأخصائي: تسجيل أخصائي جديد (lic) أو تعديل شروط أخصائي مضاف (d) ──
class DoctorForm extends StatefulWidget {
  const DoctorForm({super.key, this.d, this.lic}) : assert(d != null || lic != null);
  final Doc? d; // أخصائي مضاف للمركز
  final String? lic; // رقم تسجيل أخصائي جديد لم يوجد في السجل
  @override
  State<DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<DoctorForm> {
  Doc? get d => widget.d;

  /// بيانات الهوية (الاسم والتخصص...) تعدَّل فقط للأخصائي الجديد أو الذي سجّله هذا المركز ولم يُوثَّق بعد؛
  /// غير ذلك فهي من ملفه العام في طبيبك وتبقى للقراءة فقط.
  bool get editId => d == null || (d!.p.mine && !d!.p.verified);

  late final n = TextEditingController(text: d?.p.name), q = TextEditingController(text: d?.p.quals), exp = TextEditingController(text: d?.p.exp);
  late final licC = TextEditingController(text: d?.p.lic ?? widget.lic), ph = TextEditingController(text: d?.p.phone.replaceFirst('+249', ''));
  late final spec = {kSpecs.indexOf(d?.p.spec ?? '').clamp(0, kSpecs.length - 1).toInt()};
  late final gender = {d?.p.gender ?? 0};
  late final tm = Terms()..load(d);

  @override
  void dispose() {
    n.dispose();
    q.dispose();
    exp.dispose();
    licC.dispose();
    ph.dispose();
    tm.dispose();
    super.dispose();
  }

  void save() {
    String? phone;
    if (editId) {
      if (n.text.trim().isEmpty) return snack(context, 'أدخل اسم الأخصائي');
      if (q.text.trim().isEmpty) return snack(context, 'أدخل المؤهلات العلمية');
      phone = normPhone(ph.text);
      if (phone == null) return snack(context, 'أدخل رقم هاتف الأخصائي صحيحاً');
    }
    final e = tm.check();
    if (e != null) return snack(context, e);

    final nm = n.text.trim().startsWith('د.') ? n.text.trim() : 'د. ${n.text.trim()}';
    final ex = exp.text.trim().isEmpty ? '0' : '${num(exp.text)}';
    if (d == null) {
      if (db.lookup(licC.text) != null) return snack(context, 'هذا الرقم مسجّل مسبقاً في طبيبك');
      final p = DocProfile(licC.text.trim(), nm, kSpecs[spec.first], q.text.trim(), ex, gender: gender.first, phone: phone!, verified: false, mine: true);
      db.registry.add(p);
      final nd = Doc(p);
      tm.fill(nd);
      db.docs.add(nd);
    } else {
      final x = d!;
      if (editId) {
        x.p
          ..name = nm
          ..spec = kSpecs[spec.first]
          ..quals = q.text.trim()
          ..exp = ex
          ..gender = gender.first
          ..phone = phone!;
      }
      tm.fill(x);
    }
    db.ping();
    snack(context, 'تم حفظ بيانات الأخصائي');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => RPage(
        d == null ? 'تسجيل أخصائي جديد' : 'بيانات الأخصائي',
        bottom: bar(context, [
          btn(d == null ? 'تسجيل وإضافة للمركز' : 'حفظ', save),
          if (d != null)
            btn('إزالة من المركز', () => confirm(context, 'إزالة الأخصائي', 'سيُزال ${d!.name} من مركزك فقط، ويبقى ملفه في طبيبك.', 'إزالة', () {
                  db.docs.remove(d);
                  db.ping();
                  Navigator.pop(context);
                }), outline: true, h: 44),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          gap(10),
          if (!editId) ...[
            profileCard(d!.p),
            panel([Text('بيانات الأخصائي تأتي من ملفه في طبيبك ولا تُعدَّل من المركز؛ يمكنك تعديل شروط عمله في مركزك فقط.', style: t(12, w: FontWeight.w500, c: kGrey, h: 1.6))]),
          ] else ...[
            Center(child: Stack(children: [const CircleAvatar(radius: 44, backgroundColor: Color(0xFFE3E7EE), child: Icon(Icons.person_rounded, size: 58, color: Color(0xFF6B7788))), Positioned(bottom: 0, left: 0, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: kRed, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15)))])),
            fld('الاسم الكامل', n, hint: 'مثال: أحمد محمد علي'),
            sec('التخصص'),
            chips(kSpecs, spec, () => setState(() {})),
            fld('المؤهلات العلمية', q, hint: 'مثال: ماجستير باطنية - جامعة الخرطوم', lines: 3),
            lockedRow('رقم التسجيل (المجلس الطبي)', licC.text),
            fld('سنوات الخبرة', exp, kb: TextInputType.number, fmt: [digitsFmt]),
            sec('الجنس'),
            chips(['ذكر', 'أنثى'], gender, () => setState(() {})),
            phoneFld('رقم هاتف الأخصائي', ph),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('يُستخدم الرقم لتفعيل حساب الأخصائي ودخوله إلى طبيبك برمز تحقق. يراجع فريق طبيبك تسجيله المهني قبل ظهوره للمرضى.', style: t(11.5, w: FontWeight.w500, c: kGrey, h: 1.6))),
          ],
          ...tm.view(() => setState(() {})),
        ]),
      );
}

// ═══════════════ 7. Beds ═══════════════
class BedsScreen extends StatelessWidget {
  const BedsScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'الأسرّة',
          bottom: bar(c, [btn('+ إضافة سرير', () => go(c, const BedForm()))]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              for (final ty in kBedTypes)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 10), decoration: card(14),
                    child: Column(children: [Text(ty, style: t(12, c: kGrey)), Text('${db.beds.where((b) => b.type == ty && b.free).length}/${db.beds.where((b) => b.type == ty).length}', style: t(16, c: kRed))]),
                  ),
                ),
            ]),
            gap(14),
            for (final b in db.beds)
              GestureDetector(
                onTap: () => go(c, BedForm(b: b)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: card(16),
                  child: Row(children: [
                    tile(Icons.bed_rounded),
                    const SizedBox(width: 12),
                    Expanded(child: two('${b.type} · سرير ${b.no}', 'الطابق ${b.floor} · ${b.price} ج.س / يوم')),
                    pill(b.free ? 'متاح' : 'مشغول', b.free ? const Color(0xFFD9F3E1) : const Color(0xFFFDE8EA), b.free ? kGreen : kRed),
                    Switch(value: b.free, onChanged: (v) { b.free = v; db.ping(); }),
                  ]),
                ),
              ),
          ]),
        ),
      );
}

class BedForm extends StatefulWidget {
  const BedForm({super.key, this.b});
  final Bed? b;
  @override
  State<BedForm> createState() => _BedFormState();
}

class _BedFormState extends State<BedForm> {
  static const equip = ['جهاز تنفس', 'مونيتور', 'أكسجين', 'تكييف', 'حمّام خاص'];
  late final type = {kBedTypes.indexOf(widget.b?.type ?? 'ICU').clamp(0, 3).toInt()};
  late final no = TextEditingController(text: widget.b?.no), floor = TextEditingController(text: widget.b?.floor), price = TextEditingController(text: widget.b?.price);
  late final eq = {for (var i = 0; i < equip.length; i++) if ((widget.b?.equip ?? '').contains(equip[i])) i};
  late final free = {widget.b?.free == false ? 1 : 0};

  void save() {
    if (no.text.trim().isEmpty || price.text.trim().isEmpty) return snack(context, 'أدخل رقم السرير وسعر اليوم');
    final b = widget.b ?? Bed('', '', '', '', '');
    b.type = kBedTypes[type.first];
    b.no = no.text.trim();
    b.floor = floor.text.trim().isEmpty ? '1' : floor.text.trim();
    b.price = price.text.trim();
    b.equip = [for (final i in eq) equip[i]].join(' · ');
    b.free = free.first == 0;
    if (widget.b == null) db.beds.add(b);
    db.ping();
    snack(context, 'تم حفظ السرير');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => RPage(
        widget.b == null ? 'إضافة سرير' : 'تعديل سرير',
        bottom: bar(context, [btn('حفظ', save), if (widget.b != null) btn('حذف السرير', () { db.beds.remove(widget.b); db.ping(); Navigator.pop(context); }, outline: true, h: 44)]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          sec('نوع السرير'),
          chips(kBedTypes, type, () => setState(() {})),
          Row(children: [Expanded(child: fld('رقم السرير', no, kb: TextInputType.number)), const SizedBox(width: 12), Expanded(child: fld('الطابق', floor, kb: TextInputType.number))]),
          fld('السعر لليوم (ج.س)', price, kb: TextInputType.number),
          sec('التجهيزات'),
          chips(equip, eq, () => setState(() {}), multi: true),
          sec('الحالة'),
          chips(['متاح', 'مشغول'], free, () => setState(() {})),
        ]),
      );
}

// ═══════════════ 8. Home services — hub + 3 pages (طبيب · تمريض · سحب عينات) ═══════════════
/// Small text dialog shared by the home-service pages.
void ask(BuildContext c, String title, String hint, String init, ValueChanged<String> ok, {TextInputType? kb, String? suffix}) {
  final ctl = TextEditingController(text: init);
  showDialog(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: t(15)),
      content: TextField(controller: ctl, keyboardType: kb, decoration: InputDecoration(hintText: hint, suffixText: suffix)),
      actions: [TextButton(onPressed: () { ok(ctl.text.trim()); Navigator.pop(ctx); }, child: Text('حفظ', style: t(14, c: kRed)))],
    ),
  );
}

void editFee(BuildContext c, String title, Svc s) => ask(c, title, '', s.price, (v) {
      final n = num(v);
      if (n > 0) {
        s.price = money(n);
        db.ping();
      }
    }, kb: TextInputType.number, suffix: 'ج.س');

void addItem(BuildContext c, String title, List<Svc> list) {
  final n = TextEditingController(), p = TextEditingController();
  showDialog(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: t(15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(hintText: 'الاسم')),
        TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'السعر', suffixText: 'ج.س')),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            if (n.text.trim().isEmpty || num(p.text) == 0) return snack(ctx, 'أدخل الاسم والسعر');
            list.add(Svc(n.text.trim(), money(num(p.text))));
            db.ping();
            Navigator.pop(ctx);
          },
          child: Text('إضافة', style: t(14, c: kRed)),
        ),
      ],
    ),
  );
}

void addStaff(BuildContext c, int svc) {
  final n = TextEditingController(), role = {0};
  final roles = svc == 1 ? ['ممرض', 'ممرضة'] : ['فني مختبر', 'فنية مختبر'];
  showDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(svc == 1 ? 'إضافة ممرض / ممرضة' : 'إضافة فني مختبر', style: t(15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: n, decoration: const InputDecoration(hintText: 'الاسم')),
          gap(14),
          chips(roles, role, () => set(() {})),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              if (n.text.trim().isEmpty) return snack(ctx, 'أدخل الاسم');
              final v = '${n.text.trim()} · ${roles[role.first]}';
              if (db.staff.contains(v)) return snack(ctx, 'الاسم موجود مسبقاً');
              db.staff.add(v);
              db.ping();
              Navigator.pop(ctx);
            },
            child: Text('إضافة', style: t(14, c: kRed)),
          ),
        ],
      ),
    ),
  );
}

Widget secAdd(String s, VoidCallback onAdd) => Row(children: [Expanded(child: sec(s)), GestureDetector(onTap: onAdd, child: Text('+ إضافة', style: t(13, c: kRed)))]);

/// Header card of a home-service page: icon, name, on/off switch and the editable fee line.
Widget svcHead(BuildContext c, int i, String sub, String feeLabel) {
  final s = db.svcs[i];
  return panel([
    Row(children: [tile(kHomeIcons[i], size: 52, dark: true), const SizedBox(width: 12), Expanded(child: two(s.name, sub)), Switch(value: s.on, onChanged: (v) { s.on = v; db.ping(); })]),
    const Divider(color: kLine, height: 22),
    InkWell(
      onTap: () => editFee(c, feeLabel, s),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(feeLabel, style: t(13, w: FontWeight.w500, c: kGrey))), Text('${s.price} ج.س  ✎', style: t(13.5, c: kRed))])),
    ),
    if (!s.on) Padding(padding: const EdgeInsets.only(top: 8), child: Text('الخدمة متوقفة ولا تظهر للمرضى', style: t(11.5, w: FontWeight.w500, c: kAmber))),
  ]);
}

/// New / confirmed / completed counters for one home service.
Widget miniStats(int svc) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        for (final s in const ['جديد', 'مؤكد', 'مكتمل'])
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 10), decoration: card(14),
              child: Column(children: [Text(s, style: t(12, c: kGrey)), Text('${db.bookings.where((b) => b.type == 2 && b.svc == svc && b.status == s).length}', style: t(16, c: kRed))]),
            ),
          ),
      ]),
    );

/// Switchable price list (nursing procedures / lab tests).
Widget catalog(BuildContext c, List<Svc> list, IconData icon) => list.isEmpty
    ? panel([Text('القائمة فارغة — أضف أول عنصر', style: t(12.5, w: FontWeight.w500, c: kGrey))])
    : Column(children: [
        for (final s in list)
          Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: card(16),
            child: Row(children: [
              tile(icon, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.name, style: t(14)), GestureDetector(onTap: () => editFee(c, s.name, s), child: Text('${s.price} ج.س  ✎', style: t(12.5, c: kRed)))])),
              Switch(value: s.on, onChanged: (v) { s.on = v; db.ping(); }),
              InkWell(onTap: () { list.remove(s); db.ping(); }, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, color: kGrey))),
            ]),
          ),
      ]);

/// Nurses (svc 1) or lab technicians (svc 2) taken from db.staff.
Widget crew(int svc) {
  final list = db.staff.where((x) => x.contains(svc == 1 ? 'ممرض' : 'مختبر')).toList();
  if (list.isEmpty) return panel([Text('لم تضف ${svc == 1 ? 'أي ممرض' : 'أي فني'} بعد', style: t(12.5, w: FontWeight.w500, c: kGrey))]);
  return Column(children: [
    for (final x in list) panel([Row(children: [tile(Icons.person_rounded, size: 40), const SizedBox(width: 12), Expanded(child: Text(x, style: t(13.5))), GestureDetector(onTap: () { db.staff.remove(x); db.ping(); }, child: const Icon(Icons.delete_outline_rounded, color: kGrey))])]),
  ]);
}

/// Requests of one home service (tap → details / accept / reject).
Widget reqs(int svc) {
  final l = db.bookings.where((b) => b.type == 2 && b.svc == svc).toList();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    sec('الطلبات'),
    if (l.isEmpty) panel([Text('لا توجد طلبات حتى الآن', style: t(12.5, w: FontWeight.w500, c: kGrey))]),
    for (final b in l) BookingCard(b),
  ]);
}

// ── Hub ──
class HomeSvcScreen extends StatefulWidget {
  const HomeSvcScreen({super.key});
  @override
  State<HomeSvcScreen> createState() => _HomeSvcState();
}

class _HomeSvcState extends State<HomeSvcScreen> {
  final areas = {0, 1};
  static const pages = <Widget>[HomeDoctorScreen(), HomeNursingScreen(), HomeLabScreen()];

  Widget hubCard(BuildContext c, int i) {
    final s = db.svcs[i];
    final fresh = db.bookings.where((b) => b.type == 2 && b.svc == i && b.status == 'جديد').length;
    return GestureDetector(
      onTap: () => go(c, pages[i]),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(),
        child: Row(children: [
          tile(kHomeIcons[i], size: 52, dark: true),
          const SizedBox(width: 12),
          Expanded(child: two(s.name, '${fresh == 0 ? 'لا طلبات جديدة' : '$fresh طلب جديد'} · ${s.price} ج.س')),
          Switch(value: s.on, onChanged: (v) { s.on = v; db.ping(); }),
          chev(kInk, 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'الخدمات المنزلية',
          body: ListView(padding: const EdgeInsets.all(16), children: [
            for (var i = 0; i < 3; i++) hubCard(c, i),
            sec('مناطق التغطية'),
            chips(['الخرطوم', 'بحري', 'أم درمان', 'شرق النيل'], areas, () => setState(() {}), multi: true),
          ]),
        ),
      );
}

// ── 8.1 Doctor home visit ──
class HomeDoctorScreen extends StatelessWidget {
  const HomeDoctorScreen({super.key});
  static const slots = ['صباحاً 8 - 12', 'ظهراً 12 - 4', 'مساءً 4 - 9'];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'زيارة طبيب للمنزل',
          body: ListView(padding: const EdgeInsets.all(16), children: [
            svcHead(c, 0, 'الطبيب يزور المريض في منزله', 'سعر الزيارة الافتراضي'),
            miniStats(0),
            secAdd('الأطباء المتاحون للزيارة', () => go(c, const DoctorLookupScreen())),
            if (db.docs.isEmpty) panel([Text('أضف أخصائياً أولاً ثم فعّل له الزيارة المنزلية', style: t(12.5, w: FontWeight.w500, c: kGrey))]),
            for (final d in db.docs)
              Container(
                margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: card(16),
                child: Column(children: [
                  Row(children: [
                    tile(Icons.person_rounded, size: 44),
                    const SizedBox(width: 12),
                    Expanded(child: two(d.name, d.spec)),
                    if (!d.on) ...[pill('موقوف', kChip, kGrey), const SizedBox(width: 6)],
                    Switch(value: d.home && d.on, onChanged: d.on ? (v) { d.home = v; db.ping(); } : null),
                  ]),
                  if (d.home && d.on)
                    InkWell(
                      onTap: () => ask(c, 'سعر زيارة ${d.name}', 'اتركه فارغاً لاستخدام السعر الافتراضي', d.homePrice, (v) { d.homePrice = num(v) > 0 ? money(num(v)) : ''; db.ping(); }, kb: TextInputType.number, suffix: 'ج.س'),
                      child: kv('سعر الزيارة المنزلية', '${d.homePrice.isEmpty ? db.svcs[0].price : d.homePrice} ج.س  ✎', bold: true),
                    ),
                ]),
              ),
            sec('فترات الزيارة'),
            chips(slots, db.visitSlots, db.ping, multi: true),
            reqs(0),
          ]),
        ),
      );
}

// ── 8.2 Home nursing ──
class HomeNursingScreen extends StatelessWidget {
  const HomeNursingScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'التمريض المنزلي',
          body: ListView(padding: const EdgeInsets.all(16), children: [
            svcHead(c, 1, 'ممرضون يقدّمون الرعاية في المنزل', 'السعر يبدأ من'),
            miniStats(1),
            secAdd('الخدمات التمريضية', () => addItem(c, 'إضافة خدمة تمريضية', db.nursing)),
            catalog(c, db.nursing, Icons.vaccines_rounded),
            secAdd('طاقم التمريض', () => addStaff(c, 1)),
            crew(1),
            reqs(1),
          ]),
        ),
      );
}

// ── 8.3 Home sample collection ──
class HomeLabScreen extends StatelessWidget {
  const HomeLabScreen({super.key});
  static const slots = ['صباحاً 6 - 9', 'صباحاً 9 - 12', 'مساءً 4 - 7'];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'سحب العينات المنزلي',
          body: ListView(padding: const EdgeInsets.all(16), children: [
            svcHead(c, 2, 'فني المختبر يسحب العينة من المنزل', 'رسوم الانتقال والسحب'),
            miniStats(2),
            secAdd('التحاليل المتاحة', () => addItem(c, 'إضافة تحليل', db.tests)),
            catalog(c, db.tests, Icons.biotech_rounded),
            sec('فترات السحب'),
            chips(slots, db.labSlots, db.ping, multi: true),
            secAdd('فنيو المختبر', () => addStaff(c, 2)),
            crew(2),
            reqs(2),
          ]),
        ),
      );
}

// ═══════════════ 9. Reports ═══════════════
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) {
          const week = [.45, .7, .55, .9, .65, .8, .5];
          const names = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
          final total = db.bookings.length == 0 ? 1 : db.bookings.length;
          return RPage(
            'التقارير',
            body: ListView(padding: const EdgeInsets.all(16), children: [
              panel([Text('إجمالي الإيرادات', style: t(12.5, w: FontWeight.w500, c: kGrey)), Text('${money(db.revenue)} ج.س', style: t(26, c: kRed)), Text('من الحجوزات المؤكدة والمكتملة', style: t(11, w: FontWeight.w500, c: kGrey))]),
              panel([
                Text('الأسبوع الحالي', style: t(14)),
                gap(10),
                SizedBox(
                  height: 120,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < week.length; i++)
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Container(margin: const EdgeInsets.symmetric(horizontal: 6), height: 90 * week[i], decoration: BoxDecoration(gradient: kGrad, borderRadius: BorderRadius.circular(6))), gap(4), Text(names[i], style: t(11, c: kGrey))])),
                  ]),
                ),
              ]),
              panel([
                Text('الحجوزات حسب النوع', style: t(14)),
                gap(8),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text(kTypes[i], style: t(12.5, w: FontWeight.w600))),
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: db.bookings.where((b) => b.type == i).length / total, minHeight: 8, color: kRed, backgroundColor: kLine))),
                      const SizedBox(width: 8),
                      Text('${db.bookings.where((b) => b.type == i).length}', style: t(12.5)),
                    ]),
                  ),
              ]),
              panel([Text('الأكثر طلباً', style: t(14)), gap(6), for (final d in db.docs.take(3)) kv(d.name, '${d.price} ج.س')]),
            ]),
          );
        },
      );
}

// ═══════════════ 10. Notifications ═══════════════
class NotifsScreen extends StatelessWidget {
  const NotifsScreen({super.key});
  @override
  Widget build(BuildContext context) => RPage(
        'الإشعارات',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final n in const [
            (Icons.mark_email_unread_rounded, 'حجز جديد', 'محمد عبد الرحيم حجز كشفاً مع د. أحمد - السبت 4:30 م', 'منذ 5 دقائق'),
            (Icons.bed_rounded, 'طلب حجز سرير', 'خالد يوسف يطلب سرير ICU لمدة 3 أيام', 'منذ ساعة'),
            (Icons.home_rounded, 'طلب خدمة منزلية', 'فاطمة أحمد تطلب تمريضاً منزلياً', 'منذ ساعتين'),
            (Icons.cancel_rounded, 'إلغاء حجز', 'ألغت آمنة إبراهيم موعد الأحد', 'أمس'),
            (Icons.star_rounded, 'تقييم جديد', 'حصل د. أحمد على تقييم 5 نجوم', 'أمس'),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                tile(n.$1), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n.$2, style: t(14)), Text(n.$3, style: t(12, w: FontWeight.w500, c: kGrey, h: 1.5)), Text(n.$4, style: t(10.5, w: FontWeight.w500, c: const Color(0xFF9AA5B8)))])),
              ]),
            ),
        ]),
      );
}

// ═══════════════ 11. Account / center info ═══════════════
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  Widget row(BuildContext c, IconData i, String s, {Widget? to, Widget? tr}) => InkWell(
        onTap: to == null ? null : () => go(c, to),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), child: Row(children: [Icon(i, color: kRed), const SizedBox(width: 14), Expanded(child: Text(s, style: t(14))), tr ?? chev(kInk, 20)])),
      );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (context, _) {
          final cn = db.center;
          final me = db.me;
          return RPage(
            'حسابي',
            nav: 3,
            body: ListView(padding: const EdgeInsets.all(16), children: [
              panel([
                Row(children: [
                  tile(Icons.local_hospital_rounded, size: 60, dark: true),
                  const SizedBox(width: 14),
                  Expanded(child: two(cn.name, '${kStates[cn.state]} - ${cn.locality} · ترخيص رقم ${cn.lic}')),
                  pill('موثّق', kGreenBg, kGreen),
                ]),
                if (me != null) ...[
                  const Divider(color: kLine, height: 22),
                  kv('مسجّل الدخول باسم', '${me.name} · ${kRoles[me.role]}'),
                ],
              ]),
              Container(
                decoration: card(),
                child: Column(children: [
                  if (db.isManager) row(context, Icons.business_rounded, 'بيانات المركز وساعات العمل', to: const CenterInfoScreen()),
                  row(context, Icons.notifications_none_rounded, 'تنبيهات الحجوزات الجديدة', tr: Switch(value: db.notifyNew, onChanged: (v) {
                    db.notifyNew = v;
                    db.ping();
                  })),
                  if (db.isManager) row(context, Icons.group_rounded, 'مستخدمو المركز والصلاحيات', to: const UsersScreen()),
                  row(context, Icons.headset_mic_outlined, 'المساعدة والدعم', to: const HelpScreen()),
                  row(context, Icons.description_outlined, 'الشروط والخصوصية', to: const TermsScreen()),
                ]),
              ),
              gap(18),
              GestureDetector(
                onTap: () => logout(context),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [const Icon(Icons.logout_rounded, color: kRed), const SizedBox(width: 12), Text('تسجيل الخروج', style: t(13.5, c: kRed))])),
              ),
              if (db.isManager) ...[
                gap(18),
                GestureDetector(
                  onTap: () => confirm(context, 'حذف حساب المركز', 'سيُحذف حساب المركز وكل بياناته (الحجوزات والأخصائيون والأسرّة والمستخدمون) نهائياً ولا يمكن التراجع.', 'حذف نهائي', () {
                    db.deleteAccount(); // في الإنتاج: طلب حذف إلى الخادم مع مراعاة الاحتفاظ بالسجلات النظامية
                    logout(context);
                  }),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [const Icon(Icons.delete_forever_rounded, color: kGrey), const SizedBox(width: 12), Text('حذف حساب المركز', style: t(13.5, w: FontWeight.w600, c: kGrey))])),
                ),
              ],
            ]),
          );
        },
      );
}

class CenterInfoScreen extends StatefulWidget {
  const CenterInfoScreen({super.key});
  @override
  State<CenterInfoScreen> createState() => _CenterInfoState();
}

class _CenterInfoState extends State<CenterInfoScreen> {
  CenterProfile get c => db.center;
  late final n = TextEditingController(text: c.name), ph = TextEditingController(text: c.phone), loc = TextEditingController(text: c.locality);
  late final ad = TextEditingController(text: c.address), from = TextEditingController(text: c.from), to = TextEditingController(text: c.to);
  late final kind = {c.kind}, svc = {...c.svc};
  late int state = c.state;

  @override
  void dispose() {
    for (final x in [n, ph, loc, ad, from, to]) {
      x.dispose();
    }
    super.dispose();
  }

  void save() {
    if (n.text.trim().length < 3) return snack(context, 'أدخل اسم المركز');
    if (svc.isEmpty) return snack(context, 'اختر خدمة واحدة على الأقل');
    c
      ..name = n.text.trim()
      ..phone = ph.text.trim()
      ..locality = loc.text.trim()
      ..address = ad.text.trim()
      ..from = from.text.trim()
      ..to = to.text.trim()
      ..kind = kind.first
      ..state = state
      ..svc = {...svc};
    db.ping();
    snack(context, 'تم حفظ بيانات المركز');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => RPage(
        'بيانات المركز',
        bottom: bar(context, [btn('حفظ التغييرات', save)]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          fld('اسم المركز', n),
          sec('نوع المركز'),
          chips(kCenterKinds, kind, () => setState(() {})),
          lockedRow('رقم الترخيص', c.lic),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('لتغيير رقم الترخيص تواصل مع الدعم لإعادة المراجعة.', style: t(11.5, w: FontWeight.w500, c: kGrey))),
          fld('هاتف المركز', ph, kb: TextInputType.phone, ltr: true),
          sec('الولاية'),
          dd(state, kStates, (v) => setState(() => state = v)),
          fld('المحلية / الحي', loc),
          fld('العنوان التفصيلي', ad, lines: 2),
          Row(children: [Expanded(child: fld('بداية الدوام', from)), const SizedBox(width: 12), Expanded(child: fld('نهاية الدوام', to))]),
          sec('الخدمات التي يقدّمها المركز'),
          chips(kTypes, svc, () => setState(() {}), multi: true),
        ]),
      );
}

// ═══════════════ 12. Users & permissions (مستخدمو المركز والصلاحيات) ═══════════════
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: db,
        builder: (c, _) => RPage(
          'مستخدمو المركز',
          bottom: db.isManager ? bar(c, [btn('+ إضافة مستخدم', () => go(c, const MemberForm()))]) : null,
          body: !db.isManager
              ? empty(Icons.lock_rounded, 'هذه الصفحة لمدير المركز فقط')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  panel([Text('كل مستخدم يدخل برقم هاتفه ورمز تحقق (OTP) بدون بريد إلكتروني. حدّد لموظف الاستقبال ما يستطيع فعله.', style: t(12, w: FontWeight.w500, c: kGrey, h: 1.6))]),
                  for (final m in db.members)
                    GestureDetector(
                      onTap: () => go(c, MemberForm(m: m)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: card(),
                        child: Row(children: [
                          tile(m.role == 0 ? Icons.admin_panel_settings_rounded : Icons.support_agent_rounded, size: 48, dark: m.role == 0),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${m.name}${identical(m, db.me) ? ' (أنت)' : ''}', style: t(14.5, w: FontWeight.w800)),
                              Text(fmtPhone(m.phone), textDirection: TextDirection.ltr, style: t(12, w: FontWeight.w500, c: kGrey)),
                              gap(6),
                              Row(children: [pill(kRoles[m.role], kChip, kInk), if (!m.active) ...[const SizedBox(width: 6), pill('موقوف', kAmberBg, kAmber)]]),
                            ]),
                          ),
                          chev(kInk, 20),
                        ]),
                      ),
                    ),
                ]),
        ),
      );
}

class MemberForm extends StatefulWidget {
  const MemberForm({super.key, this.m});
  final Member? m;
  @override
  State<MemberForm> createState() => _MemberState();
}

class _MemberState extends State<MemberForm> {
  Member? get m => widget.m;
  late final n = TextEditingController(text: m?.name), ph = TextEditingController(text: m?.phone.replaceFirst('+249', ''));
  late final role = {m?.role ?? 1}, perms = {...(m?.perms ?? {0, 1})};
  late bool active = m?.active ?? true;

  bool get isMe => m != null && identical(m, db.me);
  bool get lastMgr => m != null && m!.role == 0 && db.members.where((x) => x.role == 0 && x.active).length <= 1;

  @override
  void dispose() {
    n.dispose();
    ph.dispose();
    super.dispose();
  }

  void save() {
    if (n.text.trim().length < 3) return snack(context, 'أدخل اسم المستخدم');
    final p = m == null ? normPhone(ph.text) : m!.phone;
    if (p == null) return snack(context, 'أدخل رقم هاتف سوداني صحيحاً');
    if (m == null && db.memberByPhone(p) != null) return snack(context, 'هذا الرقم مضاف مسبقاً');
    final r = role.first;
    if ((isMe || lastMgr) && (r != m!.role || !active)) return snack(context, isMe ? 'لا يمكنك تغيير دورك أو إيقاف حسابك' : 'لا يمكن إيقاف آخر مدير أو تغيير دوره');
    final ps = r == 0 ? {0, 1, 2, 3} : {...perms};
    if (m == null) {
      db.members.add(Member(n.text.trim(), p, r, perms: ps));
      snack(context, 'تمت إضافة ${n.text.trim()} — يدخل برقم هاتفه ورمز تحقق (إرسال الدعوة بـ SMS يحتاج ربط خادم)');
    } else {
      final x = m!;
      x
        ..name = n.text.trim()
        ..role = r
        ..perms = ps
        ..active = active;
      snack(context, 'تم حفظ التعديلات');
    }
    db.ping();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => RPage(
        m == null ? 'إضافة مستخدم' : 'تعديل مستخدم',
        bottom: bar(context, [
          btn('حفظ', save),
          if (m != null && !isMe && !lastMgr)
            btn('حذف المستخدم', () => confirm(context, 'حذف المستخدم', 'سيفقد ${m!.name} الدخول إلى المركز.', 'حذف', () {
                  db.members.remove(m);
                  db.ping();
                  Navigator.pop(context);
                }), outline: true, h: 44),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          fld('الاسم', n, hint: 'اسم الموظف'),
          m == null ? phoneFld('رقم الهاتف', ph) : lockedRow('رقم الهاتف (للدخول)', fmtPhone(m!.phone)),
          sec('الدور'),
          chips(kRoles, role, () => setState(() {})),
          if (role.first == 1) ...[
            sec('الصلاحيات'),
            chips(kPerms, perms, () => setState(() {}), multi: true),
          ] else
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('المدير يملك كل الصلاحيات ويدير المستخدمين وبيانات المركز.', style: t(12, w: FontWeight.w500, c: kGrey, h: 1.6))),
          if (m != null) ...[
            gap(6),
            switchRow('الحساب فعّال', active, (v) => setState(() => active = v)),
          ],
        ]),
      );
}

// ═══════════════ 13. Help & Terms ═══════════════
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  static const faq = <(String, String)>[
    ('كيف أضيف أخصائياً لمركزي؟', 'من الإدارة ← الأخصائيون ← إضافة أخصائي، ثم أدخل رقم تسجيله في المجلس الطبي. إن كان مسجّلاً لدينا يظهر ملفه مباشرة فتضيفه بشروط مركزك (السعر والدوام)، وإلا تسجّله كأخصائي جديد.'),
    ('كيف يعمل رمز التحقق؟', 'ندخلك برقم هاتفك ورمز من 6 أرقام يصلك برسالة. لا نستخدم بريداً إلكترونياً ولا كلمة مرور، فلا تشارك الرمز مع أحد.'),
    ('كيف أضيف موظف استقبال؟', 'من حسابي ← مستخدمو المركز والصلاحيات ← إضافة مستخدم. اختر دوره وصلاحياته، ويدخل برقم هاتفه ورمز تحقق.'),
    ('لماذا حساب مركزي قيد المراجعة؟', 'نراجع ترخيص المركز وبياناته قبل التفعيل. عند الاعتماد تستطيع استقبال الحجوزات وإدارة مركزك.'),
    ('كيف أغيّر رقم هاتف المدير؟', 'رقم المدير هو هوية الدخول، لذلك يتطلب تغييره تواصلاً مع الدعم للتحقق من هويتك.'),
  ];
  @override
  Widget build(BuildContext context) => RPage(
        'المساعدة والدعم',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          panel([
            Text('تواصل مع الدعم', style: t(14)),
            gap(8),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: kSupportPhone));
                snack(context, 'تم نسخ رقم الدعم');
              },
              child: Row(children: [
                const Icon(Icons.support_agent_rounded, color: kRed),
                const SizedBox(width: 10),
                Expanded(child: Text(kSupportPhone, textDirection: TextDirection.ltr, style: t(14.5))),
                const Icon(Icons.copy_rounded, size: 18, color: kGrey),
              ]),
            ),
          ]),
          sec('الأسئلة الشائعة'),
          Container(
            decoration: card(),
            child: Column(children: [
              for (final f in faq)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    iconColor: kRed, textColor: kInk, collapsedTextColor: kInk,
                    title: Text(f.$1, style: t(13.5)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(f.$2, style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.7))],
                  ),
                ),
            ]),
          ),
          gap(14),
          GestureDetector(
            onTap: () => go(context, const TermsScreen()),
            child: Row(children: [const Icon(Icons.description_outlined, color: kRed), const SizedBox(width: 10), Text('الشروط والخصوصية', style: t(13.5, c: kRed))]),
          ),
        ]),
      );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});
  // نص مبدئي للعرض — يجب أن يراجعه مستشار قانوني قبل النشر.
  static const items = <(String, String)>[
    ('الاستخدام', 'يقدّم المركز خدماته الطبية عبر طبيبك، ويلتزم بصحة بيانات المركز وترخيصه وتحديثها عند أي تغيير.'),
    ('بيانات الأخصائيين', 'يلتزم المركز بإضافة الأخصائيين بعلمهم وموافقتهم، وبأن يكونوا مسجّلين لدى الجهة المهنية المختصة. يراجع فريق طبيبك تسجيل الأخصائي الجديد قبل ظهوره للمرضى.'),
    ('خصوصية المرضى', 'بيانات المرضى والحجوزات سرّية، ولا تُستخدم إلا لتقديم الخدمة المحجوزة، ولا يجوز مشاركتها مع أي طرف آخر.'),
    ('الحسابات والدخول', 'يتم الدخول برقم الهاتف ورمز تحقق. المركز مسؤول عن مستخدميه وصلاحياتهم، وعن عدم مشاركة رموز التحقق.'),
    ('الإيقاف والحذف', 'يحق لطبيبك إيقاف أي حساب يخالف هذه الشروط. ويمكن لمدير المركز حذف حساب المركز من صفحة حسابي.'),
  ];
  @override
  Widget build(BuildContext context) => RPage(
        'الشروط والخصوصية',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final it in items) panel([Text(it.$1, style: t(14.5, w: FontWeight.w800)), gap(6), Text(it.$2, style: t(12.5, w: FontWeight.w500, c: kGrey, h: 1.8))]),
          Center(child: Text('نص مبدئي للعرض', style: t(11, w: FontWeight.w500, c: kGrey))),
        ]),
      );
}
