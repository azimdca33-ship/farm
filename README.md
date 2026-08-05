# admin.lua release

## O'rnatish
1. Barcha release fayllarini RakBot papkasiga ko'chiring.
2. `settings/config.example.txt`ni `settings/config.txt` nomiga o'zgartiring.
3. `bot_name`, Telegram `token`, `chatid`, SA-MP `password` va ixtiyoriy `gemini_key`ni kiriting.
4. `licenses.txt`dagi nick ro'yxatda bo'lishi kerak.

Updater yangi versiyani `version.json` orqali tekshiradi, SHA-256 mos kelmasa faylni almashtirmaydi va almashtirishdan oldin `admin.lua.backup` yaratadi. `sha256` Lua moduli bo'lmasa updater xavfsizlik sabab yangilamaydi.

## GitHub fayllari
`admin.lua`, `updater.lua`, `version.json`, `admin.lua.sha256`, `licenses.txt`, `config.example.txt`, `README.md`.

Maxfiy `config.txt`, tokenlar, parollar va mijoz xotira fayllarini GitHub'ga yuklamang.
