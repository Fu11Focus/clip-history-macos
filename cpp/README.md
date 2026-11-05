# ClipHistory — C++ варіант (експеримент із пам'яттю)

Порт резидентної частини ClipHistory **без AppKit і без Swift runtime**, щоб
порівняти, скільки фізичної/приватної пам'яті займає демон, що крутиться 24/7.

## Що змінилось порівняно зі Swift-версією

| | Swift (`../daemon.swift`) | C++ (`daemond.cpp`) |
|---|---|---|
| Хоткей ⌘⇧V | Carbon `RegisterEventHotKey` — тому **потрібен AppKit** (без конекшена до WindowServer події не доставляються) | `CGEventTap` на «голому» `CFRunLoop` — **AppKit не потрібен** |
| Стеження за буфером | `NSPasteboard.changeCount` | Pasteboard Manager (C API): `PasteboardSynchronize` + `kPasteboardModified` |
| Рантайм | AppKit + Carbon + ~16 `libswift*.dylib` | лише ApplicationServices, CoreFoundation, CoreGraphics, libc++ |
| Дозволи демона | хоткею Accessibility **не** треба | `CGEventTap` **вимагає Accessibility для демона** |

Пікер (`picker.mm`) — це Objective-C++ дзеркало `picker.swift`. UI неминуче на
AppKit, тож економити там нема на чому; весь сенс — у резидентному демоні.

Історія окрема від Swift-версії:
`~/Library/Application Support/ClipHistoryCpp/history.json` — щоб два демони не
конфліктували.

## Результати (Apple Silicon, `footprint` / `ps`)

Чесний показник — `phys_footprint` (private dirty). RSS роздутий спільними
сторінками фреймворків.

### Резидентний демон (крутиться завжди — це головне)

| | phys_footprint | RSS |
|---|---|---|
| **Swift** | **7745 KB** (~7.6 МБ) | 11.9 МБ |
| **C++** | **~2.2–2.6 МБ** | 6.7 МБ |

≈ **у 3 рази менше** приватної пам'яті. Різниця — це Swift runtime + AppKit,
яких C++-демон не тягне взагалі.

> ⚠️ C++-цифру виміряно поки `CGEventTap` був неактивний (демон ще не доданий в
> Accessibility). Активний tap додасть зовсім трохи — CoreGraphics уже
> завантажено; порядок (~2.5–3 МБ проти 7.6) не зміниться.

### Пікер (на вимогу, живе частку секунди)

| | phys_footprint |
|---|---|
| Swift | 13 МБ |
| C++ (Obj-C++) | 12 МБ |

Майже однаково — тут домінує AppKit, а не мова.

### Розмір бінарника демона

Swift 102 КБ · C++ 58 КБ.

## Збірка та запуск

```bash
./build.sh                 # збирає cpp/ClipHistoryCpp.app (демон + пікер)
open ClipHistoryCpp.app    # запуск через LaunchServices
```

Щоб запрацював хоткей ⌘⇧V, додай **ClipHistoryCpp** у
System Settings → Privacy & Security → Accessibility.

> Swift-версія тримає ⌘⇧V, поки її демон живий. Для чесного тесту «обох одразу»
> зупини один: `pkill ClipHistory` (Swift) або `pkill ClipHistoryCpp` (C++).

## Висновок

Для фонового агента, де головний критерій — приватна пам'ять, відмова від Swift
runtime і AppKit дає ~3× виграш (7.6 → ~2.5 МБ). Ціна: демону тепер потрібен
дозвіл Accessibility (через `CGEventTap`), якого Carbon-хоткею у Swift-версії не
вимагав.
