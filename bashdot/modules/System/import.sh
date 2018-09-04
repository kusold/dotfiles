#! /usr/bin/env bash

System::Import() {
  local lib_path=$1

  if [[ "${lib_path}" == './'* ]]; then
	# remove ./
	lib_path="${lib_path:2}";
  fi

  local local_path="$( cd "${BASH_SOURCE[1]%/*}" && pwd )";
  local_path="${localPath}/${libPath}"

  System::SourcePath "${localPath}" "$@"
}


# https://github.com/niieani/bash-oo-framework/blob/3c0291e2ace410c2d9068b82a5598164e7b49cf3/lib/oo-bootstrap.sh#L100-L110
File::GetAbsolutePath() {
  # http://stackoverflow.com/questions/3915040/bash-fish-command-to-print-absolute-path-to-a-file
  # $1 : relative filename
  local file="$1"
  if [[ "$file" == "/"* ]]
  then
    echo "$file"
  else
    echo "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  fi
}

