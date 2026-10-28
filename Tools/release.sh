#!/usr/bin/env bash
# Релизная сборка SmartSwitcher: universal binary, подпись Developer ID,
# hardened runtime, нотаризация, DMG (ТЗ 11/14). Требует Apple Developer ID.
#
# Использование:
#   DEVELOPER_ID="Developer ID Application: Имя (TEAMID)" \
#   NOTARY_PROFILE="smartswitcher-notary" \
#   [PROVISIONING_PROFILE=path/to/SmartSwitcher.provisionprofile] \
#   ./Tools/release.sh
#
# PROVISIONING_PROFILE (Developer ID profile с iCloud) включает синхронизацию
# через iCloud KVS. Без него приложение собирается без iCloud-entitlement —
# ограниченное entitlement без профиля не даёт приложению запуститься.
#
# Предварительно один раз сохранить креды нотаризации:
#   xcrun notarytool store-credentials "smartswitcher-notary" \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-pw
set -euo pipefail

APP="dist/SmartSwitcher.app"
DMG="dist/SmartSwitcher.dmg"

: "${DEVELOPER_ID:?нужна переменная DEVELOPER_ID (Developer ID Application)}"
: "${NOTARY_PROFILE:?нужна переменная NOTARY_PROFILE (профиль notarytool)}"

TEAM_ID=$(sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' <<<"$DEVELOPER_ID")
: "${TEAM_ID:?не удалось извлечь TEAMID из DEVELOPER_ID}"

echo "==> Universal-сборка и бандл"
make bundle-universal

ENTITLEMENTS="Support/SmartSwitcher.entitlements"
if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
  echo "==> Provisioning profile: синхронизация iCloud включена"
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS="$(mktemp -t smartswitcher-entitlements).plist"
  sed "s/TEAM_ID/$TEAM_ID/g" Support/SmartSwitcher-iCloud.entitlements > "$ENTITLEMENTS"
else
  echo "==> Без provisioning profile: синхронизация iCloud будет недоступна"
fi

echo "==> Подпись с hardened runtime"
codesign --force --options runtime \
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
spctl --assess --type execute --verbose=4 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
echo "Готово: $DMG (версия $VERSION)"
echo "Опубликуйте релиз v$VERSION в GitHub Releases — приложение найдёт его при проверке обновлений."
