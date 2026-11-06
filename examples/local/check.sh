# Run on the host: checks everything short of registering, which needs a
# token from GitHub. The tarball, the runner starting as its own user with
# its libraries in place, and the unit.
set -eu
cd /opt/actions-runner
sha256sum -c <<< "baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40  actions-runner-linux-x64-2.338.2.tar.gz"
[ "$(runuser -u github-runner -- build/bin/Runner.Listener --version)" = 2.338.2 ]
[ "$(stat -c %U build/config.sh)" = github-runner ]
[ "$(id -nG github-runner)" = github-runner ]
[ "$(systemctl is-enabled github-runner@build)" = enabled ]
[ "$(systemctl show -P User github-runner@build)" = github-runner ]
[ "$(systemctl show -P WorkingDirectory github-runner@build)" = /opt/actions-runner/build ]
# Not registered, so the unit's condition keeps it from starting.
systemctl start github-runner@build
[ "$(systemctl is-active github-runner@build)" = inactive ]
