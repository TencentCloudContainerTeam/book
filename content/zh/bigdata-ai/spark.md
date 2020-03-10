---
title: "Spark on TKE/EKS"
state: Alpha
---

## 概念说明

- Spark Application：由客户编写，并提交到spark框架中执行的用户代码逻辑。
- Spark Driver：运行Spark Application代码逻辑中的main函数。
- Spark Context：启动spark application的时候创建，作为Spark 运行时环境。
- Spark Executor：负责执行单独的Task。
- Spark Client mode：client模式下，driver可以运行在集群外。
- Spark Cluster mode：cluster模式下，driver需要运行在集群中。

## 架构模式

spark on k8s最先只支持standalone模式，而自spark 2.3.0版本开始，支持kubernetes原生调度。

1 standalone mode

2 k8s native mode
![spark-on-k8s.png](/images/spark-on-k8s.png)

处理流程如下：

- spark-submit提交spark程序到k8s集群中。
- spark-submit创建driver pod。
- driver 创建executor pod，并把自己设置成executor pod的ownerReferences。
- executor成功运行，并给driver上报ready 状态。
- driver下发任务到executor 中执行。
- 当任务完成之后，executor 自动终止，并被driver 清理。
- driver pod输出log，后维持在completed状态。

## 用户指南

### 编译

备注: 安装jdk1.8

```bash
# 下载
$ git clone https://github.com/apache/spark.git
# 解压
$ mkdir -p /usr/local/bin
$ tar -zxvf jdk-8u241-linux-x64.tar.gz -C /usr/local/java

$ export JAVA_HOME=/usr/local/bin/jdk1.8.0_241
$ export PATH=$JAVA_HOME/bin:$PATH
# 执行编译
$ cd ./spark/ && ./build/mvn -Pkubernetes -DskipTests clean package
```

提示：除了编译源码之外，还可以直接下载spark的release package。link：https://spark.apache.org/downloads.html

### 构建镜像

缺省软件镜像源很慢, 建议修改`./spark/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/Dockerfile`并添加如下腾讯云源。

```
RUN sed -i 's/deb.debian.org/mirrors.tencentyun.com/g' /etc/apt/sources.list  && \
sed -i 's/security.debian.org/mirrors.tencentyun.com/g' /etc/apt/sources.list
```
开始构建基础镜像并上传到ccr仓库
```bash
# 构建
sudo ./bin/docker-image-tool.sh -r ccr.ccs.tencentyun.com/hale -t 2.4.5 build
# 上传
sudo ./bin/docker-image-tool.sh -r ccr.ccs.tencentyun.com/hale -t 2.4.5 push
```

### 应用代码准备

一般来说，应用代码逻辑会编译在同一份jar文件中，Driver和executor运行过程中都会用到这个jar，最新的spark已经支持以下两种方式提供：

1 远程，把应用代码放到远程，比如hdfs或者http server，然后以远程uri的方式（http://）提供。一般推荐这种方式。

比如临时启动http server, 然后通过http://10.0.0.172:8000/来访问。

```bash
$ cd /root/spark-2.4.5-bin-hadoop2.7/examples/jars && python -m SimpleHTTPServer
```

2 本地，把应用代码提前打包到自建的镜像中，然后在命令行中以local://的方式提供。这种方式需要每次提交代码后再重新制作镜像，相对远程方式来说比较麻烦。

提示：直接从运行submit所在客户端的本地文件系统中提供应用代码，当前是不支持的。

### 集群准备

1 打开集群的外网访问或者内网访问。

2 创建命名空间（比如spark）并确保成功下发镜像仓库秘钥`qcloudregistrykey`。


### 连接集群

1 client mode

在client模式下，driver能够运行在集群外的vm上，但是driver必须要能够与集群的apiserver通信，TKE/EKS默认提供的是证书+token的认证方式（在控制台上通过集群管理-->基本信息-->集群凭证获取）。

另外，TKE/EKS集群提供的是自签名证书，java/scala代码缺省不认，因此，需要先将自签名证书导入到vm的证书库中，成为可信任证书。

```bash
# 添加
$ keytool -importcert -alias sparkonk8s -keystore cacerts -storepass changeit -file ./ca.crt
# 删除
$ keytool -delete -v -keystore cacerts -storepass changeit --alias sparkonk8s
```

接下来，就可以在集群外的vm上执行spark-submit了，命令如下，其中应用代码以远程方式（http:/）提供：

```bash
$ $SPARK_HOME/bin/spark-submit \
    --master k8s://https://$CLS_DOMIN:443 \
    --deploy-mode client \
    --class org.apache.spark.examples.SparkPi \
    --conf spark.kubernetes.container.image=$IMAGE_REPO/spark:2.4.5 \
    --conf spark.kubernetes.authenticate.caCertFile=/root/test/ca.crt \
    --conf spark.kubernetes.authenticate.oauthToken=HBlC0S64r8y2EUfqTxxxxFDzHlG5lub \
    --conf spark.executor.instances=2 \
    --conf spark.kubernetes.namespace=spark \
    --conf spark.kubernetes.container.image.pullSecrets=qcloudregistrykey \
    http://10.0.0.172:8000/examples/jars/spark-examples_2.11-2.4.5.jar
```


2 cluster mode

在cluster模式下，driver和excutor都以pod的方式运行在集群中，同时，driver可以直接通过serviceaccount与集群的apisever认证，也比较方便。因此，一般推荐用户使用这种方式。

创建serviceaccount和rolebinding的命令如下：

```bash
$ kubectl create serviceaccount spark --namespace spark
$ kubectl create rolebinding spark-edit --clusterrole=edit --serviceaccount=spark:spark --namespace=spark
```

接下来，根据spark-submit的执行环境，可以分为两种方式：



2.1 集群外节点上以命令方式执行

在集群外的vm节点上执行spark-submit命令的时候，spark-submit就需要与集群的apiserver建立通信了，可以参考client mode介绍的证书+token的认证方式与apiserver认证。命令如下，其中应用代码以本地方式（local:/）提供：

```bash
$SPARK_HOME/bin/spark-submit \
    --master k8s://https://$CLS_DOMIN:443 \
    --deploy-mode cluster \
    --class org.apache.spark.examples.SparkPi \
    --conf spark.kubernetes.container.image=$IMAGE_REPO/spark:2.4.5 \
    --conf spark.kubernetes.authenticate.submission.caCertFile=/root/test/ca.crt \
    --conf spark.kubernetes.authenticate.submission.oauthToken=HBlC0S64r8y2EUfFDzHlG5lub \
    --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
    --conf spark.executor.instances=2 \
    --conf spark.kubernetes.namespace=spark \
    --conf spark.kubernetes.container.image.pullSecrets=qcloudregistrykey \
local:///opt/spark/examples/jars/spark-examples_2.11-2.4.5.jar
```

2.2. 集群内以job的方式执行

spark-submit运行在pod中，可以通过`serviceAccountName: spark`与apiserver通信。job的样例如下：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name:  spark-submit
  namespace: spark
spec:
  template:
    metadata:
      name:  spark-submit-example
    spec:
      serviceAccountName: spark
      containers:
      - name: spark-submit-example
        args:
        - /opt/spark/bin/spark-submit
        - --master
        - k8s://https://kubernetes.default.svc.cluster.local:443
        - --deploy-mode
        - cluster
        - --conf
        - spark.kubernetes.container.image=ccr.ccs.tencentyun.com/hale/spark:2.4.5
        - --conf
        - spark.kubernetes.authenticate.driver.serviceAccountName=spark
        - --conf
        - spark.kubernetes.namespace=spark
        - --conf
        - spark.executor.instances=2
        - --conf
        - spark.kubernetes.container.image.pullSecrets=qcloudregistrykey
        - --class
        - org.apache.spark.examples.SparkPi
        - local:///opt/spark/examples/jars/spark-examples_2.11-2.4.4.jar
        env:
        - name: SPARK_HOME
        value: /opt/spark
        resources: {}
        image: ccr.ccs.tencentyun.com/hale/spark:2.4.5
        imagePullPolicy: Always
```



参数说明：

- --master： 指定要连接的k8s集群，格式为`k8s://<api_server_host>:<k8s-apiserver-port>`，其中api_server_host默认是https，而k8s-apiserver-port必须要显示指定，即使是443。

- --deploy-mode：部署模式，当前仅支持cluster和client这两种模式。

- --conf spark.kubernetes.authenticate.submission.caCertFile：submit任务时，与apiserver建立连接使用。当在client模式下，用`spark.kubernetes.authenticate.caCertFile`替代。
- --conf spark.kubernetes.authenticate.submission.oauthToken：submit任务时，与apiserver建立连接使用。当在client模式下，用`spark.kubernetes.authenticate.oauthToken`替代。
-  --conf spark.kubernetes.authenticate.driver.serviceAccountName：指定driver pod使用的serviceAccountName。

-  --conf spark.executor.instances：指定executors的具体实例数。

-  --conf spark.kubernetes.namespace：指定driver和executors pod运行的命名空间。
- 应用代码提供的方式：当前支持远程（http:/）和本地（local:/），一般建议是使用远程方式，但是在cluster模式下，如果客户提前把应用代码放到了镜像中，也可以使用本地方式。

### Driver 和 Executor 相关配置

1 镜像设置

- spark.kubernetes.container.image：指定容器镜像
- spark.kubernetes.driver.container.image：指定driver pod的容器镜像，非必须
- spark.kubernetes.executor.container.image：指定executor pod的容器镜像，非必须
- spark.kubernetes.container.image.pullPolicy：指定镜像的拉取策略，默认为IfNotPresent
- spark.kubernetes.container.image.pullSecrets：自动镜像的拉取秘钥

2 资源设置

不指定资源的情况下，driver和Executor的资源默认为

```yaml
resources:
	limits:
 		memory: 1408Mi
  requests:
    cpu: "1"
    memory: 1408Mi
```

- spark.driver.memory：设置driver的request.memory， limit.memory与request.memory保持一致
- spark.executor.memory：设置executor的request.memory，limit.memory与request.memory保持一致
- spark.driver.cores：设置driver的request.cpu， 当前进支持整数
- spark.executor.cores：设置driver的request.cpu，当前进支持整数

- spark.kubernetes.driver.limit.cores：设置driver的limit.cpu
- spark.kubernetes.executor.request.cores：设置driver的request.cpu，可以覆盖`spark.executor.cores`设置的值
- spark.kubernetes.executor.limit.cores：设置executor的limit.cpu

3 labels或者annotation设置

- spark.kubernetes.driver.label.[LabelName]：设置driver pod的label
- spark.kubernetes.driver.annotation.[AnnotationName]：设置driver pod的annotation
- spark.kubernetes.executor.label.[LabelName]：设置executor pod的label
- spark.kubernetes.executor.annotation.[AnnotationName]：设置executor pod的annotation

4 其他设置

- spark.kubernetes.node.selector.[labelKey]：设置driver 和executor pod的nodeSelector

### 检查相关

1 查看日志

```bash
$ kubectl -n=<namespace> logs -f <driver-pod-name>
```

2 访问Driver UI

当driver 运行在vm节点上时，可以直接访问`http://<vm-ip>:4040`

当driver 运行在pod中时，可以通过如下方式访问：

```bash
# 先执行kubeclt port-forward 
$ kubectl port-forward <driver-pod-name> 4040:4040
# 然后访问http://<node-ip>:4040
```



### 已知问题

1 eks要求实例规格配置

运行在eks上的pod，都需要配置具体的实例规格，可以通过设置annotation的方式给配置实例规格，参考如下：

```yaml
# 给driver pod设置实例规格，以1c2g为例
spark.kubernetes.driver.annotation.eks.tke.cloud.tencent.com/cpu=1
spark.kubernetes.driver.annotation.eks.tke.cloud.tencent.com/mem=2Gi
# 给executor pod设置实例规格，以1c2g为例
spark.kubernetes.executor.annotation.eks.tke.cloud.tencent.com/cpu=1
spark.kubernetes.executor.annotation.eks.tke.cloud.tencent.com/mem=2Gi
```

### 参考链接

- https://spark.apache.org/docs/latest/running-on-kubernetes.html#running-spark-on-kubernetes
- https://github.com/kubernetes/kubernetes/issues/34377
