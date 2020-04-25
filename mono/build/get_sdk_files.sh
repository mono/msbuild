#!/usr/bin/env bash

set -e

if [ $# -ne 1 ]; then
	echo "Usage: $0 <dest dir>"
	exit 1
fi

DESTDIR=$2

ABSOLUTE_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
THIS_DIR=`dirname $ABSOLUTE_PATH`

source $THIS_DIR/../../eng/common/tools.sh

ReadGlobalVersion "dotnet"
dotnet_sdk_version=$_ReadGlobalVersion

TMPDIR=`mktemp -d`
DOTNET_DIR=$TMPDIR/.dotnet-sdk

OLDCWD=`pwd`
cd $TMPDIR

GetDotNetInstallScript $TMPDIR
sh ./dotnet-install.sh --version $dotnet_sdk_version --install-dir $DOTNET_DIR --architecture x64 --skip-non-versioned-files
find $DOTNET_DIR -name Microsoft.NETCoreSdk.BundledVersions.props -exec cp -v {} $1 \;
find $DOTNET_DIR -name RuntimeIdentifierGraph.json -exec cp -v {} $1 \;

cd $OLDCWD
#rm -Rf $TMPDIR
