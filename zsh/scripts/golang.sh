#!/usr/bin/env zsh
autoload command_exists

# Go Lang Setup
if [[ -d "$HOME/Development/go/" ]]; then
  export GOPATH=$HOME/Development/go
fi

if [[ -d "$GOPATH/bin/" ]]; then
  export PATH=$GOPATH/bin:$PATH
fi

if [[ -d "/usr/local/go" ]]; then
  export PATH=$PATH:/usr/local/go/bin
  export GOROOT=/usr/local/go/
fi

if [[ -d "/usr/local/opt/go/libexec" ]]; then
  export PATH=$PATH:/usr/local/opt/go/libexec
  export GOROOT=/usr/local/opt/go/libexec
fi

if command_exists go; then
  function go_build () {
    OUTPUT_PREFIX=${PWD##*/}
    GOOS="$1" GOARCH="$2" go build -o "${OUTPUT_PREFIX}_${GOOS}_${GOARCH}"
  }
#  alias go-xbuild='CGO_ENABLED=0 gox -osarch="darwin/amd64 linux/amd64 linux/386" && CC="i686-w64-mingw32-gcc" CGO_ENABLED=1 gox -osarch="windows/386"'
  alias go-xbuild='go_build "darwin" "amd64" && go_build "linux" "386" && go_build "linux" "amd64"  && go_build "windows" "386"  && go_build "windows" "amd64"'
fi

if command_exists godoc; then
  alias godoc-local='godoc -http=:6060'
fi
