#!/bin/sh

configuration="debug"
host_type="core"
build_stage1=true
run_tests="--test"
run_restore="--restore"

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$ScriptRoot/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

while [[ $# -gt 0 ]]; do
  lowerI="$(echo $1 | awk '{print tolower($0)}')"
  case "$lowerI" in
    --configuration)
      configuration=$2
      shift 2
      ;;
    --build_stage1)
      build_stage1=$2
      shift 2
      ;;
    --skip_tests)
      run_tests=""
      shift
      ;;
    --skip_restore)
      run_restore=""
      shift
      ;;
    --host_type)
      host_type=$2
      shift 2
      ;;
    *)
      properties="$properties $1"
      shift 1
      ;;
  esac
done

function DownloadMSBuildForMono {
  if [[ ! -e "$mono_msbuild_dir/MSBuild.dll" ]]
  then
    mkdir -p $artifacts_dir
    echo "** Downloading MSBUILD from $msbuild_download_url"
    curl -sL -o "$msbuild_zip" "$msbuild_download_url"

    unzip -q "$msbuild_zip" -d "$artifacts_dir"
    # rename just to make it obvious when reading logs!
    mv $artifacts_dir/msbuild $mono_msbuild_dir
    chmod +x $artifacts_dir/mono-msbuild/MSBuild.dll
    rm "$msbuild_zip"
  fi
}

RepoRoot="$ScriptRoot/.."
artifacts_dir="$RepoRoot/artifacts"

mono_msbuild_dir="$artifacts_dir/mono-msbuild"
msbuild_download_url="https://github.com/mono/msbuild/releases/download/0.06/mono_msbuild_xplat-master-3c930fa8.zip"
msbuild_zip="$artifacts_dir/msbuild.zip"

if [ $host_type = "mono" ] ; then
  DownloadMSBuildForMono

  export _InitializeBuildTool="mono"
  export _InitializeMSBuildToUse="$mono_msbuild_dir/MSBuild.dll"

  configuration="$configuration-MONO"
fi

if [[ $build_stage1 == true ]];
then
	/bin/bash "$ScriptRoot/common/build.sh" $run_restore --build --ci --configuration $configuration /p:CreateBootstrap=true $properties
fi

bootstrapRoot="$artifacts_dir/bin/bootstrap"
# export to make this available to `eng/common/build.sh`
export artifacts_dir="$artifacts_dir/2"

if [ $host_type = "core" ]
then
	_InitializeMSBuildToUse="$bootstrapRoot/netcoreapp2.1/MSBuild/MSBuild.dll"
elif [ $host_type = "mono" ]
then
  export _InitializeBuildTool="mono"
  export _InitializeMSBuildToUse="$bootstrapRoot/net472/MSBuild/Current/Bin/MSBuild.dll"

  # FIXME: remove this once we move to a newer version of Arcade with a fix for $MonoTool
  # https://github.com/dotnet/arcade/commit/f6f14c169ba19cd851120e0d572cd1c5619205b3
  export MonoTool=`which mono`

  properties="$properties /p:MSBuildExtensionsPath=$bootstrapRoot/net472/MSBuild "
else
  echo "Unsupported hostType ($host_type)"
  exit 1
fi

# When using bootstrapped MSBuild:
# - Turn off node reuse (so that bootstrapped MSBuild processes don't stay running and lock files)
# - Do run tests
# - Don't try to create a bootstrap deployment
. "$ScriptRoot/common/build.sh" $run_restore --build $run_tests --ci --nodereuse false --configuration $configuration /p:CreateBootstrap=false $properties
