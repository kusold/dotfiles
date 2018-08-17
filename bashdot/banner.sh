#! /usr/bin/env bash

if command_exists git; then
  GIT_LAST_COMMIT=`git branch -vv`
fi

printf "${GREEN}\
    ____             __    ____        __ 
   / __ )____ ______/ /_  / __ \____  / /_
  / __  / __ \`/ ___/ __ \/ / / / __ \/ __/
 / /_/ / /_/ (__  ) / / / /_/ / /_/ / /_  
/_____/\__,_/____/_/ /_/_____/\____/\__/  

${MAGENTA}${GIT_LAST_COMMIT}${RESET}
\n";

