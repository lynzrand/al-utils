cmake_minimum_required(VERSION 3.21)
project(AL_NPR_Shaders LANGUAGES NONE)

find_program(SLANGC NAMES slangc REQUIRED)
set(SHADER_TARGET dxbc CACHE STRING "Output format (dxbc or dxil)")
set_property(CACHE SHADER_TARGET PROPERTY STRINGS dxbc dxil)
set(DXIL_PROFILE sm_6_0 CACHE STRING "DXIL shader model, optionally followed by +capability")
option(FILTER_BODY_OIL "Reconstruct the painted body mask as in the release" ON)

if(SHADER_TARGET STREQUAL "dxbc")
    # The Windows SDK installs FXC outside PATH on a typical developer machine.
    file(GLOB sdk_bins "$ENV{ProgramFiles\(x86\)}/Windows Kits/10/bin/10.*")
    list(SORT sdk_bins COMPARE NATURAL ORDER DESCENDING)
    find_program(FXC NAMES fxc HINTS ${sdk_bins} PATH_SUFFIXES x64 REQUIRED)
    set(profile sm_5_0)
elseif(SHADER_TARGET STREQUAL "dxil")
    set(profile "${DXIL_PROFILE}")
else()
    message(FATAL_ERROR "SHADER_TARGET must be dxbc or dxil")
endif()

set(manifest "${CMAKE_CURRENT_SOURCE_DIR}/programs.json")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${manifest}")
file(READ "${manifest}" programs)
string(JSON count LENGTH "${programs}")
math(EXPR last "${count} - 1")

# Unity pass names can share the exact same stage. Compile each source once
# and publish all of its manifest names so callers can address any pass.
foreach(index RANGE 0 ${last})
    string(JSON name MEMBER "${programs}" ${index})
    string(JSON file GET "${programs}" "${name}" file)
    string(JSON stage GET "${programs}" "${name}" stage)
    set(binary "${CMAKE_CURRENT_BINARY_DIR}/${name}.${SHADER_TARGET}")
    set(key "${file}-${stage}")
    if(DEFINED "compiled_${key}")
        add_custom_command(OUTPUT "${binary}"
            COMMAND "${CMAKE_COMMAND}" -E copy "${compiled_${key}}" "${binary}"
            DEPENDS "${compiled_${key}}" VERBATIM)
    else()
        set("compiled_${key}" "${binary}")
        set(source "${CMAKE_CURRENT_SOURCE_DIR}/${file}")
        set(args -I "${CMAKE_CURRENT_SOURCE_DIR}" -entry main -stage "${stage}" -fp-mode precise)
        if(FILTER_BODY_OIL AND file STREQUAL "Body/ForwardPS.slang")
            list(APPEND args -DFILTER_BODY_OIL=1)
        endif()
        if(SHADER_TARGET STREQUAL "dxbc")
            set(hlsl "${CMAKE_CURRENT_BINARY_DIR}/${name}.hlsl")
            add_custom_command(OUTPUT "${hlsl}"
                COMMAND "${SLANGC}" "${source}" ${args} -target hlsl -profile "${profile}"
                        -depfile "${hlsl}.d" -o "${hlsl}"
                DEPFILE "${hlsl}.d" DEPENDS "${source}" "${SLANGC}" VERBATIM)
            if(stage STREQUAL "vertex")
                set(fxc_profile vs_5_0)
            else()
                set(fxc_profile ps_5_0)
            endif()
            # Optimized FXC drops light lists carried in float register lanes.
            add_custom_command(OUTPUT "${binary}"
                COMMAND "${FXC}" /nologo /Od /Gis /T "${fxc_profile}" /E main /Fo "${binary}" "${hlsl}"
                DEPENDS "${hlsl}" "${FXC}" VERBATIM)
        else()
            add_custom_command(OUTPUT "${binary}"
                COMMAND "${SLANGC}" "${source}" ${args} -target dxil -profile "${profile}"
                        -depfile "${binary}.d" -o "${binary}"
                DEPFILE "${binary}.d" DEPENDS "${source}" "${SLANGC}" VERBATIM)
        endif()
    endif()
    add_custom_target("${name}" DEPENDS "${binary}")
    list(APPEND outputs "${binary}")
endforeach()
add_custom_target(shaders ALL DEPENDS ${outputs})
