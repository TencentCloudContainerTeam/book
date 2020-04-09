---
title: "在 TKE 上搭建 Prometheus 监控系统"
weight: 10
---

如果集群不在大陆，可以直接 Prometheus-operator 官方 helm chart 包安装:

{{< tabs name="tab_with_code" >}}
{{{< tab name="Helm 2" codelang="bash" >}}
kubectl create ns monitoring
helm upgrade --install monitoring stable/prometheus-operator -n monitoring
{{< /tab >}}
{{< tab name="Helm 3" codelang="bash" >}}
# helm repo add stable https://kubernetes-charts.storage.googleapis.com
kubectl create ns monitoring
helm install monitoring stable/prometheus-operator -n monitoring
{{< /tab >}}}
{{< /tabs >}}

如果集群在大陆以内，连不上 helm 的 stable 仓库，可以使用这里定制的 chart (一些国内拉取不到的镜像同步到了腾讯云):

{{< tabs name="tab_with_code_2" >}}
{{{< tab name="Helm 2" codelang="bash" >}}
kubectl create ns monitoring
helm repo add tencent https://tencentcloudcontainerteam.github.io/charts
helm upgrade --install monitoring tencent/prometheus-operator -n monitoring
{{< /tab >}}
{{< tab name="Helm 3" codelang="bash" >}}
kubectl create ns monitoring
helm repo add tencent https://tencentcloudcontainerteam.github.io/charts
helm install monitoring tencent/prometheus-operator -n monitoring
{{< /tab >}}}
{{< /tabs >}}

更多自定义参数请参考: https://hub.helm.sh/charts/stable/prometheus-operator