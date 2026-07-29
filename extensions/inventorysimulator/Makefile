CXX ?= g++
LD ?= ld

ifndef SOURCEMOD
$(error Set SOURCEMOD to a SourceMod source checkout)
endif

SOURCEPAWN ?= $(SOURCEMOD)/sourcepawn
AMTL ?= $(SOURCEMOD)/public/amtl

BUILD_DIR ?= build
TARGET := $(BUILD_DIR)/inventorysimulator.ext.2.csgo.so

CPPFLAGS := \
	-I sdk \
	-I $(SOURCEMOD)/public \
	-I $(SOURCEPAWN)/include \
	-I $(AMTL) \
	-I $(AMTL)/amtl
CXXFLAGS := \
	-m32 \
	-std=c++17 \
	-fPIC \
	-fno-exceptions \
	-fno-rtti \
	-fno-stack-protector \
	-fno-threadsafe-statics \
	-fvisibility=hidden \
	-Wall \
	-Wextra \
	-Wno-unused-parameter \
	-Wno-sized-deallocation \
	-Werror \
	-D_LINUX \
	-DPOSIX

OBJECTS := \
	$(BUILD_DIR)/attribute_list.o \
	$(BUILD_DIR)/extension.o \
	$(BUILD_DIR)/smsdk_ext.o

.PHONY: all clean

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/extension.o: extension.cpp extension.h attribute_list.h sdk/smsdk_config.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/attribute_list.o: attribute_list.cpp attribute_list.h sdk/smsdk_config.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/smsdk_ext.o: $(SOURCEMOD)/public/smsdk_ext.cpp sdk/smsdk_config.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJECTS)
	$(LD) -m elf_i386 -shared -o $@ $(OBJECTS)

clean:
	rm -f $(OBJECTS) $(TARGET)
