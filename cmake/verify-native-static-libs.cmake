# Verify that the embedded native-static-libs table (native-static-libs.cmake)
# matches what rustc actually reports for the host platform. Intended for CI:
#
#   cmake -P cmake/verify-native-static-libs.cmake
#
# Exits non-zero and prints the expected values when the table has drifted.

cmake_minimum_required(VERSION 3.21)

# native-static-libs.cmake selects its table by the ICU4X_PLATFORM key. Set it
# from the host (default) or from an explicit target triple in
# ICU4X_VERIFY_TARGET -- which also lets us verify a cross target such as
# x86_64-pc-windows-gnu on a Windows runner. When set, the triple is passed to
# cargo via --target.
set(_icu4x_verify_target "$ENV{ICU4X_VERIFY_TARGET}")
if(_icu4x_verify_target)
    if(_icu4x_verify_target MATCHES "windows-gnu")
        set(ICU4X_PLATFORM windows-gnu)
    elseif(_icu4x_verify_target MATCHES "windows")
        set(ICU4X_PLATFORM windows-msvc)
    elseif(_icu4x_verify_target MATCHES "apple|darwin")
        set(ICU4X_PLATFORM apple)
    else()
        set(ICU4X_PLATFORM unix)
    endif()
    set(_icu4x_cargo_target_args --target ${_icu4x_verify_target})
else()
    if(CMAKE_HOST_WIN32)
        set(ICU4X_PLATFORM windows-msvc)
    elseif(CMAKE_HOST_APPLE)
        set(ICU4X_PLATFORM apple)
    else()
        set(ICU4X_PLATFORM unix)
    endif()
    set(_icu4x_cargo_target_args "")
endif()

include(${CMAKE_CURRENT_LIST_DIR}/native-static-libs.cmake)
set(_embedded ${ICU4X_NATIVE_STATIC_LIBS} ${ICU4X_NATIVE_STATIC_LINK_OPTIONS})

set(_repo ${CMAKE_CURRENT_LIST_DIR}/..)

# rustc only prints the note when it actually compiles, so force a fresh build.
# If the clean fails, rustc may not recompile and no note would be emitted, so
# check it here to fail with an accurate message.
execute_process(
    COMMAND cargo clean --release -p icu_capi ${_icu4x_cargo_target_args}
    WORKING_DIRECTORY ${_repo}
    RESULT_VARIABLE _clean_result
)
if(NOT _clean_result EQUAL 0)
    message(
        FATAL_ERROR
        "cargo clean failed (${_clean_result}); cannot force a fresh build to "
        "read native-static-libs."
    )
endif()
execute_process(
    COMMAND
        cargo rustc --color never --release -p icu_capi --crate-type staticlib
        ${_icu4x_cargo_target_args} -- --print native-static-libs
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

# Compare as a set (deduplicated, order-independent). What matters is that every
# library rustc reports is present in the table and vice versa. Order is
# intentionally not checked: the table splits libraries from linker directives
# across two properties, so the combined order already differs from rustc's, and
# these are order-insensitive system libraries. Dedup matters because rustc may
# print the same library more than once; list(SORT) alone keeps duplicates, so
# without REMOVE_DUPLICATES a repeated entry would force a spurious "out of date"
# and push the maintainer to embed a pointless duplicate.
set(_embedded_set ${_embedded})
set(_actual_set ${_actual})
list(REMOVE_DUPLICATES _embedded_set)
list(REMOVE_DUPLICATES _actual_set)
list(SORT _embedded_set)
list(SORT _actual_set)

if(NOT "${_embedded_set}" STREQUAL "${_actual_set}")
    message(
        FATAL_ERROR
        "Embedded native-static-libs is out of date for this platform.\n"
        "  embedded: ${_embedded_set}\n"
        "  actual:   ${_actual_set}\n"
        "Update cmake/native-static-libs.cmake to match 'actual' "
        "(remember to route /-prefixed directives to ICU4X_NATIVE_STATIC_LINK_OPTIONS)."
    )
endif()

message(STATUS "native-static-libs up to date: ${_actual}")
