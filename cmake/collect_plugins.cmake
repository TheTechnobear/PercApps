# Invoked at build time via cmake -P to glob and copy plugin .so files.
# Required variables (passed with -D):
#   SRC_DIR  — Plugins build directory to search recursively
#   DEST_DIR — Destination directory for all collected .so files

file(GLOB_RECURSE so_files LIST_DIRECTORIES false "${SRC_DIR}/*.so")

foreach(f ${so_files})
    file(COPY "${f}" DESTINATION "${DEST_DIR}")
endforeach()

list(LENGTH so_files count)
message(STATUS "Collected ${count} plugin(s) to ${DEST_DIR}")
