# Verify all ELF binaries in IMAGE_DIR match the expected target architecture.
# Non-ELF files (.pkg, config, etc.) are silently skipped.
# Required variables (passed with -D):
#   IMAGE_DIR — root of the collected image to inspect
#   PLATFORM  — SSP or XMX

if(PLATFORM STREQUAL "SSP")
    set(expected_bits "ELF 32-bit")
    set(expected_arch "ARM")
else()
    set(expected_bits "ELF 64-bit")
    set(expected_arch "aarch64")
endif()

file(GLOB_RECURSE all_files LIST_DIRECTORIES false "${IMAGE_DIR}/*")

set(pass 0)
set(fail 0)

foreach(f ${all_files})
    execute_process(
        COMMAND file "${f}"
        OUTPUT_VARIABLE out
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    if(NOT out MATCHES "ELF")
        continue()
    endif()

    if(out MATCHES "${expected_bits}" AND out MATCHES "${expected_arch}")
        message(STATUS "  OK  ${f}")
        math(EXPR pass "${pass} + 1")
    else()
        message(WARNING "  FAIL ${f}\n       ${out}")
        math(EXPR fail "${fail} + 1")
    endif()
endforeach()

message(STATUS "Architecture check [${PLATFORM}]: ${pass} passed, ${fail} failed")

if(fail GREATER 0)
    message(FATAL_ERROR "Architecture check [${PLATFORM}]: ${fail} ELF file(s) have wrong architecture")
endif()
