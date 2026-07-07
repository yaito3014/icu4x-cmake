# System libraries and linker options required to link the icu_capi static
# library, embedded per platform so that configuring the project performs no
# build.
#
# A Rust static library does not record the native libraries it depends on, so
# these lists are maintained by hand. Their accuracy is verified against
# `rustc --print native-static-libs` on each platform in CI; see
# cmake/verify-native-static-libs.cmake and
# .github/workflows/native-static-libs.yml. If CI reports a mismatch, update the
# affected list with the values it prints.
#
# Sets:
#   ICU4X_NATIVE_STATIC_LIBS          - libraries for INTERFACE_LINK_LIBRARIES
#   ICU4X_NATIVE_STATIC_LINK_OPTIONS  - linker directives for INTERFACE_LINK_OPTIONS
#                                       (e.g. MSVC's /defaultlib:...), which must
#                                       not be treated as library files.
#
# The table is keyed on a single ICU4X_PLATFORM selector. A caller may set it
# explicitly (the CI verifier does, so it can check a cross target); otherwise it
# is derived from the toolchain below.

if(NOT DEFINED ICU4X_PLATFORM)
    if(WIN32 AND NOT MINGW)
        set(ICU4X_PLATFORM windows-msvc)
    elseif(WIN32)
        set(ICU4X_PLATFORM windows-gnu)
    elseif(APPLE)
        set(ICU4X_PLATFORM apple)
    else()
        set(ICU4X_PLATFORM unix)
    endif()
endif()

if(ICU4X_PLATFORM STREQUAL windows-msvc)
    # target: *-pc-windows-msvc
    set(ICU4X_NATIVE_STATIC_LIBS
        kernel32.lib
        ntdll.lib
        userenv.lib
        ws2_32.lib
        dbghelp.lib
    )
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS /defaultlib:msvcrt)
elseif(ICU4X_PLATFORM STREQUAL windows-gnu)
    # target: *-pc-windows-gnu (MinGW). The same system libraries as MSVC, but
    # named GNU-style and without the /defaultlib CRT directive. Confirmed via
    # the windows-gnu CI job.
    set(ICU4X_NATIVE_STATIC_LIBS
        -lkernel32
        -lntdll
        -luserenv
        -lws2_32
        -ldbghelp
    )
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS "")
elseif(ICU4X_PLATFORM STREQUAL apple)
    # target: *-apple-darwin (confirmed via CI on macOS)
    set(ICU4X_NATIVE_STATIC_LIBS -lSystem -lc -liconv -lm)
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS "")
elseif(ICU4X_PLATFORM STREQUAL unix)
    # target: *-unknown-linux-gnu
    set(ICU4X_NATIVE_STATIC_LIBS
        -lgcc_s
        -lutil
        -lrt
        -lpthread
        -lm
        -ldl
        -lc
    )
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS "")
else()
    message(FATAL_ERROR "icu4x: unknown ICU4X_PLATFORM '${ICU4X_PLATFORM}'")
endif()
