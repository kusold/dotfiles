#!/usr/bin/env zsh

herokupath='/usr/local/heroku/bin/heroku'
if [ -f "${heokupath}"]; then
  # Heroku Fight
  alias heroku=$herokupath
fi
