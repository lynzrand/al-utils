# Native compute probes load independent DXIL files. Unity's raster bundle
# targets, profiles and material selection do not apply to these programs.
if(NOT SHADER_TARGET STREQUAL "dxil")
    return()
endif()

function(add_visibility_kernel name source profile)
    set(input "${CMAKE_CURRENT_SOURCE_DIR}/Visibility/${source}.slang")
    set(output "${CMAKE_CURRENT_BINARY_DIR}/${name}.dxil")
    add_custom_command(OUTPUT "${output}"
        COMMAND "${SLANGC}" "${input}" -I "${CMAKE_CURRENT_SOURCE_DIR}"
                -stage compute -entry Main -target dxil -profile "${profile}"
                -fp-mode precise -O3 ${downstream} ${ARGN} -o "${output}" -depfile "${output}.d"
        DEPENDS "${input}" "${SLANGC}" DEPFILE "${output}.d" VERBATIM)
    add_custom_target("${name}" DEPENDS "${output}")
endfunction()

add_visibility_kernel(UnityInteropWrite UnityInteropWrite sm_6_0)
add_visibility_kernel(UnityRayProbe UnityRayProbe sm_6_5)
add_visibility_kernel(MapLightVisibility MapLightVisibility sm_6_5)
add_visibility_kernel(UnityDepthRayVisibility UnityDepthRayVisibility sm_6_5)
add_custom_target(visibility-kernels)
add_dependencies(visibility-kernels UnityInteropWrite UnityRayProbe MapLightVisibility UnityDepthRayVisibility)

# These frozen-camera diagnostics share the same 592-byte native Frame ABI.
# The output mask selects reported bits after all supplied lights have been traced.
add_visibility_kernel(SunBaseline UnityDepthRayVisibility sm_6_5 -DAL_RAY_OUTPUT_MASK=1)
add_visibility_kernel(SunReprojected UnityDepthRayVisibility sm_6_5 -DAL_RAY_OUTPUT_MASK=1 -DAL_RAY_REPROJECT_RECEIVER=1)
add_visibility_kernel(ReceiverAccepted UnityDepthRayVisibility sm_6_5 -DAL_RAY_REPROJECT_RECEIVER=1 -DAL_RAY_DIAG_ACCEPTED=1)
add_visibility_kernel(ReceiverRejected UnityDepthRayVisibility sm_6_5 -DAL_RAY_REPROJECT_RECEIVER=1 -DAL_RAY_DIAG_REJECTED=1)
add_visibility_kernel(AllDirectionalsReprojected UnityDepthRayVisibility sm_6_5 -DAL_RAY_REPROJECT_RECEIVER=1)
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/AllDirectionalsBaseline.dxil"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_BINARY_DIR}/UnityDepthRayVisibility.dxil"
            "${CMAKE_CURRENT_BINARY_DIR}/AllDirectionalsBaseline.dxil"
    DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/UnityDepthRayVisibility.dxil" VERBATIM)
add_custom_target(AllDirectionalsBaseline DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/AllDirectionalsBaseline.dxil")
add_custom_target(receiver-diagnostics)
add_dependencies(receiver-diagnostics SunBaseline SunReprojected ReceiverAccepted ReceiverRejected
                 AllDirectionalsBaseline AllDirectionalsReprojected)

if(DXC)
    add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/MapLightVisibility.asm"
        COMMAND "${DXC}" -dumpbin -Fc "${CMAKE_CURRENT_BINARY_DIR}/MapLightVisibility.asm"
                "${CMAKE_CURRENT_BINARY_DIR}/MapLightVisibility.dxil"
        DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/MapLightVisibility.dxil" "${DXC}" VERBATIM)
    add_custom_target(MapLightVisibilityAssembly DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/MapLightVisibility.asm")
endif()
