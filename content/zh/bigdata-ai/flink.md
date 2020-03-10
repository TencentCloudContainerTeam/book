---
title: "Flink on TKE/EKS"
state: Alpha
---


## Flink On kubernetes 方案

将 Flink 部署到 Kubernetes 有以下几种集群部署方案:

* Session Cluster: 相当于将静态部署的 [Standalone Cluster](https://ci.apache.org/projects/flink/flink-docs-release-1.10/ops/deployment/cluster_setup.html) 容器化，TaskManager 与 JobManager 都以 Deployment 方式部署，可动态提交 Job，Job 处理能力主要取决于 TaskManager 的配置 (slot/cpu/memory) 与副本数 (replicas)，调整副本数可以动态扩容。这种方式也是比较常见和成熟的方式。
* Job Cluster: 相当于给每一个独立的 Job 部署一整套 Flink 集群，这套集群就只能运行一个 Job，配备专门制作的 Job 镜像，不能动态提交其它 Job。这种模式可以让每种 Job 拥有专用的资源，独立扩容。
* Native Kubernetes: 这种方式是与 Kubernetes 原生集成，相比前面两种，这种模式能做到动态向 Kubernetes 申请资源，不需要提前指定 TaskManager 数量，就像 flink 与 yarn 和 mesos 集成一样。此模式能够提高资源利用率，但还处于试验阶段，不够成熟，不建议部署到生产环境。


参考官方文档: https://ci.apache.org/projects/flink/flink-docs-stable/ops/deployment/kubernetes.html#flink-session-cluster-on-kubernetes

## Session Cluster 方式部署

准备资源文件(`flink.yaml`):

``` yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flink-config
  labels:
    app: flink
data:
  flink-conf.yaml: |+
    jobmanager.rpc.address: flink-jobmanager
    taskmanager.numberOfTaskSlots: 1
    blob.server.port: 6124
    jobmanager.rpc.port: 6123
    taskmanager.rpc.port: 6122
    jobmanager.heap.size: 1024m
    taskmanager.memory.process.size: 1024m
  log4j.properties: |+
    log4j.rootLogger=INFO, file
    log4j.logger.akka=INFO
    log4j.logger.org.apache.kafka=INFO
    log4j.logger.org.apache.hadoop=INFO
    log4j.logger.org.apache.zookeeper=INFO
    log4j.appender.file=org.apache.log4j.FileAppender
    log4j.appender.file.file=${log.file}
    log4j.appender.file.layout=org.apache.log4j.PatternLayout
    log4j.appender.file.layout.ConversionPattern=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %-60c %x - %m%n
    log4j.logger.org.apache.flink.shaded.akka.org.jboss.netty.channel.DefaultChannelPipeline=ERROR, file
---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-jobmanager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flink
      component: jobmanager
  template:
    metadata:
      labels:
        app: flink
        component: jobmanager
    spec:
      containers:
      - name: jobmanager
        image: flink:latest
        workingDir: /opt/flink
        command: ["/bin/bash", "-c", "$FLINK_HOME/bin/jobmanager.sh start;\
          while :;
          do
            if [[ -f $(find log -name '*jobmanager*.log' -print -quit) ]];
              then tail -f -n +1 log/*jobmanager*.log;
            fi;
          done"]
        ports:
        - containerPort: 6123
          name: rpc
        - containerPort: 6124
          name: blob
        - containerPort: 8081
          name: ui
        livenessProbe:
          tcpSocket:
            port: 6123
          initialDelaySeconds: 30
          periodSeconds: 60
        volumeMounts:
        - name: flink-config-volume
          mountPath: /opt/flink/conf
        securityContext:
          runAsUser: 9999  # refers to user _flink_ from official flink image, change if necessary
      volumes:
      - name: flink-config-volume
        configMap:
          name: flink-config
          items:
          - key: flink-conf.yaml
            path: flink-conf.yaml
          - key: log4j.properties
            path: log4j.properties
---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-taskmanager
spec:
  replicas: 2
  selector:
    matchLabels:
      app: flink
      component: taskmanager
  template:
    metadata:
      labels:
        app: flink
        component: taskmanager
    spec:
      containers:
      - name: taskmanager
        image: flink:latest
        workingDir: /opt/flink
        command: ["/bin/bash", "-c", "$FLINK_HOME/bin/taskmanager.sh start; \
          while :;
          do
            if [[ -f $(find log -name '*taskmanager*.log' -print -quit) ]];
              then tail -f -n +1 log/*taskmanager*.log;
            fi;
          done"]
        ports:
        - containerPort: 6122
          name: rpc
        livenessProbe:
          tcpSocket:
            port: 6122
          initialDelaySeconds: 30
          periodSeconds: 60
        volumeMounts:
        - name: flink-config-volume
          mountPath: /opt/flink/conf/
        securityContext:
          runAsUser: 9999  # refers to user _flink_ from official flink image, change if necessary
      volumes:
      - name: flink-config-volume
        configMap:
          name: flink-config
          items:
          - key: flink-conf.yaml
            path: flink-conf.yaml
          - key: log4j.properties
            path: log4j.properties
---

apiVersion: v1
kind: Service
metadata:
  name: flink-jobmanager
spec:
  type: ClusterIP
  ports:
  - name: rpc
    port: 6123
  - name: blob
    port: 6124
  - name: ui
    port: 8081
  selector:
    app: flink
    component: jobmanager
---

apiVersion: v1
kind: Service
metadata:
  name: flink-jobmanager-rest
spec:
  type: NodePort
  ports:
  - name: rest
    port: 8081
    targetPort: 8081
  selector:
    app: flink
    component: jobmanager
```

安装：

``` bash
kubectl apply -f flink.yaml
```

如何访问 JobManager 的 UI ？在 TKE 或者 EKS 上，支持 LoadBalancer 类型的 Service，可以将 JobManager 的 UI 用 LB 暴露：

``` bash
kubectl patch service flink-jobmanager -p '{"spec":{"type":"LoadBalancer"}}'
```

卸载：

``` bash
kubectl delete -f flink.yaml
```

> 若要部署到不同命名空间，请提前创建好命名空间并在所有 kubectl 命令后加 -n <NAMESPACE>

## Job Cluster 模式部署

Job cluster 模式，给每一个独立的Job 部署一整套Flink 集群；我们会给每一个job 制作一个容器镜像，并给它分配专用的资源，所以这个Job不用和其他Job 来通信，可以独立的扩缩容。

下面将详细解析如何通过job cluster 模式在kubernetes 上运行flink 任务， 主要有下面几个步骤：

* Compile and package the Flink job jar.
* Build a Docker image containing the Flink runtime and the job jar.
* Create a Kubernetes Job for Flink JobManager.
* Create a Kubernetes Service for this Job.
* Create a Kubernetes Deployment for Flink TaskManagers.
* Enable Flink JobManager HA with ZooKeeper.
* Correctly stop and resume Flink job with SavePoint facility.

### 编写一个Flink 流式处理任务

我们创建一个简单的流式处理任务；这个任务是从网络上读取数据流，5秒钟统计一次单词个数并输出; 核心代码如下：

``` java
DataStream<Tuple2<String, Integer>> dataStream = env
    .socketTextStream("10.0.100.12", 9999)
    .flatMap(new Splitter())
    .keyBy(0)
    .timeWindow(Time.seconds(5))
    .sum(1);

dataStream.print();
```

10.0.100.12 是产生数据流的机器地址；在启动jobcluster 之前，通过nc -lk 9999, 来启动服务。

完整的maven 项目地址：https://github.com/jizhang/flink-on-kubernetes 编译打包 mvn clean package , 最终可以找到编译好的 jar 包 flink-on-kubernetes-0.0.1-SNAPSHOT-jar-with-dependencies.jar

### 制作镜像

基于官方 flink 基础镜像，https://hub.docker.com/_/flink 制作业务镜像:

``` dockerfile
FROM ccr.ccs.tencentyun.com/caryguo/flink:latest

COPY --chown=flink:flink flink-on-kubernetes-0.0.1-SNAPSHOT-jar-with-dependencies.jar /opt/flink/lib/

USER flink

docker build -t ccr.ccs.tencentyun.com/caryguo/count-word-flink-on-kubernetes:0.0.1 .
```

### 部署 JobManager

``` yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: flink-on-kubernetes-jobmanager
spec:
  template:
    metadata:
      labels:
        app: flink
        instance: flink-on-kubernetes-jobmanager
    spec:
      restartPolicy: OnFailure
      containers:
      - name: jobmanager
        image: ccr.ccs.tencentyun.com/caryguo/count-word-flink-on-kubernetes:0.0.1
        command: ["/opt/flink/bin/standalone-job.sh"]
        args: ["start-foreground",
               "-Djobmanager.rpc.address=flink-on-kubernetes-jobmanagerr",
               "-Dparallelism.default=1",
               "-Dblob.server.port=6124",
               "-Dqueryable-state.server.ports=6125"]
        ports:
        - containerPort: 6123
          name: rpc
        - containerPort: 6124
          name: blob
        - containerPort: 6125
          name: query
        - containerPort: 8081
          name: ui
```

参考： http://shzhangji.com/blog/2019/08/24/deploy-flink-job-cluster-on-kubernetes/

## Native Kuubernetes 方式部署

在 flink 1.10 之前，在 k8s 上运行 flink 任务都是需要事先指定 TaskManager 的个数以及CPU和内存的，存在一个问题：大多数情况下，你在任务启动前根本无法精确的预估这个任务需要多少个TaskManager，如果指定多了，会导致资源浪费，指定少了，会导致任务调度不起来。本质原因是在 Kubernetes 上运行的 Flink 任务并没有直接向 Kubernetes 集群去申请资源。

在 2020-02-11 发布了 flink 1.10，该版本完成了与 k8s 集成的第一阶段，实现了向 k8s 动态申请资源，就像跟 yarn 或 mesos 集成那样。

### 部署步骤

确定 flink 部署的 namespace，这里我选 "flink"，确保 namespace 已创建:

``` bash
kubectl create ns flink
```

创建 RBAC (创建 ServiceAccount 绑定 flink 需要的对 k8s 集群操作的权限):

``` yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flink
  namespace: flink

---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flink-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- kind: ServiceAccount
  name: flink
  namespace: flink
```

利用 job 运行启动 flink 的引导程序 (请求 k8s 创建 jobmanager 相关的资源: service, deployment, configmap):

``` yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: boot-flink
  namespace: flink
spec:
  template:
    spec:
      serviceAccount: flink
      restartPolicy: OnFailure
      containers:
      - name: start
        image: flink:1.10
        workingDir: /opt/flink
        command: ["bash", "-c", "$FLINK_HOME/bin/kubernetes-session.sh \
          -Dkubernetes.cluster-id=roc \
          -Dkubernetes.jobmanager.service-account=flink \
          -Dtaskmanager.memory.process.size=1024m \
          -Dkubernetes.taskmanager.cpu=1 \
          -Dtaskmanager.numberOfTaskSlots=1 \
          -Dkubernetes.container.image=flink:1.10 \
          -Dkubernetes.namespace=flink"]
```

* `kubernetes.cluster-id`: 指定 flink 集群的名称，后续自动创建的 k8s 资源会带上这个作为前缀或后缀
* `kubernetes.namespace`: 指定 flink 相关的资源创建在哪个命名空间，这里我们用 `flink` 命名空间
* `kubernetes.jobmanager.service-account`: 指定我们刚刚为 flink 创建的 ServiceAccount
* `kubernetes.container.image`: 指定 flink 需要用的镜像，这里我们部署的 1.10 版本，所以镜像用 `flink:1.10`

部署完成后，我们可以看到有刚刚运行完成的 job 的 pod 和被这个 job 拉起的 flink jobmanager 的 pod，前缀与配置 `kubernetes.cluster-id` 相同:

``` bash
$ kubectl -n flink get pod
NAME                  READY   STATUS      RESTARTS   AGE
roc-cf9f6b5df-csk9z   1/1     Running     0          84m
boot-flink-nc2qx      0/1     Completed   0          84m
```

还有 jobmanager 的 service:

``` bash
$ kubectl -n flink get svc
NAME       TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
roc        ClusterIP      172.16.255.152   <none>           8081/TCP,6123/TCP,6124/TCP   88m
roc-rest   LoadBalancer   172.16.255.11    150.109.27.251   8081:31240/TCP               88m
```

访问 http://150.109.27.251:8081 即可进入此 flink 集群的 ui 界面。

### 参考资料

* Active Kubernetes integration phase 2 - Advanced Features: https://issues.apache.org/jira/browse/FLINK-14460
* Apache Flink 1.10.0 Release Announcement: https://flink.apache.org/news/2020/02/11/release-1.10.0.html
* Native Kubernetes Setup Beta (flink与kubernetes集成的官方教程): https://ci.apache.org/projects/flink/flink-docs-release-1.10/ops/deployment/native_kubernetes.html


## operator 模式

google flink kubernetes operator

参考: http://shzhangji.com/blog/2019/08/24/deploy-flink-job-cluster-on-kubernetes/