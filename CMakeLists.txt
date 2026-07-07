cmake_minimum_required(VERSION 3.21)

project(icu4x LANGUAGES CXX)

option(ICU4X_INSTALL "Generate install rules for icu4x" ${PROJECT_IS_TOP_LEVEL})

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

find_program(CARGO_EXECUTABLE cargo REQUIRED)

execute_process(
    COMMAND "${CARGO_EXECUTABLE}" metadata --format-version 1
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    OUTPUT_VARIABLE _icu4x_metadata
    RESULT_VARIABLE _icu4x_metadata_result
)
if(NOT _icu4x_metadata_result EQUAL 0)
    message(
        FATAL_ERROR
        "icu4x: `cargo metadata` failed (${_icu4x_metadata_result}); "
        "cannot locate the icu_capi package or its C++ bindings headers."
    )
endif()

# cargo honours CARGO_TARGET_DIR and workspace target directories, so ask
# metadata where build artifacts actually land instead of assuming ./target.
string(JSON _icu4x_target_dir GET "${_icu4x_metadata}" target_directory)

set(_icu4x_lib_name
    "${CMAKE_STATIC_LIBRARY_PREFIX}icu_capi${CMAKE_STATIC_LIBRARY_SUFFIX}"
)
set(_icu4x_lib_path "${_icu4x_target_dir}/release/${_icu4x_lib_name}")

# Sets ICU4X_NATIVE_STATIC_LIBS and ICU4X_NATIVE_STATIC_LINK_OPTIONS -- the
# system libraries icu_capi must be linked against. See the file for rationale.
include("${CMAKE_CURRENT_LIST_DIR}/cmake/native-static-libs.cmake")

# icu_capi is always built for the host target; no --target is passed, so
# cross-compilation (a CMAKE_TOOLCHAIN_FILE targeting another arch/OS) is not
# supported.
add_custom_command(
    OUTPUT "${_icu4x_lib_path}"
    COMMAND
        "${CARGO_EXECUTABLE}" rustc --release -p icu_capi --crate-type staticlib
    DEPENDS
        "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml"
        "${CMAKE_CURRENT_LIST_DIR}/Cargo.lock"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
)

# Build the static library as part of the default target whenever we might
# install it, so `cmake --build` populates ${_icu4x_lib_path} before
# `cmake --install` copies it. This covers both a top-level build and a
# subproject that opted into ICU4X_INSTALL. Otherwise (consumed as a subproject
# without install), it is built on demand via the dependency below when
# something links icu4x.
if(PROJECT_IS_TOP_LEVEL OR ICU4X_INSTALL)
    add_custom_target(_icu4x_build ALL DEPENDS "${_icu4x_lib_path}")
else()
    add_custom_target(_icu4x_build DEPENDS "${_icu4x_lib_path}")
endif()

add_library(_icu4x_imported STATIC IMPORTED GLOBAL)
set_target_properties(
    _icu4x_imported
    PROPERTIES
        IMPORTED_LOCATION "${_icu4x_lib_path}"
        INTERFACE_LINK_LIBRARIES "${ICU4X_NATIVE_STATIC_LIBS}"
        INTERFACE_LINK_OPTIONS "${ICU4X_NATIVE_STATIC_LINK_OPTIONS}"
)
add_dependencies(_icu4x_imported _icu4x_build)

string(JSON _icu4x_pkg_len LENGTH "${_icu4x_metadata}" packages)
math(EXPR _icu4x_pkg_len_minus_one "${_icu4x_pkg_len} - 1")
foreach(_i RANGE ${_icu4x_pkg_len_minus_one})
    string(JSON _pkg_name GET "${_icu4x_metadata}" packages ${_i} name)
    if(_pkg_name STREQUAL icu_capi)
        string(
            JSON _icu4x_manifest_path
            GET "${_icu4x_metadata}"
            packages
            ${_i}
            manifest_path
        )
        # Report the actually-resolved icu_capi version in the package config
        # rather than a hardcoded string, so find_package(icu4x <version>)
        # reflects the headers and library that are really shipped.
        string(
            JSON _icu4x_version
            GET "${_icu4x_metadata}"
            packages
            ${_i}
            version
        )
        break()
    endif()
endforeach()
get_filename_component(_icu4x_manifest_dir "${_icu4x_manifest_path}" DIRECTORY)

if(NOT _icu4x_manifest_dir)
    message(
        FATAL_ERROR
        "icu4x: could not locate the icu_capi package via `cargo metadata`; "
        "its C++ bindings headers cannot be found."
    )
endif()

add_library(icu4x INTERFACE)
target_link_libraries(icu4x INTERFACE _icu4x_imported)
target_include_directories(
    icu4x
    INTERFACE
        $<BUILD_INTERFACE:${_icu4x_manifest_dir}/bindings/cpp>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

add_library(icu4x::icu4x ALIAS icu4x)

# --- Consumption via FetchContent(OVERRIDE_FIND_PACKAGE) --------------------
# When a consumer declares this project with OVERRIDE_FIND_PACKAGE and then
# calls find_package(icu4x), FetchContent redirects the call to the targets
# defined above. Provide a redirected config so find_package(icu4x [version])
# resolves cleanly. CMAKE_FIND_PACKAGE_REDIRECTS_DIR only exists on CMake >= 3.24,
# which is also the minimum required to use OVERRIDE_FIND_PACKAGE, so the guard
# doubles as a version gate.
if(DEFINED CMAKE_FIND_PACKAGE_REDIRECTS_DIR AND NOT PROJECT_IS_TOP_LEVEL)
    file(
        WRITE "${CMAKE_FIND_PACKAGE_REDIRECTS_DIR}/icu4x-config.cmake"
        [[
# icu4x::icu4x is already defined by the add_subdirectory() call that
# FetchContent performed before redirecting find_package(icu4x) here, so this
# config only needs to exist. Version handling lives in the companion
# icu4x-config-version.cmake file.
]]
    )
    write_basic_package_version_file(
        "${CMAKE_FIND_PACKAGE_REDIRECTS_DIR}/icu4x-config-version.cmake"
        VERSION "${_icu4x_version}"
        COMPATIBILITY SameMajorVersion
    )
endif()

# --- Install path -----------------------------------------------------------
# Produce a relocatable installed package so downstream projects can use
# find_package(icu4x) against the install prefix. Copies the prebuilt static
# library and the ICU4X C++ bindings headers into the install tree and ships a
# hand-written config that rebuilds the imported targets there.
if(ICU4X_INSTALL)
    # The archive is private (consumers link icu4x::icu4x, never the file), so
    # install it under a package subdirectory to avoid clashing with an
    # unrelated icu_capi archive in a shared prefix's lib/.
    install(
        FILES "${_icu4x_lib_path}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/icu4x"
    )

    # Stage the ICU4X C++ headers out of the cargo registry cache into the build
    # tree at configure time, then install from there. This keeps
    # `cmake --install` independent of the registry cache, which may be evicted
    # between configure and install; install(DIRECTORY) from a missing source
    # would otherwise silently install no headers. (file(COPY) also fails loudly
    # here if the headers are somehow absent at configure time.)
    set(_icu4x_staged_include "${CMAKE_CURRENT_BINARY_DIR}/icu4x-include")
    file(
        COPY "${_icu4x_manifest_dir}/bindings/cpp/"
        DESTINATION "${_icu4x_staged_include}"
        FILES_MATCHING
        PATTERN "*.hpp"
        PATTERN "*.h"
    )
    install(
        DIRECTORY "${_icu4x_staged_include}/"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
    )

    configure_package_config_file(
        "${CMAKE_CURRENT_LIST_DIR}/cmake/icu4x-config.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/icu4x-config.cmake"
        INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/icu4x"
        PATH_VARS CMAKE_INSTALL_LIBDIR CMAKE_INSTALL_INCLUDEDIR
    )

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/icu4x-config-version.cmake"
        VERSION "${_icu4x_version}"
        COMPATIBILITY SameMajorVersion
    )

    install(
        FILES
            "${CMAKE_CURRENT_BINARY_DIR}/icu4x-config.cmake"
            "${CMAKE_CURRENT_BINARY_DIR}/icu4x-config-version.cmake"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/icu4x"
    )
endif()
