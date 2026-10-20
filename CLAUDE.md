# Working rules for this repository

- UI work follows **Impeccable** (installed in `.claude/skills/impeccable`, hooks in `.claude/settings.local.json`) and the design system in `DESIGN.md` / `PRODUCT.md`. Before editing any window, panel, toolbar or control, read `DESIGN.md`; take colours only from `Brand.swift`; build controls from `Chrome.swift`.
- Every user-visible string goes through `t("…")` and has a Thai entry in `Strings.swift` (no duplicate keys: the dictionary traps at runtime).
- Verify with `swift run ChaeDiewChecks` and the UI tour (`ChaeDiew --ui-tour <dir>`) — both must be clean before a build is called done.
- Credit line everywhere a "about" surface exists: **Powered by Panupong Nijjaboon**.
- The licence private key lives only in `~/Library/Application Support/Tenix-ChaeDiew-Keygen/` — never commit or print it.
- **Mac / Windows share this repo**: `Sources/`, `Package.swift`, `scripts/` are macOS-side only; `electron/` is owned by the Windows side (work on branch `windows`, merge by Pull Request, never force-push). Never change the licence key format or `electron/src/public-key.js` on one side only. See `docs/WINDOWS-GIT-WORKFLOW.md`.
