APP_NAME = SmartSwitcher
DIST = dist/$(APP_NAME).app

# Command Line Tools с SDK macOS 27 не содержат плагин SwiftUIMacros
# (`@State` стал макросом) — собираем полным Xcode, если он установлен.
XCODE_DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer
ifneq ($(wildcard $(XCODE_DEVELOPER_DIR)),)
export DEVELOPER_DIR ?= $(XCODE_DEVELOPER_DIR)
endif

.PHONY: build test integration test-all bundle bundle-universal assemble run icon clean

build:
	swift build -c release

# Собственный раннер (ADR-0003): работает и с CLT, и с Xcode.
test:
	swift run SmartSwitcherChecks

# Интеграционный тест (ТЗ 7.1): реальный движок + живой перенабор в своё окно.
# Открывает временное окно, прав Accessibility не требует.
integration:
	swift run SmartSwitcherIntegration

test-all: test integration

bundle: build
	$(MAKE) assemble BINARY=.build/release/$(APP_NAME)

# Universal binary (arm64 + x86_64) для дистрибуции.
bundle-universal:
	swift build -c release --arch arm64 --arch x86_64
	$(MAKE) assemble BINARY=.build/apple/Products/Release/$(APP_NAME)

assemble:
	rm -rf dist
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp Support/Info.plist $(DIST)/Contents/Info.plist
	cp $(BINARY) $(DIST)/Contents/MacOS/$(APP_NAME)
	# Ресурсы SPM (словари, модели, локализация) — обязательны для Bundle.module
	cp -R $(dir $(BINARY))$(APP_NAME)_SmartSwitcherKit.bundle $(DIST)/Contents/Resources/
	cp Resources/AppIcon.icns $(DIST)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(DIST)
	@echo "Готово: $(DIST)"

run: bundle
	open $(DIST)

icon:
	swift Tools/make_icon.swift /tmp/ss_icon_1024.png
	rm -rf /tmp/ss.iconset && mkdir -p /tmp/ss.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s /tmp/ss_icon_1024.png --out /tmp/ss.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d /tmp/ss_icon_1024.png --out /tmp/ss.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	mkdir -p Resources
	iconutil -c icns /tmp/ss.iconset -o Resources/AppIcon.icns
	@echo "Иконка: Resources/AppIcon.icns"

clean:
	rm -rf .build dist
