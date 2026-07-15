# Cluster lifecycle

Symmetric up / down sequences. The "up" side restores a host after a reboot; the
"down" side prepares a host for a reboot. **Teardown is the destroy step — only
for the AWS/EKS lifecycle or a deliberate full local reset, never the reboot
cycle.**

| Up (after reboot)                              | Down (before reboot)        |
|------------------------------------------------|-----------------------------|
| `setup-cluster-ubuntu-<role>.sh` — iptables LAN exposure **+** `minikube start` (a reboot wipes the iptables rules, so re-run this; cluster state is preserved) | `stop-tunnel.sh` — kill the tunnel + remove the root-owned `tunnels.json` |
| `start-tunnel-detached.sh` — persistent `minikube tunnel` | `stop-cluster.sh` — `minikube stop` (state preserved) |
| —                                              | `teardown-cluster.sh` — `minikube delete` (**destroy**; AWS/full-reset only) |

Reboot ubuntu-team:

```
# before reboot
ssh ubuntu-team
bash sheep-dog-ops/infra/minikube/stop-tunnel.sh
bash sheep-dog-ops/infra/minikube/stop-cluster.sh
sudo reboot

# after reboot — setup-cluster ends in a foreground tunnel meant to be killed,
# so run it under a pty (sudo's cached credential needs a real terminal) and
# kill that tunnel, then start the detached one.
ssh -tt ubuntu-team
bash sheep-dog-ops/infra/minikube/setup-cluster-ubuntu-team.sh   # Ctrl-C the trailing tunnel once "Starting tunnel" prints
bash sheep-dog-ops/infra/minikube/start-tunnel-detached.sh
# if the svc pods are CrashLoopBackOff (AMQ restarted under them), once
# sheep-dog-amq is Running: kubectl rollout restart deploy -n qa
```

### Remote startup from ubuntu-client (post-outage / bulk restart)

Bringing both LAN clusters (ubuntu-team + ubuntu-sandbox) back up after a power
outage without SSH-ing in and babysitting each one interactively. Run from
ubuntu-client, once per host. The trick is that a non-interactive SSH session
(`ssh host '...'`) does **not** source `~/.bashrc`, so `$SUDO_PASSWORD` isn't
set and `setup-cluster.sh`'s `sudo iptables` calls have no cached credential and
no tty to prompt on. Source the password file and prime `sudo` first:

```bash
# Per host: ubuntu-team (role team) / ubuntu-sandbox (role sandbox)
ssh -tt ubuntu-team '
  source ~/.config/sudo_password                 # $SUDO_PASSWORD (see tools-overview.md § env-vars)
  echo "$SUDO_PASSWORD" | sudo -S -v             # cache the sudo credential for the iptables step
  cd ~/git/sheep-dog-main
  nohup bash sheep-dog-ops/infra/minikube/setup-cluster-ubuntu-team.sh \
        > /tmp/setup-cluster.log 2>&1 &
  disown
  sleep 75                                        # hold the pty while the early sudo/iptables run
'
# setup-cluster ends in a *foreground* `minikube tunnel` that needs sudo; under
# nohup with no tty it fails with "a terminal is required to read the password"
# — expected and harmless. minikube itself is up. Then start the real tunnel:
ssh ubuntu-team '
  source ~/.config/sudo_password
  bash sheep-dog-ops/infra/minikube/start-tunnel-detached.sh   # sudo -SE nohup, detached
'
```

Poll `minikube status` and `tail /tmp/setup-cluster.log` between the two steps;
wait for `apiserver: Running` and the trailing tunnel's sudo-failure line before
launching `start-tunnel-detached.sh`. Verify from the client with
`kubectl --context=minikube-team get ns` and `--context=minikube-sandbox`.

> After a bulk restart, also check each host's checkouts aren't stale — a
> reboot doesn't pull. `sheep-dog-ops`/`sheep-dog-specs` are public (anonymous
> fetch); the rest are private and need `$GITHUB_TOKEN`. `sheep-dog-grammar/src-gen`
> may show as locally-modified generated files that block a fast-forward —
> `git checkout -- sheep-dog-grammar/src-gen` (it's regenerated) then pull.

```
kubectl config get-contexts            # pipe through `cat` if output looks empty (snap kubectl quirk)
kubectl config use-context minikube              # local cluster
kubectl config use-context minikube-sandbox      # remote sandbox cluster
kubectl config use-context minikube-team         # remote team cluster (once set up)
kubectl config use-context arn:aws:eks:...       # EKS as before
kubectl config current-context
```

```
cd ~/git/sheep-dog-main
sudo -v   # cache credential once interactively
nohup bash sheep-dog-ops/infra/minikube/setup-cluster-ubuntu-sandbox.sh > /tmp/setup-cluster.log 2>&1 &
disown
tail -f /tmp/setup-cluster.log
```

```
kubectl --context=minikube-team scale deployment,statefulset --all -n qa --replicas=0
kubectl --context=minikube-team scale deployment,statefulset --all -n qa --replicas=1
kubectl --context=minikube-team get deploy,sts -n qa
```

```
kubectl --context=minikube-team -n qa rollout restart deployment/sheep-dog-uml-api-svc
kubectl --context=minikube-team -n qa rollout status deployment/sheep-dog-uml-api-svc
```

```
echo "$SUDO_PASSWORD" | sudo -SE nohup minikube tunnel > /tmp/tunnel.log 2>&1 &
disown
```
