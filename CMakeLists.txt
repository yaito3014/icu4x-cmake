cmake_minimum_required(VERSION 3.20)

find_program(CARGO_EXECUTABLE cargo REQUIRED)

if(UNIX)
    set(_icu4x_lib_path ${CMAKE_CURRENT_LIST_DIR}/target/release/libicu_capi.a)
elseif(WIN32)
    set(_icu4x_lib_path ${CMAKE_CURRENT_LIST_DIR}/target/release/icu_capi.lib)
endif()

add_custom_command(
    OUTPUT ${_icu4x_lib_path}
    COMMAND
        ${CARGO_EXECUTABLE} rustc --release -p icu_capi --crate-type staticlib
    DEPENDS
        ${CMAKE_CURRENT_LIST_DIR}/Cargo.toml
        ${CMAKE_CURRENT_LIST_DIR}/Cargo.lock
    WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
)
add_custom_target(_icu4x_build DEPENDS "${_icu4x_lib_path}")

add_library(_icu4x_imported STATIC IMPORTED GLOBAL)
set_target_properties(
    _icu4x_imported
    PROPERTIES IMPORTED_LOCATION ${_icu4x_lib_path}
)
add_dependencies(_icu4x_imported _icu4x_build)

execute_process(
    COMMAND ${CARGO_EXECUTABLE} metadata --format-version 1
    WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
    OUTPUT_VARIABLE _icu4x_metadata
)

string(JSON _icu4x_pkg_len LENGTH ${_icu4x_metadata} packages)
math(EXPR _icu4x_pkg_len_minus_one "${_icu4x_pkg_len} - 1")
foreach(_i RANGE ${_icu4x_pkg_len_minus_one})
    string(JSON _pkg_name GET ${_icu4x_metadata} packages ${_i} name)
    if(_pkg_name STREQUAL icu_capi)
        string(
            JSON _icu4x_manifest_path
            GET ${_icu4x_metadata}
            packages
            ${_i}
            manifest_path
        )
        break()
    endif()
endforeach()
get_filename_component(_icu4x_manifest_dir ${_icu4x_manifest_path} DIRECTORY)

add_library(icu4x INTERFACE)
target_link_libraries(icu4x INTERFACE _icu4x_imported)
target_include_directories(icu4x INTERFACE ${_icu4x_manifest_dir}/bindings/cpp)

add_library(icu4x::icu4x ALIAS icu4x)
