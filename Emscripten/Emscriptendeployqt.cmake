include(CMakeParseArguments)

find_package(Qt5Core REQUIRED)

get_target_property(_qmake_executable Qt5::qmake IMPORTED_LOCATION)
get_filename_component(_qt_bin_dir "${_qmake_executable}" DIRECTORY)
find_path(QT_WASM_PLATFORMS_PATH NAMES qtloader.js HINTS "${_qt_bin_dir}/../plugins/platforms")
find_path(QT_LIBS_PATH NAMES libQt5Core.a HINTS "${_qt_bin_dir}/../lib")
find_program(EMSCRIPTEN_EMRUN NAMES emrun)

function(deploy_qt)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs)
    cmake_parse_arguments(EMS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    set(TARGET ${ARGV0})
    
    set_target_properties(HabView PROPERTIES COMPILE_FLAGS "-s USE_PTHREADS=0")

    # Link every static lib we can find and put it in a linker group so the linker order doesn't matter
    target_link_libraries(${TARGET} "-Wl,--start-group")
    file(GLOB_RECURSE QT_QML_DEPENDING_PLUGINS LIST_DIRECTORIES false "${_qt_bin_dir}/../*.a")
    foreach(LIB ${QT_QML_DEPENDING_PLUGINS})
        get_filename_component(LIB_NAME "${LIB}" NAME)
        add_library(${LIB_NAME} STATIC IMPORTED)
        set_property(TARGET ${LIB_NAME} PROPERTY IMPORTED_LOCATION "${LIB}")
        target_link_libraries(${TARGET} ${LIB_NAME})
    endforeach()
    target_link_libraries(${TARGET} "-Wl,--end-group")
    
    target_link_libraries(${TARGET} "-s WASM=1 -s USE_PTHREADS=0 $<$<CONFIG:Debug>:--emrun> -s FULL_ES2=1 $<$<CONFIG:Debug>:-s ASSERTIONS=1> -s ALLOW_MEMORY_GROWTH=1 -s USE_WEBGL2=1 -s NO_EXIT_RUNTIME=0 -s ERROR_ON_UNDEFINED_SYMBOLS=1 --bind -s \"BINARYEN_TRAP_MODE='clamp'\"")
        
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy "${QT_WASM_PLATFORMS_PATH}/qtloader.js" "$<TARGET_FILE_DIR:${TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy "${QT_WASM_PLATFORMS_PATH}/qtlogo.svg" "$<TARGET_FILE_DIR:${TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy "${QT_WASM_PLATFORMS_PATH}/wasm_shell.html" "$<TARGET_FILE_DIR:${TARGET}>"
        COMMAND sed -i 's/APPNAME/$<TARGET_NAME:${TARGET}>/g' "$<TARGET_FILE_DIR:${TARGET}>/wasm_shell.html")
    
    add_custom_target(${TARGET}-run
        COMMAND "${EMSCRIPTEN_EMRUN}" "$<TARGET_FILE_DIR:${TARGET}>/wasm_shell.html")
    
endfunction()
