# Strip all ELF binaries in IMAGE_DIR in-place using STRIP_CMD.
# Required variables (passed with -D):
#   IMAGE_DIR  — root of the image
#   STRIP_CMD  — path to the strip executable

file(GLOB_RECURSE all_files LIST_DIRECTORIES false "${IMAGE_DIR}/*")

set(stripped 0)
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

    execute_process(
        COMMAND "${STRIP_CMD}" --strip-unneeded "${f}"
        RESULT_VARIABLE result
        ERROR_VARIABLE err
    )
    if(result EQUAL 0)
        message(STATUS "  stripped: ${f}")
        math(EXPR stripped "${stripped} + 1")
    else()
        message(WARNING "  strip failed: ${f}\n  ${err}")
    endif()
endforeach()

message(STATUS "Stripped ${stripped} ELF file(s) in ${IMAGE_DIR}")
