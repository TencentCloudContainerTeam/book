---
title: "EKS 常见问题"
state: Alpha
---

#### 1. EKS 支持 hostPath 吗

不支持。serverless，没有 node，也就没有 hostPath

#### 2. EKS 支持 kubectl exec -it 来登录容器吗

在灰度，需要开白名单，请提工单或联系售后开白。

#### 3. EKS 如何让所有 pod 时区保持一致

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

#### 4. EKS 支持从自定义镜像仓库中拉去镜像么？

目前还不支持。
EKS 现在只能从腾讯云官方镜像仓库CCR https://console.cloud.tencent.com/tke2/registry/user?rid=1 及 TCR https://console.cloud.tencent.com/tcr 
中拉去镜像。可以考虑将自己的镜像仓库迁移到腾讯云CCR/TCR; Harbor 可以直接同步镜像到CCR/TCR 。

#### 5. EKS 如何收集容器日志？

EKS日志功能主要通过下面的环境变量来控制，如不加下面环境变量，则不收集日志。
- name: EKS_LOGS_OUTPUT_TYPE 日志收集到哪里，目前支持kafka, cls（腾讯云日志服务） 
  value: kafka
- name: EKS_LOGS_KAFKA_HOST kafka host； 如果多个host ，用分号隔开
  value: 10.0.16.42
- name: EKS_LOGS_KAFKA_PORT kafka port
  value: "9092"
- name: EKS_LOGS_KAFKA_TOPIC kafka topic
  value: eks
- name: EKS_LOGS_METADATA_ON 是否收集 eks 的metadata 信息
  value: "true"
- name: EKS_LOGS_LOG_PATHS 支持收集标准输出和 文件路径； 如同时收集，用分开隔开；
  value: stdout;/tmp/busy*.log

参考下面demo 

```
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "1"
  labels:
    k8s-app: kafka
    qcloud-app: kafka
  name: kafka
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: kafka
      qcloud-app: kafka
  template:
    metadata:
      annotations:
        eks.tke.cloud.tencent.com/cpu: "0.25"
        eks.tke.cloud.tencent.com/mem: "0.5Gi"
      labels:
        k8s-app: kafka
        qcloud-app: kafka
    spec:
      containers:
      - env:
        - name: EKS_LOGS_OUTPUT_TYPE
          value: kafka
        - name: EKS_LOGS_KAFKA_HOST
          value: 10.0.16.42
        - name: EKS_LOGS_KAFKA_PORT
          value: "9092"
        - name: EKS_LOGS_KAFKA_TOPIC
          value: eks
        - name: EKS_LOGS_METADATA_ON
          value: "false"
        - name: EKS_LOGS_LOG_PATHS
          value: stdout;/tmp/busy*.log
        image: busybox:latest
        command: ["/bin/sh"]
        args: ["-c", "while true; do echo hello world; date; echo hello >> /tmp/busy.log; sleep 1; done"]
        imagePullPolicy: Always
        name: while
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
```
