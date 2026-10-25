# Samosa POS (Android APK + Windows EXE)

Offline point-of-sale app: menu, stock with recipes, Udhar ledger, tables/held orders,
receipts (share/save as image), English/Urdu, database backup.

## Get the APK and EXE from GitHub

1. Create a new GitHub repository and upload everything in this folder
   (keep the structure: `lib/`, `pubspec.yaml`, `.github/workflows/build.yml`, ...).
2. Open the **Actions** tab. The build starts automatically on every push to `main`.
   You can also press **Run workflow** on "Build Android APK and Windows EXE".
3. When both jobs are green, open the run and download:
   - `SamosaPOS-Android-APK` -> `SamosaPOS.apk` (install on the phone)
   - `SamosaPOS-Windows-EXE` -> `SamosaPOS-Windows.zip` (unzip, run `samosa_pos.exe`)
4. For a permanent download page, create a tag like `v1.0.0`
   (Releases -> Draft a new release -> choose a new tag). The APK and ZIP are attached automatically.

## Notes

- The Windows app needs the whole unzipped folder (the exe plus the DLLs next to it).
- The APK is signed with a debug key: fine for installing directly, not for Google Play.
- Data is stored locally. Windows: `%APPDATA%` app-support folder; backups go to
  `Documents\SamosaPOS\Backups`. Android: use Settings -> Share database backup.
- Android and Windows each have their own database; backups are not auto-synced.
- Printing is by receipt image (share/save). Direct Bluetooth thermal printing is not included.
