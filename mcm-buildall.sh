#!/bin/bash

# static linked i686 binaries are basically "poor man's x32".
BOOTSTRAP=i686-linux-musl

# Script to build all supported cross and native compilers using
# https://github.com/richfelker/musl-cross-make

[ -z "$OUTPUT" ] && OUTPUT="$PWD/output"

make_toolchain()
{
  # Change title bar
  echo -en "\033]2;$TARGET-$TYPE\007"

  # Set cross compiler path
  LP="$PATH"
  if [ -z "$TYPE" ]
  then
    OUTPUT="$PWD/host-$TARGET"
    EXTRASUB=y
  else
    if [ "$TYPE" == static ]
    then
      HOST=$BOOTSTRAP
      [ "$TARGET" = "$HOST" ] && LP="$PWD/host-$HOST/bin:$LP"
      TYPE=cross
      EXTRASUB=y
    else
      HOST="$TARGET"
      export NATIVE=y
    fi
    LP="$OUTPUT/$HOST-cross/bin:$LP"
    COMMON_CONFIG="CC=\"$HOST-gcc -static --static\" CXX=\"$HOST-g++ -static --static\""
    export -n HOST
    OUTPUT="$OUTPUT/$TARGET-$TYPE"
  fi

  [ -e "$OUTPUT/bin/"*ld ] && return

  rm -rf build/"$TARGET" &&
  if [ -z "$CPUS" ]
  then
    CPUS="$(nproc)"
    [ "$CPUS" != 1 ] && CPUS=$(($CPUS+1))
  fi
  set -x &&
  PATH="$LP" make OUTPUT="$OUTPUT" TARGET="$TARGET" \
    GCC_CONFIG="--disable-nls --disable-libquadmath --disable-decimal-float $GCC_CONFIG" COMMON_CONFIG="$COMMON_CONFIG" \
    install -j$CPUS || exit 1
  set +x
  echo -e '#ifndef __MUSL__\n#define __MUSL__ 1\n#endif' \
    >> "$OUTPUT/${EXTRASUB:+$TARGET/}include/features.h"
}

# Expand compressed target into binutils/gcc "tuple" and call make_toolchain
make_tuple()
{
  PART1=${1/:*/}
  PART3=${1/*:/}
  PART2=${1:$((${#PART1}+1)):$((${#1}-${#PART3}-${#PART1}-2))}

  for j in static native
  do
    echo === building $PART1
    set -o pipefail
    TYPE=$j TARGET=${PART1}-linux-musl${PART2} GCC_CONFIG="$PART3" \
      make_toolchain 2>&1 | tee "$OUTPUT"/log/${PART1}-${j}.log
    [ $? -ne 0 ] && exit 1
  done
}

if [ -z "$NOCLEAN" ]
then
  rm -rf build
  [ $# -eq 0 ] && rm -rf "$OUTPUT" host-* *.log
fi
mkdir -p "$OUTPUT"/log

# Make bootstrap compiler (no $TYPE, dynamically linked against host libc)
# We build the rest of the cross compilers with this so they're linked against
# musl-libc, because glibc doesn't fully support static linking and dynamic
# binaries aren't really portable between distributions
TARGET=$BOOTSTRAP make_toolchain 2>&1 | tee -a i686-host.log

# Without this i686-static build reuses the dynamically linked host build files.
[ -z "$NOCLEAN" ] && make clean

if [ $# -gt 0 ]
then
  rm -rf build
  for i in "$@"
  do
    make_tuple "$i"
  done
else
  for i in i686:: m68k:: x86_64:: x86_64:x32: sh4::--enable-incomplete-targets \
         armv5l:eabihf:--with-arch=armv5t armv7l:eabihf:--with-arch=armv7-a \
         "armv7m:eabi:--with-arch=armv7-m --with-mode=thumb --disable-libatomic --enable-default-pie" \
         armv7r:eabihf:"--with-arch=armv7-r --enable-default-pie" \
         aarch64:eabi: i486:: sh2eb:fdpic:--with-cpu=mj2 s390x:: mipsel:: \
         mips:: powerpc:: microblaze:: mips64:: powerpc64:: powerpc64le::
  do
    make_tuple "$i"
  done
fi
