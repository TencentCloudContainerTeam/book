---
title: "EKS 常见问题"
state: Alpha
---

## EKS 支持 hostPath 吗

不支持。serverless，没有 node，也就没有 hostPath

## EKS 支持 kubectl exec -it 来登录容器吗

在灰度，需要开白名单，请提工单或联系售后开白。

## EKS 如何让所有 pod 时区保持一致

由于不支持 hostPath，所以不能用此方法来挂载时区文件，可以通过挂载 configmap 来实现。

先通过时区文件创建 configmap:

``` bash
kubectl create cm timezone-configmap --from-file=/usr/share/zoneinfo/Asia/Shanghai
```

再在 pod 里挂载 configmap:

``` yaml
apiVersion: v1
kind: Pod
metadata:
  name: tz-configmap
  namespace: default
  annotations:
    eks.tke.cloud.tencent.com/cpu: "1"
    eks.tke.cloud.tencent.com/mem: 2Gi
spec:
  restartPolicy: OnFailure
  containers:
  - name: busy-box-test
    env:
    - name: TZ
      value: Asia/Shanghai
    image: busybox
    imagePullPolicy: IfNotPresent
    command: ["sleep", "60000"]
    volumeMounts:
    - name: timezone
      mountPath: /etc/localtimeX
      subPath: Shanghai
  volumes:
  - configMap:
      name: timezone-configmap
      items:
      - key: Shanghai
        path: Shanghai
    name: timezone
```

> 注: 由于 configmap 是 namespace 隔离的，如果要所有 pod 都时区同步，需要在所有 namespace 都创建时区的 configmap
