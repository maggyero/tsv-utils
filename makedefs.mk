# This makefile (makedefs.mk) is included by the subdirectory makefiles. eg. Included by
# the tsv-arrange/makefile. It establishes the basic definitions used across the project.
# An executable typically includes this file, adds any shared files used to the
# 'common_srcs' variable, and includes the makeapp.mk include. See the app makefiles for
# examples. The 'common' subdirectory makefile also includes this, but has it's own
# makefile targets.
#
# This makefile can be customized by setting the DCOMPILER, DFLAGS, LDC_LTO,
# LDC_BUILD_RUNTIME, and LDC_PGO variables. These can also be set on the make command line.
#
# - DCOMPILER - path to the D compiler to use. Should include one of 'dmd', 'ldc', or
#   'gdc' in the compiler name.
# - DFLAGS - Passed to the compiler on the command line.
# - LDC_LTO - One of 'thin', 'full', 'off', or 'default'. An empty or undefined value
#   is treated as 'default'. It is only used if DCOMPILER specifies an ldc compiler.
# - LDC_LTO_RUNTIME - Turns on LTO for the runtime libraries (phobos, druntime). This is
#   an alternative to LDC_BUILD_RUNTIME available starting with LDC 1.9. It uses LTO
#   with LDC rather than downloading the library source and building.
# - LDC_BUILD_RUNTIME - Used to enable building the druntime and phobos runtime libraries
#   using LTO. If set to '1', builds the runtimes using the 'ldc-build-runtime' tool.
#   Otherwise is expected to be a path to the tool. Available starting with ldc 1.5.
# - LDC_PGO - If set to '1', uses the file at ./profile_data/app.profdata to profile
#   instrumented profile data. At present PGO is only enabled for LDC release builds
#   where LDC_LTO_RUNTIME or LDC_BUILD_RUNTIME is also used. Normally this variable is
#   set in the makefile of tools that have been setup for LTO.
#
# Current LTO defaults when using LDC:
# - OS X: thin
# - OS X, LDC_LTO_RUNTIME or LDC_BUILD_RUNTIME: thin
# - Linux: off
# - Linux, LDC_LTO_RUNTIME: thin
# - Linux, LDC_BUILD_RUNTIME: full
#
# NOTE: Due to https://github.com/ldc-developers/ldc/issues/2208, LTO is only
# on OS X in release mode. Issue seen in LDC 1.5.0-beta1 with tsv-filter.

DCOMPILER =
DFLAGS =
LDC_HOME =
LDC_LTO =
LDC_LTO_RUNTIME = 
LDC_BUILD_RUNTIME =
LDC_PGO =
LDC_PGO_TYPE ?= AST

## Directory and file paths

project_dir ?= $(realpath ..)
tsv_utils_pkg_name = tsv_utils
common_srcdir = $(project_dir)/common/src/$(tsv_utils_pkg_name)/common
project_bindir = $(project_dir)/bin
buildtools_dir = $(project_dir)/buildtools
diff_test_result_dirs = $(buildtools_dir)/diff-test-result-dirs
ldc_runtime_thin_dir = $(project_dir)/ldc-build-runtime.thin
ldc_runtime_full_dir = $(project_dir)/ldc-build-runtime.full
objdir = obj
bindir = bin
testsdir = tests
ldc_profile_data_dir = profile_data
ldc_profdata_file = $(ldc_profile_data_dir)/app.profdata
ldc_profdata_collect_prog = collect_profile_data.sh

# This is set to $(ldc_profdata_file) if the app is being built with
# PGO. It is intended as a make target.
app_ldc_profdata_file =

OS_NAME := $(shell uname -s)

## Identify the compiler as dmd, ldc, or gdc

compiler_type =

ifndef DCOMPILER
	DCOMPILER = dmd
	compiler_type = dmd
else
	compiler_name = $(notdir $(basename $(DCOMPILER)))

	ifeq ($(compiler_name),dmd)
		compiler_type = dmd
	else ifeq ($(compiler_name),ldc)
		compiler_type = ldc
	else ifeq ($(compiler_name),ldc2)
		compiler_type = ldc
	else ifeq ($(compiler_name),gdc)
		compiler_type = gdc
	else ifeq ($(findstring dmd,$(compiler_name)),dmd)
		compiler_type = dmd
	else ifeq ($(findstring ldc,$(compiler_name)),ldc)
		compiler_type = ldc
	else ifeq ($(findstring gdc,$(compiler_name)),gdc)
		compiler_type = gdc
	else
		compiler_type = dmd
	endif
endif

## Make sure compiler_type was set to something legitimate.
ifneq ($(compiler_type),dmd)
	ifneq ($(compiler_type),ldc)
		ifneq ($(compiler_type),gdc)
                        ## Note: Spaces not tabs on the error function line.
                        $(error "Internal error. Invalid compiler_type value: '$(compiler_type)'. Must be 'dmd', 'ldc', or 'gdc'.")
		endif
	endif
endif

ifneq ($(compiler_type),ldc)
	ifneq ($(LDC_LTO),)
                $(error "Non-LDC compiler detected ($(compiler_type)) and LDC_LTO parameter set: '$(LDC_LTO)'.")
	endif
	ifneq ($(LDC_LTO_RUNTIME),)
                $(error "Non-LDC compiler detected ($(compiler_type)) and LDC_LTO_RUNTIME parameter set: '$(LDC_LTO_RUNTIME)'.")
	endif
	ifneq ($(LDC_BUILD_RUNTIME),)
                $(error "Non-LDC compiler detected ($(compiler_type)) and LDC_BUILD_RUNTIME parameter set: '$(LDC_BUILD_RUNTIME)'.")
	endif
endif

## Variables used for LDC LTO. These get updated when using the LDC compiler
##   ldc_version - Version number reported by the LDC compiler eg: 1.5.0, 1.7.0-beta1
##   ldc_build_runtime_tool - Path to the ldc-build-runtime tool
##   ldc_build_runtime_dir - Directory for the runtime (ldc-build-runtime.[thin|full].<version>)
##   ldc_build_runtime_dflags - Flags passed to ldc-build-runtime tool. eg. -flto=[thin|full]
##   ldc_lto_with_runtime_libs - Set to 1 if either LDC_LTO_RUNTIME or LDC_BUILD_RUNTUME is 1.
##   lto_option - LTO option passed to ldc (-flto=[thin|full).
##   lto_release_option - LTO option passed to ldc (-flto=[thin|full) on release builds.
##   lto_link_flags - Additional linker flags to pass to compiler. Examples:
##       * LTO with supplied runtime libs (LDC_LTO_RUNTIME): -defaultlib=phobos2-ldc-lto,druntime-ldc-lto
##       * LTO with build-runtime libs (LDC_BUILD_RUNTIME): -L-L$(ldc_build_runtime_dir)/lib -linker=gold
##       * LTO without runtime libs: -linker=gold
##   pgo_link_flags - Additional linker flags to pass to the compiler. eg. -fprofile-use=...
##   pgo_generate_link_flags - Additional linker flags when generating an instrumented build
##       eg. -fprofile-generate=...

ldc_version =
ldc_build_runtime_tool =
ldc_build_runtime_dir = ldc-build-runtime.off
ldc_build_runtime_dflags =
ldc_lto_with_runtime_libs =
lto_option =
lto_release_option =
lto_link_flags =
pgo_link_flags =
pgo_generate_link_flags =

## If using LDC, setup all the parameters

ifeq ($(compiler_type),ldc)
	# if LDC_HOME was provided, update the compiler path
	ifneq ($(LDC_HOME),)
		override DCOMPILER := $(LDC_HOME)/bin/$(DCOMPILER)
	endif

	# Set the compiler version
	ldc_version = $(shell $(DCOMPILER) --version | head -n 1 | sed s'/^LDC.*( *//' | sed s'/):* *$$//' )
	ifeq ($(ldc_version),)
		ldc_version = unknown
	endif

	# Get the major and minor form of the version number
	ldc_version_major_minor = $(shell $(DCOMPILER) --version | head -n 1 | sed s'/^LDC.*( *//' | sed s'/\.[[:digit:]][-[:digit:][:alnum:]]*):* *$$//' )
	ifeq ($(ldc_version_major_minor),)
		ldc_version_major_minor = unknown
	endif

	# Update/validate the LDC_LTO parameter
	ifeq ($(LDC_LTO),)
		override LDC_LTO = default
	endif

	ifneq ($(LDC_LTO),default)
		ifneq ($(LDC_LTO),thin)
			ifneq ($(LDC_LTO),full)
				ifneq ($(LDC_LTO),off)
                                    $(error "Invalid LDC_LTO value: '$(LDC_LTO)'. Must be 'thin', 'full', 'off', 'default', or empty.")
				endif
			endif
		endif
	endif

	ifneq ($(LDC_LTO_RUNTIME),)
		ifneq ($(LDC_LTO_RUNTIME),1)
                        $(error "Invalid LDC_LTO_RUNTIME flag: '$(LDC_LTO_RUNTIME)'. Must be '1' or not set.")
		endif
		ifeq ($(LDC_LTO),off)
                     $(error "LDC_LTO value 'off' inconsistent with LDC_LTO_RUNTIME value '$(LDC_LTO_RUNTIME)'")
		endif
		ldc_lto_with_runtime_libs = 1
	endif

	ifneq ($(LDC_BUILD_RUNTIME),)
		ifneq ($(LDC_BUILD_RUNTIME),1)
                        $(error "Invalid LDC_BUILD_RUNTIME flag: '$(LDC_BUILD_RUNTIME)'. Must be '1' or not set.")
		endif
		ifeq ($(LDC_LTO),off)
                     $(error "LDC_LTO value 'off' inconsistent with LDC_BUILD_RUNTIME value '$(LDC_BUILD_RUNTIME)'")
		endif
		ldc_lto_with_runtime_libs = 1
	endif

	# Set the ldc-build-tool path and select the LDC_LTO default

	ldc_build_runtime_tool_name = ldc-build-runtime
	ldc_build_runtime_tool = $(ldc_build_runtime_tool_name)

	ifneq ($(LDC_HOME),)
		ldc_build_runtime_tool = $(LDC_HOME)/bin/$(ldc_build_runtime_tool_name)
	endif

	ifneq ($(ldc_lto_with_runtime_libs),)
		ifeq ($(LDC_LTO),default)
			ifeq ($(OS_NAME),Darwin)
				override LDC_LTO = thin
			else ifeq ($(LDC_LTO_RUNTIME),1)
				override LDC_LTO = thin
			else
				override LDC_LTO = full
			endif
		endif
		ifneq ($(LDC_PGO),)
			ifneq ($(LDC_PGO),1)
				ifneq ($(LDC_PGO),2)
                                        $(error "Invalid LDC_PGO flag: '$(LDC_PGO)'. Must be '1', '2', or not set.")
				endif
			endif
			ifneq ($(APP_USES_LDC_PGO),)
				this_app_uses_pgo=0
				ifeq ($(APP_USES_LDC_PGO),1)
					this_app_uses_pgo=1
				else ifeq ($(APP_USES_LDC_PGO),2)
					ifeq ($(LDC_PGO),2)
						this_app_uses_pgo=1
					endif
				else ifneq ($(APP_USES_LDC_PGO),1)
					ifneq ($(APP_USES_LDC_PGO),2)
                                                $(error "Invalid APP_USES_LDC_PGO flag: '$(APP_USES_LDC_PGO)'. Must be '1', '2', or not set. (Usually set in makefile.)"")
					endif
				endif
				ifeq ($(this_app_uses_pgo),1)
					pgo_qualifier =
					ifeq ($(LDC_PGO_TYPE),AST)
						pgo_qualifier = -instr
					else ifneq ($(LDC_PGO_TYPE),IR)
                                                $(error "Invalid LDC_PGO_TYPE flag: '$(LDC_PGO_TYPE)'. Must be 'AST' or 'IR' or not set.")
					endif

					pgo_link_flags = -fprofile$(pgo_qualifier)-use=$(ldc_profdata_file)
					pgo_generate_link_flags = -fprofile$(pgo_qualifier)-generate=profile.%p.raw
					app_ldc_profdata_file = $(ldc_profdata_file)
				endif
			endif
		endif
	else ifeq ($(LDC_LTO),default)
		ifeq ($(OS_NAME),Darwin)
			override LDC_LTO = thin
		else
			override LDC_LTO = off
		endif
	endif

	# Ensure LDC_LTO is set correctly. Either thin, full, or off at this point.

	ifneq ($(LDC_LTO),thin)
		ifneq ($(LDC_LTO),full)
			ifneq ($(LDC_LTO),off)
                                $(error "Internal error. Invalid LDC_LTO value: '$(LDC_LTO)'. Must be 'thin', 'full', or 'off' at this line.")
			endif
		endif
	endif

	# Update the ldc_build_runtime_dir name.

	ifeq ($(LDC_LTO),thin)
		ldc_build_runtime_dir = $(ldc_runtime_thin_dir).v-$(ldc_version)
	else ifeq ($(LDC_LTO),full)
		ldc_build_runtime_dir = $(ldc_runtime_full_dir).v-$(ldc_version)
	endif

	# Set the LTO compile/link options

	ifneq ($(LDC_LTO),off)
		lto_option = -flto=$(LDC_LTO)
		lto_release_option = -flto=$(LDC_LTO)
	endif

	ifeq ($(OS_NAME),Darwin)
		ldc_build_runtime_dflags = -flto=$(LDC_LTO)
	else
		ldc_build_runtime_dflags = -flto=$(LDC_LTO)
	endif

	ifneq ($(LDC_LTO_RUNTIME),)
		lto_link_flags = -defaultlib=phobos2-ldc-lto,druntime-ldc-lto -link-defaultlib-shared=false
	else ifneq ($(LDC_BUILD_RUNTIME),)
		ifeq ($(OS_NAME),Darwin)
			lto_link_flags = -L-L$(ldc_build_runtime_dir)/lib
		else
			lto_link_flags = -L-L$(ldc_build_runtime_dir)/lib -linker=gold
		endif
	else ifneq ($(LDC_LTO),off)
		ifneq ($(OS_NAME),Darwin)
			lto_link_flags = -linker=gold
		endif
	endif
endif

## Done with the LDC LTO setting. Now the general compile/link settings.

debug_compile_flags_base =
release_compile_flags_base = -release -O
debug_link_flags_base =
release_link_flags_base =
release_instrumented_link_flags_base =

ifeq ($(compiler_type),dmd)
	release_compile_flags_base = -release -O -boundscheck=off -inline
else ifeq ($(compiler_type),ldc)
	# NOTE: Due to https://github.com/ldc-developers/ldc/issues/2208, only
	# use LTO on OS X in release mode. Issue seen in LDC 1.5.0-beta1 with tsv-filter.
	ifneq ($(OS_NAME),Darwin)
		debug_compile_flags_base = $(lto_option)
		debug_link_flags_base = $(lto_link_flags)
	endif
	# Compile flags currently the same for instrumented and final build. May need to separate
	# in the future for IR-PGO. See: https://github.com/ldc-developers/ldc/issues/2582
	release_compile_flags_base = -release -O3 -boundscheck=off -singleobj $(lto_release_option)
	release_instrumented_compile_flags_base = -release -O3 -boundscheck=off -singleobj $(lto_release_option)
	release_link_flags_base = $(pgo_link_flags) $(lto_link_flags)
	release_instrumented_link_flags_base = $(pgo_generate_link_flags) $(lto_link_flags)
endif

##
## These are the key variables used in makeapp.mk
###
debug_flags = $(debug_compile_flags_base) -od$(objdir) $(debug_link_flags_base) $(DFLAGS)
release_flags = $(release_compile_flags_base) -od$(objdir) $(release_link_flags_base) $(DFLAGS)
release_instrumented_flags =  $(release_instrumented_compile_flags_base) -od$(objdir) -d-version=LDC_PROFILE $(release_instrumented_link_flags_base) $(DFLAGS)
unittest_flags = $(DFLAGS) -unittest -main -run
codecov_flags = -od$(objdir) $(DFLAGS) -cov
unittest_codecov_flags = -od$(objdir) $(DFLAGS) -cov -unittest -main -run
