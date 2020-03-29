include(CMakeParseArguments)

# copy_replace_in_file(<filename> [REGEX] DESTINATION <dst> MATCH <match_string> REPLACE <replace replace_string>)
function(copy_replace_in_file)
    set(options REGEX)
    set(oneValueArgs DESTINATION MATCH REPLACE)
    set(multiValueArgs)
    cmake_parse_arguments(CP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    file(READ "${ARGV0}" FILE_CONTENT)
    if(CP_MATCH AND CP_REPLACE)
        if(CP_REGEX)
            string(REGEX REPLACE ${CP_MATCH} ${CP_REPLACE} REPLACED_CONTENT ${FILE_CONTENT})
        else()
            string(REPLACE ${CP_MATCH} ${CP_REPLACE} REPLACED_CONTENT ${FILE_CONTENT})
        endif()
    endif()
    file(WRITE "${CP_DESTINATION}" ${REPLACED_CONTENT})
endfunction()

# replace_in_file(<filename> [REGEX] MATCH <match_string> REPLACE <replace replace_string>)
function(replace_in_file)
    set(options REGEX)
    set(oneValueArgs MATCH REPLACE)
    set(multiValueArgs)
    cmake_parse_arguments(CP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    file(READ "${ARGV0}" FILE_CONTENT)
    if(CP_MATCH AND CP_REPLACE)
        if(CP_REGEX)
            string(REGEX REPLACE ${CP_MATCH} ${CP_REPLACE} REPLACED_CONTENT ${FILE_CONTENT})
        else()
            string(REPLACE ${CP_MATCH} ${CP_REPLACE} REPLACED_CONTENT ${FILE_CONTENT})
        endif()
    endif()
    file(WRITE "${ARGV0}" ${REPLACED_CONTENT})
endfunction()

# add_translation(<target> TS_FILES <ts_files> FILES_TO_TRANSLATE <files>)
function(add_translation TARGET)
    set(options)
    set(oneValueArgs TS_FILES)
    set(multiValueArgs FILES_TO_TRANSLATE)
    cmake_parse_arguments(TRANSL "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    find_package(Qt5LinguistTools REQUIRED)
    find_package(Qt5Core REQUIRED)
    
    get_filename_component(_QT_TRANSLATION "${Qt5Core_DIR}/../../../translations" ABSOLUTE)
    
    set(Qt5_LCONVERT_EXECUTABLE Qt5::lconvert)
    
    if(NOT TARGET ${TARGET})
        message(FATAL_ERROR "Missing a valid target")
    endif()
   
    set(qmSourcesJoint)
   
    foreach(_ts_file ${TRANSL_TS_FILES})
    
        get_filename_component(_abs_ts_FILE ${_ts_file} ABSOLUTE)
        get_filename_component(ts_FILE_NAME ${_abs_ts_FILE} NAME)
        get_filename_component(_abs_ts_FILE_DIR ${_abs_ts_FILE} DIRECTORY)
        
        string(REGEX REPLACE "\\.[^.]*$" "" QM_FILE_NAME ${ts_FILE_NAME})
    
        set(qm_file "${CMAKE_CURRENT_BINARY_DIR}/${QM_FILE_NAME}.qm")
    
        message(STATUS "Adding ts file ${_abs_ts_FILE}, generating qm file ${qm_file}")
    
        set(_CONTENT "empty")
        if(NOT EXISTS "${_abs_ts_FILE}")
            get_target_property(lupdate_exe ${Qt5_LUPDATE_EXECUTABLE} IMPORTED_LOCATION)
            execute_process(COMMAND "${lupdate_exe}" "${CMAKE_PARENT_LIST_FILE}" -ts "${_abs_ts_FILE}")
            message(STATUS "Creating empty ts file ${_abs_ts_FILE}")
        endif()
        file(READ "${_abs_ts_FILE}" _CONTENT LIMIT 200)
        string(REGEX MATCH "language=\"([a-z]+)_" MATCH ${_CONTENT})
        if(MATCH)
            message(STATUS "Given ts file targets language: ${CMAKE_MATCH_1}")
            if(EXISTS "${_QT_TRANSLATION}")
                file(GLOB _QT_TRANSLATION_FILES_LANG "${_QT_TRANSLATION}/qt*_${CMAKE_MATCH_1}.qm")
                list(REMOVE_ITEM _QT_TRANSLATION_FILES_LANG "${_QT_TRANSLATION}/qt_${CMAKE_MATCH_1}.qm")
                message(STATUS "Adding default qt translation files for language ${CMAKE_MATCH_1}: ${_QT_TRANSLATION_FILES_LANG}")
            else()
                message(WARNING "This qt installation doesn't contain default qt translation files")
            endif()
        else()
            message(FATAL_ERROR "Couldn't parse ts file: ${_abs_ts_FILE}")
        endif()
        
        set(merged_qm "${CMAKE_CURRENT_BINARY_DIR}/qt_merged_${CMAKE_MATCH_1}.qm")
        
        message(STATUS "Crating merged translation file for language ${CMAKE_MATCH_1}: ${merged_qm}")
        
        message(STATUS "Translating file ${TRANSL_FILES_TO_TRANSLATE}")
        
        set(options ${CMAKE_CURRENT_SOURCE_DIR} ${TRANSL_FILES_TO_TRANSLATE} -I ${CMAKE_CURRENT_SOURCE_DIR} -locations relative -ts ${_abs_ts_FILE})
        
        add_custom_command(
            #TARGET ${TARGET}
            #PRE_BUILD
            OUTPUT ${_abs_ts_FILE}
            COMMAND ${Qt5_LUPDATE_EXECUTABLE} ${options}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            DEPENDS ${TRANSL_FILES_TO_TRANSLATE}
            VERBATIM
        )
        
        add_custom_command(OUTPUT ${qm_file}
            COMMAND ${Qt5_LRELEASE_EXECUTABLE}
            ARGS ${_abs_ts_FILE} -qm ${qm_file}
            DEPENDS ${_abs_ts_FILE}
            VERBATIM
        )
        
        set(lconvert_args "-o;${merged_qm};${_QT_TRANSLATION_FILES_LANG};${qm_file}")
        
        add_custom_command(OUTPUT ${merged_qm}
            COMMAND ${Qt5_LCONVERT_EXECUTABLE}
            ARGS ${lconvert_args}
            DEPENDS ${qm_file} VERBATIM
        )
        
        target_sources(${TARGET} PRIVATE ${merged_qm})
        
        get_filename_component(fileName ${merged_qm} NAME)
        set(qmSourcesJoint "${qmSourcesJoint}<file alias=\"${fileName}\">${merged_qm}</file>")
        
    endforeach()
    
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/i18n.qrc "<RCC><qresource prefix=\"/i18n\">${qmSourcesJoint}</qresource></RCC>")
    qt5_add_resources(resSources "${CMAKE_CURRENT_BINARY_DIR}/i18n.qrc")
    
    target_sources(${TARGET} PRIVATE ${resSources})
    
endfunction()

# Allows generator expressions in config files. Accepts all parameters "configure_file()" accepts.
# WARNING: The creation of the file is delayed until build system generation see https://cmake.org/cmake/help/latest/manual/cmake-generator-expressions.7.html
macro(configure_file_gen_expr)
    configure_file(${ARGV})
    file(READ "${ARGV1}" FILE_CONTENT)
    file(REMOVE "${ARGV1}")
    file(GENERATE OUTPUT "${ARGV1}" CONTENT "${FILE_CONTENT}")
endmacro()
