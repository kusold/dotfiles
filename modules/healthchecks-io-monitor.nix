
{ config, pkgs, ... }:
{
    age.secrets.monitoring-healthchecks-url.file = ../secrets/monitoring-healthchecks-url.age;


# [Unit]
# Description=Important service
# OnFailure=healthchecks-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:failure.service
# OnSuccess=healthcheck-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:success.service
# Wants=healthcheck-monitor@deda567a-21e0-4744-ba9e-603c51e258b0:start.service

  systemd.services.healthchecks-monitor = {
    description = "Pings healthchecks (%i)";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.curl ];
    scriptArgs = "%i";
    script = ''
      HC_URL=$(cat ${age.secrets.monitoring-healthchecks-url.file})
      IFS=: read -r SLUG ACTION <<< "%i"
      if [ "$ACTION" = "start" ]; then
        LOGS=""
        EXIT_CODE="start"
      else
        LOGS=$(journalctl --no-pager -n 50 -u $MONITOR_UNIT)
        EXIT_CODE=$MONITOR_EXIT_STATUS
      fi
      curl -fSs -m 10 --retry 3 --data-raw "$LOGS" "$HC_URL/$SLUG/$EXIT_CODE?create=1"
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

}
