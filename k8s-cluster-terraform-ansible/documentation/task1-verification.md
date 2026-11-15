# Week 10 Task 1 — verification

```
ok
NAME                      HOLDER                                               AGE
kube-controller-manager   ip-10-50-1-10_1ce544d0-351e-494b-8a39-0463e3d0b1fc   14m
kube-scheduler            ip-10-50-1-10_5035b664-b3b2-4276-9617-c0a0ec310b5b   14m
NAME       STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION           CONTAINER-RUNTIME
worker-1   Ready    <none>   11m   v1.36.1   10.50.1.21    <none>        Ubuntu 24.04.5 LTS   7.0.0-1014-aws (arm64)   containerd://2.2.1
worker-2   Ready    <none>   11m   v1.36.1   10.50.1.22    <none>        Ubuntu 24.04.5 LTS   7.0.0-1014-aws (arm64)   containerd://2.2.1
NAME            READY   STATUS    RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
week10-client   1/1     Running   0          6s    10.244.1.2   worker-2   <none>           <none>
week10-http     1/1     Running   0          7s    10.244.0.3   worker-1   <none>           <none>

HTTP between nodes using the Pod IP
week10-ok

DNS and HTTP through the Service
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

week10-ok

Secret encryption in etcd
control-plane | CHANGED | rc=0 >>
k8s:enc:aescbc:v1:week10-key-1:
```
