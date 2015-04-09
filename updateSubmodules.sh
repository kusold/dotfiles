!# /bin/bash
git submodule foreach "git pull; git submodule update --init --recursive"
