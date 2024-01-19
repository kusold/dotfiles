
{ config, pkgs, ... }:
{
    config.age.secrets.monitoring-healthchecks-url.file = ../secrets/monitoring-healthchecks-url.age;


# [Unit]
# Description=Important service
# OnFailure=healthchecks-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:failure.service
# OnSuccess=healthcheck-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:success.service
# Wants=healthcheck-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:start.service

  config.systemd.services."healthchecks-monitor@" = {
    description = "Pings healthchecks (%i)";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.bash pkgs.curl ];
# Scripts did not work because the special systemd variables were not getting passed in. I had to collapse it to a single line for ExecStart
#    scriptArgs = "%i";
#    script = ''
#      HC_URL=$(cat ${config.age.secrets.monitoring-healthchecks-url.path})
#      IFS=: read -r SLUG ACTION <<< "%i"
#      if [ "$ACTION" = "start" ]; then
#        LOGS=""
#        EXIT_CODE="start"
#      else
#        #LOGS=$(journalctl --no-pager -n 50 -u $MONITOR_UNIT)
#        LOGS=""
#        EXIT_CODE=$MONITOR_EXIT_STATUS
#      fi
#      echo "curl -fSs -m 10 --retry 3 --data-raw \"$LOGS\" \"$HC_URL/$SLUG/$EXIT_CODE?create=1\""
#      curl -fSs -m 10 --retry 3 --data-raw "$LOGS" "$HC_URL/$SLUG/$EXIT_CODE?create=1"
#    '';
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'HC_URL=$(cat ${config.age.secrets.monitoring-healthchecks-url.path}); IFS=: read -r SLUG ACTION <<< "%i"; if [ "$ACTION" = "start" ]; then LOGS="" && EXIT_CODE="start"; else LOGS=$(journalctl --no-pager -n 50 -u $MONITOR_UNIT) && EXIT_CODE=$MONITOR_EXIT_STATUS; fi && echo "curl -fSs -m 10 --retry 3 --data-raw \"$LOGS\" \"$HC_URL/$SLUG/$EXIT_CODE?create=1\"" && curl -fSs -m 10 --retry 3 --data-raw "$LOGS" "$HC_URL/$SLUG/$EXIT_CODE?create=1"'
      '';
    };
  };

}
