# Copy files matching PATTERN from SRC_DIR to DEST_DIR at build time.
# Required variables (passed with -D):
#   SRC_DIR  — directory to search (non-recursive)
#   DEST_DIR — destination directory
#   PATTERN  — glob pattern, e.g. "core-*.pkg"

file(GLOB matched "${SRC_DIR}/${PATTERN}")

if(NOT matched)
    message(WARNING "collect_files: no files matching '${PATTERN}' in ${SRC_DIR}")
else()
    foreach(f ${matched})
        file(COPY "${f}" DESTINATION "${DEST_DIR}")
    endforeach()
    list(LENGTH matched count)
    message(STATUS "Collected ${count} file(s) matching '${PATTERN}' to ${DEST_DIR}")
endif()
