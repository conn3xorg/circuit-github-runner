# Local example

Applies circuit-github-runner to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

By default it installs one runner, `build`, without registering it, which needs nothing from GitHub:

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To look at the result:

```sh
ssh -p 2309 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 runuser -u github-runner -- /opt/actions-runner/build/bin/Runner.Listener --version
```

To register it too, make a private repository to try it on, since a self-hosted runner shouldn't serve a public one. Then pass a registration token and the repository's URL:

```sh
export TF_VAR_registration_token=$(gh api -X POST repos/OWNER/REPO/actions/runners/registration-token -q .token)
conn3x apply -var register=true -var github_url=https://github.com/OWNER/REPO
```

The runner shows up as `box-build` with the label `conn3x-test`, and takes jobs with `runs-on: [self-hosted, conn3x-test]`. Remove it from the repository's runners page before you run `./down.sh`, or GitHub lists it as offline for 14 days.

`up.sh` listens on `127.0.0.1:2309`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
