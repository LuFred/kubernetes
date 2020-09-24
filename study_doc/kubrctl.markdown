https://developer.ibm.com/articles/a-tour-of-the-kubernetes-source-code/#overview


编译
> make WATH='cmd/kubectl'

启动k8s开发环境
> PATH=$PATH KUBERNETES_PROVIDER=local hack/local-up-cluster.sh

测试，创建ngins
> cluster/kubectl.sh create -f ~/nginx_kube_example/nginx_pod.yaml
