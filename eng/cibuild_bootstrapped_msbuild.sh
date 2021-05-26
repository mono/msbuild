#! /bin/bash

configuration="Debug"
host_type="core"
build_stage1=true
run_tests="--test"
run_restore="--restore"
properties=
extra_properties=
use_system_mono=false

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
    --use_system_mono)
      use_system_mono=true
      shift
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

    if [[ `uname -s` != 'Darwin' ]]; then
        # with no .so available, this ends up breaking the build
        rm -Rf $mono_msbuild_dir/SdkResolvers/Microsoft.DotNet.MSBuildSdkResolver
    fi
    rm "$msbuild_zip"
  fi
}

RepoRoot="$ScriptRoot/.."
artifacts_dir="$RepoRoot/artifacts"
Stage1Dir="$RepoRoot/stage1"
PerfLogDir="$ArtifactsDir/log/$configuration/PerformanceLogs"

mono_msbuild_dir="$artifacts_dir/mono-msbuild"
msbuild_download_url="https://github.com/mono/msbuild/releases/download/v16.9.0/mono_msbuild_6.12.0.137.zip"
msbuild_zip="$artifacts_dir/msbuild.zip"
roslyn_version_to_use=`grep -i MicrosoftNetCompilersVersion $ScriptRoot/Versions.props  | sed -e 's,^.*>\([^<]*\)<.*$,\1,'`
nuget_version_to_use=`grep -i NuGetBuildTasksVersion $ScriptRoot/Versions.props  | sed -e 's,^.*>\([^<]*\)<.*$,\1,'`

if [ $host_type = "mono" ] ; then
  if [ -z "$roslyn_version_to_use" ]; then
      echo  "Unable to find a Roslyn version to use for Microsoft.Net.Compilers.Toolset"
      exit 1
  fi
  if [ -z "$nuget_version_to_use" ]; then
      echo  "Unable to find a NuGet.Build.Tasks version to use."
  fi
  if [ $use_system_mono == false ] ; then
      DownloadMSBuildForMono

      export _InitializeBuildTool="mono"
      export _InitializeBuildToolCommand="$mono_msbuild_dir/MSBuild.dll"
      export _InitializeBuildToolFramework="net472"


      configuration="$configuration-MONO"
      extn_path="$mono_msbuild_dir/Extensions"

      extra_properties=" /p:MSBuildExtensionsPath=$extn_path /p:MSBuildExtensionsPath32=$extn_path /p:MSBuildExtensionsPath64=$extn_path /p:DeterministicSourcePaths=false /fl /flp:v=diag /m /p:MicrosoftNetCompilersVersion=$roslyn_version_to_use /p:NuGetBuildTasksVersion=$nuget_version_to_use"
  else
      export _InitializeBuildTool="msbuild"
      export _InitializeBuildToolCommand=""
      export _InitializeBuildToolFramework="net472"

      configuration="$configuration-MONO"
      extra_properties=" /fl /flp:v=diag /p:MicrosoftNetCompilersVersion=$roslyn_version_to_use /p:NuGetBuildTasksVersion=$nuget_version_to_use"
  fi
fi

pkill -9 -f VBCSCompiler.exe

if [[ $build_stage1 == true ]];
then
    "$_InitializeBuildTool" "$_InitializeBuildToolCommand" $extra_properties /bl mono/build/update_bundled_bits.proj || exit $?

	/bin/bash "$ScriptRoot/common/build.sh" $run_restore --build --ci --configuration $configuration /p:CreateBootstrap=true $properties $extra_properties || exit $?
fi

bootstrapRoot="$Stage1Dir/bin/bootstrap"

if [ $host_type = "core" ]
then
  _InitializeBuildTool="$_InitializeDotNetCli/dotnet"
  _InitializeBuildToolCommand="$bootstrapRoot/net5.0/MSBuild/MSBuild.dll"
  _InitializeBuildToolFramework="netcoreapp2.1"
elif [ $host_type = "mono" ]
then
  export _InitializeBuildTool="mono"
  export _InitializeBuildToolCommand="$bootstrapRoot/net472/MSBuild/Current/Bin/MSBuild.dll"
  export _InitializeBuildToolFramework="net472"

  # FIXME: remove this once we move to a newer version of Arcade with a fix for $MonoTool
  # https://github.com/dotnet/arcade/commit/f6f14c169ba19cd851120e0d572cd1c5619205b3
  export MonoTool=`which mono`

  extn_path="$bootstrapRoot/net472/MSBuild"
  extra_properties=" /p:MSBuildExtensionsPath=$extn_path /p:MSBuildExtensionsPath32=$extn_path /p:MSBuildExtensionsPath64=$extn_path /p:DeterministicSourcePaths=false /fl /flp:v=diag /p:MicrosoftNetCompilersVersion=$roslyn_version_to_use /p:NuGetBuildTasksVersion=$nuget_version_to_use"
else
  echo "Unsupported hostType ($host_type)"
  exit 1
fi

mv $artifacts_dir $Stage1Dir

# Ensure that debug bits fail fast, rather than hanging waiting for a debugger attach.
export MSBUILDDONOTLAUNCHDEBUGGER=true

# Opt into performance logging.
export DOTNET_PERFLOG_DIR=$PerfLogDir

# Prior to 3.0, the Csc task uses this environment variable to decide whether to run
# a CLI host or directly execute the compiler.
export DOTNET_HOST_PATH="$_InitializeDotNetCli/dotnet"

# When using bootstrapped MSBuild:
# - Turn off node reuse (so that bootstrapped MSBuild processes don't stay running and lock files)
# - Do run tests
# - Don't try to create a bootstrap deployment
. "$ScriptRoot/common/build.sh" $run_restore --build $run_tests --ci --nodereuse false --configuration $configuration /p:CreateBootstrap=false $properties $extra_properties
