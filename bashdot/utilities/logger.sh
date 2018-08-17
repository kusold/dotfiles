#! /usr/bin/env bash

# import colors

INDENTATION=''

indents() {
  INDENTATION=''
  local indentLevel=$1
  local i=0;
  while [ $i -lt $indentLevel ]; do
    INDENTATION+='\t';
    i+=1;
  done
}

log_module() {
  local msg="${@}";
  indents 0
  printf "${BLUE}${msg}${RESET}"
}

run_task() {
  local p=("$@")
  local cmd="${p[0]}";
  local msg="${p[1]}";

  indents 1

  printf "${INDENTATION}${msg}\r"
  local cmd_result=$($cmd);

  local color='';
  case $cmd_result in
    $STATUS_NOT_MODIFIED)
      color=${GREEN}
      ;;
    $STATUS_MODIFIED)
      color=${YELLOW}
      ;;
    $STATUS_ERROR)
      color=${RED}
      ;;
    *)
      color=${RED}
      ;;
  esac

  printf "${INDENTATION}${color}${msg}${RESET}\n"
}

STATUS_NOT_MODIFIED="NOT MODIFIED";
STATUS_MODIFIED="MODIFIED";
STATUS_ERROR="ERROR";

