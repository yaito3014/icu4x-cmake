# Verify that the embedded native-static-libs table (native-static-libs.cmake)
# matches what rustc actually reports for the host platform. Intended for CI:
#
#   cmake -P cmake/verify-native-static-libs.cmake
#
# Exits non-zero and prints the expected values when the table has drifted.

cmake_minimum_required(VERSION 3.21)

# native-static-libs.cmake branches on WIN32/APPLE/UNIX (target variables). In
# script mode there is no target, so mirror the host onto those variables so the
# same branch is selected for the platform we are verifying.
if(CMAKE_HOST_WIN32)
    set(WIN32 1)
elseif(CMAKE_HOST_APPLE)
    set(APPLE 1)
endif()
if(CMAKE_HOST_UNIX)
    set(UNIX 1)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/native-static-libs.cmake)
set(_embedded ${ICU4X_NATIVE_STATIC_LIBS} ${ICU4X_NATIVE_STATIC_LINK_OPTIONS})

set(_repo ${CMAKE_CURRENT_LIST_DIR}/..)

# rustc only prints the note when it actually compiles, so force a fresh build.
execute_process(
    COMMAND cargo clean --release -p icu_capi
    WORKING_DIRECTORY ${_repo}
)
execute_process(
    COMMAND
        cargo rustc --release -p icu_capi --crate-type staticlib -- --print
        native-static-libs
    WORKING_DIRECTORY ${_repo}
    OUTPUT_QUIET
    ERROR_VARIABLE _stderr
    RESULT_VARIABLE _result
)
if(NOT _result EQUAL 0)
    message(FATAL_ERROR "cargo rustc failed (${_result}):\n${_stderr}")
endif()
if(NOT _stderr MATCHES "native-static-libs: ([^\n]*)")
    message(
        FATAL_ERROR
        "no 'native-static-libs' note in rustc output:\n${_stderr}"
    )
endif()
string(STRIP "${CMAKE_MATCH_1}" _line)
string(REGEX REPLACE " +" ";" _actual "${_line}")

# Compare as sets: presence of every entry is what matters for link correctness;
# the order rustc prints them in is not significant for detecting drift.
set(_embedded_sorted ${_embedded})
set(_actual_sorted ${_actual})
list(SORT _embedded_sorted)
list(SORT _actual_sorted)

if(NOT "${_embedded_sorted}" STREQUAL "${_actual_sorted}")
    message(
        FATAL_ERROR
        "Embedded native-static-libs is out of date for this platform.\n"
        "  embedded: ${_embedded_sorted}\n"
        "  actual:   ${_actual_sorted}\n"
        "Update cmake/native-static-libs.cmake to match 'actual' "
        "(remember to route /-prefixed directives to ICU4X_NATIVE_STATIC_LINK_OPTIONS)."
    )
endif()

message(STATUS "native-static-libs up to date: ${_actual}")
