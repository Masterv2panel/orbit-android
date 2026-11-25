// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/widgets.dart';

/// Returns the English UI equivalent for [persian] in English locales;
/// otherwise preserves the original Persian text.
String orbitText(BuildContext context, String persian) {
  if (Localizations.localeOf(context).languageCode != 'en') return persian;
  return _orbitEnglish[persian] ?? persian;
}

/// Use for text containing runtime values or when a stable key-based lookup is
/// unsuitable. Supply both complete localized forms at the call site.
String orbitTextPair(BuildContext context, String fa, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : fa;

/// Formats dynamic UI copy after selecting the appropriate language template.
/// The formatter receives the selected language so callers can format values
/// (for example dates, units, and interpolated names) appropriately.
String orbitTextFormat(
  BuildContext context, {
  required String fa,
  required String en,
  required String Function(String template, bool isEnglish) format,
}) {
  final isEnglish = Localizations.localeOf(context).languageCode == 'en';
  return format(isEnglish ? en : fa, isEnglish);
}

const Map<String, String> _orbitEnglish = <String, String>{
  // VPN setup, connection dialogs, status, controls and errors.
  'لینک باید با hysteria2:// یا hy2:// شروع شود.':
      'The link must start with hysteria2:// or hy2://.',
  'نشانی سرور در لینک نیست.': 'The link does not contain a server address.',
  'رمز اتصال در لینک نیست.': 'The link does not contain a connection password.',
  'مقدار insecure باید 0/1 یا false/true باشد.':
      'The insecure value must be 0/1 or false/true.',
  'نوع obfuscation این لینک پشتیبانی نمی‌شود.':
      'This link uses an unsupported obfuscation type.',
  'برای Salamander باید obfs-password هم باشد.':
      'Salamander requires an obfs-password.',
  'راه‌اندازی هستهٔ اتصال ناموفق بود.':
      'Could not initialize the connection core.',
  'لینک اتصال قابل‌خواندن نیست.': 'The connection link could not be read.',
  'اول لینک Hysteria2 سرور را وارد و بررسی کن.':
      'Enter and validate the server’s Hysteria2 link first.',
  'گواهی TLS بررسی نمی‌شود': 'TLS certificate is not verified',
  'این پروفایل هر گواهی سروری را می‌پذیرد. مهاجم واسطه می‌تواند اتصال را جعل یا شنود کند. فقط اگر به ارائه‌دهنده و سرور اعتماد داری ادامه بده.': 'This profile accepts any server certificate. A man-in-the-middle attacker could impersonate or intercept the connection. Continue only if you trust the provider and server.',
  'لغو': 'Cancel',
  'می‌پذیرم و ادامه': 'Accept and continue',
  'مجوز VPN در اندروید داده نشد.': 'Android VPN permission was not granted.',
  'اتصال شروع نشد؛ تنظیمات یا سرور را بررسی کن.':
      'Connection did not start; check the settings or server.',
  'پاسخ نامعتبر': 'Invalid response',
  'ناموفق': 'Failed',
  'مجوزها و اطلاعات برنامه': 'App permissions and information',
  'بدون هیچ‌گونه ضمانت': 'provided without any warranty',
  'متصل': 'Connected',
  'در حال اتصال': 'Connecting',
  'خطا در اتصال': 'Connection error',
  'قطع': 'Disconnected',
  'پروفایل سرور وارد نشده': 'No server profile entered',
  'لینک Hysteria2': 'Hysteria2 link',
  'اطلاعات لینک فقط در حافظهٔ همین اجرا نگه داشته می‌شود.':
      'Link data is kept only in memory for this session.',
  'پنهان‌کردن لینک': 'Hide link',
  'نمایش موقت لینک': 'Temporarily show link',
  'بررسی و بارگذاری لینک': 'Validate and load link',
  'هشدار: بررسی گواهی TLS خاموش است؛ اتصال در برابر حملهٔ واسطه آسیب‌پذیر است.': 'Warning: TLS certificate verification is off; the connection is vulnerable to man-in-the-middle attacks.',
  'بررسی گواهی TLS روشن است.': 'TLS certificate verification is on.',
  'در حال انجام…': 'Working…',
  'قطع اتصال': 'Disconnect',
  'اتصال VPN': 'Connect VPN',
  'سنجش تأخیر از داخل تونل': 'Measure latency through tunnel',
  'با اتصال، اندروید درخواست مجوز VPN را نشان می‌دهد. فقط پس از تأیید تو، تونل شروع می‌شود. اتصال واقعی به سرور نیاز دارد و وضعیت «متصل» پس از گزارش هسته نمایش داده می‌شود.': 'When you connect, Android will request VPN permission. The tunnel starts only after you approve. A real server is required, and “Connected” is shown only after the core reports the connection.',
  'هماهنگ‌سازی timezone مرورگر؟': 'Synchronize browser time zone?',
  'برای برآورد منطقهٔ زمانی، Orbit یک درخواست HTTPS به ipapi.co می‌فرستد. این سرویس IP خروجی VPN را دریافت می‌کند. تنظیم فقط روی JavaScript مرورگر اثر می‌گذارد، نه ساعت Android، و ممکن است در WebViewهای قدیمی دیر اعمال شود.': 'To estimate the time zone, Orbit sends an HTTPS request to ipapi.co. This service receives the VPN exit IP. The setting affects browser JavaScript only, not the Android clock, and may be applied late in older WebViews.',
  'فعلاً نه': 'Not now',
  'فعال‌سازی': 'Enable',
  'درخواست بیرونی timezone غیرفعال است؛ از timezone دستگاه استفاده می‌شود.': 'External time-zone lookup is disabled; the device time zone will be used.',
  'منطقهٔ زمانی VPN دریافت نشد؛ از منطقهٔ زمانی دستگاه استفاده می‌شود.':
      'Could not get the VPN time zone; the device time zone will be used.',
  'منطقهٔ زمانی خروجی VPN': 'VPN exit time zone',
  'هنگام فعال‌بودن، ipapi.co درخواست دریافت می‌کند و IP خروجی VPN را می‌بیند. در صورت خاموش‌کردن، صفحات جدید از timezone دستگاه استفاده می‌کنند.': 'When enabled, ipapi.co receives a request and sees the VPN exit IP. When disabled, new pages use the device time zone.',
  'خاموش و استفاده از دستگاه': 'Turn off and use device',
  'فعال‌سازی / تلاش دوباره': 'Enable / try again',
  'فعال‌کردن کوکی شخص ثالث؟': 'Enable third-party cookies?',
  'مسدودکردن کوکی شخص ثالث؟': 'Block third-party cookies?',
  'این کار ممکن است ورود یا پرداخت بعضی سایت‌ها را بهتر کند، اما سرویس‌های تعبیه‌شده می‌توانند کوکی بین‌سایتی داشته باشند.': 'This may improve sign-in or payment on some sites, but embedded services may use cross-site cookies.',
  'با مسدودکردن، حریم خصوصی بهتر می‌شود؛ ورود یکپارچه یا برخی امکانات سایت ممکن است از کار بیفتد.': 'Blocking improves privacy, but single sign-on or some site features may stop working.',
  'انصراف': 'Cancel',
  'تأیید': 'Confirm',
  'VPN قطع شد؛ صفحات برای جلوگیری از ادامهٔ بارگذاری بسته شدند.':
      'VPN disconnected; pages were closed to prevent further loading.',

  // Browser menus, navigation, controls, prompts and errors.
  'زبانهٔ جدید': 'New tab',
  'زبانهٔ خالی': 'Empty tab',
  'بستن زبانه': 'Close tab',
  'پاک‌کردن داده‌های سایت؟': 'Clear site data?',
  'کوکی‌ها، cache و داده‌های وب ذخیره‌شده پاک می‌شوند و ممکن است از سایت‌ها خارج شوی. تاریخچه و نشانک‌ها جداگانه در کتابخانه مدیریت می‌شوند.': 'Cookies, cache, and stored web data will be deleted, and you may be signed out of websites. History and bookmarks are managed separately in the library.',
  'پاک‌کردن دادهٔ سایت': 'Clear site data',
  'داده‌های وب پاک شدند.': 'Web data was cleared.',
  'پاک‌سازی کامل نشد؛ بخشی از داده‌ها ممکن است باقی مانده باشد.':
      'Cleanup was incomplete; some data may remain.',
  'درخواست دریافت فایل': 'File download request',
  'بستن': 'Close',
  'نشانی دانلود کپی شد.': 'Download address copied.',
  'کپی لینک': 'Copy link',
  'VPN متصل · در حال بررسی timezone': 'VPN connected · checking time zone',
  'timezone دستگاه': 'device time zone',
  'برای وب‌گردی VPN را وصل کن': 'Connect the VPN to browse',
  'حذف نشانک': 'Remove bookmark',
  'افزودن نشانک': 'Add bookmark',
  'ابزارهای مرورگر': 'Browser tools',
  'تاریخچه و نشانک‌ها': 'History and bookmarks',
  'پیداکردن در صفحه': 'Find on page',
  'مسدودکردن کوکی شخص ثالث': 'Block third-party cookies',
  'اجازهٔ کوکی شخص ثالث': 'Allow third-party cookies',
  'تنظیم timezone مرورگر': 'Set browser time zone',
  'فعال‌کردن timezone VPN': 'Enable VPN time zone',
  'پاک‌کردن داده‌های سایت': 'Clear site data',
  'امنیت و حریم خصوصی': 'Security and privacy',
  'نشانی وب یا جست‌وجو': 'Web address or search',
  'رفتن': 'Go',
  'عبارت در این صفحه': 'Find in this page',
  'نتیجهٔ قبلی': 'Previous result',
  'نتیجهٔ بعدی': 'Next result',
  'بستن جست‌وجو': 'Close search',
  'بازگشت': 'Back',
  'جلو': 'Forward',
  'خانه': 'Home',
  'توقف بارگذاری': 'Stop loading',
  'بارگذاری دوباره': 'Reload',
  'بارگذاری شروع نشد. نشانی یا اتصال VPN را بررسی کن.':
      'Loading did not start. Check the address or VPN connection.',
  'قفل مرورگر فعال است؛ برای وب‌گردی ابتدا VPN را وصل کن.':
      'Browser lock is active; connect the VPN before browsing.',
  'نشانی معتبر HTTP/HTTPS یا عبارت جست‌وجو وارد کن.':
      'Enter a valid HTTP/HTTPS address or a search query.',
  'بارگذاری صفحه ناموفق بود. اتصال یا نشانی را بررسی کن.':
      'Page failed to load. Check the connection or address.',
  'جست‌وجو یا نشانی را وارد کن': 'Enter a search query or address',
  'JavaScript و ذخیره‌سازی وب فعال است. تاریخچه و نشانک‌ها روی همین دستگاه می‌مانند.': 'JavaScript and web storage are enabled. History and bookmarks stay on this device.',
  'برای جلوگیری از شروع ناخواستهٔ بارگذاری، تا اتصال VPN هیچ سایتی باز نمی‌شود.': 'To prevent unintended loading, no website opens until the VPN is connected.',
  'جست‌وجو در وب': 'Search the web',
  'جست‌وجو': 'Search',
  'در حال دریافت منطقهٔ زمانی از IP خروجی VPN…':
      'Getting the time zone from the VPN exit IP…',
  'بازکردن اتصال VPN': 'Open VPN connection',
  'کتابخانه': 'Library',
  'برای قفل‌کردن کل دستگاه، Always-on VPN و Block connections without VPN را در تنظیمات Android هم فعال کن.': 'To lock down the entire device, also enable Always-on VPN and Block connections without VPN in Android settings.',
  'باید VPN را وصل کنی': 'Connect the VPN first',
  'تغییر زبان': 'Switch language',
  'VPN متصل': 'VPN connected',
  'زبانه‌های باز': 'Open tabs',
  'GPL-3.0-or-later · بدون هیچ‌گونه ضمانت':
      'GPL-3.0-or-later · provided without any warranty',
  'تونل فعال': 'Tunnel active',
  'تونل امن Hysteria2': 'Hysteria2 secure tunnel',
  'پروفایل اتصال': 'Connection profile',
  'موتور صفحه از کار افتاد؛ می‌توانی همین تب را دوباره بارگذاری کنی.':
      'The page renderer stopped unexpectedly. You can reload this tab.',
  'Android موتور این صفحه را متوقف کرد؛ می‌توانی دوباره تلاش کنی.':
      'Android stopped this page renderer. You can try again.',
  'تلاش دوباره': 'Try again',
  'بازگشت به خانه': 'Back to home',
  'این تب پس از توقف موتور صفحه قابل بازیابی است؛ تلاش دوباره صفحهٔ فعلی را بارگذاری می‌کند. تاریخچهٔ همین صفحه ممکن است در دسترس نباشد.': 'This tab can recover after its page renderer stops. Retrying reloads the current page; this page’s in-WebView history may no longer be available.',
  'زبانه‌های زنده می‌توانند از حافظهٔ دستگاه استفاده کنند. Orbit زبانه‌ها را خودکار حذف نمی‌کند تا تاریخچهٔ هرکدام حفظ شود.': 'Live tabs can use device memory. Orbit does not automatically discard tabs so their navigation history is preserved.',

  // Browser library, history and bookmarks.
  'کتابخانهٔ مرورگر': 'Browser library',
  'تاریخچه': 'History',
  'نشانک‌ها': 'Bookmarks',
  'پاک‌کردن تاریخچه؟': 'Clear history?',
  'همهٔ بازدیدهای ذخیره‌شده پاک می‌شوند.': 'All saved visits will be deleted.',
  'پاک‌کردن نشانک‌ها؟': 'Clear bookmarks?',
  'همهٔ نشانک‌های ذخیره‌شده پاک می‌شوند.':
      'All saved bookmarks will be deleted.',
  'پاک‌کردن': 'Clear',
  'پاک‌کردن تاریخچه': 'Clear history',
  'پاک‌کردن نشانک‌ها': 'Clear bookmarks',
  'هنوز موردی در تاریخچه نیست.': 'There are no history items yet.',
  'حذف از تاریخچه': 'Remove from history',
  'هنوز نشانکی ذخیره نشده است.': 'No bookmarks have been saved yet.',

  // Security guide: introduction and complete section titles/body copy.
  'این صفحه دقیقاً وضعیت پیاده‌سازی را توضیح می‌دهد؛ ویژگی‌ای که تضمین نشده، به‌عنوان تضمین امنیتی معرفی نمی‌شود.': 'This page describes the implementation as it is. Features that are not guaranteed are not presented as security guarantees.',
  'تونل VPN و نشانی IP': 'VPN tunnel and IP address',
  'Orbit از هستهٔ sing-box و پروفایل Hysteria2 برای ساخت تونل Android استفاده می‌کند. تا وقتی وضعیت اتصال از هسته تأیید نشده، مرورگر اجازهٔ بازکردن سایت نمی‌دهد.': 'Orbit uses the sing-box core and a Hysteria2 profile to create an Android tunnel. The browser will not open websites until the core confirms the connection status.',
  'هنگام اتصال، ترافیک دستگاه از تونل عبور می‌کند و سایت‌ها معمولاً IP خروجی VPN را می‌بینند. Orbit هویت خانگی یا IP مسکونی جعل نمی‌کند؛ نوع IP را ارائه‌دهندهٔ VPN تعیین می‌کند.': 'When connected, device traffic passes through the tunnel and websites usually see the VPN exit IP. Orbit does not fake a residential identity or residential IP; the VPN provider determines the type of IP.',
  'DNS چه مسیری دارد؟': 'How is DNS routed?',
  'در پیکربندی فعلی، درخواست‌های DNS به resolver برابر 1.1.1.1 می‌روند و sing-box آن‌ها را با detour: proxy از outbound تونل عبور می‌دهد؛ TUN نیز DNS را hijack می‌کند.': 'In the current configuration, DNS requests go to the 1.1.1.1 resolver, and sing-box routes them through the tunnel outbound using detour: proxy; TUN also hijacks DNS.',
  'این تنظیم DNS-over-HTTPS نیست: resolver نهایی می‌تواند محتوای پرس‌وجوهای DNS را ببیند. این اپ هم نمی‌تواند در همهٔ دستگاه‌ها، نسخه‌های WebView یا زمان قطع تونل نشت DNS را به‌طور مطلق رد کند.': 'This is not DNS-over-HTTPS: the final resolver can see the contents of DNS queries. This app also cannot absolutely rule out DNS leaks on every device, WebView version, or during tunnel interruption.',
  'هماهنگ‌سازی منطقهٔ زمانی با VPN': 'Synchronizing the time zone with the VPN',
  'پس از تأیید اتصال، Orbit می‌تواند منطقهٔ زمانی خروجی IP را با سرویس ipapi.co درخواست کند. درخواست از شبکهٔ تونل‌شده ارسال می‌شود؛ سرویس، در حالت عادی، IP خروجی VPN را می‌بیند، نه GPS یا نشانی اصلی ارائه‌دهندهٔ اینترنت.': 'After the connection is confirmed, Orbit can request the IP exit time zone from ipapi.co. The request is sent over the tunneled network; normally the service sees the VPN exit IP, not GPS or your original ISP address.',
  'در اولین اتصال، پیش از درخواست از ipapi.co اجازه خواسته می‌شود. می‌توانی رد کنی یا بعداً از منوی مرورگر این گزینه را روشن یا خاموش کنی. اگر روشن بماند، برای هر اتصال VPN یک درخواست لازم است؛ این درخواست فقط timezone را برمی‌گرداند و مکان GPS درخواست نمی‌کند.': 'On the first connection, permission is requested before contacting ipapi.co. You can decline or later turn this option on or off from the browser menu. If left enabled, one request is needed for each VPN connection; it returns only the time zone and does not request GPS location.',
  'منطقهٔ زمانی فقط در JavaScript صفحات مرورگر تنظیم می‌شود؛ ساعت Android و برنامه‌های دیگر تغییر نمی‌کنند. پیاده‌سازی، APIهای رایج Intl و Date را هدف می‌گیرد و شبیه‌سازی کامل موتور JavaScript یا همهٔ اثرانگشت‌ها نیست.': 'The time zone is set only in browser-page JavaScript; the Android clock and other apps are unchanged. The implementation targets common Intl and Date APIs and is not a complete emulation of the JavaScript engine or all fingerprints.',
  'تزریق در ابتدای document به نسخه و قابلیت Android System WebView وابسته است. در WebViewهای فاقد قابلیت document-start، خود افزونه تزریق زودهنگام را فقط best-effort انجام می‌دهد؛ صفحه ممکن است پیش از تزریق، منطقهٔ زمانی گوشی را خوانده باشد. در صورت خطای lookup یا پشتیبانی‌نشدن قابلیت، باید وضعیت به‌صورت محدود/ناموفق نمایش داده شود، نه اینکه موفقیت تضمین شود.': 'Injection at document start depends on the version and capabilities of Android System WebView. In WebViews without document-start support, the plugin can only make a best-effort early injection; the page may read the phone time zone before injection. If lookup fails or the capability is unsupported, the status should be shown as limited/failed, not as guaranteed success.',
  'سازگاری وب‌سایت‌های جدید': 'Compatibility with modern websites',
  'JavaScript، DOM Storage و وب‌ویو سخت‌افزاری فعال‌اند تا برنامه‌های وب امروزی کار کنند. موتور رندر، Android System WebView نصب‌شده روی گوشی است؛ برای سازگاری بهتر آن را از Google Play یا فروشگاه دستگاه به‌روز نگه دار.': 'JavaScript, DOM Storage, and hardware-accelerated WebView are enabled so modern web apps can work. The rendering engine is the Android System WebView installed on the phone; keep it updated from Google Play or the device app store for better compatibility.',
  'Safe Browsing در صورت پشتیبانی WebView روشن می‌ماند. HTTP غیررمزشده همچنان ممکن است باز شود، اما قفل HTTPS در نوار نشانی باید برای محتوای امن بررسی شود.': 'Safe Browsing remains enabled when supported by WebView. Unencrypted HTTP may still open, but check for the HTTPS lock in the address bar for secure content.',
  'مجوزها، WebRTC و اثرانگشت': 'Permissions, WebRTC, and fingerprinting',
  'درخواست موقعیت وب، دوربین، میکروفون و مجوزهای رسانه‌ای به‌طور پیش‌فرض رد می‌شوند. این کار ممکن است نقشه، تماس و بارگذاری فایل در بعضی سایت‌ها را محدود کند.': 'Web location, camera, microphone, and media permission requests are denied by default. This may limit maps, calls, and file uploads on some websites.',
  'WebRTC در موتور WebView به‌طور کامل خاموش نشده است. ترافیک آن هنگام اتصال باید از TUN عبور کند، ولی این تضمین مستقلی علیه نشت نیست. Android گزینه‌های Always-on VPN و Block connections without VPN را برای قفل کل دستگاه ارائه می‌کند و کاربر باید آن‌ها را دستی فعال کند.': 'WebRTC is not completely disabled in the WebView engine. Its traffic should pass through TUN while connected, but this is not an independent guarantee against leaks. Android provides Always-on VPN and Block connections without VPN to lock down the whole device; users must enable them manually.',
  'مرورگر fingerprint را حذف نمی‌کند و خودش را به‌عنوان کاربر خانگی جا نمی‌زند. تغییر timezone یا user-agent به‌تنهایی IP دیتاسنتری را مسکونی نمی‌کند و ممکن است باعث ناسازگاری قابل‌تشخیص شود.': 'The browser does not remove fingerprints or pretend to be a residential user. Changing the time zone or user agent alone does not make a datacenter IP residential and may cause detectable incompatibilities.',
  'کوکی‌های شخص ثالث': 'Third-party cookies',
  'کوکی شخص ثالث به‌طور پیش‌فرض مسدود است. از منوی مرورگر می‌توانی با تأیید روشنش کنی؛ بعضی ورودهای یکپارچه یا پرداخت‌ها ممکن است به آن نیاز داشته باشند، اما فعال‌سازی می‌تواند ردیابی بین‌سایتی را آسان‌تر کند.': 'Third-party cookies are blocked by default. You can enable them with confirmation from the browser menu; some single sign-ons or payments may need them, but enabling them can make cross-site tracking easier.',
  'کوکی‌های اصلی سایت برای ورود و عملکرد صفحه همچنان می‌توانند ذخیره شوند. پاک‌کردن داده‌های سایت، کوکی‌ها و دادهٔ وب را حذف می‌کند و ممکن است نشست‌ها را ببندد.': 'First-party site cookies may still be stored for sign-in and page functionality. Clearing site data deletes cookies and web data and may end sessions.',
  'هشدار پروفایل insecure=1': 'insecure=1 profile warning',
  'اگر لینک Hysteria2 شامل insecure=1 باشد، اعتبار گواهی TLS سرور بررسی نمی‌شود. برنامه پیش از اتصال هشدار می‌دهد و تأیید صریح می‌خواهد؛ این گزینه می‌تواند اتصال را در برابر حملهٔ واسطه آسیب‌پذیر کند.': 'If the Hysteria2 link contains insecure=1, the server TLS certificate is not validated. The app warns and requires explicit confirmation before connecting; this option can make the connection vulnerable to a man-in-the-middle attack.',
  'فقط برای سروری ادامه بده که به اپراتورش اعتماد داری. امن‌ترین حالت استفاده از گواهی معتبر و خاموش‌بودن insecure است.': 'Continue only for a server whose operator you trust. The safest option is to use a valid certificate and keep insecure turned off.',
  'تاریخچه، نشانک و داده‌های محلی': 'History, bookmarks, and local data',
  'تاریخچه و نشانک‌ها در فضای محلی برنامه ذخیره می‌شوند و Orbit آن‌ها را به حساب ابری خودش همگام نمی‌کند. در APKهای ساخته‌شده، Android Auto Backup برای برنامه غیرفعال شده است؛ این موضوع به معنی رمزگذاری داده‌های محلی نیست. هر نشانی کامل ممکن است query حساس داشته باشد.': 'History and bookmarks are stored locally by the app, and Orbit does not sync them to its own cloud account. Android Auto Backup is disabled for built APKs; this does not mean local data is encrypted. A full URL may contain a sensitive query.',
  'گزینهٔ پاک‌کردن داده‌های وب، کوکی‌ها، cache و storage سایت را پاک می‌کند؛ تاریخچه و نشانک‌ها جدا هستند و از صفحهٔ کتابخانه پاک می‌شوند. پاک‌کردن دادهٔ وب ممکن است نشست ورود را ببندد.': 'The clear web data option deletes cookies, cache, and site storage; history and bookmarks are separate and are cleared from the library screen. Clearing web data may end sign-in sessions.',
  'دانلودها در خود مرورگر ذخیره یا مدیریت نمی‌شوند. Orbit نام فایل یا لینک درخواست‌شده را نشان می‌دهد و می‌تواند URL را در کلیپ‌بورد کپی کند تا آن را در دانلودمنیجر باز کنی؛ مقصد و رفتار دانلودمنیجر بیرون از کنترل صفحهٔ مرورگر است.': 'Downloads are not stored or managed in the browser itself. Orbit shows the requested file name or link and can copy the URL to the clipboard so you can open it in a download manager; the destination and behavior of that manager are outside the browser’s control.',
  'ذخیره‌سازی محلی در sandbox برنامه است، اما مگر آنکه نسخه صریحاً رمزگذاری را پیاده‌سازی کند، نباید آن را مخزن رمزگذاری‌شده فرض کرد. از دستگاه قفل‌شده و به‌روز استفاده کن.': 'Local storage is in the app sandbox, but unless a version explicitly implements encryption, do not assume it is an encrypted vault. Use a locked, up-to-date device.',
  'سنجش تأخیر': 'Latency measurement',
  'سنجش فعلی یک درخواست HTTPS آزمایشی از مسیر شبکهٔ پس از اتصال اندازه می‌گیرد. این ICMP ping یا اندازه‌گیری مستقیم handshake سرور Hysteria2 نیست و نتیجه به مسیر، DNS و endpoint آزمایش وابسته است.': 'The current measurement times a test HTTPS request over the network route after connection. It is not an ICMP ping or a direct measurement of the Hysteria2 server handshake, and the result depends on the route, DNS, and test endpoint.',
  'آنچه این مرورگر تضمین نمی‌کند': 'What this browser does not guarantee',
  'Orbit ناشناس‌بودن کامل، جلوگیری از همهٔ انواع نشت، fingerprint معتبر، IP مسکونی، timezone کاملاً نامرئی، یا در دسترس‌بودن دائمی سرور VPN را تضمین نمی‌کند. اتصال واقعی و رفتار WebRTC/DNS باید روی گوشی و شبکهٔ خودت آزمایش شود.': 'Orbit does not guarantee complete anonymity, prevention of every kind of leak, a valid fingerprint, a residential IP, a completely invisible time zone, or continuous availability of the VPN server. The actual connection and WebRTC/DNS behavior should be tested on your own phone and network.',
  'برای قفل سراسری Android، Always-on VPN و Block connections without VPN را در تنظیمات سیستم روشن کن. گزینهٔ داخل مرورگر فقط بارگذاری صفحات همین رابط را کنترل می‌کند.': 'For system-wide Android lockdown, enable Always-on VPN and Block connections without VPN in system settings. The browser option controls page loading only in this interface.',
};
