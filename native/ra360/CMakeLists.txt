cmake_minimum_required(VERSION 3.22.1)
project(kanade_ra360 LANGUAGES C CXX)

if(WIN32)
    # Windows renders 360 Reality Audio for speakers with Ittiam's MPEG-H decoder.
    set(mpegh_commit f7ff0ac78d4d83f0b853bf2dff2ef075c92724f8)
    set(mpegh_archive "${CMAKE_CURRENT_BINARY_DIR}/libmpegh-${mpegh_commit}.tar.gz")
    set(mpegh_dir "${CMAKE_CURRENT_BINARY_DIR}/libmpegh-${mpegh_commit}")
    if(NOT EXISTS "${mpegh_dir}/CMakeLists.txt")
        file(DOWNLOAD "https://codeload.github.com/ittiam-systems/libmpegh/tar.gz/${mpegh_commit}"
            "${mpegh_archive}"
            EXPECTED_HASH "SHA256=3f26613bcd3949d5e0bb94715cd762f9205d40f4bdd6061609f10facdd1524bc"
            TLS_VERIFY ON TIMEOUT 180)
        file(ARCHIVE_EXTRACT INPUT "${mpegh_archive}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
    set(LC_LEVEL_4 ON CACHE BOOL "" FORCE)
    # libmpegh asks for CMake 3.8; 3.9/3.10 policies don't affect its Windows build.
    set(CMAKE_POLICY_VERSION_MINIMUM 3.10)
    add_subdirectory("${mpegh_dir}" libmpegh EXCLUDE_FROM_ALL)
    unset(CMAKE_POLICY_VERSION_MINIMUM)

    add_library(kanade_ra360 SHARED mpegh_decoder.cpp speaker_layout.cpp)
    target_compile_features(kanade_ra360 PRIVATE cxx_std_17)
    target_compile_definitions(kanade_ra360 PRIVATE LC_LEVEL_4 NOMINMAX WIN32_LEAN_AND_MEAN)
    target_link_libraries(kanade_ra360 PRIVATE ia_mpeghd_lib ole32)
    target_compile_options(kanade_ra360 PRIVATE /utf-8)
    set_property(TARGET kanade_ra360 PROPERTY KANADE_MPEGH_LICENSE "${mpegh_dir}/LICENSE")
else()
    # Android renders headphone binaural audio with QQ Music's Sony decoder. Its libraries
    # are packaged from jni/ by Gradle and loaded at run time: lld rejects their symbol tables.
    file(TO_CMAKE_PATH "${KANADE_RA360_ANDROID_RUNTIME}" runtime)
    set(decoder "${runtime}/jni/arm64-v8a/libqm_native_decoder_360ra.so")
    set(common "${runtime}/jni/arm64-v8a/libaudio_common.so")
    set(parser "${runtime}/jni/arm64-v8a/libextra_mp4_parser.so")
    set(hrtf "${runtime}/com.sony.360ra.hrtf13.standard.hki")
    foreach(input decoder common parser hrtf)
        if(NOT EXISTS "${${input}}")
            message(FATAL_ERROR "Missing local 360 Reality Audio input ${${input}}")
        endif()
    endforeach()
    foreach(pair
            "decoder;0e182e84ff687b749711f9fa6b997a2697f0f32a4dad62783b7cd16407602fa1"
            "common;9373a1e59589a9423a854a86c89d8a719a6befbcbfd661ee20d76e32f53117ad"
            "parser;20b6caf1d90796f1199d4c2c837a8de91908970bdc541f262ad00d4e6efcb047"
            "hrtf;f065d16bdf1e3a67a7888f1f71830398cef2f77a58e4cd428f11f7085b287c64")
        list(GET pair 0 input)
        list(GET pair 1 expected)
        file(SHA256 "${${input}}" actual)
        if(NOT actual STREQUAL expected)
            message(FATAL_ERROR "Unsupported 360 Reality Audio file ${${input}}")
        endif()
    endforeach()
    file(SIZE "${hrtf}" hrtf_size)

    enable_language(ASM)
    configure_file(ra360_assets.S.in ra360_assets.S @ONLY)
    set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/ra360_assets.S" PROPERTY OBJECT_DEPENDS "${hrtf}")
    add_library(kanade_ra360 SHARED sony_decoder.cpp "${CMAKE_CURRENT_BINARY_DIR}/ra360_assets.S")
    target_compile_features(kanade_ra360 PRIVATE cxx_std_17)
    target_compile_options(kanade_ra360 PRIVATE -fno-exceptions -fno-rtti)
    target_compile_definitions(kanade_ra360 PRIVATE "KANADE_RA360_HRTF_SIZE=${hrtf_size}")
    target_link_libraries(kanade_ra360 PRIVATE dl)
endif()
