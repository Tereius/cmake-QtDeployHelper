# This script contains work of Laurent Gomila 

# Qt Android CMake utility script
# -------------------------------

# Copyright (c) 2018, Laurent Gomila (laurent.gom@gmail.com)
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# 1.  Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.

# 2.  Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.

# 3.  Neither the name of the copyright holder nor the names of its
#     contributors may be used to endorse or promote products derived from this
#     software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

cmake_minimum_required(VERSION 3.2)

# store the current source directory for future use
set(QT_ANDROID_SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR})

# make sure that the Android toolchain is used
if(NOT ANDROID)
    message(FATAL_ERROR "Trying to use the CMake Android package without the Android toolchain. Please use the provided toolchain (toolchain/android.toolchain.cmake)")
endif()

find_package(Java COMPONENTS Development REQUIRED)
if(Java_JAVA_EXECUTABLE)
    get_filename_component(JAVA_HOME_DIR "${Java_JAVA_EXECUTABLE}/../.." ABSOLUTE)
endif()

# find the Qt root directory
find_package(Qt5Core REQUIRED)
get_filename_component(QT_ANDROID_QT_ROOT "${Qt5Core_DIR}/../../.." ABSOLUTE)

find_program(ANDROID_DEPLOY_QT "androiddeployqt" PATHS "${QT_ANDROID_QT_ROOT}/bin")
if(ANDROID_DEPLOY_QT)
    message(STATUS "Found Qt for Android: ${QT_ANDROID_QT_ROOT}")
else()
    message(FATAL_ERROR "Missing 'androiddeployqt'. Is this Qt for android?")
endif()

# find the Android SDK
find_path(ANDROID_SDK_ROOT "tools/lib/android.el" PATHS "$ENV{ANDROID_SDK_ROOT}" "$ENV{ANDROID_SDK}")
if(ANDROID_SDK_ROOT)
    message(STATUS "Found Android SDK: ${ANDROID_SDK_ROOT}")
else()
    message(FATAL_ERROR "Missing ANDROID_SDK_ROOT root")
endif()
string(REPLACE "\\" "/" QT_ANDROID_SDK_ROOT ${ANDROID_SDK_ROOT}) # androiddeployqt doesn't like backslashes in paths

get_filename_component(NDK_HINT "${CMAKE_TOOLCHAIN_FILE}" DIRECTORY)

# find the Android NDK
find_path(ANDROID_NDK_ROOT "build/cmake/android.toolchain.cmake" PATHS "$ENV{ANDROID_NDK_ROOT}" "$ENV{ANDROID_NDK}" "${NDK_HINT}/../../")
if(ANDROID_NDK_ROOT)
    message(STATUS "Found Android NDK: ${ANDROID_NDK_ROOT}")
else()
    message(FATAL_ERROR "Missing ANDROID_NDK_ROOT root")
endif()
string(REPLACE "\\" "/" QT_ANDROID_NDK_ROOT ${ANDROID_NDK_ROOT}) # androiddeployqt doesn't like backslashes in paths

include(CMakeParseArguments)
include(QtDeployCommon)

# This function takes a cmake target and prepares it for deployment. The target has to be a shared library.
#
# androiddeployqt(<target>
#     [NAME <app-name>]
#     [PACKAGE <package-name>]
#     [PACKAGE_SOURCES <path>]
#     [STYLE_EXTRACTION [DEFAULT|FULL|MINIMAL|NONE]]
#     [QML_ROOT_PATH <path>]
#     [MIN_SDK_VERSION <int>]
#     [TARGET_SDK_VERSION <int>]
#     [VERSION_CODE <int> [VERSION_STRING <string>]]
#     [KEYSTORE <keystore path> <keystore alias>]
#     [KEYSTORE_PASSWORD <keystore pwd>]
#     [DEPENDS <path> | <target> ...]
#)
#
# NAME: The name of your app. Defaults to target name.
# PACKAGE: The package in reverse domain name notation (e.g. "org.mydomain.awesomeapp"). Defaults to "org.qtproject.${NAME}".
# PACKAGE_SOURCES: You may want to specify a directory where all android specific files are located (like AndroidManifest.xml, apptheme.xml, ..). As a minimum you have to provide your own valid 
#   AndroidManifest.xml. If the manifest contains the Qt specific placeholders (like "-- %%INSERT_LOCAL_LIBS%% --", "- %%INSERT_INIT_CLASSES%% --") these will be automatically replaced by androiddeployqt.
#   Use the AndroidManifest.xml in you Qt install folder as a basis for your custom manifest (<QT_HOME>/src/android/templates).
# STYLE_EXTRACTION: Use FULL for QWidget & Quick Controls 1 apps, MINIMAL for Quick Controls 2 apps (it is much faster than "FULL"), NONE for everything else.
#   There is a fourth option DEFAULT - In most cases this will be the same as "FULL", but it can also be something else if needed, e.g., for compatibility reasons. Defaults to MINIMAL if QML_ROOT_PATH is given DEFAULT otherwise.
# QML_ROOT_PATH: If you want to deploy a QML application you sould provide the root directory where the qml files are located. The files will we searched for dependencies which will then be included in the apk.
# MIN_SDK_VERSION: Provide a specific min sdk version. Defaults to autodetection or 21 if detection fails.
# TARGET_SDK_VERSION: Provide a specific target sdk version. Defaults to 28.
# VERSION_CODE: Provide a version code [0, 2100000000]. By default derived from PROJECT_VERSION and CMAKE_ANDROID_ARCH_ABI. If PROJECT_VERSION is missing the version will be in the range of [0, 9].
#   If both (PROJECT_VERSION and CMAKE_ANDROID_ARCH_ABI) are missing it will default to 0. Allowed ranges: PROJECT_VERSION_MAJOR [0, 2099], PROJECT_VERSION_MINOR [0, 99],  PROJECT_VERSION_PATCH [0, 99], PROJECT_VERSION_TWEAK [0, 9]
#   If you plan to deploy multiple apks targeting DIFFERENT abi's the version code has to be different between those apks.
# VERSION_STRING: Provide a version name. By default derived from VERSION_CODE.
# KEYSTORE: If you want to sign the apk you have to provide a keystore file (like .jks) and the alias like: /path/mykey.jks myalias
# KEYSTORE_PASSWORD: A password for your keystore
# DEPENDS: libraries (besides Qt) that should be deployed too. Either provide a valid target or the absolute path of the library.
#
# This function will introducte some new handy targets:
# apk: Creates an apk
# apk-install: Creates and installs an apk on the connected android device
# apk-run: Creates and installs and starts an apk on the connected android device
# apk-debug: Creates and installs and attatches a debugger on the connected android device
# install-private: Is called by the default cmake install target. This will copy the apk to the CMAKE_INSTALL_PREFIX

function(androiddeployqt TARGET)

    if(TARGET ${TARGET})
        get_target_property(target_type ${TARGET} TYPE)
        if (NOT target_type STREQUAL "SHARED_LIBRARY")
            message(FATAL_ERROR "The given target is not a shared library. Please use 'add_library(<name> SHARED [...]' for the given target.")
        endif()
    else()
        message(FATAL_ERROR "Missing a valid target")
    endif()

    # apply ARG_ prefix because of conformity with other arguments
    set(ARG_TARGET ${TARGET})

    # parse the arguments
    cmake_parse_arguments(ARG "" "NAME;PACKAGE;PACKAGE_SOURCES;STYLE_EXTRACTION;KEYSTORE_PASSWORD;QML_ROOT_PATH;VERSION_CODE;VERSION_STRING;MIN_SDK_VERSION;TARGET_SDK_VERSION" "DEPENDS;KEYSTORE" ${ARGN})

    # generate a default version code by reading the project version (if set)
    if(NOT ARG_VERSION_CODE)

        set(ARG_VERSION_CODE "0")

        if(DEFINED PROJECT_VERSION_MAJOR AND NOT PROJECT_VERSION_MAJOR STREQUAL "")
            if(PROJECT_VERSION_MAJOR LESS "2100" AND PROJECT_VERSION_MAJOR GREATER "-1")
                math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + ${PROJECT_VERSION_MAJOR} * 1000000")
            else()
                message(FATAL_ERROR "PROJECT_VERSION_MAJOR exceeding the allowed range of [0, 2099]")
            endif()
        endif()
        if(DEFINED PROJECT_VERSION_MINOR AND NOT PROJECT_VERSION_MINOR STREQUAL "")
            if(PROJECT_VERSION_MINOR LESS "100" AND PROJECT_VERSION_MINOR GREATER "-1")
                math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + ${PROJECT_VERSION_MINOR} * 10000")
            else()
                message(FATAL_ERROR "PROJECT_VERSION_MINOR exceeding the allowed range of [0, 99]")
            endif()
        endif()
        if(DEFINED PROJECT_VERSION_PATCH AND NOT PROJECT_VERSION_PATCH STREQUAL "")
            if(PROJECT_VERSION_PATCH LESS "100" AND PROJECT_VERSION_PATCH GREATER "-1")
                math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + ${PROJECT_VERSION_PATCH} * 100")
            else()
                message(FATAL_ERROR "PROJECT_VERSION_PATCH exceeding the allowed range of [0, 99]")
            endif()
        endif()
        if(DEFINED PROJECT_VERSION_TWEAK AND NOT PROJECT_VERSION_TWEAK STREQUAL "")
            if(PROJECT_VERSION_TWEAK LESS "10" AND PROJECT_VERSION_TWEAK GREATER "-1")
                math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + ${PROJECT_VERSION_TWEAK} * 10")
            else()
                message(FATAL_ERROR "PROJECT_VERSION_TWEAK exceeding the allowed range of [0, 9]")
            endif()
        endif()
        if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 1")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a" AND NOT CMAKE_ANDROID_ARM_NEON)
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 2")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a" AND CMAKE_ANDROID_ARM_NEON)
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 3")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v6")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 4")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 5")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "mips")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 6")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "mips64")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 7")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 8")
        elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
            math(EXPR ARG_VERSION_CODE "${ARG_VERSION_CODE} + 9")
        else()
            message(WARNING "Couldn't read valid CMAKE_ANDROID_ARCH_ABI. The VERSION_CODE won't be distinguishable between different abi's")
        endif()
    endif()

    if(NOT ARG_MIN_SDK_VERSION)
        set(ARG_MIN_SDK_VERSION 21)

        if(DEFINED ANDROID_PLATFORM_LEVEL)
            set(QT_ANDROID_API_LVL ${ANDROID_PLATFORM_LEVEL})
        elseif(DEFINED ANDROID_PLATFORM)
            string(SUBSTRING ${ANDROID_PLATFORM} 8 -1 QT_ANDROID_API_LVL)
        elseif(DEFINED CMAKE_SYSTEM_VERSION)
            set(QT_ANDROID_API_LVL ${CMAKE_SYSTEM_VERSION})
        endif()

        if(QT_ANDROID_API_LVL GREATER 0)
            set(ARG_MIN_SDK_VERSION ${QT_ANDROID_API_LVL})
        else()
            message(STATUS "Using a default minSdkVersion of ${ARG_MIN_SDK_VERSION}")
        endif()
    endif()

    if(NOT ARG_TARGET_SDK_VERSION)
        set(ARG_TARGET_SDK_VERSION 28)
        message(STATUS "Using a default targetSdkVersion of ${ARG_TARGET_SDK_VERSION}")
    endif()

    if(NOT ARG_VERSION_CODE MATCHES "^[0-9]+$")
        message(FATAL_ERROR "The given VERSION_CODE '${ARG_VERSION_CODE}' is not a valid number")
    endif()

    if(ARG_VERSION_CODE LESS "0" OR ARG_VERSION_CODE GREATER "2100000000")
        message(FATAL_ERROR "The given VERSION_CODE '${ARG_VERSION_CODE}' is not in the valid range [0, 2100000000]")
    endif()

    # generate a default version name by reading the project version (if set). Otherwise use the VERSION_CODE as VERSION_STRING
    if(NOT ARG_VERSION_NAME)
        set(ARG_VERSION_NAME ${ARG_VERSION_CODE})
        if(DEFINED PROJECT_VERSION AND NOT PROJECT_VERSION STREQUAL "")
            set(ARG_VERSION_NAME ${PROJECT_VERSION})
        endif()
    endif()

    # define the application name
    if(NOT ARG_NAME)
        message(STATUS "Generating a NAME from the target")
        set(ARG_NAME ${ARG_TARGET})
    endif()

    # define the application package name
    if(NOT ARG_PACKAGE)
        message(STATUS "Generating a PACKAGE from the target")
        set(ARG_PACKAGE "org.qtproject.${ARG_NAME}")
    endif()
    
    if(ARG_QML_ROOT_PATH)
        message(STATUS "Deploying a QML application from ${ARG_QML_ROOT_PATH}")
        set(QT_ANDROID_QML_ROOT_PATH "${ARG_QML_ROOT_PATH}")
    endif()
    
    # detect style extraction method
    if(NOT ARG_STYLE_EXTRACTION)
        set(ARG_STYLE_EXTRACTION default)
        if(ARG_QML_ROOT_PATH)
            set(ARG_STYLE_EXTRACTION minimal)
        endif()
    else()
        string(TOLOWER ${ARG_STYLE_EXTRACTION} ARG_STYLE_EXTRACTION)
    endif()
    
    if(NOT(ARG_STYLE_EXTRACTION STREQUAL minimal OR ARG_STYLE_EXTRACTION STREQUAL full OR ARG_STYLE_EXTRACTION STREQUAL none OR ARG_STYLE_EXTRACTION STREQUAL default))
        message(FATAL_ERROR "Invalid value provided for option STYLE_EXTRACTION")
    endif()
    
    message(STATUS "Using style extraction method: ${ARG_STYLE_EXTRACTION}")

    # detect latest Android SDK build-tools revision
    set(QT_ANDROID_SDK_BUILDTOOLS_REVISION "0.0.0")
    file(GLOB ALL_BUILD_TOOLS_VERSIONS RELATIVE ${ANDROID_SDK_ROOT}/build-tools ${ANDROID_SDK_ROOT}/build-tools/*)
    foreach(BUILD_TOOLS_VERSION ${ALL_BUILD_TOOLS_VERSIONS})
        # find subfolder with greatest version
        if(${BUILD_TOOLS_VERSION} VERSION_GREATER ${QT_ANDROID_SDK_BUILDTOOLS_REVISION})
            set(QT_ANDROID_SDK_BUILDTOOLS_REVISION ${BUILD_TOOLS_VERSION})
        endif()
    endforeach()

    if(QT_ANDROID_SDK_BUILDTOOLS_REVISION VERSION_GREATER "0.0.0")
        message(STATUS "Detected Android SDK build tools version ${QT_ANDROID_SDK_BUILDTOOLS_REVISION}")
    else()
        message(FATAL_ERROR "Couldn't detect SDK build tools version")
    endif()

    # define the STL shared library path
    if(ANDROID_STL_SHARED_LIBRARIES)
        list(GET ANDROID_STL_SHARED_LIBRARIES 0 STL_LIBRARY_NAME) # we can only give one to androiddeployqt
        if(ANDROID_STL_PATH)
            set(QT_ANDROID_STL_PATH "${ANDROID_STL_PATH}/libs/${ANDROID_ABI}/lib${STL_LIBRARY_NAME}.so")
        else()
            set(QT_ANDROID_STL_PATH "${ANDROID_NDK_ROOT}/sources/cxx-stl/${ANDROID_STL_PREFIX}/libs/${ANDROID_ABI}/lib${STL_LIBRARY_NAME}.so")
        endif()
        message(STATUS "STL in use ${QT_ANDROID_STL_PATH}")
    else()
        message(FATAL_ERROR "Couldn't find a STL")
    endif()

    message(STATUS "The apk manifest will contain following values:")
    message(STATUS "    abi: ${CMAKE_ANDROID_ARCH_ABI}")
    message(STATUS "    name: ${ARG_NAME}")
    message(STATUS "    package: ${ARG_PACKAGE}")
    message(STATUS "    versionCode: ${ARG_VERSION_CODE}")
    message(STATUS "    versionName: ${ARG_VERSION_NAME}")
    message(STATUS "    minSdkVersion: ${ARG_MIN_SDK_VERSION}")
    message(STATUS "    targetSdkVersion: ${ARG_TARGET_SDK_VERSION}")

    set(QT_ANDROID_APP_NAME ${ARG_NAME})
    set(QT_ANDROID_APP_PACKAGE_NAME ${ARG_PACKAGE})

    # define the application source package directory
    if(ARG_PACKAGE_SOURCES)
        message(STATUS "You specified 'PACKAGE_SOURCES'. You have to provide your own manifest")
        set(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT "${ARG_PACKAGE_SOURCES}")
    else()
        # create a subdirectory for the extra package sources
        set(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/package")

        file(READ "${QT_ANDROID_QT_ROOT}/src/android/templates/AndroidManifest.xml" CONTENT)
        string(REGEX MATCH "android:configChanges=\"([^\"]*)\"" MATCH ${CONTENT})

        if(MATCH)
            set(QT_ANDROID_APP_CONFIG_CHANGES ${CMAKE_MATCH_1})

            if(ARG_MIN_SDK_VERSION LESS 24)
                message(STATUS "Removing value 'density' from manifest 'configChange' (only supported by API level >= 24)")
                string(REPLACE "|density" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "density|" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "density" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
            elseif(ARG_MIN_SDK_VERSION LESS 17)
                message(STATUS "Removing value 'layoutDirection' from manifest 'configChange' (only supported by API level >= 17)")
                string(REPLACE "|layoutDirection" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "layoutDirection|" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "layoutDirection" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
            elseif(ARG_MIN_SDK_VERSION LESS 13)
                message(STATUS "Removing value 'screenSize', 'smallestScreenSize' from manifest 'configChange' (only supported by API level >= 13)")
                string(REPLACE "|screenSize" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "screenSize|" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "screenSize" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "|smallestScreenSize" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "smallestScreenSize|" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "smallestScreenSize" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
            elseif(ARG_MIN_SDK_VERSION LESS 8)
                message(STATUS "Removing value 'uiMode' from manifest 'configChange' (only supported by API level >= 8)")
                string(REPLACE "|uiMode" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "uiMode|" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
                string(REPLACE "uiMode" "" QT_ANDROID_APP_CONFIG_CHANGES ${QT_ANDROID_APP_CONFIG_CHANGES})
            endif()
        endif()

        # copy the Qt provided manifest and modify it
        #copy_replace_in_file("${QT_ANDROID_QT_ROOT}/src/android/templates/AndroidManifest.xml" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "package=\"org.qtproject.example\"" REPLACE "package=\"@ARG_PACKAGE@\"")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "-- %%INSERT_VERSION_NAME%% --" REPLACE "@ARG_VERSION_NAME@")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "-- %%INSERT_VERSION_CODE%% --" REPLACE "@ARG_VERSION_CODE@")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "-- %%INSERT_APP_NAME%% --" REPLACE "@ARG_NAME@")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "android:minSdkVersion=\"16\"" REPLACE "android:minSdkVersion=\"@ARG_MIN_SDK_VERSION@\"")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "android:targetSdkVersion=\"28\"" REPLACE "android:targetSdkVersion=\"@ARG_TARGET_SDK_VERSION@\"")

        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "<!-- meta-data android:name=\"android.app.splash_screen_drawable\" android:resource=\"@drawable/logo\"/ -->" REPLACE "<meta-data android:name=\"android.app.splash_screen_drawable\" android:resource=\"@drawable/splash\" />")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "android:launchMode=\"singleTop\">" REPLACE "android:theme=\"@style/AppTheme\"\nandroid:launchMode=\"singleTop\">")
        #replace_in_file("${CMAKE_CURRENT_BINARY_DIR}/AndroidManifest.xml.in" MATCH "<meta-data android:name=\"android.app.extract_android_style\" android:value=\"default\"/>" REPLACE "<meta-data android:name=\"android.app.extract_android_style\" android:value=\"${ARG_STYLE_EXTRACTION}\"/>")
        file(COPY "${QT_ANDROID_SOURCE_DIR}/res" DESTINATION "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/")
        #file(COPY "${QT_ANDROID_SOURCE_DIR}/logo.png" DESTINATION "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/res/drawable")
        #file(COPY "${QT_ANDROID_SOURCE_DIR}/splash.xml" DESTINATION "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/res/drawable")
        #file(COPY "${QT_ANDROID_SOURCE_DIR}/apptheme.xml" DESTINATION "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/res/values")
        #file(COPY "${QT_ANDROID_SOURCE_DIR}/colors.xml" DESTINATION "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/res/values")

        # generate a manifest from the qt template
        configure_file("${QT_ANDROID_SOURCE_DIR}/AndroidManifest.xml.in" "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml" @ONLY)
        #configure_file("${QT_ANDROID_SOURCE_DIR}/AndroidManifest.xml.in" "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml" @ONLY)
    endif()
    
    # set the list of dependant libraries
    if(ARG_DEPENDS)
        foreach(LIB ${ARG_DEPENDS})
            if(TARGET ${LIB})
                # item is a CMake target, extract the library path
                if(CMAKE_BUILD_TYPE STREQUAL "Debug")
                    get_property(LIB_PATH TARGET ${LIB} PROPERTY DEBUG_LOCATION)
                else()
                    get_property(LIB_PATH TARGET ${LIB} PROPERTY LOCATION)
                endif()
                set(LIB ${LIB_PATH})
            endif()
        if(EXTRA_LIBS)
            set(EXTRA_LIBS "${EXTRA_LIBS},${LIB}")
        else()
            set(EXTRA_LIBS "${LIB}")
        endif()
        endforeach()
        set(QT_ANDROID_APP_EXTRA_LIBS "\"android-extra-libs\": \"${EXTRA_LIBS}\",")
    endif()

    # set some toolchain variables used by androiddeployqt;
    # unfortunately, Qt tries to build paths from these variables although these full paths
    # are already available in the toochain file, so we have to parse them
    string(REGEX MATCH "${ANDROID_NDK_ROOT}/toolchains/(.*)-(.*)/prebuilt/.*" ANDROID_TOOLCHAIN_PARSED ${ANDROID_TOOLCHAIN_ROOT})
    if(ANDROID_TOOLCHAIN_PARSED)
        set(QT_ANDROID_TOOLCHAIN_PREFIX ${CMAKE_MATCH_1})
        set(QT_ANDROID_TOOLCHAIN_VERSION ${CMAKE_MATCH_2})
    else()
        message(FATAL_ERROR "Failed to parse ANDROID_TOOLCHAIN_ROOT to get toolchain prefix and version")
    endif()

    # make sure that the output directory for the Android package exists
    file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI})

    # create the configuration file that will feed androiddeployqt
    configure_file_gen_expr(${QT_ANDROID_SOURCE_DIR}/qtdeploy.json.in ${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json @ONLY)

    # check if the apk must be signed
    if(ARG_KEYSTORE)
        if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
            message(STATUS "Apk will be signed with the provided certificate")
            set(SIGN_OPTIONS --release --sign ${ARG_KEYSTORE} --tsa http://timestamp.digicert.com)
            if(ARG_KEYSTORE_PASSWORD)
                set(SIGN_OPTIONS ${SIGN_OPTIONS} --storepass ${ARG_KEYSTORE_PASSWORD})
            endif()
        else()
            message(WARNING "Apk will be signed with a debug certificate even though you provided a keystore file. Switch to a release build to use the provided certificate")
        endif()
    else()
        message(STATUS "Apk will be signed with a debug certificate")
    endif()

    # specify the Android API level
    if(QT_ANDROID_API_LVL GREATER 0)
        set(TARGET_LEVEL_OPTIONS --android-platform android-${QT_ANDROID_API_LVL})
    else()
        message(WARNING "Couldn't determine android platform version. Will use the highest available version")
    endif()

    # create a custom command that will run the androiddeployqt utility to generate the APK
    add_custom_target(
        apk
        DEPENDS ${ARG_TARGET}
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI} # it seems that recompiled libraries are not copied if we don't remove them first
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}
        COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${ARG_TARGET}> ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}
        COMMAND ${ANDROID_DEPLOY_QT} $<$<BOOL:${CMAKE_VERBOSE_MAKEFILE}>:--verbose> --output ${CMAKE_CURRENT_BINARY_DIR} --input ${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json $<$<CONFIG:Debug>:--no-strip> $<$<CONFIG:RelWithDebInfo>:--no-strip> $<$<CONFIG:Release>:--release> $<$<CONFIG:RelWithDebInfo>:--release> $<$<CONFIG:MinSizeRel>:--release> --no-generated-assets-cache --jdk ${JAVA_HOME_DIR} --gradle ${TARGET_LEVEL_OPTIONS} ${SIGN_OPTIONS}
    )
    
    # create a custom command that will install the APK on a connected android device
    add_custom_target(
        apk-install
        DEPENDS apk
        COMMAND ${ANDROID_DEPLOY_QT} $<$<BOOL:${CMAKE_VERBOSE_MAKEFILE}>:--verbose> --no-build --reinstall --output ${CMAKE_CURRENT_BINARY_DIR} --input ${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json $<$<CONFIG:Debug>:--no-strip> $<$<CONFIG:RelWithDebInfo>:--no-strip> $<$<CONFIG:Release>:--release> $<$<CONFIG:RelWithDebInfo>:--release> $<$<CONFIG:MinSizeRel>:--release> --no-generated-assets-cache --jdk ${JAVA_HOME_DIR} --gradle ${TARGET_LEVEL_OPTIONS} ${SIGN_OPTIONS}
    )

    # create a custom command that will start activity on a connected android device
    add_custom_target(
        apk-run
        DEPENDS apk-install
        COMMAND ${ANDROID_SDK_ROOT}/platform-tools/adb shell am start -n ${ARG_PACKAGE}/org.qtproject.qt5.android.bindings.QtActivity
    )
    
    # create a custom command that will start debugging session activity on a connected android device
    add_custom_target(
        apk-debug
        DEPENDS apk-install
        #COMMAND ${ANDROID_NDK_ROOT}/ndk-gdb --adb ${ANDROID_SDK_ROOT}/platform-tools/adb --project ${CMAKE_CURRENT_BINARY_DIR} --launch-list
        COMMAND ${ANDROID_NDK_ROOT}/ndk-gdb --adb ${ANDROID_SDK_ROOT}/platform-tools/adb --project ${CMAKE_CURRENT_BINARY_DIR} --launch --verbose
    )
    
    add_custom_target(
        install-private
        DEPENDS apk
        COMMAND "${CMAKE_COMMAND}" -E copy_directory "${CMAKE_CURRENT_BINARY_DIR}/build/outputs/apk/$<$<CONFIG:Debug>:debug>$<$<NOT:$<CONFIG:Debug>>:release>" "${CMAKE_INSTALL_PREFIX}"
    )
    
    install(CODE "execute_process(COMMAND \"${CMAKE_COMMAND}\" --build \"${CMAKE_BUILD_DIRECTORY}\" --target install-private)")
    
    #set(GDB_SOLIB_PATH ${CMAKE_CURRENT_BINARY_DIR}/obj/local/${ANDROID_NDK_ABI_NAME}/)
    
    # 1. generate essential Android Makefiles
    #file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/jni/Android.mk "APP_ABI := ${ANDROID_ABI}\n")
    #file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/jni/Application.mk "APP_ABI := ${ANDROID_ABI}\n")

    # 2. generate gdb.setup
    #get_directory_property(PROJECT_INCLUDES DIRECTORY ${PROJECT_SOURCE_DIR} INCLUDE_DIRECTORIES)
    #message(STATUS "--------------${PROJECT_INCLUDES}")
    #string(REGEX REPLACE ";" " " PROJECT_INCLUDES "${PROJECT_INCLUDES}")
    #file(WRITE  ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_NDK_ABI_NAME}/gdb.setup "set solib-search-path ./libs/${ANDROID_NDK_ABI_NAME}\n")
    #file(APPEND ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_NDK_ABI_NAME}/gdb.setup "directory ${PROJECT_INCLUDES}\n")

    # 3. copy gdbserver executable
    #file(COPY ${ANDROID_NDK_ROOT}/prebuilt/android-arm/gdbserver/gdbserver DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_NDK_ABI_NAME}/)
    
    #file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/nop.sh "#!/bin/bash")
    
    #file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/start_app.sh "#!/bin/bash\n${ANDROID_NDK_ROOT}/ndk-gdb --adb ${ANDROID_SDK_ROOT}/platform-tools/adb --project ${CMAKE_CURRENT_BINARY_DIR} --launch --verbose --nowait --delay 10.0")
    
    #file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/attach_app.sh "#!/bin/bash\n${ANDROID_NDK_ROOT}/ndk-gdb --adb ${ANDROID_SDK_ROOT}/platform-tools/adb --project ${CMAKE_CURRENT_BINARY_DIR} --verbose")

endfunction(androiddeployqt)

# Creates an Android package in the build directory <destination> and
# builds it into an .apk file.

# Optional arguments:
#   --input <inputfile>: Reads <inputfile> for options generated by
#      qmake. A default file name based on the current working
#      directory will be used if nothing else is specified.
#   --deployment <mechanism>: Supported deployment mechanisms:
#      bundled (default): Include Qt files in stand-alone package.
#      ministro: Use the Ministro service to manage Qt files.
#   --no-build: Do not build the package, it is useful to just install
#      a package previously built.
#   --install: Installs apk to device/emulator. By default this step is
#      not taken. If the application has previously been installed on
#      the device, it will be uninstalled first.
#   --reinstall: Installs apk to device/emulator. By default this step
#      is not taken. If the application has previously been installed on
#      the device, it will be overwritten, but its data will be left
#      intact.
#   --device [device ID]: Use specified device for deployment. Default
#      is the device selected by default by adb.
#   --android-platform <platform>: Builds against the given android
#      platform. By default, the highest available version will be
#      used.
#   --gradle. Use gradle instead of ant to create and install the apk.
#   --ant <path/to/ant>: If unspecified, ant from the PATH will be
#      used.
#   --release: Builds a package ready for release. By default, the
#      package will be signed with a debug key.
#   --sign <url/to/keystore> <alias>: Signs the package with the
#      specified keystore, alias and store password. Also implies the
#      --release option.
#      Optional arguments for use with signing:
#        --storepass <password>: Keystore password.
#        --storetype <type>: Keystore type.
#        --keypass <password>: Password for private key (if different
#          from keystore password.)
#        --sigfile <file>: Name of .SF/.DSA file.
#        --digestalg <name>: Name of digest algorithm. Default is
#          "SHA1".
#        --sigalg <name>: Name of signature algorithm. Default is
#          "SHA1withRSA".
#        --tsa <url>: Location of the Time Stamping Authority.
#        --tsacert <alias>: Public key certificate for TSA.
#        --internalsf: Include the .SF file inside the signature block.
#        --sectionsonly: Don't compute hash of entire manifest.
#        --protected: Keystore has protected authentication path.
#        --jarsigner: Force jarsigner usage, otherwise apksigner will be
#          used if available.
#   --gdbserver: Adds the gdbserver to the package. By default the gdbserver
#      is bundled for debug pacakges.
#   --no-gdbserver: Prevents the gdbserver from being added to the package
#      By default the gdbserver is bundled for debug pacakges.
#   --jdk <path/to/jdk>: Used to find the jarsigner tool when used
#      in combination with the --release argument. By default,
#      an attempt is made to detect the tool using the JAVA_HOME and
#      PATH environment variables, in that order.
#   --qml-import-paths: Specify additional search paths for QML
#      imports.
#   --verbose: Prints out information during processing.
#   --no-generated-assets-cache: Do not pregenerate the entry list for
#      the assets file engine.
#   --aux-mode: Operate in auxiliary mode. This will only copy the
#      dependencies into the build directory and update the XML templates.
#      The project will not be built or installed.
#   --no-strip: Do not strip debug symbols from libraries.
#   --help: Displays this information.
