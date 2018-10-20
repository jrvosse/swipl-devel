# Include in all Prolog packages
#
# This CMAKE file is used to make   handling  the packages as uniform as
# possible such that we can perform   all  global package reorganization
# centrally.

# Get cmake files from this package, the package infrastructure and
# SWI-Prolog overall
set(CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake"
    "${CMAKE_CURRENT_SOURCE_DIR}/../cmake"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")

# CMake modules we always need
include(CheckIncludeFile)
include(CheckFunctionExists)
include(CheckSymbolExists)

# Arity is of size_t.  This should now be the case for all packages
set(PL_ARITY_AS_SIZE 1)
if(MULTI_THREADED)
  set(O_PLMT 1)
  set(_REENTRANT 1)			# FIXME: packages should use O_PLMT
endif()

string(REGEX REPLACE "^.*-" "" SWIPL_PKG ${PROJECT_NAME})

# get SWI-Prolog.h and SWI-Stream.h
include_directories(BEFORE ${SWIPL_ROOT}/src ${SWIPL_ROOT}/src/os)
if(WIN32)
  include_directories(BEFORE
		      ${SWIPL_ROOT}/src/os/windows
		      ${SWIPL_ROOT}/src/win32/console)
endif()
include_directories(BEFORE ${CMAKE_CURRENT_BINARY_DIR})

# On ELF systems there is no need for   the  modules to link against the
# core system. Dropping this has two advantages: the result is easier to
# relocate and building  the  packages  can   for  a  large  part happen
# concurrently with the main system.

if(CMAKE_EXECUTABLE_FORMAT STREQUAL "ELF")
  set(SWIPL_LIBRARIES "")
else()
  set(SWIPL_LIBRARIES libswipl)
endif()

# swipl_plugin(name
#	       [MODULE name]
#	       [C_SOURCES file ...]
#	       [C_LIBS lib ...]
#	       [C_INCLUDE_DIR dir ...]
#	       [PL_GENERATED_LIBRARIES ...]
#	       {[PL_LIB_SUBDIR subdir]
#	           [PL_LIBS file ...])}*
#
# Define a plugin. A  plugin  consists   optionally  of  a shared object
# (module) and a number of Prolog sources  that must be installed in the
# library or a subdirectory thereof. It   creates  a target ${name} that
# creates the shared object, make sure  the Prolog sources are installed
# in our shadow home and the `install` target is extended to install the
# module and Prolog files.
#
# A SWI-Prolog package (directory under `packages`) may provide multiple
# plugins.

function(swipl_plugin name)
  set(target ${name})
  set(type MODULE)
  set(v_module ${name})
  set(v_c_sources)
  set(v_c_libs)
  set(v_c_include_dirs)
  set(v_pl_subdir)			# current subdir
  set(v_pl_subdirs)			# list of subdirs
  set(v_pl_gensubdirs)			# list of subdirs (generated files)

  add_custom_target(${target})

  set(mode)

  foreach(arg ${ARGN})
    if(arg STREQUAL "MODULE")
      set(mode module)
    elseif(arg STREQUAL "SHARED")
      set(mode module)
      set(type SHARED)
    elseif(arg STREQUAL "C_SOURCES")
      set(mode c_sources)
    elseif(arg STREQUAL "THREADED")
      set(v_c_libs ${v_c_libs} ${CMAKE_THREAD_LIBS_INIT})
    elseif(arg STREQUAL "C_LIBS")
      set(mode c_libs)
    elseif(arg STREQUAL "C_INCLUDE_DIR")
      set(mode c_include_dirs)
    elseif(arg STREQUAL "PL_LIB_SUBDIR")
      set(mode pl_lib_subdir)
    elseif(mode STREQUAL "pl_lib_subdir")
      set(v_pl_subdir ${arg})
      set(mode after_subdir)
    elseif(mode STREQUAL after_subdir)
      if(arg STREQUAL "PL_LIBS")
	set(v_pl_subdirs ${v_pl_subdirs} "@${v_pl_subdir}")
	string(REPLACE "/" "_" subdir_var "v_pl_subdir_${v_pl_subdir}")
	set(${subdir_var})
      elseif(arg STREQUAL "PL_GENERATED_LIBRARIES")
	set(v_pl_gensubdirs ${v_pl_gensubdirs} "@${v_pl_subdir}")
	string(REPLACE "/" "_" subdir_var "v_pl_gensubdir_${v_pl_subdir}")
	set(${subdir_var})
      else()
        message(FATAL_ERROR "PL_LIB_SUBDIR must be followed by \
	                     PL_LIBS or PL_GENERATED_LIBRARIES")
      endif()
      set(mode pl_files)
    elseif(arg STREQUAL "PL_LIBS")
      set(v_pl_subdirs ${v_pl_subdirs} "@${v_pl_subdir}")
      string(REPLACE "/" "_" subdir_var "v_pl_subdir_${v_pl_subdir}")
      set(${subdir_var})
      set(mode pl_files)
    elseif(arg STREQUAL "PL_GENERATED_LIBRARIES")
      set(v_pl_gensubdirs ${v_pl_gensubdirs} "@${v_pl_subdir}")
      string(REPLACE "/" "_" subdir_var "v_pl_gensubdir_${v_pl_subdir}")
      set(${subdir_var})
      set(mode pl_files)
    elseif(mode STREQUAL "pl_files")
      set(${subdir_var} ${${subdir_var}} ${arg})
    elseif(mode STREQUAL "module")
      set(v_module ${arg})
    else()
      set(v_${mode} ${v_${mode}} ${arg})
    endif()
  endforeach()

  if(v_c_sources)
    set(foreign_target "plugin_${v_module}")
    add_library(${foreign_target} ${type} ${v_c_sources})
    set_target_properties(${foreign_target} PROPERTIES
			  OUTPUT_NAME ${v_module} PREFIX "")
    target_compile_options(${foreign_target} PRIVATE -D__SWI_PROLOG__)
    target_link_libraries(${foreign_target} PRIVATE
			  ${v_c_libs} ${SWIPL_LIBRARIES})
    if(v_c_include_dirs)
      target_include_directories(${foreign_target} BEFORE PRIVATE
				 ${v_c_include_dirs})
    endif()
    add_dependencies(${target} ${foreign_target})

    install(TARGETS ${foreign_target}
	    LIBRARY DESTINATION ${SWIPL_INSTALL_MODULES})
  endif()

  foreach(sd ${v_pl_subdirs})
    string(REPLACE "@" "" sd "${sd}")
    string(REPLACE "/" "_" subdir_var "v_pl_subdir_${sd}")
    if(${subdir_var})
      string(REPLACE "/" "_" src_target "plugin_${name}_${sd}_pl_libs")
      install_src(${src_target}
		  FILES ${${subdir_var}}
		  DESTINATION ${SWIPL_INSTALL_LIBRARY}/${sd})
      add_dependencies(${target} ${src_target})
    endif()
  endforeach()

  foreach(sd ${v_pl_gensubdirs})
    string(REPLACE "@" "" sd "${sd}")
    string(REPLACE "/" "_" subdir_var "v_pl_gensubdir_${sd}")
    if(${subdir_var})
      prepend(_genlibs ${CMAKE_CURRENT_BINARY_DIR}/ ${${subdir_var}})
      string(REPLACE "/" "_" src_target "plugin_${name}_${sd}_pl_libs")
      install(FILES ${_genlibs}
	      DESTINATION ${SWIPL_INSTALL_LIBRARY}/${sd})
    endif()
  endforeach()
endfunction(swipl_plugin)

# install_dll(file ...)
#
# Install support DLL files.  This function is normally passes the link
# library used to build the dll.  It determines the dll from this link
# library and copies this both to the current binary and final installation
# tree.

function(install_dll)
if(WIN32)
  set(dlls)

  foreach(lib ${ARGN})
    set(dll)

    if(lib MATCHES "\\.lib$")
      string(REPLACE ".lib" ".dll" dll ${lib})
    elseif(lib MATCHES "\\.dll$")
      set(dll ${lib})
    elseif(lib MATCHES "\\.dll\\.a$")
      string(REPLACE ".dll.a" ".la" la ${lib})
      if(EXISTS ${la})
	file(READ ${la} la_content)
	string(REGEX MATCH "dlname='[-._a-zA-Z/0-9]*'" line ${la_content})
	string(REGEX REPLACE "^dlname='(.*)'" "\\1" dlname ${line})
	get_filename_component(dir ${lib} DIRECTORY)
	get_filename_component(dll ${dir}/${dlname} ABSOLUTE)
      else()
        get_filename_component(base ${lib} NAME_WE)
        file(STRINGS ${lib} dlname REGEX "${base}.*\\.dll$")
	get_filename_component(dir ${lib} DIRECTORY)
	get_filename_component(dll ${dir}/../bin/${dlname} ABSOLUTE)
      endif()
    endif()
    if(dll)
      set(dlls ${dlls} ${dll})
    else()
      message("Could not find DLL from ${lib}")
    endif()
  endforeach()

  file(COPY ${dlls}
       DESTINATION ${CMAKE_BINARY_DIR}/src)
  install(FILES ${dlls}
	  DESTINATION ${SWIPL_INSTALL_ARCH_EXE})
endif()
endfunction()

# swipl_examples(file ... [SUBDIR dir])
#
# Install the examples

function(swipl_examples)
  set(mode mfiles)
  set(files)
  set(dirs)
  set(subdir)
  set(subdir_)

  foreach(arg ${ARGN})
    if(arg STREQUAL "SUBDIR")
      set(mode msubdir)
    elseif(arg STREQUAL "FILES")
      set(mode mfiles)
    elseif(arg STREQUAL "DIRECTORIES")
      set(mode mdirectories)
    elseif(mode STREQUAL "msubdir")
      set(subdir ${arg})
    elseif(mode STREQUAL "mfiles")
      set(files ${files} ${arg})
    elseif(mode STREQUAL "mdirectories")
      set(dirs ${dirs} ${arg})
    endif()
  endforeach()

  set(extdest ${SWIPL_INSTALL_PREFIX}/doc/packages/examples/${SWIPL_PKG})
  if(subdir)
    set(extdest ${extdest}/${subdir})
    set(subdir_ ${subdir}_)
  endif()

  get_filename_component(pkg ${CMAKE_CURRENT_SOURCE_DIR} NAME)

  if(files)
    install_src(plugin_${pkg}_${subdir_}example_files
		FILES ${files} DESTINATION ${extdest}
	        COMPONENT Examples)
  endif()
  if(dirs)
    install_src(plugin_${pkg}_${subdir_}example_dirs
		DIRECTORY ${dirs} DESTINATION ${extdest}
		COMPONENT Examples)
  endif()
endfunction()

# test_lib(name
#	   [PACKAGES ...]
#	   [PARENT_LIB])
#
# Run test_${name} in test_${name}.pl

if(NOT SWIPL_PATH_SEP)
  set(SWIPL_PATH_SEP ":")
endif()

function(test_lib name)
  cmake_parse_arguments(my "PARENT_LIB" "NAME" "PACKAGES" ${ARGN})
  set(test_goal "test_${name}")
  set(test_source "${CMAKE_CURRENT_SOURCE_DIR}/test_${name}.pl")

  if(my_NAME)
    set(test_name ${my_NAME})
  else()
    set(test_name ${name})
  endif()

  foreach(pkg ${my_PACKAGES})
    get_filename_component(src ${CMAKE_CURRENT_SOURCE_DIR}/../${pkg} ABSOLUTE)
    get_filename_component(bin ${CMAKE_CURRENT_BINARY_DIR}/../${pkg} ABSOLUTE)
    set(plibrary "${plibrary}${SWIPL_PATH_SEP}${src}")
    set(pforeign "${pforeign}${SWIPL_PATH_SEP}${bin}")
  endforeach()

  add_test(NAME "${SWIPL_PKG}:${test_name}"
	   COMMAND swipl -p "foreign=${pforeign}"
			 -p "library=${plibrary}"
			 -f none -s ${test_source}
			 -g "${test_goal}"
			 -t halt)
endfunction(test_lib)

# test_libs(name ...
#	    [PACKAGES package ...]
#	    [PARENT_LIB])

function(test_libs)
  set(mode tests)
  set(tests)
  set(packages)
  set(extra)

  foreach(arg ${ARGN})
    if(arg STREQUAL "PACKAGES")
      set(mode "packages")
    elseif(arg STREQUAL "PARENT_LIB")
      set(extra PARENT_LIB)
    else()
      set(${mode} ${${mode}} ${arg})
    endif()
  endforeach()

  foreach(test ${tests})
    test_lib(${test} PACKAGES ${packages} ${extra})
  endforeach()
endfunction(test_libs)

# Documentation support
include(PackageDoc)