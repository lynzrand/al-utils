cmake_minimum_required(VERSION 3.21)
project(AL_NPR_Shaders LANGUAGES NONE)
set(shader_root "${CMAKE_CURRENT_LIST_DIR}")

find_program(SLANGC NAMES slangc REQUIRED)
set(SHADER_TARGET dxbc CACHE STRING "Output format (dxbc or dxil)")
set_property(CACHE SHADER_TARGET PROPERTY STRINGS dxbc dxil)
set(SHADING npr CACHE STRING "Material implementation (npr or stock)")
set_property(CACHE SHADING PROPERTY STRINGS npr stock)
if(NOT SHADING MATCHES "^(npr|stock)$")
    message(FATAL_ERROR "SHADING must be npr or stock")
endif()
set(DXIL_PROFILE sm_6_0 CACHE STRING "DXIL shader model, optionally followed by +capability")
option(FILTER_BODY_OIL "Reconstruct the painted body mask as in the release" ON)

# Windows SDK compilers are normally installed outside PATH.
file(GLOB sdk_bins "$ENV{ProgramFiles\(x86\)}/Windows Kits/10/bin/10.*")
list(SORT sdk_bins COMPARE NATURAL ORDER DESCENDING)
if(SHADER_TARGET STREQUAL "dxbc")
    find_program(FXC NAMES fxc HINTS ${sdk_bins} PATH_SUFFIXES x64 REQUIRED)
elseif(SHADER_TARGET STREQUAL "dxil")
    find_program(DXC NAMES dxc HINTS ${sdk_bins} PATH_SUFFIXES x64)
    if(DXC)
        get_filename_component(dxc_dir "${DXC}" DIRECTORY)
        set(downstream -dxc-path "${dxc_dir}")
    endif()
else()
    message(FATAL_ERROR "SHADER_TARGET must be dxbc or dxil")
endif()

# The comparison build preserves the recovered SM5 arithmetic and lane packing.
# Other targets can choose the optimized FXC flags used by their original tools.
function(compile_stage name source stage fxc_profile fxc_flags)
    set(binary "${CMAKE_CURRENT_BINARY_DIR}/${name}.${SHADER_TARGET}")
    set(args -I "${shader_root}" -entry main -stage "${stage}" -fp-mode precise ${ARGN})
    if(SHADER_TARGET STREQUAL "dxbc")
        set(hlsl "${CMAKE_CURRENT_BINARY_DIR}/${name}.hlsl")
        add_custom_command(OUTPUT "${hlsl}"
            COMMAND "${SLANGC}" "${source}" ${args} -target hlsl -profile sm_5_0
                    -depfile "${hlsl}.d" -o "${hlsl}"
            DEPFILE "${hlsl}.d" DEPENDS "${source}" "${SLANGC}" VERBATIM)
        add_custom_command(OUTPUT "${binary}"
            COMMAND "${FXC}" /nologo ${fxc_flags} /T "${fxc_profile}" /E main /Fo "${binary}" "${hlsl}"
            DEPENDS "${hlsl}" "${FXC}" VERBATIM)
    else()
        add_custom_command(OUTPUT "${binary}"
            COMMAND "${SLANGC}" "${source}" ${args} ${downstream} -target dxil -profile "${DXIL_PROFILE}"
                    -depfile "${binary}.d" -o "${binary}"
            DEPFILE "${binary}.d" DEPENDS "${source}" "${SLANGC}" VERBATIM)
    endif()
endfunction()

set(manifest "${shader_root}/programs.json")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${manifest}")
file(READ "${manifest}" programs)
string(JSON count LENGTH "${programs}")
math(EXPR last "${count} - 1")

# Unity pass names can share the exact same stage. Compile each source once
# and publish all of its manifest names so callers can address any pass.
foreach(index RANGE 0 ${last})
    string(JSON name MEMBER "${programs}" ${index})
    string(JSON record GET "${programs}" "${name}")
    string(JSON file GET "${record}" file)
    string(JSON features ERROR_VARIABLE missing GET "${record}" defines)
    if(missing)
        set(features "[]")
    endif()
    if(SHADING STREQUAL "stock")
        string(JSON stock_file ERROR_VARIABLE missing GET "${programs}" "${name}" stock file)
        if(NOT missing)
            set(file "${stock_file}")
        endif()
        string(JSON stock_features ERROR_VARIABLE missing GET "${record}" stock defines)
        if(NOT missing)
            set(features "${stock_features}")
        endif()
    endif()
    set(defines)
    string(JSON feature_count LENGTH "${features}")
    if(feature_count GREATER 0)
        math(EXPR final_feature "${feature_count} - 1")
        foreach(i RANGE 0 ${final_feature})
            string(JSON feature GET "${features}" ${i})
            list(APPEND defines "-D${feature}")
        endforeach()
    endif()
    if(SHADING STREQUAL "npr" AND FILTER_BODY_OIL AND name STREQUAL "BodyForwardPS")
        list(APPEND defines -DFILTER_BODY_OIL=1)
    endif()
    string(JSON stage GET "${programs}" "${name}" stage)
    set(binary "${CMAKE_CURRENT_BINARY_DIR}/${name}.${SHADER_TARGET}")
    string(JOIN "," flags_key ${defines})
    set(key "${file}-${stage}-${flags_key}")
    if(DEFINED "compiled_${key}")
        add_custom_command(OUTPUT "${binary}"
            COMMAND "${CMAKE_COMMAND}" -E copy "${compiled_${key}}" "${binary}"
            DEPENDS "${compiled_${key}}" VERBATIM)
    else()
        set("compiled_${key}" "${binary}")
        if(stage STREQUAL "vertex")
            set(fxc_profile vs_5_0)
        else()
            set(fxc_profile ps_5_0)
        endif()
        compile_stage("${name}" "${shader_root}/${file}" "${stage}" "${fxc_profile}" "/Od;/Gis" ${defines})
    endif()
    add_custom_target("${name}" DEPENDS "${binary}")
    list(APPEND outputs "${binary}")
endforeach()
add_custom_target(shaders ALL DEPENDS ${outputs})

if(SHADER_TARGET STREQUAL "dxbc" AND SHADING STREQUAL "npr")
    set(AL_BUNDLE_PYTHON python CACHE FILEPATH "Python with UnityPy and lz4 for standalone packaging")
    set(standalone "${shader_root}/../standalone")
    set(standalone_output "${CMAKE_CURRENT_BINARY_DIR}/standalone/al-skin-lighting.unity3d")
    add_custom_command(OUTPUT "${standalone_output}"
        COMMAND "${AL_BUNDLE_PYTHON}" "${standalone}/build.py" "${CMAKE_CURRENT_BINARY_DIR}" "${standalone_output}"
        DEPENDS ${outputs} "${standalone}/build.py" "${standalone}/unity_bundle.py"
                "${standalone}/layouts/Face.json" "${standalone}/layouts/Body.json"
                "${standalone}/layouts/Cloth.json" "${standalone}/layouts/ClothAlpha.json"
                "${standalone}/layouts/Hair.json" "${shader_root}/../tools/patch_skin_map_params.py"
        VERBATIM)
    add_custom_target(standalone-bundle DEPENDS "${standalone_output}")
endif()

# The reference and broad keyword-variant builds read the local game data.
set(AL_GAME_PATH "$ENV{AL_GAME_PATH}" CACHE PATH "Amanatsu Location 1.0.4 game directory")
if(AL_GAME_PATH)
    include("${shader_root}/cmake/UnityBundle.cmake")
endif()

include("${shader_root}/../../AL_Performance/shaders/Performance.cmake")
include("${shader_root}/cmake/RayKernels.cmake")
