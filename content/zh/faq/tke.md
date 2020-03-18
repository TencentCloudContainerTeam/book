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

##### TKE中的容器和IDC自建k8s中的容器网络可以互通么？

这个问题分两种情况，分别说明：
（1） IDC k8s 中的容器访问TKE 中的容器。
完全可以，tke 的容器网络默认是基于全局路由的模式，IDC 和 腾讯云拉通专线（或者接入云联网）后，只要将TKE 集群的容器路由下发到IDC 的网关，就可以实现访问。

（2） TKE 的容器访问IDC k8s 中的容器。
不一定：要看自建k8s 集群使用的网络模式，能否把容器路由发布到腾讯云的网关。
如果自建k8s 使用使用3层路由（如calico 的bgp模式），或者大二层（如macvlan）的模式网络模式，则可以将容器路由发布到云上，实现访问。
如果自建k8s 使用隧道网络模式（如flannel 或者calico 的ipip 模式），无法将路由发布出来，则无法访问。

##### IDC 集群是否可以纳管云上的cvm 么？

理论上可行，但不建议这么做，建议使用多集群方案，主要有以下几个原因：
1. IDC和云上cvm 依赖专线或者云联网互通，网络抖动和延迟都会对集群管理带来影响。
2. IDC的网络环境和云上不一样，需要根据实际情况选择合适的网络插件，导致IDC 和 云上的网络插件不一致，使容器网络的管理复杂度增高：
3. 目前还没有这样的客户案例，未经过生产验证，风险较高。
4. 通过多集群来避免但集群故障，使用原生fedration 或者 一些开源工具（如rancher）来管理多集群也很方便。 

##### 在TKE Pod 中为什么无法访问到公网？
在TKE 中，podip 首先snat 成nodeip, 然后通过nodeip 出公网。
podip snat 成nodeip 是通过k8s 组件 ip-masq-agent  修改iptables 规则来实现的。
TKE  默认 ip-masq-agent-config 配置在vpc 内不做snat, vpc 之外都做snat. 

所以如果pod 无法访问公网，需要分两种情况检查以下配置：
1. 如果node可以访问公网； 
检查ip-masq-agent-config 配置，podip 出公网时是否做了snat 。
2. 如果node 不可以访问公网
1)  检查/etc/resolv.conf ，看nameserver 配置是否正确，腾讯云主机默认nameserver如下：
   nameserver 183.60.83.19
   nameserver 183.60.82.98  
2)  如果域名解析没有问题，那就应该是公网ip 或者nat网关的问题，联系相关同事排查。

##### cfs挂载在pod下的时候root权限，我的pod启动是普通用户，没法写入cfs，怎么解决，你们有什么方案吗?
https://cloud.tencent.com/document/product/582/10951 

如cfs 文档所示，默认情况下文件系统的权限是755， 只有root 用户有写权限。
如果非root 用户要写，那么有两种情况：
1. 非root 用户在root 组，要求文件系统的权限为 775 (rwxrwxr-x)
2. 非root 用户不在root 组，要求文件系统权限为 777 (rwxrwxrwx)
总之用户要有对应的写权限。

具体如何改文件系统权限，可以咨询下cfs 的同事。
一种做法是：将nfs 挂载到本地，通过chmod 来改。




