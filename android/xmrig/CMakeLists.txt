# XMRT Node — XMRig native build for Android ARM64
#
# Build: cmake -B build -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#               -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=24
#
# The actual XMRig source should be cloned as a submodule:
#   git submodule add https://github.com/xmrig/xmrig.git android/xmrig/src

cmake_minimum_required(VERSION 3.22)
project(xmrig NONE)

# XMRig is compiled as a static library then linked into the app
# For the initial build, use the prebuilt .so in jniLibs/
# Full XMRig CMakeLists.txt is at android/xmrig/src/CMakeLists.txt
# Once submodule is in place, uncomment the add_subdirectory below:

# add_subdirectory(src/xmrig)
# target_link_libraries(xmrig_bridge xmrig)

message(STATUS "XMRT Node native build")
message(STATUS "Use prebuilt xmrig.so from jniLibs/arm64-v8a/ for now")
message(STATUS "Full source build requires: git submodule update --init android/xmrig/src")
