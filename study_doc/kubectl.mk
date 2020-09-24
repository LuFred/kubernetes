

源码结构分析
api: 输出接口文档用，基本是json源码

build：构建脚本

cmd：所有的二进制可执行文件入口代码，也就是各种命令的接口代码。

pkg：项目diamante主目录，cmd只是接口，这里是具体实现。cmd类似业务代码，pkg类似核心

plugin：插件

test：测试相关的工具

third_party：第三方工具

docs：文档

example：使用例子

Godeps：项目依赖的Go的第三方包，比如docker客户端sdk，rest等

hack：工具箱，各种编译，构建，校验的脚本都在这。

## kubectl
kubernetes命令使用Cobra框架

cmd/kubectl目录下的kubectl.go是命令kubectl的main函数入口
内部引用了pkg/kubectl/cmd

1. cmd.NewDefaultKubectlCommand() //初始化默认kubectl命令

pkg/kubectl/cmd目录下
2.NewDefaultKubectlCommand：
	创建默认是kubectlCommand
	2.1NewDefaultPluginHandler 创建默认的处理函数插件
		插件名前缀：kubectl
	2.2 调用NewDefaultKubectlCommandWithArgs创建
		2.2.1 创建cobra.Command
		2.2.2 实际执行函数Run：runHelp
			出事话命令组（如create，logs等，命令）
			实际上这些命令源码在kubectl/pkg/cmd/目录下

## kubectl create 命令
k8s.io/kubectl/pkg/cmd/create目录下有一个create.go

###RunCreate:实现kubectl create命令的主要功能
NewBuilder使用了构造器模式
一旦完成所有初始化程序，该resource.NewBuilder函数最终将调用一个Do函数。
该Do函数至关重要，因为它返回一个Result对象，该对象将用于驱动我们的资源的创建。
该Do函数还创建一个Visitor对象，该对象可用于遍历与此调用相关联的资源列表resource.NewBuilder。
该Do功能的实现如下所示。
