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

if(WIN32 AND NOT MINGW)
    # target: *-pc-windows-msvc
    set(ICU4X_NATIVE_STATIC_LIBS
        kernel32.lib
        ntdll.lib
        userenv.lib
        ws2_32.lib
        dbghelp.lib
    )
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS /defaultlib:msvcrt)
elseif(WIN32)
    # MinGW / *-pc-windows-gnu links a different native set and cannot consume
    # the MSVC /defaultlib directive. It is neither embedded nor verified in CI,
    # so fail loudly rather than silently linking against the MSVC set above.
    message(
        FATAL_ERROR
        "icu4x: native-static-libs for the MinGW (windows-gnu) target are not "
        "embedded; only the MSVC target is supported. Add a branch to "
        "cmake/native-static-libs.cmake (and a CI job) if you need MinGW."
    )
elseif(APPLE)
    # target: *-apple-darwin (confirmed via CI on macOS)
    set(ICU4X_NATIVE_STATIC_LIBS -lSystem -lc -liconv -lm)
    set(ICU4X_NATIVE_STATIC_LINK_OPTIONS "")
else()
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
endif()
