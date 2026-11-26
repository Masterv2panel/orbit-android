// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'orbit_localization.dart';

class SecurityGuideScreen extends StatelessWidget {
  const SecurityGuideScreen({super.key, this.onToggleLocale});

  final VoidCallback? onToggleLocale;

  static const _muted = Color(0xFFADB7C8);
  static const _accent = Color(0xFF52E6DF);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        orbitText(context, 'امنیت و حریم خصوصی'),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: orbitText(context, 'تغییر زبان'),
          onPressed: onToggleLocale,
          icon: Text(
            Localizations.localeOf(context).languageCode == 'en' ? 'FA' : 'EN',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: const [
        _GuideIntro(),
        SizedBox(height: 8),
        _GuideCard(
          icon: Icons.shield_outlined,
          title: 'تونل VPN و نشانی IP',
          paragraphs: [
            'Orbit از هستهٔ sing-box و پروفایل Hysteria2 برای ساخت تونل Android استفاده می‌کند. تا وقتی وضعیت اتصال از هسته تأیید نشده، مرورگر اجازهٔ بازکردن سایت نمی‌دهد.',
            'هنگام اتصال، ترافیک دستگاه از تونل عبور می‌کند و سایت‌ها معمولاً IP خروجی VPN را می‌بینند. Orbit هویت خانگی یا IP مسکونی جعل نمی‌کند؛ نوع IP را ارائه‌دهندهٔ VPN تعیین می‌کند.',
          ],
        ),
        _GuideCard(
          icon: Icons.dns_outlined,
          title: 'DNS چه مسیری دارد؟',
          paragraphs: [
            'در پیکربندی فعلی، درخواست‌های DNS به resolver برابر 1.1.1.1 می‌روند و sing-box آن‌ها را با detour: proxy از outbound تونل عبور می‌دهد؛ TUN نیز DNS را hijack می‌کند.',
            'این تنظیم DNS-over-HTTPS نیست: resolver نهایی می‌تواند محتوای پرس‌وجوهای DNS را ببیند. این اپ هم نمی‌تواند در همهٔ دستگاه‌ها، نسخه‌های WebView یا زمان قطع تونل نشت DNS را به‌طور مطلق رد کند.',
          ],
        ),
        _GuideCard(
          icon: Icons.schedule_outlined,
          title: 'هماهنگ‌سازی منطقهٔ زمانی با VPN',
          paragraphs: [
            'پس از تأیید اتصال، Orbit می‌تواند منطقهٔ زمانی خروجی IP را با سرویس ipapi.co درخواست کند. درخواست از شبکهٔ تونل‌شده ارسال می‌شود؛ سرویس، در حالت عادی، IP خروجی VPN را می‌بیند، نه GPS یا نشانی اصلی ارائه‌دهندهٔ اینترنت.',
            'در اولین اتصال، پیش از درخواست از ipapi.co اجازه خواسته می‌شود. می‌توانی رد کنی یا بعداً از منوی مرورگر این گزینه را روشن یا خاموش کنی. اگر روشن بماند، برای هر اتصال VPN یک درخواست لازم است؛ این درخواست فقط timezone را برمی‌گرداند و مکان GPS درخواست نمی‌کند.',
            'منطقهٔ زمانی فقط در JavaScript صفحات مرورگر تنظیم می‌شود؛ ساعت Android و برنامه‌های دیگر تغییر نمی‌کنند. پیاده‌سازی، APIهای رایج Intl و Date را هدف می‌گیرد و شبیه‌سازی کامل موتور JavaScript یا همهٔ اثرانگشت‌ها نیست.',
            'تزریق در ابتدای document به نسخه و قابلیت Android System WebView وابسته است. در WebViewهای فاقد قابلیت document-start، خود افزونه تزریق زودهنگام را فقط best-effort انجام می‌دهد؛ صفحه ممکن است پیش از تزریق، منطقهٔ زمانی گوشی را خوانده باشد. در صورت خطای lookup یا پشتیبانی‌نشدن قابلیت، باید وضعیت به‌صورت محدود/ناموفق نمایش داده شود، نه اینکه موفقیت تضمین شود.',
          ],
        ),
        _GuideCard(
          icon: Icons.javascript_outlined,
          title: 'سازگاری وب‌سایت‌های جدید',
          paragraphs: [
            'JavaScript، DOM Storage و وب‌ویو سخت‌افزاری فعال‌اند تا برنامه‌های وب امروزی کار کنند. موتور رندر، Android System WebView نصب‌شده روی گوشی است؛ برای سازگاری بهتر آن را از Google Play یا فروشگاه دستگاه به‌روز نگه دار.',
            'Safe Browsing در صورت پشتیبانی WebView روشن می‌ماند. HTTP غیررمزشده همچنان ممکن است باز شود، اما قفل HTTPS در نوار نشانی باید برای محتوای امن بررسی شود.',
          ],
        ),
        _GuideCard(
          icon: Icons.privacy_tip_outlined,
          title: 'مجوزها، WebRTC و اثرانگشت',
          paragraphs: [
            'درخواست موقعیت وب، دوربین، میکروفون و مجوزهای رسانه‌ای به‌طور پیش‌فرض رد می‌شوند. این کار ممکن است نقشه، تماس و بارگذاری فایل در بعضی سایت‌ها را محدود کند.',
            'WebRTC در موتور WebView به‌طور کامل خاموش نشده است. ترافیک آن هنگام اتصال باید از TUN عبور کند، ولی این تضمین مستقلی علیه نشت نیست. Android گزینه‌های Always-on VPN و Block connections without VPN را برای قفل کل دستگاه ارائه می‌کند و کاربر باید آن‌ها را دستی فعال کند.',
            'مرورگر fingerprint را حذف نمی‌کند و خودش را به‌عنوان کاربر خانگی جا نمی‌زند. تغییر timezone یا user-agent به‌تنهایی IP دیتاسنتری را مسکونی نمی‌کند و ممکن است باعث ناسازگاری قابل‌تشخیص شود.',
          ],
        ),
        _GuideCard(
          icon: Icons.cookie_outlined,
          title: 'کوکی‌های شخص ثالث',
          paragraphs: [
            'کوکی شخص ثالث به‌طور پیش‌فرض مسدود است. از منوی مرورگر می‌توانی با تأیید روشنش کنی؛ بعضی ورودهای یکپارچه یا پرداخت‌ها ممکن است به آن نیاز داشته باشند، اما فعال‌سازی می‌تواند ردیابی بین‌سایتی را آسان‌تر کند.',
            'کوکی‌های اصلی سایت برای ورود و عملکرد صفحه همچنان می‌توانند ذخیره شوند. پاک‌کردن داده‌های سایت، کوکی‌ها و دادهٔ وب را حذف می‌کند و ممکن است نشست‌ها را ببندد.',
          ],
        ),
        _GuideCard(
          icon: Icons.key_outlined,
          title: 'هشدار پروفایل insecure=1',
          paragraphs: [
            'اگر لینک Hysteria2 شامل insecure=1 باشد، اعتبار گواهی TLS سرور بررسی نمی‌شود. برنامه پیش از اتصال هشدار می‌دهد و تأیید صریح می‌خواهد؛ این گزینه می‌تواند اتصال را در برابر حملهٔ واسطه آسیب‌پذیر کند.',
            'فقط برای سروری ادامه بده که به اپراتورش اعتماد داری. امن‌ترین حالت استفاده از گواهی معتبر و خاموش‌بودن insecure است.',
          ],
        ),
        _GuideCard(
          icon: Icons.history_toggle_off,
          title: 'تاریخچه، نشانک و داده‌های محلی',
          paragraphs: [
            'تاریخچه و نشانک‌ها در فضای محلی برنامه ذخیره می‌شوند و Orbit آن‌ها را به حساب ابری خودش همگام نمی‌کند. در APKهای ساخته‌شده، Android Auto Backup برای برنامه غیرفعال شده است؛ این موضوع به معنی رمزگذاری داده‌های محلی نیست. هر نشانی کامل ممکن است query حساس داشته باشد.',
            'گزینهٔ پاک‌کردن داده‌های وب، کوکی‌ها، cache و storage سایت را پاک می‌کند؛ تاریخچه و نشانک‌ها جدا هستند و از صفحهٔ کتابخانه پاک می‌شوند. پاک‌کردن دادهٔ وب ممکن است نشست ورود را ببندد.',
            'دانلودها در خود مرورگر ذخیره یا مدیریت نمی‌شوند. Orbit نام فایل یا لینک درخواست‌شده را نشان می‌دهد و می‌تواند URL را در کلیپ‌بورد کپی کند تا آن را در دانلودمنیجر باز کنی؛ مقصد و رفتار دانلودمنیجر بیرون از کنترل صفحهٔ مرورگر است.',
            'ذخیره‌سازی محلی در sandbox برنامه است، اما مگر آنکه نسخه صریحاً رمزگذاری را پیاده‌سازی کند، نباید آن را مخزن رمزگذاری‌شده فرض کرد. از دستگاه قفل‌شده و به‌روز استفاده کن.',
          ],
        ),
        _GuideCard(
          icon: Icons.speed_outlined,
          title: 'سنجش تأخیر',
          paragraphs: [
            'سنجش فعلی یک درخواست HTTPS آزمایشی از مسیر شبکهٔ پس از اتصال اندازه می‌گیرد. این ICMP ping یا اندازه‌گیری مستقیم handshake سرور Hysteria2 نیست و نتیجه به مسیر، DNS و endpoint آزمایش وابسته است.',
          ],
        ),
        _GuideCard(
          icon: Icons.warning_amber_outlined,
          title: 'آنچه این مرورگر تضمین نمی‌کند',
          paragraphs: [
            'Orbit ناشناس‌بودن کامل، جلوگیری از همهٔ انواع نشت، fingerprint معتبر، IP مسکونی، timezone کاملاً نامرئی، یا در دسترس‌بودن دائمی سرور VPN را تضمین نمی‌کند. اتصال واقعی و رفتار WebRTC/DNS باید روی گوشی و شبکهٔ خودت آزمایش شود.',
            'برای قفل سراسری Android، Always-on VPN و Block connections without VPN را در تنظیمات سیستم روشن کن. گزینهٔ داخل مرورگر فقط بارگذاری صفحات همین رابط را کنترل می‌کند.',
          ],
        ),
      ],
    ),
  );
}

class _GuideIntro extends StatelessWidget {
  const _GuideIntro();

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: const Color(0xFF12212B),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0x6652E6DF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: SecurityGuideScreen._accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              orbitText(
                context,
                'این صفحه دقیقاً وضعیت پیاده‌سازی را توضیح می‌دهد؛ ویژگی‌ای که تضمین نشده، به‌عنوان تضمین امنیتی معرفی نمی‌شود.',
              ),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.title,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    color: const Color(0xFF111A27),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF29384A)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2B3A),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: SecurityGuideScreen._accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  orbitText(context, title),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final paragraph in paragraphs) ...[
            Text(
              orbitText(context, paragraph),
              style: const TextStyle(
                color: SecurityGuideScreen._muted,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
