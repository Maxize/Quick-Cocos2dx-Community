LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

CCX_ROOT := $(LOCAL_PATH)/../../..
CCX_ROOT_2 := $(LOCAL_PATH)/../../cocos2d-x
GAF_LIB_SOURCES := $(LOCAL_PATH)/../Library/Sources
GAF_BINDINGS_SOURCES := $(LOCAL_PATH)/bindings

LOCAL_MODULE := gafjsbindings_static

LOCAL_MODULE_FILENAME := libgafjsbindings

CLASSES_FILES := $(wildcard $(GAF_LIB_SOURCES)/*.cpp) $(wildcard $(GAF_BINDINGS_SOURCES)/*.cpp)
LOCAL_SRC_FILES := $(CLASSES_FILES:$(LOCAL_PATH)/%=%)

LOCAL_C_INCLUDES := \
$(CCX_ROOT)/cocos \
$(CCX_ROOT)/cocos/platform/android \
$(CCX_ROOT)/plugin/jsbindings/manual \
$(CCX_ROOT)/../bindings/manual \
$(CCX_ROOT_2)/cocos \
$(CCX_ROOT_2)/cocos/platform/android \
$(CCX_ROOT_2)/plugin/jsbindings/manual \
$(CCX_ROOT_2)/../bindings/manual \
$(GAF_LIB_SOURCES) \
$(GAF_BINDINGS_SOURCES) \

LOCAL_STATIC_LIBRARIES := spidermonkey_static

include $(BUILD_STATIC_LIBRARY)

$(call import-module,external/spidermonkey/prebuilt/android)