---
title: "TensorFlow"
state: Alpha
---

## 简介

Kubeflow 开始是从支持tensorflow分布式训练演化而来，现在已经是一个由众多子项目组成的开源产品，愿景是在 Kubernetes 上运行各种机器学习工作负载， 包括tensorflow,pytorch等主流计算引擎，面向机器学习场景的工作流引擎argo等。支持从模型开发，模型训练到最终服务部署的全链条工具。采用tf-operator进行分布式tf训练可以方便提交任务，具有重试，容错等优势

## 安装部署

### 安装 kubeflow

``` bash
curl -sL https://github.com/kubeflow/kfctl/releases/download/v1.0/kfctl_v1.0-0-g94c35cf_linux.tar.gz | tar -xzvf -C /home/ubuntu/kubeflow
export PATH=$PATH:/home/ubuntu/kubeflow
export KF_NAME=my-kubeflow
export BASE_DIR=/home/ubuntu/kubeflow
export KF_DIR=${BASE_DIR}/${KF_NAME}
export CONFIG_URI=https://raw.githubusercontent.com/kubeflow/manifests/v1.0-branch/kfdef/kfctl_k8s_istio.v1.0.0.yaml
kfctl build -V -f $(CONFIG_URI)
```

###  安装 tf-operator

``` bash
kustomize build my-kubeflow/kustomize/tf-job-crds/overlays/application | kubectl create –f -
kustomize build my-kubeflow/kustomize/tf-job-operator/overlays/application | kubectl create –f
```

### 测试

``` bash
git clone https://github.com/tensorflow/k8s.git
kubectl create –f k8s/examples/v1/dist-mnist/tf_job_mnist.yaml
```

## 使用kube-batch调度器

k8s缺省的调度器以pod为单位进行调度,也不提供按训练任务优先级优先级进行整体调度的功能，但是分布式机器学习会同时启动多种task，比如PS,WORKER，而且每种task都会有多个副本，这样有可能出现一个任务的部分pod被创建，而其他pod处于pending状态，出现资源被占用但是训练任务不能被启动执行的状态。kube-batch就是解决这种问题的批调度器，另外也提供队列和资源公平调度drf等功能。


### 部署kube-batch

``` bash
git clone http://github.com/kubernetes-sigs/kube-batch
cd kube-batch/deployment/kube-batch
helm install --name kube-batch --namespace kube-system
```

缺省安装后kube-batch缺乏必要的权限来lw集群资源，需要额外创建RBAC，添加对应serviceaccount的cluster-admin权限用于lw集群中的node, pod等对象来维护自身的资源视图

### 修改tf-operator

启动参数添加enable-gang-scheduling=true

tf-operator缺省使用volcano调度器，添加启动参数gang-scheduler-name=kube-batch, （或者在TFJOB的申请中指定调度器名）

修改RBAC添加tf-operator serviceaccount访问podgroups资源的权限

### 测试

``` yaml
apiVersion: scheduling.incubator.k8s.io/v1alpha1
kind: PodGroup
metadata:
  name: tfjob-group
spec:
  minMember: 6
 
---
 
apiVersion: "kubeflow.org/v1"
kind: "TFJob"
metadata:
  name: "dist-mnist-for-e2e-test"
spec:
  tfReplicaSpecs:
    PS:
      replicas: 2
      restartPolicy: Never
      template:
        metadata:
          annotations:
            scheduling.k8s.io/group-name: tfjob-group
        spec:
          schedulerName: kube-batch
          containers:
            - name: tensorflow
              image: ccr.ccs.tencentyun.com/chenyong/tf-dist-mnist-test:1.0
    Worker:
      replicas: 4
      restartPolicy: Never
      template:
        metadata:
          annotations:
            scheduling.k8s.io/group-name: tfjob-group
        spec:
          schedulerName: kube-batch
          containers:
            - name: tensorflow
              image: ccr.ccs.tencentyun.com/chenyong/tf-dist-mnist-test:1.0
```

## 使用volcano调度器

### 部署

``` bash
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/master/installer/volcano-development.yaml
```


###  修改tf-operator启用volcano调度器

tf-operator缺省使用volcano，只要添加enable-gang-scheduling=true启动参数就可以，非常方便

###  测试

``` yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: dist-mnist-for-e2e-test
spec:
  minMember: 6
---
apiVersion: "kubeflow.org/v1"
kind: "TFJob"
metadata:
  name: "dist-mnist-for-e2e-test"
spec:
  tfReplicaSpecs:
    PS:
      replicas: 2
      restartPolicy: Never
      template:
        spec:
          containers:
            - name: tensorflow
              image: ccr.ccs.tencentyun.com/chenyong/tf-dist-mnist-test:1.0
    Worker:
      replicas: 4
      restartPolicy: Never
      template:
        spec:
          containers:
            - name: tensorflow
              image: ccr.ccs.tencentyun.com/chenyong/tf-dist-mnist-test:1.0
```

### 直接使用volcano进行训练

volcano除了包含批调度器外，还实现了一组CRD和controller， 通过创建CRD就可以直接启动分布式tensorflow的训练任务

``` yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: tensorflow-dist-mnist
spec:
  minAvailable: 3
  schedulerName: volcano
  plugins:
    env: []
    svc: []
  policies:
    - event: PodEvicted
      action: RestartJob
  tasks:
    - replicas: 1
      name: ps
      template:
        spec:
          containers:
            - command:
                - sh
                - -c
                - |
                  PS_HOST=`cat /etc/volcano/ps.host | sed 's/$/&:2222/g' | sed 's/^/"/;s/$/"/' | tr "\n" ","`;
                  WORKER_HOST=`cat /etc/volcano/worker.host | sed 's/$/&:2222/g' | sed 's/^/"/;s/$/"/' | tr "\n" ","`;
                  export TF_CONFIG={\"cluster\":{\"ps\":[${PS_HOST}],\"worker\":[${WORKER_HOST}]},\"task\":{\"type\":\"ps\",\"index\":${VK_TASK_INDEX}},\"environment\":\"cloud\"};
                  python /var/tf_dist_mnist/dist_mnist.py
              image: volcanosh/dist-mnist-tf-example:0.0.1
              name: tensorflow
              ports:
                - containerPort: 2222
                  name: tfjob-port
              resources: {}
          restartPolicy: Never
    - replicas: 2
      name: worker
      policies:
        - event: TaskCompleted
          action: CompleteJob
      template:
        spec:
          containers:
            - command:
                - sh
                - -c
                - |
                  PS_HOST=`cat /etc/volcano/ps.host | sed 's/$/&:2222/g' | sed 's/^/"/;s/$/"/' | tr "\n" ","`;
                  WORKER_HOST=`cat /etc/volcano/worker.host | sed 's/$/&:2222/g' | sed 's/^/"/;s/$/"/' | tr "\n" ","`;
                  export TF_CONFIG={\"cluster\":{\"ps\":[${PS_HOST}],\"worker\":[${WORKER_HOST}]},\"task\":{\"type\":\"worker\",\"index\":${VK_TASK_INDEX}},\"environment\":\"cloud\"};
                  python /var/tf_dist_mnist/dist_mnist.py
              image: volcanosh/dist-mnist-tf-example:0.0.1
              name: tensorflow
              ports:
                - containerPort: 2222
                  name: tfjob-port
              resources: {}
          restartPolicy: Never
```

## tf-operator on EKS

tf-operator也可以在eks平台上部署和调度任务，但是目前还不支持扩展调度器，如果eks资源池足够大，不会出现部分pod被调度的情况
