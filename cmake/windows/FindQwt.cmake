# Windows override for FindQwt.cmake
# Used when building with the MSYS2 ucrt64 pre-built Qwt package.
# Paths are injected by build_windows.ps1 via -DQWT_INCLUDE_DIR and -DQWT_LIBRARY.
# The original FindQwt.cmake uses GET_PREREQUISITES which fails on Windows DLL
# import libraries, so this override is searched first via CMAKE_MODULE_PATH.

if (NOT QWT_INCLUDE_DIR OR NOT QWT_LIBRARY)
  message(FATAL_ERROR "QWT_INCLUDE_DIR and QWT_LIBRARY must be set for Windows builds.")
endif()

set(QWT_INCLUDE_DIRS ${QWT_INCLUDE_DIR})
set(QWT_LIBRARIES    ${QWT_LIBRARY})
set(QWT_FOUND        true)

message(STATUS "Found Qwt (Windows override): ${QWT_LIBRARY}")
