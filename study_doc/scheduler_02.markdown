入口：
> cmd/kube-scheduler/scheduler.go
```
func main() {
	rand.Seed(time.Now().UnixNano())

	command := app.NewSchedulerCommand()

	// TODO: once we switch everything over to Cobra commands, we can go back to calling
	// utilflag.InitFlags() (by removing its pflag.Parse() call). For now, we have to set the
	// normalize func and add the go flag set by hand.
	pflag.CommandLine.SetNormalizeFunc(cliflag.WordSepNormalizeFunc)
	// utilflag.InitFlags()
	logs.InitLogs()
	defer logs.FlushLogs()

	if err := command.Execute(); err != nil {
		os.Exit(1)
	}
}
```
command.Execute()  

1.NewSchedulerCommand()  
初始化一个scheduler命令对象  
2.command.Execute()  
执行  

Execute执行什么呢？  
回过头查看NewSchedulerCommand源代码  

> cmd/kube-scheduler/app/server.go
因为已经知道k8s的命令框架使用的是cobra，因此很容易看到NewSchedulerCommand函数内的核心逻辑是Command对象中的Run函数
```
cmd := &cobra.Command{
		Use: "kube-scheduler",
		Long: `The Kubernetes scheduler is a control plane process which assigns
Pods to Nodes. The scheduler determines which Nodes are valid placements for
each Pod in the scheduling queue according to constraints and available
resources. The scheduler then ranks each valid Node and binds the Pod to a
suitable Node. Multiple different schedulers may be used within a cluster;
kube-scheduler is the reference implementation.
See [scheduling](https://kubernetes.io/docs/concepts/scheduling-eviction/)
for more information about scheduling and the kube-scheduler component.`,
		Run: func(cmd *cobra.Command, args []string) {
			if err := runCommand(cmd, opts, registryOptions...); err != nil {
				fmt.Fprintf(os.Stderr, "%v\n", err)
				os.Exit(1)
			}
		},
		Args: func(cmd *cobra.Command, args []string) error {
			for _, arg := range args {
				if len(arg) > 0 {
					return fmt.Errorf("%q does not take any arguments, got %q", cmd.CommandPath(), args)
				}
			}
			return nil
		},
	}
```

而其函数内部又执行了一个runCommand(cmd, opts, registryOptions...)，  
```
// runCommand runs the scheduler.
func runCommand(cmd *cobra.Command, opts *options.Options, registryOptions ...Option) error {
	verflag.PrintAndExitIfRequested()
	cliflag.PrintFlags(cmd.Flags())

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
    //基于传入的参数和配置，创建一个基础的scheduler对象
	cc, sched, err := Setup(ctx, opts, registryOptions...)
	if err != nil {
		return err
	}

	if len(opts.WriteConfigTo) > 0 {
		if err := options.WriteConfigFile(opts.WriteConfigTo, &cc.ComponentConfig); err != nil {
			return err
		}
		klog.Infof("Wrote configuration to: %s\n", opts.WriteConfigTo)
		return nil
	}
    //执行实际的Run
	return Run(ctx, cc, sched)
}

```
这里主要是创建一个scheduler，表示scheduler的daemon程序储备差不多了  

Scheduler结构体参数：
```
type Scheduler struct {
	SchedulerCache internalcache.Cache
	Algorithm core.ScheduleAlgorithm
	NextPod func() *framework.QueuedPodInfo
	Error func(*framework.QueuedPodInfo, error)
	StopEverything <-chan struct{}
	SchedulingQueue internalqueue.SchedulingQueue
	Profiles profile.Map
	client clientset.Interface
}

```
说明：
NextPod：一个阻塞直到下一个需要调度的pod到达，这里作者没有考虑使用channel，是认为channel中调度pod本身需要花费时间，且不希望pod在channel中停留的时间导致超时。
StopEverything： scheduler关闭事件channel
SchedulingQueue：待调度的pod队列

然后实际调用的就是这个Run(ctx, cc, sched)方法，传入了sched对象。  
接着往下看这个Run  
## 查看Run内部逻辑
Run函数申明： 
> Run executes the scheduler based on the given configuration. It only returns on error or when context is done.   
> func Run(ctx context.Context, cc *schedulerserverconfig.CompletedConfig, sched *scheduler.Scheduler) error 

根据Run注释可知，Run已经启动，永远不会终止，除非抛异常或上下文结束时退出。  
接收3个参数
* ctx: 上下文
* cc: 运行scheduler所需要的所有配置
* sched: 核心参数，Scheduler对象，其作用：监视新的未调度的pod。 试图找到适合的节点，并将pod和node的绑定关系写回到api服务器。


顺着Run内部的代码往下看：  
#### 1.
```

	// Configz registration.
	if cz, err := configz.New("componentconfig"); err == nil {
		cz.Set(cc.ComponentConfig)
	} else {
		return fmt.Errorf("unable to register configz: %s", err)
	}
```
这里做了2个动作  
1.注册一个带名称的config对象，保存在全局configs中  
2.将ComponentConfig保存到cz中，
查看ComponentConfig注释可知它保存了scheduler服务所需要的配置参数
```
// Config has all the context to run a Scheduler
type Config struct {
	// ComponentConfig is the scheduler server's configuration object.
	ComponentConfig kubeschedulerconfig.KubeSchedulerConfiguration
```

#### 2.??  
```
	// Prepare the event broadcaster.
	cc.EventBroadcaster.StartRecordingToSink(ctx.Done())
```
准备广播事件
>> 什么叫广播事件？

#### 3.初始化并启用健康检查 ??  
```
	// Setup healthz checks.
	var checks []healthz.HealthChecker
	if cc.ComponentConfig.LeaderElection.LeaderElect {
		checks = append(checks, cc.LeaderElection.WatchDog)
	}

    // Start up the healthz server.
	if cc.InsecureServing != nil {
		separateMetrics := cc.InsecureMetricsServing != nil
		handler := buildHandlerChain(newHealthzHandler(&cc.ComponentConfig, separateMetrics, checks...), nil, nil)
		if err := cc.InsecureServing.Serve(handler, 0, ctx.Done()); err != nil {
			return fmt.Errorf("failed to start healthz server: %v", err)
		}
	}
```
添加健康检查事件
LeaderElection: 定义领导者选举客户端的配置。  
LeaderElect:使领导者选举客户能够在执行主循环之前获得领导权。 在运行复制的组件以实现高可用性时启用此功能。    
InsecureServing:如果未nil则表示禁用在不安全端口上的服务，不安全指：http不包含身份验证或权限验证

#### 4.构建并启动Metrics服务??  
```
	if cc.InsecureMetricsServing != nil {
		handler := buildHandlerChain(newMetricsHandler(&cc.ComponentConfig), nil, nil)
		if err := cc.InsecureMetricsServing.Serve(handler, 0, ctx.Done()); err != nil {
			return fmt.Errorf("failed to start metrics server: %v", err)
		}
	}	
```

#### 5.构建并启动安全服务  
```
	if cc.SecureServing != nil {
		handler := buildHandlerChain(newHealthzHandler(&cc.ComponentConfig, false, checks...), cc.Authentication.Authenticator, cc.Authorization.Authorizer)
		// TODO: handle stoppedCh returned by c.SecureServing.Serve
		if _, err := cc.SecureServing.Serve(handler, 0, ctx.Done()); err != nil {
			// fail early for secure handlers, removing the old error loop from above
			return fmt.Errorf("failed to start secure server: %v", err)
		}
	}
```

#### 6.??  
```
	// Start all informers.
	cc.InformerFactory.Start(ctx.Done())

	// Wait for all caches to sync before scheduling.
	cc.InformerFactory.WaitForCacheSync(ctx.Done())
```


#### 7.执行sched.Run(ctx)  
```
	// If leader election is enabled, runCommand via LeaderElector until done and exit.
	if cc.LeaderElection != nil {
		cc.LeaderElection.Callbacks = leaderelection.LeaderCallbacks{
			OnStartedLeading: sched.Run,
			OnStoppedLeading: func() {
				klog.Fatalf("leaderelection lost")
			},
		}
		leaderElector, err := leaderelection.NewLeaderElector(*cc.LeaderElection)
		if err != nil {
			return fmt.Errorf("couldn't create leader elector: %v", err)
		}

		leaderElector.Run(ctx)

		return fmt.Errorf("lost lease")
	}

	// Leader election is disabled, so runCommand inline until done.
	sched.Run(ctx)
```