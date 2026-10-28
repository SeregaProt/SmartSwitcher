#!/usr/bin/env bash
# Релизная сборка SmartSwitcher: universal binary, подпись Developer ID,
# hardened runtime, нотаризация, DMG (ТЗ 11/14). Требует Apple Developer ID.
#
# Использование:
#   DEVELOPER_ID="Developer ID Application: Имя (TEAMID)" \
#   NOTARY_PROFILE="smartswitcher-notary" \
#   ./Tools/release.sh
#
# Предварительно один раз сохранить креды нотаризации:
#   xcrun notarytool store-credentials "smartswitcher-notary" \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-pw
set -euo pipefail

APP="dist/SmartSwitcher.app"
ENTITLEMENTS="Support/SmartSwitcher.entitlements"
DMG="dist/SmartSwitcher.dmg"

: "${DEVELOPER_ID:?нужна переменная DEVELOPER_ID (Developer ID Application)}"
: "${NOTARY_PROFILE:?нужна переменная NOTARY_PROFILE (профиль notarytool)}"

echo "==> Universal-сборка и бандл"
make bundle-universal

echo "==> Подпись с hardened runtime"
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID" \
  --timestamp "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Сборка DMG"
rm -f "$DMG"
hdiutil create -volname "SmartSwitcher" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "==> Нотаризация (ожидание вердикта Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Степлинг тикета"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo "==> Проверка Gatekeeper"
spctl --assess --type execute --verbose=4 "$APP" || true

echo "Готово: $DMG"
echo "Не забудьте: обновить appcast (EdDSA-подпись) для канала Sparkle."
