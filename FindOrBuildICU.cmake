include(CMakeParseArguments)
include(ExternalProject)

set(FIND_OR_BUILD_ICU_DIR ${CMAKE_CURRENT_LIST_DIR})

# Searches the system using find_package for an ICU version that is greater
# or equal to the minimum version specified via the VERSION argument to the
# function. If find_package does not find a suitable version, ICU is added
# as an external project to be downloaded form the specified URL and
# validated with the specified URL_HASH.

# The function creates an interface library "icu" that should be linked
# against by code that wishes to use ICU headers or ICU library functions.
# The library target added should ensure that transitive dependencies are
# satisfied.
#
# This function requires at least CMake version 3.2.0 for the
# BUILD_BYPRODUCTS argument to ExternalProject_Add
function(FindOrBuildICU)
  cmake_parse_arguments(FindOrBuildICU "" "VERSION;URL;URL_HASH" "" ${ARGN})

  if (NOT FindOrBuildICU_VERSION)
    message(FATAL_ERROR "You must provide a minimum version")
  endif()

  if (NOT FindOrBuildICU_URL)
    message(FATAL_ERROR "You must provide a download url to the ICU sources")
  endif()

  message("-- Searching for ICU ${FindOrBuildICU_VERSION}")

  find_package(ICU ${FindOrBuildICU_VERSION} COMPONENTS data i18n uc)

  if (NOT ICU_VERSION OR NOT ICU_VERSION VERSION_EQUAL "${FindOrBuildICU_VERSION}")
    # for some reason, ICU_FOUND seems to always be set...
    if (NOT ICU_VERSION)
      message("-- ICU not found; attempting to build it...")
    else()
      message("-- ICU version found is ${ICU_VERSION}, expected ${FindOrBuildICU_VERSION}; attempting to build ICU from scratch...")
    endif()
    if (WIN32 AND NOT MINGW)
      # not going to attempt to build ICU if we're on Windows for now
      # probably could, but it's more trouble than it's worth I think
      message("-- ICU building not supported on Windows.")
      message(FATAL_ERROR "   -- Please download the latest ICU binaries from http://site.icu-project.org/download")
    elseif(UNIX OR MINGW)

      # determine platform for runConfigureICU
      if (APPLE)
        set(ICU_PLATFORM "MacOSX")
      elseif(MINGW)
        set(ICU_PLATFORM "MinGW")
      else()
        set(ICU_PLATFORM "Linux")
      endif()

      # if we're compling with position independent code, force ICU to do
      # so as well
      if (CMAKE_POSITION_INDEPENDENT_CODE)
        set(ICU_CFLAGS "-fPIC")
        set(ICU_CXXFLAGS "-fPIC")
      endif()

      # determine a reasonable number of threads to build ICU with
      include(ProcessorCount)
      ProcessorCount(CORES)
      if (NOT CORES EQUAL 0)
        # limit the number of cores to 4 on travis
        if (CORES GREATER 4)
          if ($ENV{TRAVIS})
            set(CORES 4)
          endif()
        endif()
        set(ICU_MAKE_EXTRA_FLAGS "-j${CORES}")
      endif()

      set(ICU_EP_PREFIX ${PROJECT_SOURCE_DIR}/deps/icu)

      if (MINGW)
        set(ICU_EP_LIBICUDATA ${ICU_EP_PREFIX}/lib/sicudt.a)
        set(ICU_EP_LIBICUI18N ${ICU_EP_PREFIX}/lib/libsicuin.a)
        set(ICU_EP_LIBICUUC ${ICU_EP_PREFIX}/lib/libsicuuc.a)
        set(ICU_EP_PATCH_COMMAND patch -p0 -i ${FIND_OR_BUILD_ICU_DIR}/msys-mkinstalldirs.patch)
      else()
        set(ICU_EP_LIBICUDATA ${ICU_EP_PREFIX}/lib/libicudata.a)
        set(ICU_EP_LIBICUI18N ${ICU_EP_PREFIX}/lib/libicui18n.a)
        set(ICU_EP_LIBICUUC ${ICU_EP_PREFIX}/lib/libicuuc.a)
        set(ICU_EP_PATCH_COMMAND "")
      endif()

      ExternalProject_Add(ExternalICU
        PREFIX ${ICU_EP_PREFIX}
        URL ${FindOrBuildICU_URL}
        URL_HASH ${FindOrBuildICU_URL_HASH}
        PATCH_COMMAND ${ICU_EP_PATCH_COMMAND}
        CONFIGURE_COMMAND CC=${CMAKE_C_COMPILER} CXX=${CMAKE_CXX_COMPILER} CFLAGS=${ICU_CFLAGS} CXXFLAGS=${ICU_CXXFLAGS} ${ICU_EP_PREFIX}/src/ExternalICU/source/runConfigureICU ${ICU_PLATFORM}
        --disable-shared --enable-static --disable-dyload --disable-extras
        --disable-tests --disable-samples
        --prefix=<INSTALL_DIR>
        BUILD_COMMAND make ${ICU_MAKE_EXTRA_FLAGS}
        INSTALL_COMMAND make install
        BUILD_BYPRODUCTS ${ICU_EP_LIBICUDATA};${ICU_EP_LIBICUI18N};${ICU_EP_LIBICUUC}
      )
      set(ICU_INCLUDE_DIRS ${ICU_EP_PREFIX}/include)

      add_library(icudata IMPORTED STATIC)
      set_target_properties(icudata PROPERTIES IMPORTED_LOCATION
        ${ICU_EP_LIBICUDATA})
      add_dependencies(icudata ExternalICU)

      add_library(icui18n IMPORTED STATIC)
      set_target_properties(icui18n PROPERTIES IMPORTED_LOCATION
        ${ICU_EP_LIBICUI18N})
      add_dependencies(icui18n ExternalICU)

      add_library(icuuc IMPORTED STATIC)
      set_target_properties(icuuc PROPERTIES IMPORTED_LOCATION
        ${ICU_EP_LIBICUUC})
      add_dependencies(icuuc ExternalICU)

      set(ICU_LIBRARIES icui18n icuuc icudata)
      set(ICU_IS_EXTERNAL TRUE)
    else()
      message(FATAL_ERROR "-- ICU building not supported for this platform")
    endif()
  endif()

  message("-- ICU include dirs: ${ICU_INCLUDE_DIRS}")
  message("-- ICU libraries: ${ICU_LIBRARIES}")

  add_library(icu INTERFACE)
  if (ICU_IS_EXTERNAL)
    file(MAKE_DIRECTORY ${ICU_INCLUDE_DIRS})
  endif()
  target_link_libraries(icu INTERFACE ${ICU_LIBRARIES})
  target_include_directories(icu SYSTEM INTERFACE ${ICU_INCLUDE_DIRS})
endfunction()
