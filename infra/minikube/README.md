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
kubectl --context=minikube-sandbox scale deployment,statefulset --all -n qa --replicas=0
kubectl --context=minikube-sandbox scale deployment,statefulset --all -n qa --replicas=1
kubectl --context=minikube-sandbox get deploy,sts -n qa
```

```
echo "$SUDO_PASSWORD" | sudo -SE nohup minikube tunnel > /tmp/tunnel.log 2>&1 &
disown
```
