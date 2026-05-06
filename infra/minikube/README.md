```
kubectl config get-contexts          # pipe through `cat` if output looks empty (snap kubectl quirk)
kubectl config use-context ubuntu-client    # local cluster (was "minikube")
kubectl config use-context ubuntu-sandbox   # remote minipc cluster
kubectl config use-context arn:aws:eks:...  # EKS as before
kubectl config current-context
```