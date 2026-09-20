# ORBIT — ساخت اپلیکیشن اندروید (APK) با GitHub Actions

این پوشه یه پروژهٔ Capacitor آماده‌ست که وب‌اپ ORBIT رو داخل یه اپ اندرویدی واقعی
بسته‌بندی می‌کنه. بیلد نهایی (APK) رو GitHub به‌صورت خودکار و رایگان برات می‌سازه —
نیازی به Android Studio یا SDK روی گوشی نیست.

## مرحله ۱: ساخت ریپازیتوری روی گیت‌هاب
از مرورگر گوشی یا از Termux با `gh` (اگه نصبه) یه ریپو خصوصی یا عمومی بساز، مثلاً
به اسم `orbit-android`.

## مرحله ۲: آپلود این پوشه به ریپو (از Termux)
```bash
cd orbit-android          # همین پوشه‌ای که این فایل توشه
git init
git add .
git commit -m "Initial ORBIT Android project"
git branch -M main
git remote add origin https://github.com/USERNAME/orbit-android.git
git push -u origin main
```
به‌جای `USERNAME` نام کاربری خودت رو بذار. موقع push ازت یوزرنیم/پسورد یا
Personal Access Token می‌خواد (پسورد معمولی گیت‌هاب دیگه کار نمی‌کنه — باید
از GitHub Settings → Developer settings → Personal access tokens یه توکن بسازی
و به‌جای پسورد ازش استفاده کنی).

## مرحله ۳: صبر برای بیلد خودکار
به محض push شدن، تب **Actions** توی ریپوی گیت‌هابت رو باز کن — یه workflow به اسم
"Build Android APK" خودش شروع به اجرا می‌کنه (حدود ۳ تا ۵ دقیقه طول می‌کشه).

## مرحله ۴: دانلود APK
وقتی بیلد سبز (✅) شد:
1. روی همون ران کلیک کن
2. پایین صفحه، بخش **Artifacts** رو پیدا کن
3. فایل `orbit-debug-apk` رو دانلود کن (یه zip هست که APK توشه)
4. اون رو روی گوشی اندرویدت باز/نصب کن (شاید لازم باشه توی تنظیمات گوشی
   نصب از «منابع ناشناس» رو موقتاً فعال کنی)

## اگه خواستی هر بار خودت دوباره بیلد کنی
هر بار که فایل `www/index.html` (همون وب‌اپ) رو عوض کردی:
```bash
cd orbit-android
git add .
git commit -m "Update app"
git push
```
GitHub Actions خودش دوباره APK جدید می‌سازه.

## نکات مهم
- این APK یه **نسخهٔ debug** هست — برای نصب مستقیم و تست کاملاً کافیه.
  برای انتشار روی Google Play باید نسخهٔ **release** امضا (sign) بشه که
  مرحلهٔ جداگانه‌ایه (بگو تا اون workflow رو هم اضافه کنم).
- اسم اپ و آیکون رو می‌تونی از `capacitor.config.json` (فیلد `appName`)
  و پوشهٔ آیکون‌های اندروید (بعد از اولین بیلد لوکال) تغییر بدی.
- اگه از دیتابیس Cloudflare (D1) استفاده می‌کنی، حتماً قبل از push کردن،
  مقدار `API_BASE` رو داخل `www/index.html` با آدرس Worker خودت پر کن.
