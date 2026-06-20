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
kubectl --context=minikube-team -n qa rollout restart deployment/sheep-dog-asciidoc-api-svc
kubectl --context=minikube-team -n qa rollout status deployment/sheep-dog-asciidoc-api-svc
```

```
echo "$SUDO_PASSWORD" | sudo -SE nohup minikube tunnel > /tmp/tunnel.log 2>&1 &
disown
```
