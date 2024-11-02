# K8s-HELM-ARGO-DEMO
This repo consists of scripts to spin up a self-contained single node cluster with k3s, Helm, ArgoCD and nginx as a demo service. It also has a script to teardown the whole setup. 

The scripts are grouped into CPU architecure.

## Apple Silicon ARM_x64 (M1+)
- install UTM app https://mac.getutm.app/. I wasn't able to get VMWare Fusion, VirtualBox, Ubuntu Multipass virtualisation software working on Apple M1 Pro/M2 at all, UTM was the saviour.
- Use Ubuntu 22.04
- SSH into the VM and run the setup

### Quick TLS setup using self-signed certificate
- Assuming the `openssl` is installed, run the following commands to generate a private key and self-signed certificate (valid for 365 days).
  ```
  openssl genrsa -out demo-svc.key 4096
  openssl req -x509 -new -nodes -days 365 -key demo-svc.key -out demo-svc.crt -subj="/CN=your domain or IP address"
  ```
  The browsers will warn you for usign this self-signed cert. But this is the start.

- Add K8s secret using this key and the cert. 
  `kubectl create secret demo-tls-secret --key demo-svc.key --cert demo-svc.crt` 
- Look at the created secret 
  `kubectl describe secrets/demo-tls-secret`
- Take a look at the service ports in your cluster using `kubectl get service -A` or by name. You will see something like `nginx         nginx-app                                 NodePort       10.43.26.102    <none>         80:31818/TCP,443:30890/TCP   26d`. 30890 is the port that you should use from your client/host machine.