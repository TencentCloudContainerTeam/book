---
title: "TKE 常见问题"
---

##### 为什么挂载的 CFS 容量是 10G

创建负载的时候可以挂载 NFS，如果使用 CFS 提供的 NFS 服务，当 NFS 被挂载好去查看实际容量时发现是 10G。

原因是: nfs的盘，默认的挂载大小为10G，支持自动扩容

cfs 扩容方式: 小于1T，容量到50%触发自动扩容，每次加100G; 大于 1T,到80%触发自动扩容。每次加500G

cfs 收费方式: 计费是根据实际的使用量，小于10G不收费，多于10G开始收费

##### 为什么 controller-manager 和 scheduler 状态显示 Unhealthy

``` bash
kubectl get cs
NAME                 STATUS      MESSAGE                                                                                        ERROR
scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: getsockopt: connection refused
controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: getsockopt: connection refused
etcd-0               Healthy     {"health": "true"}
```

查看组件状态发现 controller-manager 和 scheduler 状态显示 Unhealthy，但是集群正常工作，是因为TKE metacluster托管方式集群的  apiserver 与 controller-manager 和 scheduler 不在同一个节点导致的，这个不影响功能。如果发现是 Healthy 说明 apiserver 跟它们部署在同一个节点，所以这个取决于部署方式。

**更详细的原因：**

apiserver探测controller-manager 和 scheduler写死直接连的本机
``` go
func (s componentStatusStorage) serversToValidate() map[string]*componentstatus.Server {
	serversToValidate := map[string]*componentstatus.Server{
		"controller-manager": {Addr: "127.0.0.1", Port: ports.InsecureKubeControllerManagerPort, Path: "/healthz"},
		"scheduler":          {Addr: "127.0.0.1", Port: ports.InsecureSchedulerPort, Path: "/healthz"},
	}
```
源码：https://github.com/kubernetes/kubernetes/blob/v1.14.3/pkg/registry/core/rest/storage_core.go#L256

相关 issue:
- https://github.com/kubernetes/kubernetes/issues/19570
- https://github.com/kubernetes/enhancements/issues/553

##### 为什么 kubectl top nodes 不行

执行 `kubectl top nodes` 报 NotFound:
``` bash
$ kubectl top nodes
Error from server (NotFound): the server could not find the requested resource
```

这是因为 metrics api 的 apiservice 指向的 TKE 自带的 hpa-metrics-server，而 hpa-metrics-server 不支持 node 相关的指标，hpa-metrics-server 主要用于 HPA 功能(Pod 横向自动伸缩)，伸缩判断指标最开始使用的 metrics api，后来改成了 custom metrics api。

`kubectl top nodes` 是请求的 metrics api，由于 TKE 控制台的 HPA 功能不依赖 metrics api 了，可以自行修改其 apiservice 的指向为自建的 metrics server，比如最简单的官方开源的 [metrics-server](https://github.com/kubernetes-sigs/metrics-server)，参考 [在 TKE 中安装 metrics-server](../../andon/install-metrics-server-on-tke/)，或者如果你集群中使用 prometheus，可以安装 [k8s-prometheus-adapter](https://github.com/DirectXMan12/k8s-prometheus-adapter) 来适配 metrics api，也可以直接部署 [kube-prometheus](https://github.com/coreos/kube-prometheus) 安装更全面的 prometheus on kubernetes 全家桶套件。

不管怎样，最后确保 `v1beta1.metrics.k8s.io` 这个 apiservice 指向了你自己的 metrics api 适配服务，通过 `kubectl -n kube-system edit apiservice v1beta1.metrics.k8s.io` 可以修改。

##### 我从 TKE 集群所在 VPC 之外有办法能直接访问容器 IP 吗

如果你的网络已经通过专线、对等连接、云联网或 VPN 等方式跟 TKE 集群所在 VPC 做了打通，可以参考 [容器路由互通](../../network/container-route/) 来进一步打通容器路由。
