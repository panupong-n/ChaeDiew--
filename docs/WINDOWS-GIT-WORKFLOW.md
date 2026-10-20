# แบ่งงาน Mac / Windows ใน repo เดียว ไม่ให้ทับกัน

## กติกาเจ้าของโฟลเดอร์
| โฟลเดอร์ | ใครแก้ได้ |
|---|---|
| `Sources/`, `Package.swift`, `scripts/`, `brand/` | **ฝั่ง Mac เท่านั้น** (Swift) |
| `electron/` | **ฝั่ง Windows เป็นหลัก** (ฝั่ง Mac แก้ได้เฉพาะตอนตกลงกันแล้ว และต้องผ่าน Pull Request) |
| `docs/`, `README.md`, `CLAUDE.md` | แก้ได้ทั้งสองฝั่ง แต่แก้เฉพาะบรรทัดของตัวเอง |
| **ห้ามทั้งสองฝั่ง** แก้ `electron/src/public-key.js` และรูปแบบคีย์ใน `electron/src/license.js` (ต้องตรงกับ Swift) | — |

## ขั้นตอนฝั่ง Windows (ทำครั้งแรก)
1. `git clone https://github.com/panupong-n/ChaeDiew--.git` แล้ว `git checkout -b windows` (ทำงานบน branch `windows` เสมอ **ห้าม commit ตรงเข้า `main`**)
2. ฝั่ง Windows มีโค้ด `electron/` ที่แก้แล้วจาก zip เดิม ให้ทำแบบนี้ (กันทับ):
   - ย้ายโฟลเดอร์เดิมไปเก็บสำรองก่อน เช่น `C:\dev\electron-windows-backup`
   - เทียบความต่างระหว่างสำรองกับ `electron/` ใน repo ด้วย `git diff --no-index` หรือโปรแกรมเทียบไฟล์
   - ใช้เวอร์ชันของฝั่ง Windows เป็นหลัก แล้วนำการเปลี่ยนแปลงของฝั่ง Mac (ระบบคีย์แบบ "ใส่คีย์แล้วจบ": `requireActivation`, หน้าไลเซนส์) มารวม ตามไฟล์ `electron/WINDOWS-PROMPT-KEY-ONLY-LICENSE.md`
   - ไม่ต้องนำ `node_modules/` และ `dist/` ไปไว้ใน git (ถูกละเว้นอยู่แล้ว)
3. `git add electron docs` (ระบุโฟลเดอร์ ห้าม `git add -A` ที่ราก ถ้าไม่แน่ใจ) แล้ว `git status` ดูว่ามีไฟล์นอก `electron/` และ `docs/` ติดมาหรือไม่ ถ้ามีให้ยกเลิก
4. commit แล้ว `git push -u origin windows` แล้วเปิด **Pull Request** จาก `windows` เข้า `main` ให้ฝั่ง Mac ตรวจก่อน merge

## ทุกครั้งที่ทำงานต่อ (ฝั่ง Windows)
- เริ่มด้วย `git fetch origin` และ `git merge origin/main` เข้า `windows` เพื่อรับของฝั่ง Mac ก่อน ถ้ามี conflict ในไฟล์ใต้ `electron/` ให้แก้เอง ถ้า conflict ในไฟล์นอก `electron/` **ห้ามแก้ ให้หยุดแล้วแจ้งเจ้าของ**
- ก่อน push รัน `git diff --stat origin/main` ตรวจว่าไฟล์ที่เปลี่ยนอยู่ใน `electron/` และ `docs/` เท่านั้น
- ห้าม `git push --force`, `git reset --hard origin/main`, `git clean -fd` โดยไม่ถามเจ้าของ
- ห้ามนำไฟล์คีย์ (`*licenses*.csv`), `private.key`, `ledger.json` ใส่ใน repo เด็ดขาด

## ทุกครั้งที่ทำงานต่อ (ฝั่ง Mac)
- แก้เฉพาะ `Sources/`, `scripts/`, `docs/` ฯลฯ ที่ branch `main` หรือ branch ของตัวเอง
- merge Pull Request จาก `windows` เมื่อตรวจแล้ว จากนั้นรัน `swift run ChaeDiewChecks` และ `cd electron && npm test`
