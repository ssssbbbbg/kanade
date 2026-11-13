cmake_minimum_required(VERSION 3.22.1)
project(kanade_android_audio LANGUAGES CXX ASM)

if(KANADE_NAC_MODEL)
    add_subdirectory(../nac nac)
endif()

if(KANADE_DTS_ANDROID_RUNTIME)
    add_subdirectory(../dts dts)
endif()

if(KANADE_RA360_ANDROID_RUNTIME)
    add_subdirectory(../ra360 ra360)
endif()
