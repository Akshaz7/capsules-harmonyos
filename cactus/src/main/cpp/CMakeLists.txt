cmake_minimum_required(VERSION 3.5.0)
project(CactusNapi)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
# Prebuilt Cactus engine (cross-compiled separately, see SPIKE_LOG.md step 2).
set(CACTUS_LIB_DIR ${NATIVERENDER_ROOT_PATH}/../../../libs/${OHOS_ARCH})

add_library(cactus_engine SHARED IMPORTED)
set_target_properties(cactus_engine PROPERTIES IMPORTED_LOCATION ${CACTUS_LIB_DIR}/libcactus_engine.so)

add_library(cactus_napi SHARED napi_init.cpp)
set_target_properties(cactus_napi PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
target_include_directories(cactus_napi PRIVATE ${NATIVERENDER_ROOT_PATH}/include)
target_link_libraries(cactus_napi PUBLIC libace_napi.z.so libhilog_ndk.z.so cactus_engine)
