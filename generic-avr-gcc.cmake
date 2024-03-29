##########################################################################
# The toolchain requires some variables set.
#
# AVR_MCU (default: atmega8)
#     the type of AVR the application is built for
# AVR_L_FUSE (NO DEFAULT)
#     the LOW fuse value for the MCU used
# AVR_H_FUSE (NO DEFAULT)
#     the HIGH fuse value for the MCU used
# AVR_UPLOADTOOL (default: avrdude)
#     the application used to upload to the MCU
#     NOTE: The toolchain is currently quite specific about
#           the commands used, so it needs tweaking.
# AVR_UPLOADTOOL_PORT (default: usb)
#     the port used for the upload tool, e.g. usb
# AVR_PROGRAMMER (default: avrispmkII)
#     the programmer hardware used, e.g. avrispmkII
##########################################################################


##########################################################################
# executables in use
##########################################################################
find_program(AVR_CC avr-gcc REQUIRED)
find_program(AVR_CXX avr-g++ REQUIRED)
find_program(AVR_OBJCOPY avr-objcopy REQUIRED)
find_program(AVR_SIZE_TOOL avr-size REQUIRED)
find_program(AVR_OBJDUMP avr-objdump REQUIRED)
find_program(AVR_UPLOADTOOL avrdude REQUIRED)

##########################################################################
# toolchain starts with defining mandatory variables
##########################################################################
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR avr)
set(CMAKE_C_COMPILER ${AVR_CC})
set(CMAKE_CXX_COMPILER ${AVR_CXX})


##########################################################################
# Identification
##########################################################################
set(AVR 1)




##########################################################################
# _check_default_defines
#
# Check that all the necessary tools and variables for AVR builds, which may
# not defined yet
# - AVR_UPLOADTOOL
# - AVR_UPLOADTOOL_PORT
# - AVR_PROGRAMMER
# - AVR_MCU
# - AVR_SIZE_ARGS
#
# Creates targets and dependencies for AVR toolchain, building an
# executable. Calls add_executable with ELF file as target name, so
# any link dependencies need to be using that target, e.g. for
# target_link_libraries(<EXECUTABLE_NAME>-${AVR_MCU}.elf ...).
##########################################################################
function (_check_default_defines)


    if (NOT AVR_UPLOADTOOL)
        set (AVR_UPLOADTOOL avrdude CACHE STRING "Set default upload tool: avrdude")
    endif()

    if (NOT AVR_UPLOADTOOL_PORT) 
        set (AVR_UPLOADTOOL_PORT CACHE STRING "Set default upload tool port: usb")
    endif()

    if (NOT AVR_PROGRAMMER)
        set (AVR_PROGRAMMER avrispmkII
                CACHE STRING "Set default programmer hardware model: avrispmkII")
    endif()

    if (NOT AVR_MCU) 
        set (AVR_MCU atmega8 
            CACHE STRING "Set default MCU: atmega8 (see 'avr-gcc --target-help' for valid values)")
    endif()





    # prepare base flags for upload tool
    set(AVR_UPLOADTOOL_BASE_OPTIONS -p ${AVR_MCU} -c ${AVR_PROGRAMMER})

    # use AVR_UPLOADTOOL_BAUDRATE as baudrate for upload tool (if defined)
    if(AVR_UPLOADTOOL_BAUDRATE)
        set(AVR_UPLOADTOOL_BASE_OPTIONS ${AVR_UPLOADTOOL_BASE_OPTIONS} -b ${AVR_UPLOADTOOL_BAUDRATE})
    endif()
endfunction()



# file(GLOB SOURCES src/*.c)

# add_executable(${PROJECT_NAME} ${SOURCES})


##########################################################################
# add_avr_executable
# - IN_VAR: EXECUTABLE_NAME
#
# Creates targets and dependencies for AVR toolchain, building an
# executable. Calls add_executable with ELF file as target name, so
# any link dependencies need to be using that target, e.g. for
# target_link_libraries(<EXECUTABLE_NAME>-${AVR_MCU}.elf ...).
##########################################################################
function(add_avr_executable EXECUTABLE_NAME)

    if(NOT ARGN)
        message(FATAL_ERROR "No source files given for ${EXECUTABLE_NAME}.")
    endif(NOT ARGN)
    
    _check_default_defines()
    set(MCU_TYPE_FOR_FILENAME "")

    # set file names
    set(elf_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.elf)
    set(hex_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.hex)
    set(lst_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.lst)
    set(map_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.map)
    set(eeprom_image ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}-eeprom.hex)

    set (${EXECUTABLE_NAME}_ELF_TARGET ${elf_file} PARENT_SCOPE)
    set (${EXECUTABLE_NAME}_HEX_TARGET ${hex_file} PARENT_SCOPE)
    set (${EXECUTABLE_NAME}_LST_TARGET ${lst_file} PARENT_SCOPE)
    set (${EXECUTABLE_NAME}_MAP_TARGET ${map_file} PARENT_SCOPE)
    set (${EXECUTABLE_NAME}_EEPROM_TARGET ${eeprom_file} PARENT_SCOPE)     

    # elf file
    add_executable(${elf_file} EXCLUDE_FROM_ALL ${ARGN})

    set_target_properties(
        ${elf_file}
        PROPERTIES
            COMPILE_FLAGS "-mmcu=${AVR_MCU}"
            LINK_FLAGS "-mmcu=${AVR_MCU} -Wl,--gc-sections -mrelax -Wl,-Map,${map_file}"
    )

    add_custom_command(
        OUTPUT ${hex_file}
        COMMAND
            ${AVR_OBJCOPY} -j .text -j .data -O ihex ${elf_file} ${hex_file}
        COMMAND
            ${AVR_SIZE_TOOL} ${AVR_SIZE_ARGS} ${elf_file}
        DEPENDS ${elf_file}
    )

    add_custom_command(
        OUTPUT ${lst_file}
        COMMAND
            ${AVR_OBJDUMP} -d ${elf_file} > ${lst_file}
        DEPENDS ${elf_file}
    )

    # eeprom
    add_custom_command(
        OUTPUT ${eeprom_image}
        COMMAND
            ${AVR_OBJCOPY} -j .eeprom --set-section-flags=.eeprom=alloc,load
            --change-section-lma .eeprom=0 --no-change-warnings
            -O ihex ${elf_file} ${eeprom_image}
        DEPENDS ${elf_file}
    )

    add_custom_target(
        ${EXECUTABLE_NAME}
        ALL
        DEPENDS ${hex_file} ${lst_file} ${eeprom_image}
    )

    set_target_properties(
        ${EXECUTABLE_NAME}
        PROPERTIES
            OUTPUT_NAME "${elf_file}"
    )

    # clean
    get_directory_property(clean_files ADDITIONAL_MAKE_CLEAN_FILES)
    set_directory_properties(
        PROPERTIES
            ADDITIONAL_MAKE_CLEAN_FILES "${map_file}"
    )

    # upload - with avrdude
    add_custom_target(
        upload-${EXECUTABLE_NAME}
        ${AVR_UPLOADTOOL} ${AVR_UPLOADTOOL_BASE_OPTIONS} ${AVR_UPLOADTOOL_OPTIONS}
            -v -V -D -U flash:w:${hex_file}
            -P ${AVR_UPLOADTOOL_PORT}
        DEPENDS ${hex_file}
        COMMENT "Uploading ${hex_file} to ${AVR_MCU} using ${AVR_PROGRAMMER}"
    )

    # upload eeprom only - with avrdude
    # see also bug http://savannah.nongnu.org/bugs/?40142
    add_custom_target(
        upload-${EXECUTABLE_NAME}_eeprom
        ${AVR_UPLOADTOOL} ${AVR_UPLOADTOOL_BASE_OPTIONS} ${AVR_UPLOADTOOL_OPTIONS}
            -U eeprom:w:${eeprom_image}
            -P ${AVR_UPLOADTOOL_PORT}
        DEPENDS ${eeprom_image}
        COMMENT "Uploading ${eeprom_image} to ${AVR_MCU} using ${AVR_PROGRAMMER}"
    )

    # disassemble
    add_custom_target(
        disassemble-${EXECUTABLE_NAME}
        ${AVR_OBJDUMP} -h -S ${elf_file} > ${EXECUTABLE_NAME}.lst
        DEPENDS ${elf_file}
    )
endfunction()




##########################################################################
# add_avr_library
# - IN_VAR: LIBRARY_NAME
#
# Calls add_library with an optionally concatenated name
# <LIBRARY_NAME>${MCU_TYPE_FOR_FILENAME}.
# This needs to be used for linking against the library, e.g. calling
# target_link_libraries(...).
##########################################################################
function(add_avr_library LIBRARY_NAME)
    if(NOT ARGN)
        message(FATAL_ERROR "No source files given for ${LIBRARY_NAME}.")
    endif()



    _check_default_defines()

    set(lib_file ${LIBRARY_NAME}${MCU_TYPE_FOR_FILENAME})
    set (${LIBRARY_NAME}_LIB_TARGET ${elf_file} PARENT_SCOPE)

    add_library(${lib_file} STATIC ${ARGN})

    set_target_properties(
            ${lib_file}
            PROPERTIES
            COMPILE_FLAGS "-mmcu=${AVR_MCU}"
            OUTPUT_NAME "${lib_file}"
    )

    if(NOT TARGET ${LIBRARY_NAME})
        add_custom_target(
                ${LIBRARY_NAME}
                ALL
                DEPENDS ${lib_file}
        )

        set_target_properties(
                ${LIBRARY_NAME}
                PROPERTIES
                OUTPUT_NAME "${lib_file}"
        )
    endif()

endfunction()


##########################################################################
# avr_target_link_libraries
# - IN_VAR: EXECUTABLE_TARGET
# - ARGN  : targets and files to link to
#
# Calls target_link_libraries with AVR target names (concatenation,
# extensions and so on.
##########################################################################
function(avr_target_link_libraries EXECUTABLE_TARGET)
   if(NOT ARGN)
      message(FATAL_ERROR "Nothing to link to ${EXECUTABLE_TARGET}.")
   endif()
    
   _check_default_defines()
   get_target_property(TARGET_LIST ${EXECUTABLE_TARGET} OUTPUT_NAME)

   foreach(TGT ${ARGN})
      if(TARGET ${TGT})
         get_target_property(ARG_NAME ${TGT} OUTPUT_NAME)
         list(APPEND NON_TARGET_LIST ${ARG_NAME})
      else()
         list(APPEND NON_TARGET_LIST ${TGT})
      endif()
   endforeach()

   target_link_libraries(${TARGET_LIST} ${NON_TARGET_LIST})
endfunction()


set(CMAKE_TRY_COMPILE_TARGET_TYPE "STATIC_LIBRARY")

