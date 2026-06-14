# نسخه Windows برنامه MultiCodex

## بیلد

در PowerShell از ریشه پروژه اجرا کنید:

```powershell
.\Windows\build-windows.ps1
```

خروجی مستقل برنامه در مسیر زیر ساخته می‌شود:

```text
Windows\dist\MultiCodex.exe
```

این خروجی به `.NET Desktop Runtime 10` نیاز دارد. برای ساخت نسخه‌ای که Runtime را هم داخل خود دارد:

```powershell
.\Windows\build-windows.ps1 -SelfContained
```

## استفاده

1. ابتدا Codex CLI را نصب کنید و مطمئن شوید دستور `codex --version` کار می‌کند.
2. برنامه `MultiCodex.exe` را اجرا کنید.
3. روی `Run Codex login` بزنید و ورود را در ترمینال کامل کنید.
4. به برنامه برگردید، `Add current login` را بزنید و برای حساب یک نام انتخاب کنید.
5. برای حساب بعدی دوباره Login و سپس Add current login را انجام دهید.
6. حساب موردنظر را انتخاب کرده و `Switch selected` را بزنید.

برنامه با بستن پنجره در System Tray باقی می‌ماند. برای خروج کامل، روی آیکن Tray راست‌کلیک و `Exit` را انتخاب کنید.

داده‌ها در `%APPDATA%\MultiCodex` و حساب فعال Codex در `%USERPROFILE%\.codex\auth.json` نگهداری می‌شوند.
