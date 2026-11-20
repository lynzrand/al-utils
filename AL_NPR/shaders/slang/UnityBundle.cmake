find_package(Python3 3.11 COMPONENTS Interpreter REQUIRED)
get_filename_component(tools "${CMAKE_CURRENT_SOURCE_DIR}/../../tools" ABSOLUTE)
set(bundle_tool "${tools}/slang_bundle.py")
set(run "${CMAKE_COMMAND}" -E env "AL_GAME_PATH=${AL_GAME_PATH}"
        "SLANGC=${SLANGC}" "FXC=${FXC}" "${Python3_EXECUTABLE}")
set(game_assets "${AL_GAME_PATH}/AmanatsuLocation_Data/globalgamemanagers.assets")
set(templates "${AL_GAME_PATH}/lib/ma/te/c/000_08/00.unity3d"
              "${AL_GAME_PATH}/lib/ma/pre/sc/000_08/02.unity3d")
set(reference_dir "${CMAKE_CURRENT_BINARY_DIR}/stock-reference")
foreach(index RANGE 0 ${last})
    string(JSON name MEMBER "${programs}" ${index})
    list(APPEND reference_files "${reference_dir}/${name}.dxbc")
endforeach()
add_custom_command(OUTPUT ${reference_files}
    COMMAND ${run} "${bundle_tool}" stock-reference "${reference_dir}"
    DEPENDS "${manifest}" "${bundle_tool}" "${game_assets}" VERBATIM)
add_custom_target(stock-reference DEPENDS ${reference_files})

set(original_bundle "${CMAKE_CURRENT_BINARY_DIR}/original/al-skin-lighting.unity3d")
add_custom_command(OUTPUT "${original_bundle}"
    COMMAND ${run} "${bundle_tool}" original-bundle "${original_bundle}"
    DEPENDS "${bundle_tool}" "${tools}/build_skin_assets.py" "${game_assets}" ${templates} VERBATIM)
add_custom_target(original-bundle DEPENDS "${original_bundle}")

if(NOT SHADER_TARGET STREQUAL "dxbc")
    return()
endif()

set(work "${CMAKE_CURRENT_BINARY_DIR}/variants")
set(base "${work}/paired-individual-soft.unity3d")
set(release "${work}/release.unity3d")
file(GLOB baseline_tools "${tools}/patch_*.py" "${tools}/../../AL_Performance/tools/patch_*.py")
add_custom_command(OUTPUT "${base}"
    COMMAND ${run} "${tools}/build_default.py" --prepare-only --output-dir "${work}"
    DEPENDS "${tools}/build_default.py" "${tools}/build_skin_assets.py"
            "${tools}/build_toon_band_trials.py" "${tools}/build_toon_cloth_trials.py"
            ${baseline_tools} "${game_assets}" ${templates} VERBATIM)

function(link_variants source output builder)
    add_custom_command(OUTPUT "${output}"
        COMMAND ${run} "${tools}/${builder}.py" "${source}" "${output}"
        DEPENDS "${source}" "${tools}/${builder}.py" "${tools}/build_view_band_trial.py"
                "${tools}/compiled_material_entry.py" "${SLANGC}" "${FXC}" ${ARGN} VERBATIM)
endfunction()
link_variants("${base}" "${work}/material.unity3d" build_material_response BundleEntries.slang SceneLighting.slang)
link_variants("${work}/material.unity3d" "${work}/hair.unity3d" build_hair_reflection BundleEntries.slang HairLighting.slang SceneLighting.slang)
link_variants("${work}/hair.unity3d" "${work}/face.unity3d" build_face_shadow_trial
              BundleEntries.slang SceneLighting.slang ShadowFiltering.slang)
link_variants("${work}/face.unity3d" "${release}" build_fluid_filter FluidSample.slang FluidMask.slang)
add_custom_target(release-bundle DEPENDS "${release}")

if(SHADING STREQUAL "npr")
    set(base_args --base "${release}")
    set(bundle_inputs "${release}")
else()
    set(bundle_inputs "${game_assets}" ${templates})
endif()
set(bundle "${CMAKE_CURRENT_BINARY_DIR}/al-skin-lighting.unity3d")
add_custom_command(OUTPUT "${bundle}"
    COMMAND ${run} "${bundle_tool}" bundle "${bundle}" --programs "${CMAKE_CURRENT_BINARY_DIR}" --shading "${SHADING}" ${base_args}
    DEPENDS ${outputs} ${bundle_inputs} "${manifest}" "${bundle_tool}" "${tools}/build_skin_assets.py" VERBATIM)
add_custom_target(bundle DEPENDS "${bundle}")
add_custom_target(check-bundle
    COMMAND ${run} "${tools}/check_slang_bundle.py" "${bundle}" --programs "${CMAKE_CURRENT_BINARY_DIR}" ${base_args}
    DEPENDS "${bundle}" VERBATIM)
