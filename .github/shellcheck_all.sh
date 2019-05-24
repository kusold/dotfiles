set -e

find ./ -iname \*.sh -exec shellcheck {} \;
