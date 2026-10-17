{ config, pkgs, ... }:

let
  httpsUrl = "https://github.com/patatepartie/nix-config.git";
  stateDir = "/var/lib/nix-auto-update";
  checkoutPath = "${stateDir}/nix-config";

  envFile = "${stateDir}/telegram.env";
  logFile = "/var/log/nix-auto-update.log";
  markerFile = "${stateDir}/run-in-progress";
  runnerPath = "${stateDir}/run-update.sh";
  switchLog = "${stateDir}/switch-output.log";

  functions = import ./auto-update-functions.nix { inherit pkgs envFile checkoutPath; };

  updateRunner = pkgs.writeShellScript "nix-auto-update-runner" ''
    set -euo pipefail
    export PATH=/run/current-system/sw/bin:/usr/bin:/bin

    HOSTNAME=$(hostname)
    RUN_ID="$1"

    ${functions}
    trap 'rm -f ${markerFile}; notify_failure "unexpected error on line $LINENO"' ERR

    if [ -f ${markerFile} ]; then
      PREVIOUS=$(cat ${markerFile})
      log "Previous run did not complete: $PREVIOUS"
      notify "nix auto-update on $HOSTNAME did not complete its previous run ($PREVIOUS); it was killed before finishing"
    fi

    echo "run $RUN_ID started $(date '+%Y-%m-%d %H:%M:%S')" > ${markerFile}

    log "Starting nix auto-update (run $RUN_ID)"

    if [ ! -d ${checkoutPath} ]; then
      log "Cloning repository"
      mkdir -p ${stateDir}
      git clone ${httpsUrl} ${checkoutPath}
    fi

    cd ${checkoutPath}

    log "Syncing from origin"
    BEFORE=$(git rev-parse HEAD)
    git fetch origin
    git reset --hard origin/main
    git clean -fd

    AFTER=$(git rev-parse HEAD)
    if [ "$BEFORE" = "$AFTER" ]; then
      log "Already up to date"
      rm -f ${markerFile}
      exit 0
    fi

    log "Rebuilding system ($BEFORE -> $AFTER)"
    switch_status=0
    darwin-rebuild switch --flake ${checkoutPath} 2>&1 | tee ${switchLog} || switch_status=$?
    report_warnings ${switchLog}

    if [ "$switch_status" -ne 0 ]; then
      rm -f ${markerFile}
      notify_failure "darwin-rebuild switch failed ($BEFORE -> $AFTER)"
      exit 1
    fi

    rm -f ${markerFile}
    log "Update complete"
  '';

  # setsid(2) fails if the caller is already a process group leader, which the
  # launchd-spawned job is. Fork first so the child is never a group leader, then
  # the child's setsid always succeeds and it leaves the job's session entirely.
  #
  # The parent must not exit until the child has actually called setsid: launchd
  # tears the job's process group down within milliseconds of the job going
  # inactive, and a child still in that group at teardown is killed. The pipe
  # makes the parent block until the child reports it is clear.
  detachHelper = pkgs.writeScript "nix-auto-update-detach" ''
    #!${pkgs.perl}/bin/perl
    use strict;
    use warnings;
    use POSIX qw(setsid);

    pipe(my $r, my $w) or die "pipe failed: $!";

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid) {
      close($w);
      # Blocks until the child writes, or closes the pipe by dying.
      my $ok = <$r>;
      die "child failed to detach" unless defined $ok;
      exit 0;
    }

    close($r);
    setsid() != -1 or die "setsid failed: $!";
    print $w "detached\n";
    close($w);
    exec @ARGV or die "exec failed: $!";
  '';

  # The launchd job must exit promptly: nix-darwin's activation reloads any
  # launchd service whose plist changed, and this job's plist changes whenever
  # the runner's store path does. If the tracked process were still doing the
  # work, `launchctl unload` would kill it mid-rebuild.
  autoUpdateLauncher = pkgs.writeShellScript "nix-auto-update" ''
    set -euo pipefail
    export PATH=/run/current-system/sw/bin:/usr/bin:/bin

    mkdir -p ${stateDir}
    install -m 0755 ${updateRunner} ${runnerPath}

    RUN_ID="$(date '+%Y%m%dT%H%M%S')-$$"

    ${detachHelper} /usr/bin/caffeinate -is ${runnerPath} "$RUN_ID" >> ${logFile} 2>&1
  '';
in
{
  launchd.daemons.nix-auto-update = {
    serviceConfig = {
      ProgramArguments = [ "${autoUpdateLauncher}" ];
      StartCalendarInterval = [{ Hour = 7; Minute = 30; }];
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
