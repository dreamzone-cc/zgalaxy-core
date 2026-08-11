# إصلاح خطأ الترجمة على ويندوز في `service/OneService.cpp`

## ملخص

تم إصلاح خطأ ترجمة (Build Error) يظهر فقط عند بناء مشروع **ZGALAXY One** على ويندوز
باستخدام MSVC، بينما البناء على لينكس يعمل دون مشاكل. الخطأ كان:

```
service/OneService.cpp(30,10): error C1083: Cannot open include file: 'netdb.h': No such file or directory
```

السبب الجذري هو استخدام ماكرو `__WINDOWS__` في `service/OneService.cpp` **قبل** تضمين
`../node/Constants.hpp` الذي يعرّف هذا الماكرو، مما جعل المحوّل (Preprocessor) ينتقل
إلى فرع `#else` ويحاول تضمين رؤوس POSIX غير المتوفرة على ويندوز.

---

## المشكلة بالتفصيل

### 1. الماكرو `__WINDOWS__` من أين يأتي؟

ماكرو `__WINDOWS__` **ليس** ماكرواً معرفاً من المترجم (Compiler). هو ماكرو خاص بمشروع
ZeroTier/ZGALAXY يُعرَّف يدوياً في `node/Constants.hpp`:

```cpp
// node/Constants.hpp — السطر 89-95
#if defined(_WIN32) || defined(_WIN64)
...
#ifndef __WINDOWS__
#define __WINDOWS__
#endif
```

أي أن `__WINDOWS__` لا يكون معرّفاً إلا **بعد** أن يتم تضمين `Constants.hpp` في ملف
الترجمة.

> ملاحظة: الماكرو `_WIN32` و `_WIN64` على النقيض هما ماكروان **معرّفان تلقائياً من
> المترجم** MSVC عند البناء على منصات ويندوز، ولا يعتمدان على أي تضمين.

### 2. الكتلة الشرطية المسببة للمشكلة

في `service/OneService.cpp` كانت الكتلة التالية موجودة في بداية الملف
(قبل تضمين `Constants.hpp`):

```cpp
// service/OneService.cpp — قبل الإصلاح
#include <algorithm>
...
#include <vector>

#ifdef __WINDOWS__          // <-- السطر 26: التقييم هنا يحدث قبل تضمين Constants.hpp
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netdb.h>          // <-- السطر 30: هذا الفرع يُختار على ويندوز (خطأ!)
#include <sys/socket.h>
#endif

#include "../include/ZeroTierOne.h"
#include "../node/Constants.hpp"   // <-- السطر 41: __WINDOWS__ يُعرَّف هنا فقط
```

عندما يبدأ المترجم في معالجة السطر 26، يكون الماكرو `__WINDOWS__` غير معرّف بعد
(لأن `Constants.hpp` يُضمَّن في السطر 41 لاحقاً)، لذلك يقوم المحوّل باختيار فرع
`#else` ويحاول تضمين:

- `netdb.h` — رأس POSIX غير موجود على ويندوز (سبب الخطأ `C1083`)
- `sys/socket.h` — رأس POSIX أيضاً غير متوفر على ويندوز

أما على لينكس/ماك فإن الماكرو `__WINDOWS__` غير معرّف دائماً، فيكون فرع `#else`
هو الفرع الصحيح، ولا تظهر المشكلة إطلاقاً. لهذا لم يكتشف المطورون الخطأ إلا عند
البناء على ويندوز.

### 3. لماذا ظهر هذا الكود أساساً؟

الكتلة أُضيفت في commit `b32c1ba2` — *"feat(client): native reactive dynamic-DNS
layer"* — والذي أضاف طبقة **حل أسماء النطاقات (DNS resolution)** الديناميكية، وهي
تستخدم دالات `getaddrinfo` / `freeaddrinfo` عبر `struct addrinfo`:

```cpp
// service/OneService.cpp — دالة _resolveDomainIPv4s (سطر 1119)
struct addrinfo hints;
memset(&hints, 0, sizeof(hints));
hints.ai_family = AF_INET;
hints.ai_socktype = SOCK_DGRAM;
struct addrinfo* res = (struct addrinfo*)0;
if (getaddrinfo(domain.c_str(), (const char*)0, &hints, &res) != 0) { ... }
freeaddrinfo(res);
```

تتطلب هذه الدالات على لينكس تضمين `netdb.h`، وعلى ويندوز تضمين `ws2tcpip.h`.
لذلك أُضيفت الكتلة الشرطية `#ifdef __WINDOWS__ ... #else netdb.h` في أعلى الملف —
ولكن في موضع خاطئ من الناحية اللغوية، لأنها وُضعت قبل نقطة تعريف الماكرو.

---

## الإصلاح المطبَّق

تم استبدال الشرط `#ifdef __WINDOWS__` بالشرط المكافئ الذي يعتمد على ماكرو المترجم:

```cpp
// service/OneService.cpp — بعد الإصلاح (السطر 26)
#if defined(_WIN32) || defined(_WIN64)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netdb.h>
#include <sys/socket.h>
#endif
```

### لماذا هذا الحل صحيح؟

1. **`_WIN32` / `_WIN64` معرفان تلقائياً**: لا يعتمدان على ترتيب التضمين، لذا يعمل
   التقييم بشكل صحيح مهما كان موقع الكتلة في الملف.
2. **تطابق مع اصطلاح المشروع**: الملفات الأخرى تعتمد على نفس النمط، على سبيل
   المثال `include/ZeroTierOne.h` (السطر 20) يستخدم `#if defined(_WIN32) || defined(_WIN64)`
   لنفس الغرض (تضمين winsock2/ws2tcpip)، وكذلك `node/Constants.hpp` (السطر 89).
3. **لا يؤثر على لينكس/ماك**: على المنصات غير ويندوز يبقى السلوك مطابقاً تماماً —
   يختار فرع `#else` ويتضمن `netdb.h` + `sys/socket.h` كما كان.

### بدائل أخرى تمت دراستها (ولم تُعتمد)

| البديل | لماذا لم يُعتمد |
|---|---|
| نقل كتلة التضمين إلى ما بعد `#include "../node/Constants.hpp"` | يغيّر ترتيب التضمينات وقد يكسر سلوك رؤوس النظام (ترتيب winsock2 قبل windows.h مهم)، كما أن التعديل الأصغر أقل عرضة للخطأ |
| إضافة `#include "../node/Constants.hpp"` في أعلى الملف | تضمين مكرر لملف رأس بعيد عن مكانه الأصلي، وتغيير أكبر من اللازم |
| إزالة الكتلة كلياً (الاعتماد على ZeroTierOne.h) | `ZeroTierOne.h` لا يتضمن `netdb.h` على المنصات غير ويندوز، فينكسر بناء لينكس |

---

## أين يقع الخطأ داخل بنية الملف؟

الكتل الشرطية الأخرى في نفس الملف (سطر 97، 116، 144) تستخدم `__WINDOWS__` بشكل
**صحيح** لأنها جميعها تقع **بعد** تضمين `../node/Constants.hpp` (السطر 41)، أي أن
الماكرو يكون معرّفاً عند تقييمها. المشكلة حصرية في الكتلة الأولى (السطر 26) التي
تسبق تضمين `Constants.hpp`.

```
السطر 26  →  #if defined(_WIN32)...  ← الكتلة المُصلّحة (قبل تضمين Constants.hpp)
السطر 39  →  #include "../include/ZeroTierOne.h"
السطر 41  →  #include "../node/Constants.hpp"   ← تعريف __WINDOWS__ هنا
السطر 97  →  #ifdef __WINDOWS__   ✓ صحيح (بعد السطر 41)
السطر 116 →  #elif defined(__WINDOWS__)  ✓ صحيح (بعد السطر 41)
السطر 144 →  #ifdef __WINDOWS__   ✓ صحيح (بعد السطر 41)
```

---

## التحقق من الإصلاح

تم التحقق من نجاح الإصلاح عبر البناء الكامل على ويندوز:

1. **بناء مكتبة Rust** `zeroidc` (مطلوبة لميزة SSO) — نجح.
2. **بناء المحرك** عبر MSBuild (Release / x64) — نجح بدون أي أخطاء `C1083`:

   ```
   ZeroTierOne.vcxproj -> windows\Build\x64\Release\zerotier-one_x64.exe
   ```

3. **تشغيل الملف الناتج** يعرض الإصدار الصحيح:

   ```
   > zgalaxy-one.exe -v
   1.16.2
   ```

4. **التحقق من غياب مراجع ZeroTier الرسمية** في الملف الثنائي:
   - `my.zerotier.com` → غير موجود ✓
   - `central.zerotier.com` → غير موجود ✓
   - `204.80.128` (IP خوادم ZeroTier الرسمية) → غير موجود ✓

5. **بناء المثبت** NSIS `ZGALAXY-One-Setup.exe` — نجح.

---

## حالة التعديل

التعديل موجود محلياً في `service/OneService.cpp` (ملف `M` في حالة `git status`) ولم
يُرفع بعد إلى المستودع. وثيقة البناء `docs/BUILD-WINDOWS.md` توضح أن نفس المستودع
يُبنى محلياً على ويندوز عبر `windows/build-windows.ps1`، مما يؤكد أن هذا الإصلاح
ضروري لاستمرار مسار البناء المحلي (Option B).
