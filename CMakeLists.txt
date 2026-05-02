cmake_minimum_required(VERSION 3.15)
project(PercApps NONE)

include(ExternalProject)

set(BUILD_TYPE "Release" CACHE STRING "Build type (Debug/Release)")
set(PARALLEL_JOBS 6 CACHE STRING "Number of parallel build jobs")
set(LOG_DIR ${CMAKE_CURRENT_BINARY_DIR}/logs)

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

foreach(PLATFORM IN ITEMS SSP XMX)
    string(TOLOWER ${PLATFORM} PL)

    # Step 1 — cross-build FFTW dependency
    add_custom_target(er301_fftw_${PLATFORM}
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for 'er301_fftw_${PLATFORM}' => output to terminal"
        COMMAND ${CMAKE_COMMAND} -E env TOOLCHAIN_FLAVOR=${PL}
                bash ${ER301_DIR}/scripts/build-fftw-cross.sh
        WORKING_DIRECTORY ${ER301_DIR}
        COMMENT "er-301 [${PLATFORM}]: building FFTW dependency"
        VERBATIM
    )

    # Step 2 — make percussa
    add_custom_target(er301_percussa_${PLATFORM}
        COMMAND ${CMAKE_COMMAND} -E echo
            "Performing build step for 'er301_percussa_${PLATFORM}' => output to terminal"
        COMMAND ${CMAKE_MAKE_PROGRAM} -j${PARALLEL_JOBS} percussa
                TOOLCHAIN_FILE=scripts/toolchains/${PL}.mk
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
