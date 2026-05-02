cmake_minimum_required(VERSION 3.15)
project(PercApps NONE)

include(ExternalProject)

set(BUILD_TYPE    "Release" CACHE STRING "Build type (Debug/Release)")
set(PARALLEL_JOBS 6        CACHE STRING "Number of parallel build jobs")
set(LOG_DIR ${CMAKE_CURRENT_BINARY_DIR}/logs)

set(STRIP_SSP "/opt/homebrew/bin/arm-linux-gnueabihf-strip" CACHE FILEPATH "SSP strip utility")
set(STRIP_XMX "/opt/homebrew/bin/aarch64-elf-strip"         CACHE FILEPATH "XMX strip utility")

# ── cmake-based subprojects (PercCmd / Plugins / TraxHost) ───────────────────
# Individual targets: PercCmd_SSP, Plugins_XMX, TraxHost_SSP, …
# Build one with:  cmake --build build --target PercCmd_SSP

function(add_subproject NAME PLATFORM TOOLCHAIN)
    set(BUILD_LOG ${LOG_DIR}/${NAME}_${PLATFORM}-build-out.log)

    ExternalProject_Add(
        ${NAME}_${PLATFORM}
        SOURCE_DIR  ${CMAKE_CURRENT_SOURCE_DIR}/external/${NAME}
        BINARY_DIR  ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_${PLATFORM}
        LOG_DIR     ${LOG_DIR}
        CMAKE_ARGS
            -DCMAKE_TOOLCHAIN_FILE=${CMAKE_CURRENT_SOURCE_DIR}/external/${NAME}/${TOOLCHAIN}
            -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
        BUILD_COMMAND
            ${CMAKE_COMMAND} --build . --parallel ${PARALLEL_JOBS}
        INSTALL_COMMAND ""
        LOG_CONFIGURE ON
        LOG_BUILD     ON
    )

    # Announce the log file path before the build step runs.
    # ALWAYS ON ensures the message appears on every build invocation.
    # USES_TERMINAL ON writes to the terminal even though LOG_BUILD is ON.
    ExternalProject_Add_Step(${NAME}_${PLATFORM} build_announce
        COMMENT "Performing build step for '${NAME}_${PLATFORM}' => log: ${BUILD_LOG}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for '${NAME}_${PLATFORM}' => log: ${BUILD_LOG}"
        USES_TERMINAL ON
        ALWAYS ON
        DEPENDEES configure
        DEPENDERS build
    )
endfunction()

# SSP
add_subproject(PercCmd  SSP xcSSP.cmake)
add_subproject(Plugins  SSP xcSSP.cmake)
add_subproject(TraxHost SSP xcSSP.cmake)
ExternalProject_Add_StepDependencies(TraxHost_SSP build PercCmd_SSP Plugins_SSP)

# XMX
add_subproject(PercCmd  XMX xcXMX.cmake)
add_subproject(Plugins  XMX xcXMX.cmake)
add_subproject(TraxHost XMX xcXMX.cmake)
ExternalProject_Add_StepDependencies(TraxHost_XMX build PercCmd_XMX Plugins_XMX)

# ── er-301 (Makefile-based, 3 sequential steps per platform) ─────────────────
# Individual targets per step so a failed step can be retried in isolation:
#   er301_fftw_SSP / er301_percussa_SSP / er301_core_SSP / er301_SSP  (and XMX)
# Retry a step:  cmake --build build --target er301_percussa_SSP

set(ER301_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/er-301)

# Fetch tags at configure time so git describe always has version info.
execute_process(
    COMMAND git fetch --tags
    WORKING_DIRECTORY ${ER301_DIR}
    RESULT_VARIABLE _git_fetch_result
    ERROR_QUIET
)
if(NOT _git_fetch_result EQUAL 0)
    message(WARNING "er-301: git fetch --tags failed (offline build?)")
endif()

execute_process(
    COMMAND git describe --match "v*.*.*-*" --tags --abbrev=0
    WORKING_DIRECTORY ${ER301_DIR}
    OUTPUT_VARIABLE ER301_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(ER301_VERSION STREQUAL "")
    message(WARNING "er-301: no matching git tag found, FIRMWARE_VERSION will be empty")
else()
    message(STATUS "er-301: version ${ER301_VERSION}")
endif()

foreach(PLATFORM IN ITEMS SSP XMX)
    string(TOLOWER ${PLATFORM} PL)

    set(ER301_BUILD_DIR  ${CMAKE_CURRENT_BINARY_DIR}/er301_${PLATFORM})
    set(FFTW_STAGE_DIR   ${ER301_BUILD_DIR}/fftw-stage)   # DESTDIR for fftw install
    set(FFTW_STAGE_ROOT  ${FFTW_STAGE_DIR}/usr)           # what percussa.mk expects
    set(FFTW_BUILD_DIR   ${ER301_BUILD_DIR}/fftw-build)   # fftw configure/compile tree

    # Step 1 — cross-build FFTW dependency (all output stays in cmake build tree)
    add_custom_target(er301_fftw_${PLATFORM}
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for 'er301_fftw_${PLATFORM}' => output to terminal"
        COMMAND ${CMAKE_COMMAND} -E env
                TOOLCHAIN_FLAVOR=${PL}
                DESTDIR=${FFTW_STAGE_DIR}
                BUILD_DIR=${FFTW_BUILD_DIR}
                bash ${ER301_DIR}/scripts/build-fftw-cross.sh
        WORKING_DIRECTORY ${ER301_DIR}
        COMMENT "er-301 [${PLATFORM}]: building FFTW dependency"
        VERBATIM
    )

    # Step 2 — make percussa (build_dir redirects output into cmake build tree)
    add_custom_target(er301_percussa_${PLATFORM}
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for 'er301_percussa_${PLATFORM}' => output to terminal"
        COMMAND ${CMAKE_MAKE_PROGRAM} -j${PARALLEL_JOBS} percussa
                TOOLCHAIN_FILE=scripts/toolchains/${PL}.mk
                build_dir=${ER301_BUILD_DIR}
                FFTW_STAGE_ROOT=${FFTW_STAGE_ROOT}
                FIRMWARE_VERSION=${ER301_VERSION}
        WORKING_DIRECTORY ${ER301_DIR}
        DEPENDS er301_fftw_${PLATFORM}
        COMMENT "er-301 [${PLATFORM}]: make percussa"
        VERBATIM
    )

    # Step 3 — make core
    add_custom_target(er301_core_${PLATFORM}
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for 'er301_core_${PLATFORM}' => output to terminal"
        COMMAND ${CMAKE_MAKE_PROGRAM} -j${PARALLEL_JOBS} core
                TOOLCHAIN_FILE=scripts/toolchains/${PL}.mk
                build_dir=${ER301_BUILD_DIR}
        WORKING_DIRECTORY ${ER301_DIR}
        DEPENDS er301_percussa_${PLATFORM}
        COMMENT "er-301 [${PLATFORM}]: make core"
        VERBATIM
    )

    # Platform rollup — ALL ensures these are included in the default cmake --build
    add_custom_target(er301_${PLATFORM} ALL DEPENDS er301_core_${PLATFORM})
endforeach()

# ── Top-level convenience targets ────────────────────────────────────────────
# cmake --build build --target ssp   (all four subprojects, SSP only)
# cmake --build build --target xmx   (all four subprojects, XMX only)
# cmake --build build                (everything)

add_custom_target(ssp DEPENDS PercCmd_SSP Plugins_SSP TraxHost_SSP er301_SSP)
add_custom_target(xmx DEPENDS PercCmd_XMX Plugins_XMX TraxHost_XMX er301_XMX)

# ── Image collection ──────────────────────────────────────────────────────────
# Gathers all artifacts for a platform into build/image/<platform>/:
#
#   PercCmd               — launcher executable
#   TraxHost              — plugin host executable
#   librtaudio.so         — audio library required by TraxHost
#   percussa-<pl>.elf     — er-301 Percussa port
#   plugins/*.so          — all plugin shared objects (flattened)
#
# Build with:  cmake --build build --target image_SSP
#              cmake --build build --target image_XMX

set(IMAGE_DIR ${CMAKE_CURRENT_BINARY_DIR}/image)

foreach(PLATFORM IN ITEMS SSP XMX)
    string(TOLOWER ${PLATFORM} PL)
    set(ROOT ${IMAGE_DIR}/${PL})
    set(ER301_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR}/er301_${PLATFORM})

    # Architecture label used by er-301 for its mod package subdirectory.
    # Derived from the first word of the toolchain TRIPLE:
    #   SSP: arm-linux-gnueabihf  → arm
    #   XMX: aarch64-rockchip-linux-gnu → aarch64
    if(PLATFORM STREQUAL "SSP")
        set(ER301_ARCH arm)
    else()
        set(ER301_ARCH aarch64)
    endif()

    add_custom_target(image_${PLATFORM}
        DEPENDS PercCmd_${PLATFORM} TraxHost_${PLATFORM} Plugins_${PLATFORM} er301_${PLATFORM}

        COMMAND ${CMAKE_COMMAND} -E make_directory ${ROOT}/plugins
        COMMAND ${CMAKE_COMMAND} -E make_directory ${ROOT}/er301/rear

        # PercCmd
        COMMAND ${CMAKE_COMMAND} -E copy
            ${CMAKE_CURRENT_BINARY_DIR}/PercCmd_${PLATFORM}/PercCmd
            ${ROOT}/PercCmd

        # TraxHost + audio library
        COMMAND ${CMAKE_COMMAND} -E copy
            ${CMAKE_CURRENT_BINARY_DIR}/TraxHost_${PLATFORM}/TraxHost
            ${ROOT}/TraxHost
        COMMAND ${CMAKE_COMMAND} -E copy
            ${CMAKE_CURRENT_BINARY_DIR}/TraxHost_${PLATFORM}/rtaudio/librtaudio.so
            ${ROOT}/librtaudio.so

        # Plugins — glob for all .so files at build time
        COMMAND ${CMAKE_COMMAND}
            -DSRC_DIR=${CMAKE_CURRENT_BINARY_DIR}/Plugins_${PLATFORM}
            -DDEST_DIR=${ROOT}/plugins
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/collect_plugins.cmake

        # er-301 binary
        COMMAND ${CMAKE_COMMAND} -E copy
            ${ER301_BUILD_DIR}/percussa-${PL}/percussa-${PL}.elf
            ${ROOT}/er301.elf

        # er-301 core mod package → er301/rear/
        COMMAND ${CMAKE_COMMAND}
            -DSRC_DIR=${ER301_BUILD_DIR}/mods-${ER301_ARCH}
            -DDEST_DIR=${ROOT}/er301/rear
            -DPATTERN=core-*.pkg
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/collect_files.cmake

        # er-301 Lua script tree — same for both platforms
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${ER301_DIR}/xroot
            ${ROOT}/er301/xroot

        # Resources — common first, then platform-specific (may overlay common)
        COMMAND ${CMAKE_COMMAND}
            -DSRC_DIR=${CMAKE_CURRENT_SOURCE_DIR}/resources/common
            -DDEST_DIR=${ROOT}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/collect_resources.cmake
        COMMAND ${CMAKE_COMMAND}
            -DSRC_DIR=${CMAKE_CURRENT_SOURCE_DIR}/resources/${PL}
            -DDEST_DIR=${ROOT}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/collect_resources.cmake

        # Strip all ELF binaries in-place
        COMMAND ${CMAKE_COMMAND}
            -DIMAGE_DIR=${ROOT}
            -DSTRIP_CMD=${STRIP_${PLATFORM}}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/strip_image.cmake

        # Zip the image — run from inside the image dir so there is no ssp/xmx prefix
        COMMAND ${CMAKE_COMMAND} -E chdir ${ROOT}
            ${CMAKE_COMMAND} -E tar cf ${CMAKE_CURRENT_BINARY_DIR}/tbapps_${PL}.zip --format=zip .
        COMMAND ${CMAKE_COMMAND} -E echo
            "==> Image ready: ${CMAKE_CURRENT_BINARY_DIR}/tbapps_${PL}.zip"

        COMMENT "Collecting, stripping and zipping ${PLATFORM} artifacts => tbapps_${PL}.zip"
        VERBATIM
    )

    add_custom_target(check_${PLATFORM}
        DEPENDS image_${PLATFORM}
        COMMAND ${CMAKE_COMMAND}
            -DIMAGE_DIR=${ROOT}
            -DPLATFORM=${PLATFORM}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/check_arch.cmake
        COMMENT "Checking ${PLATFORM} image architecture (expected: ${ER301_ARCH})"
        VERBATIM
    )
endforeach()
