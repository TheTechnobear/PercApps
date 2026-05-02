# Copy the contents of SRC_DIR into DEST_DIR at build time.
# No-op (with a status note) if SRC_DIR does not exist yet.
# Required variables (passed with -D):
#   SRC_DIR  — resource directory to copy from
#   DEST_DIR — destination root

if(EXISTS "${SRC_DIR}" AND IS_DIRECTORY "${SRC_DIR}")
    file(COPY "${SRC_DIR}/" DESTINATION "${DEST_DIR}")
    message(STATUS "Copied resources: ${SRC_DIR} => ${DEST_DIR}")
else()
    message(STATUS "No resources at ${SRC_DIR} (skipped)")
endif()
