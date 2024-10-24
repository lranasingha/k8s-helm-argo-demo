# K8s-HELM-ARGO-DEMO
This repo consists of scripts to spin up a self-contained single node cluster with k3s, Helm, ArgoCD and nginx as a demo service. It also has a script to teardown the whole setup. 

The scripts are grouped into CPU architecure.

## Apple Silicon ARM_x64 (M1+)
- install UTM app https://mac.getutm.app/. I wasn't able to get VMWare Fusion, VirtualBox, Ubuntu Multipass virtualisation software working on Apple M1 Pro/M2 at all, UTM was the saviour.
- Use Ubuntu 22.04
- SSH into the VM and run the setup