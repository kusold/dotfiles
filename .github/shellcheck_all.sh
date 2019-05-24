set -e

find ./ -iname \*.sh -print0 | xargs -0 shellcheck

