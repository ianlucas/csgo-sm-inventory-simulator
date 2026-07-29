VERSION ?= 0.1.0

SPCOMP ?= spcomp
SPCOMP_PATH := $(shell command -v $(SPCOMP) 2>/dev/null || printf '%s' $(SPCOMP))
SM_INCLUDE ?= $(dir $(SPCOMP_PATH))include

BUILD_DIR := build
PLUGIN_BINARY := $(BUILD_DIR)/inventorysimulator.smx
EXTENSION_BINARY := extensions/inventorysimulator/build/inventorysimulator.ext.2.csgo.so
PACKAGE_DIR := $(BUILD_DIR)/package
ARCHIVE := $(BUILD_DIR)/InventorySimulator-v$(VERSION)-linux.zip

PLUGIN_SOURCES := \
	scripting/inventorysimulator.sp \
	$(wildcard scripting/inventorysimulator/*.sp) \
	scripting/include/inventorysimulator.inc

.PHONY: all plugin extension package archive checksums clean

all: archive

plugin: $(PLUGIN_BINARY)

$(PLUGIN_BINARY): $(PLUGIN_SOURCES)
	mkdir -p $(BUILD_DIR)
	$(SPCOMP) \
		-i $(SM_INCLUDE) \
		-i scripting/include \
		-o $@ \
		scripting/inventorysimulator.sp

extension:
	$(MAKE) -C extensions/inventorysimulator \
		SOURCEMOD="$(SOURCEMOD)" \
		$(if $(SOURCEPAWN),SOURCEPAWN="$(SOURCEPAWN)") \
		$(if $(AMTL),AMTL="$(AMTL)")

package: plugin
	test -f $(EXTENSION_BINARY)
	rm -rf $(PACKAGE_DIR)
	install -Dm644 $(PLUGIN_BINARY) \
		$(PACKAGE_DIR)/addons/sourcemod/plugins/inventorysimulator.smx
	install -Dm755 $(EXTENSION_BINARY) \
		$(PACKAGE_DIR)/addons/sourcemod/extensions/inventorysimulator.ext.2.csgo.so
	install -Dm644 gamedata/inventorysimulator.games.txt \
		$(PACKAGE_DIR)/addons/sourcemod/gamedata/inventorysimulator.games.txt
	install -Dm644 translations/inventorysimulator.phrases.txt \
		$(PACKAGE_DIR)/addons/sourcemod/translations/inventorysimulator.phrases.txt

archive: package
	rm -f $(ARCHIVE)
	cd $(PACKAGE_DIR) && zip -q -r ../$(notdir $(ARCHIVE)) .

checksums: archive
	sha256sum $(PLUGIN_BINARY) $(EXTENSION_BINARY) $(ARCHIVE)

clean:
	rm -f $(PLUGIN_BINARY) $(ARCHIVE)
	rm -rf $(PACKAGE_DIR)
