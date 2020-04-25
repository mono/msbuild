#!/usr/bin/env bash

set -e

if [ $# -ne 2 ]; then
	echo "Usage: $0 <dotnet_runtime_nuget_version> <dest_dir>"
	exit 1
fi

DESTDIR=$2

ABSOLUTE_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
THIS_DIR=`dirname $ABSOLUTE_PATH`

source $THIS_DIR/../../eng/common/tools.sh

TMPDIR=`mktemp -d`
DOTNET_DIR=$TMPDIR/.dotnet

OLDCWD=`pwd`
cd $TMPDIR

GetDotNetInstallScript $TMPDIR
sh ./dotnet-install.sh --version $1 --install-dir $DOTNET_DIR --architecture x64 --runtime dotnet --skip-non-versioned-files
find $DOTNET_DIR -name libhostfxr.dylib | xargs -I {} cp -v {} $DESTDIR

cd $OLDCWD
rm -Rf $TMPDIR
