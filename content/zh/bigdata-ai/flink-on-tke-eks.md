---
title: "Flink on TKE/EKS"
state: TODO
hidden: true
---



2.2 job cluster 模式
Job cluster 模式，给每一个独立的Job 部署一整套Flink 集群；我们会给每一个job 制作一个容器镜像，并给它分配专用的资源，所以这个Job不用和其他Job 来通信，可以独立的扩缩容。

下面将详细解析如何通过job cluster 模式在kubernetes 上运行flink 任务， 主要有下面几个步骤：
Compile and package the Flink job jar.
Build a Docker image containing the Flink runtime and the job jar.
Create a Kubernetes Job for Flink JobManager.
Create a Kubernetes Service for this Job.
Create a Kubernetes Deployment for Flink TaskManagers.
Enable Flink JobManager HA with ZooKeeper.
Correctly stop and resume Flink job with SavePoint facility.

2.2.1 编写一个Flink 流式处理任务
我们创建一个简单的流式处理任务；这个任务是从网络上读取数据流，5秒钟统计一次单词个数并输出; 核心代码如下：

DataStream<Tuple2<String, Integer>> dataStream = env
    .socketTextStream("10.0.100.12", 9999)
    .flatMap(new Splitter())
    .keyBy(0)
    .timeWindow(Time.seconds(5))
    .sum(1);

dataStream.print();


10.0.100.12 是产生数据流的机器地址；在启动jobcluster 之前，通过nc -lk 9999, 来启动服务。

完整的maven 项目地址：https://github.com/jizhang/flink-on-kubernetes
编译打包 mvn clean package , 最终可以找到编译好的 jar 包
flink-on-kubernetes-0.0.1-SNAPSHOT-jar-with-dependencies.jar

2.2.2 制作镜像
基于官方 flink 基础镜像，https://hub.docker.com/_/flink
制作业务镜像:
FROM ccr.ccs.tencentyun.com/caryguo/flink:latest

COPY --chown=flink:flink flink-on-kubernetes-0.0.1-SNAPSHOT-jar-with-dependencies.jar /opt/flink/lib/

USER flink

docker build -t ccr.ccs.tencentyun.com/caryguo/count-word-flink-on-kubernetes:0.0.1 .

2.3.2 部署JobManager 
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









http://shzhangji.com/blog/2019/08/24/deploy-flink-job-cluster-on-kubernetes/


2.3 operator 模式
google flink kubernetes operator 

参考 http://shzhangji.com/blog/2019/08/24/deploy-flink-job-cluster-on-kubernetes/
知乎案例
