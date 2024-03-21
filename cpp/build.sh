#!/usr/bin/env bash

# Obtain the base directory this script resides in.
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "BASE_DIR=${BASE_DIR}"

# Useful constants
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_OFF="\033[0m"

function detect_platform() {
  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)     PLATFORM=Linux;;
      Darwin*)    PLATFORM=Mac;;
      Windows*)   PLATFORM=Windows;;
      *)          PLATFORM="UNKNOWN:${unameOut}"
  esac
  echo -e "${COLOR_GREEN}Detected platform: $PLATFORM ${COLOR_OFF}"
}

function build() {
  echo -e "${COLOR_GREEN}[ INFO ]Building backend ${COLOR_OFF}"
  MAYBE_BUILD_QUIC=""
  if [ "$WITH_QUIC" == true ] ; then
    setup_mvfst
    MAYBE_BUILD_QUIC="-DBUILD_QUIC=On"
  fi

  MAYBE_USE_STATIC_DEPS=""
  MAYBE_LIB_FUZZING_ENGINE=""
  MAYBE_BUILD_SHARED_LIBS=""
  MAYBE_BUILD_TESTS="-DBUILD_TESTS=ON"
  if [ "$NO_BUILD_TESTS" == true ] ; then
    MAYBE_BUILD_TESTS="-DBUILD_TESTS=OFF"
  fi

  if [ -z "$PREFIX" ]; then
    PREFIX=$BWD
  fi

  # Build torchserve_cpp with cmake
  cd "$BWD" || exit

  CMAKE_PREFIX_PATH=`python3 -c 'import torch;print(torch.utils.cmake_prefix_path)'`

  if [ "$PLATFORM" = "Linux" ]; then
    NCCL_PATH=`python3 -c 'import torch;from pathlib import Path;print(Path(torch.__file__).parents[1]/"nvidia"/"nccl"/"lib")'`
    export LD_LIBRARY_PATH=${NCCL_PATH}:${LD_LIBRARY_PATH}
    cmake                                                                                     \
    -DCMAKE_PREFIX_PATH="$DEPS_DIR;$CMAKE_PREFIX_PATH"                                                           \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"                                                          \
    "$MAYBE_BUILD_QUIC"                                                                       \
    "$MAYBE_BUILD_TESTS"                                                                      \
    "$MAYBE_BUILD_SHARED_LIBS"                                                                \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                                                               \
    "$MAYBE_USE_STATIC_DEPS"                                                                  \
    "$MAYBE_LIB_FUZZING_ENGINE"                                                               \
    ..

  elif [ "$PLATFORM" = "Mac" ]; then
    export LIBRARY_PATH=${LIBRARY_PATH}:`brew --prefix icu4c`/lib:`brew --prefix libomp`/lib

    cmake                                                                                     \
    -DCMAKE_PREFIX_PATH="$DEPS_DIR;$CMAKE_PREFIX_PATH"                                        \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"                                                          \
    "$MAYBE_BUILD_QUIC"                                                                       \
    "$MAYBE_BUILD_TESTS"                                                                      \
    "$MAYBE_BUILD_SHARED_LIBS"                                                                \
    "$MAYBE_OVERRIDE_CXX_FLAGS"                                                               \
    "$MAYBE_USE_STATIC_DEPS"                                                                  \
    "$MAYBE_LIB_FUZZING_ENGINE"                                                               \
    "-DLLAMA_METAL=OFF"                                                                       \
    ..


  else
    # TODO: Windows
    echo -e "${COLOR_RED}[ ERROR ] Unknown platform: $PLATFORM ${COLOR_OFF}"
    exit 1
  fi

  make -j "$JOBS"
  make install
  echo -e "${COLOR_GREEN}torchserve_cpp build is complete. To run unit test: \
  ./_build/test/torchserve_cpp_test ${COLOR_OFF}"

  cd $DEPS_DIR/../..
  if [ -f "$DEPS_DIR/../test/torchserve_cpp_test" ]; then
    $DEPS_DIR/../test/torchserve_cpp_test
  else
    echo -e "${COLOR_RED}[ ERROR ] _build/test/torchserve_cpp_test not exist ${COLOR_OFF}"
    exit 1
  fi
}

function install_torchserve_cpp() {
  TARGET_DIR=`python -c "import ts; from pathlib import Path; print(Path(ts.__file__).parent / 'cpp')"`

  if [ -d $TARGET_DIR ]; then
    rm -rf $TARGET_DIR
  fi
  mkdir $TARGET_DIR
  cp -rp $BASE_DIR/_build/bin $TARGET_DIR/bin
  cp -rp $BASE_DIR/_build/libs $TARGET_DIR/lib
  cp -rp $BASE_DIR/_build/resources $TARGET_DIR/resources
}

# Parse args
JOBS=8
WITH_QUIC=false
INSTALL_DEPENDENCIES=false
PREFIX=""
COMPILER_FLAGS=""
USAGE="./build.sh [-j num_jobs] [-q|--with-quic] [-t|--no-tets] [-p|--prefix] [-x|--compiler-flags]"
while [ "$1" != "" ]; do
  case $1 in
    -j | --jobs ) shift
                  JOBS=$1
                  ;;
    -q | --with-quic )
                  WITH_QUIC=true
                  ;;
    -t | --no-tests )
                  NO_BUILD_TESTS=true
      ;;
    -p | --prefix )
                  shift
                  PREFIX=$1
      ;;
    -x | --compiler-flags )
                  shift
                  COMPILER_FLAGS=$1
      ;;
    * )           echo $USAGE
                  exit 1
esac
shift
done

detect_platform

MAYBE_OVERRIDE_CXX_FLAGS=""
if [ -n "$COMPILER_FLAGS" ] ; then
  MAYBE_OVERRIDE_CXX_FLAGS="-DCMAKE_CXX_FLAGS=$COMPILER_FLAGS"
fi

BUILD_DIR=$BASE_DIR/_build
if [ ! -d "$BUILD_DIR" ] ; then
  mkdir -p $BUILD_DIR
fi

set -e nounset
trap 'cd $BASE_DIR' EXIT
cd $BUILD_DIR || exit
BWD=$(pwd)
DEPS_DIR=$BWD/_deps
LIBS_DIR=$BWD/libs
TR_DIR=$BWD/test/resources/
mkdir -p "$DEPS_DIR"
mkdir -p "$LIBS_DIR"
mkdir -p "$TR_DIR"

# Must execute from the directory containing this script
cd $BASE_DIR

git submodule update --init --recursive

build
install_torchserve_cpp
