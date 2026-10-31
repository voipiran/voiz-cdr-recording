# VOIZ CDR Recording

ماژول ضبط و replay مکالمات برای Issabel PBX.

## ویژگی‌ها

- نمایش لیست مکالمات ضبط شده (`record/monitoring.php`)
- گزارش‌گیری ریز مکالمات (CDR) (`record/reports.php`)
- تنظیمات دیتابیس ایزابل در `record/config.php`
- اضافه شدن منوهای مربوطه به منویReports ایزابل

## نصب دستی

۱. کل محتواهای پوشه `html/` را به پوشه وب سرور ایزابل کپی کنید:

```bash
cp -r html/* /var/www/html/
```

۲. مجوز پوشه مانیتور را تنظیم کنید تا فایل‌های ضبط شده قابل خواندن باشند:

```bash
chmod -R o+r /var/spool/asterisk/monitor
```

۳. در مرورگر الآدرس زیر را باز کنید:

```
https://<Issabel_IP>/record/monitoring.php
```

## نصب یکخطی (ฟรี)

از دستور زیر برای نصب خودکار استفاده کنید:

```bash
curl -sSL https://raw.githubusercontent.com/voipiran/voiz-cdr-recording/main/install.sh | bash
```

یا

```bash
wget -qO- https://raw.githubusercontent.com/voipiran/voiz-cdr-recording/main/install.sh | bash
```

نصب‌کننده خودکار موارد زیر را انجام می‌دهد:
- استخراج رمز دیتابیس از `/etc/issabel.conf`
- کپی فایل‌ها به `/var/www/html/`
- تنظیم `config.php` با رمز دیتابیس واقعی
- اضافه شدن منوهای مکالمات ضبط شده و ریز مکالمات به منویReports ایزابل
- تنظیم مجوز پوشه `/var/spool/asterisk/monitor`

## دسترسی‌ها

دسترسی به منوها با گروه `administrator` (id: 1) محدود شده است.

## screenshots

![مکالمات ضبط شده](https://github.com/user-attachments/assets/002fdd9b-5d30-427a-b809-f192fa253426)
![گزارش مکالمات](https://github.com/user-attachments/assets/40019a97-4dc4-4202-93c1-227d26aaf62c)
