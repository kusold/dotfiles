#!/usr/bin/env zsh

# JumpCloud Go Directory
if [[ -d "$HOME/Development/go/src/github.com/TheJumpCloud" ]]; then
  alias -g gojc=$HOME/Development/go/src/github.com/TheJumpCloud
fi

# Necessary for the grpc node_module to run
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib

#Jumpcloud Specific Aliases
alias fetch-agent-staging='scp -r mike@staging.jumpcloud.com:/opt/provisioning-server/files/* ~/Development/SI/agent-files/'
alias rsync-agent-staging='rsync -avz --progress mike@staging.jumpcloud.com:/opt/provisioning-server/files/ ~/Development/SI/agent-files/'
alias rsync-agent-test='rsync -avz --progress mike@test.jumpcloud.com:/opt/provisioning-server/files/ ~/Development/SI/agent-files/'
alias load-int-fixture='mongorestore -db SI /home/mike/Development/SI/test/webui/integration/fixture/SI-integration'
alias load-alarm-int-fixture='mongorestore -db SI /home/mike/Development/SI/test/webui/integration/fixture/alarms/SI-integration'
alias load-personal-fixture='mongorestore -db SI /home/mike/Development/mongodumps/personal/SI'
alias restart-ramdb='/home/mike/Development/SI/bin/mongod-ramdb-linux stop;/home/mike/Development/SI/bin/mongod-ramdb-linux start'
alias reload-ramdb='restart-ramdb;load-int-fixture'
alias reload-personal-ramdb='restart-ramdb;load-personal-fixture'
alias reload-alarm-ramdb='restart-ramdb;load-alarm-int-fixture'
alias drop-test-dbs='mongo /home/mike/Development/SI/bin/queries/drop-SI-Test-dbs.js'
alias fucking-mongo="$HOME/Development/documentation/mongo-unlock-database.sh"

