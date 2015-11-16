#!/bin/bash
set -e

pushd `dirname $0`
echo "Fetching latest curl certs (via HTTPS)"
mkdir -p ./certs/
curl -o ./certs/ca-bundle.crt https://raw.githubusercontent.com/bagder/ca-bundle/master/ca-bundle.crt
popd
