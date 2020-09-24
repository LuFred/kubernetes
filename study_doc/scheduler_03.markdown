前面说到了在执行schduler命令之后，创建了sched对象，执行sched.Run(ctx)，  
接下去分析sched.Run(ctx)内部实现：
源码文件：  
> pkg/scheduler/scheduer.go


```
307行
// Run begins watching and scheduling. It waits for cache to be synced, then starts scheduling and blocked until the context is done.
func (sched *Scheduler) Run(ctx context.Context) {
	sched.SchedulingQueue.Run()
	wait.UntilWithContext(ctx, sched.scheduleOne, 0)
	sched.SchedulingQueue.Close()
}
```
源码可见这个Run一共只有3行代码：
1.sched.SchedulingQueue.Run()
> 启用schedulerlingQueue队列，负责存储等待调度的pod，也就是说只有pod需要调度都会进入这个queue，而Run函数就是启动这个goroutine。  
2.wait.UntilWithContext(ctx, sched.scheduleOne, 0)  
> UntilWithContext是一个辅助函数，里面是个死循环，上面3个参数表示每0秒执行一次函数sched.scheduleOne，直到上下文退出为止。  
3.sched.SchedulingQueue.Close()
> 显而易见，关闭SchedulingQueue退出。

下面分别看看这3步都在做什么。

### sched.SchedulingQueue.Run()  
SchedulingQueue本身是一个interface，这里我们要找到的是具体的实现类。  
翻会前面初始化scheduler的代码，会在pkg/schduler/factory.go文件内找到如下代码：
```
	podQueue := internalqueue.NewSchedulingQueue(
		lessFn,
		internalqueue.WithPodInitialBackoffDuration(time.Duration(c.podInitialBackoffSeconds)*time.Second),
		internalqueue.WithPodMaxBackoffDuration(time.Duration(c.podMaxBackoffSeconds)*time.Second),
		internalqueue.WithPodNominator(nominator),
	)
```
而NewSchedulingQueue函数点进去会发现它调用了个NewPriorityQueue，NewPriorityQueue返回的对象是一个PriorityQueue指针，因此可以断定scheduler对象中的SchedulingQueue使用的是PriorityQueue结构体，它实现了接口SchedulingQueue.  
现在又看sched.SchedulingQueue.Run()变成了看PriorityQueue对象的Run具体实现。  

#### PriorityQueue.Run  （pgk/scheduler/internal/queue/scheduling_queue.go）

第240行
```
// Run starts the goroutine to pump from podBackoffQ to activeQ
func (p *PriorityQueue) Run() {
    //每秒循环一次，将到达补偿时间的pod重新仍回到activeQ
	go wait.Until(p.flushBackoffQCompleted, 1.0*time.Second, p.stop)
    // 每30秒循环一次，将unschedulableQ中的pod仍会podBackoffQ 或activeQ
	go wait.Until(p.flushUnschedulableQLeftover, 30*time.Second, p.stop)
}
```
从注释上直到Run的作用是运行一个goroutine，将podBackoffQ队列中的内容转到activeQ。在这里需要说明的是PriorityQueue对象有3个Queue。
> activeQ : 存放待调度的pod，scheduler就是从该队列中获取待调度的pod，它是一个对Heap对象，堆头是优先级最高的pod。  
> unschedulableQ : 保存已尝试并确定不可调度的pod，内部是一个map对象。
> podBackoffQ : 称为补偿队列，也是一个Heap对象，按补偿完成时间排序，它的作用是补偿队列，它的包含从unschedulableQ队列移动过来的pod，当补偿完成时，该队列中的pod会重新转到activeQ。


### wait.UntilWithContext(ctx, sched.scheduleOne, 0)  

### sched.SchedulingQueue.Close()