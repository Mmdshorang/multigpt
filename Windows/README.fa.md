# نسخه Windows برنامه MultiCodex

## بیلد

ساده‌ترین مسیر از ریشه پروژه:

```powershell
just win-run
```

دستورهای آماده:

```powershell
just win-build                 # بیلد Debug
just win-build Release         # بیلد Release
just win-run                   # بیلد و اجرای Debug
just win-publish               # خروجی Windows\dist\MultiCodex.exe
just win-publish-self-contained # خروجی مستقل همراه Runtime
```

بدون `just` هم می‌توانید مستقیم در PowerShell اجرا کنید:

```powershell
.\Windows\build-windows.ps1              # بیلد Debug
.\Windows\build-windows.ps1 -Run         # بیلد و اجرا
.\Windows\build-windows.ps1 -Publish     # publish در Windows\dist
```

خروجی publish در مسیر زیر ساخته می‌شود:

```text
Windows\dist\MultiCodex.exe
```

این خروجی به `.NET Desktop Runtime 10` نیاز دارد. برای ساخت نسخه‌ای که Runtime را هم داخل خود دارد:

```powershell
just win-publish-self-contained
# یا:
.\Windows\build-windows.ps1 -SelfContained
```

## استفاده

1. ابتدا Codex CLI را نصب کنید و مطمئن شوید دستور `codex --version` کار می‌کند.
2. برنامه `MultiCodex.exe` را اجرا کنید.
3. روی `Log in account` بزنید و برای حساب یک نام انتخاب کنید. سپس یکی از دو روش را انتخاب کنید: `Device code` (پیشنهادی) یا `Normal browser login`.
4. در روش Device Code، کد یک‌بارمصرف را در **صفحه مرورگر** وارد کنید، نه در ترمینال. روش Normal Browser کد ندارد و نتیجه را از callback محلی روی پورت `1455` دریافت می‌کند.
5. برای حساب بعدی دوباره `Log in account` را با یک نام جدید اجرا کنید.
6. حساب موردنظر را انتخاب کرده و `Switch selected` را بزنید.

برنامه با بستن پنجره در System Tray باقی می‌ماند. برای خروج کامل، روی آیکن Tray راست‌کلیک و `Exit` را انتخاب کنید.

هر حساب در `%APPDATA%\MultiCodex\managed-homes\<account>\auth.json` نگهداری می‌شود. با `Switch selected`، فایل حساب انتخاب‌شده به `%USERPROFILE%\.codex\auth.json` کپی می‌شود؛ بنابراین ترمینال‌های جدیدی که `codex` را اجرا می‌کنند با همان حساب انتخاب‌شده کار می‌کنند.

اگر `codex login` معمولی روی Windows خطای `os error 10013` بدهد، علت معمولا blocked/reserved بودن پورت callback محلی است. نسخه Windows برنامه برای جلوگیری از این مشکل از `codex login --device-auth` درون خود برنامه استفاده می‌کند.

ورود با device code باید در `ChatGPT Settings > Security` برای حساب شخصی فعال باشد. در Workspaceهای سازمانی ممکن است ادمین باید این مجوز را فعال کند. برنامه نمی‌تواند این سیاست امنیتی سمت ChatGPT را دور بزند، اما متن خطای Codex را کامل در پنجره ورود نشان می‌دهد.

پیش از شروع Normal Browser Login، برنامه آزادبودن پورت `1455` را بررسی می‌کند. اگر Windows یا برنامه دیگری آن را مسدود کرده باشد، فرایند خراب شروع نمی‌شود و می‌توانید همان‌جا Device Code را انتخاب کنید.
