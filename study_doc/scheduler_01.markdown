Scheduler

对于每一个新创建或者是未调度的pod，kube-scheduler负责为它们选择匹配最有的node。

在群集中，满足Pod调度要求的节点称为可行节点。 如果没有合适的节点，则在调度程序能够放置之前，该容器将保持未调度状态。
> 不存在调度超时？

scheduler找到Pod的可行节点集合，然后运行一组函数对可行节点进行评分，并从可行节点中选择得分最高的节点来运行Pod。 然后，调度程序在称为绑定的过程中将此决定通知API服务器。

调度决策需要考虑的因素包括个人和集体资源需求，硬件/软件/策略约束，亲和力和反亲和力，数据局部性，工作负载间的干扰等。
> Factors that need taken into account for scheduling decisions include individual and collective resource requirements, hardware / software / policy constraints, affinity and anti-affinity specifications, data locality, inter-workload interference, and so on.

kube-scheduler 匹配pod和node 分2步骤：
> doc:https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/  
1.筛选  
2.计分

### 1.筛选
过滤步骤会在可行的情况下找到一组Pod。 例如，PodFitsResources筛选器检查候选节点是否具有足够的可用资源来满足Pod的特定资源请求。 在此步骤之后，节点列表将包含任何合适的节点。 通常，会有不止一个。 如果列表为空，则该Pod尚无法安排。

### 2.计分
在计分步骤中，调度程序对筛选出的节点进行排名，以选择最合适的Pod位置。 调度程序根据活动评分规则为每个筛选出的节点分配一个分数。

最后，kube-scheduler将Pod分配给排名最高的节点。 如果存在多个得分相等的节点，则kube-scheduler会随机选择其中之一。


### Scheduling Policies
调度策略可用于指定 predicates and priorities，在kube-scheduler运行以分别过滤和给节点计分时。
可通过命令：
> kube-scheduler --policy-config-file <filename>
> kube-scheduler --policy-configmap <ConfigMap> 

以下predicates 实现过滤：

PodFitsHostPorts：检查节点是否为Pod请求的Pod端口具有空闲端口（网络协议类型）。

PodFitsHost：检查Pod是否通过其主机名指定了特定的Node。

PodFitsResources：检查节点是否具有可用资源（例如CPU和内存）以满足Pod的要求。

MatchNodeSelector：检查Pod的节点选择器是否与节点的标签匹配。

NoVolumeZoneConflict：考虑到该存储的故障区域限制，评估节点上Pod请求的卷是否可用。

NoDiskConflict：评估Pod是否可以由于其请求的卷以及已安装的卷而适合节点。

MaxCSIVolumeCount：决定应附加多少CSI卷，以及是否超出配置的限制。

CheckNodeMemoryPressure：如果节点正在报告内存压力，并且没有配置的异常，则不会在此处安排Pod。

CheckNodePIDPressure：如果节点报告进程ID稀缺，并且没有配置的异常，则不会在此处安排Pod。

CheckNodeDiskPressure：如果某个节点正在报告存储压力（文件系统已满或几乎已满），并且没有配置的异常，则不会在此处安排Pod。

CheckNodeCondition：节点可以报告它们具有完全完整的文件系统，网络不可用或者kubelet尚未准备好运行Pod。如果为节点设置了这样的条件，并且没有配置的异常，则不会在此处安排Pod。

PodToleratesNodeTaints：检查Pod的容忍度是否可以容忍Node的污点。

CheckVolumeBinding：评估Pod是否适合其请求的容量。这适用于绑定和未绑定的PVC。


以下priorities实现评分：

SelectorSpreadPriority：将Pod跨主机分布，考虑到属于同一Service，StatefulSet或ReplicaSet的Pod。

InterPodAffinityPriority：实现首选的pod间亲和力和反亲和力(affininity and antiaffinity)。

LeastRequestedPriority：使用较少的请求资源来偏爱节点。换句话说，放置在节点上的Pod越多，这些Pod使用的资源越多，此策略给出的排名就越低。

MostRequestedPriority：使用请求最多的资源支持节点。该策略将使计划的Pod适应运行整体工作负载所需的最少数量的节点。

RequestedToCapacityRatioPriority：使用默认资源评分功能形状创建基于requestToCapacity的ResourceAllocationPriority。

BalancedResourceAllocation：支持具有平衡资源使用量的节点。

NodePreferAvoidPodsPriority：根据节点注释scheduler.alpha.kubernetes.io/preferAvoidPods对节点进行优先级排序。您可以使用它来暗示两个不同的Pod不应在同一Node上运行。

NodeAffinityPriority：根据PreferredDuringSchedulingIgnoredDuringExecution中指示的节点相似性调度首选项对节点进行优先级排序。您可以在将Pod分配给节点中了解有关此内容的更多信息。

TaintTolerationPriority：根据节点上无法忍受的污点数量，为所有节点准备优先级列表。此策略会考虑该列表来调整节点的等级。

ImageLocalityPriority：支持已经具有本地缓存​​该Pod的容器映像的节点。

ServiceSpreadingPriority：对于给定的服务，此策略旨在确保该服务的Pod在不同的节点上运行。它有利于调度到没有Pod的节点上，因为该节点已经在此处分配了服务。总体结果是，该服务对于单个节点故障变得更具弹性。

EqualPriority：对所有节点赋予相等的权重。

EvenPodsSpreadPriority：实现首选的Pod拓扑扩展约束。

### Scheduling Profiles 
可以配置实现不同调度阶段的插件，包括：队列排序，过滤器，得分，绑定，保留，许可等。 还可以将kube-scheduler配置为运行不同的配置文件。  
调度是通过以下扩展点公开的一系列阶段中进行的：
QueueSort：这些插件提供了排序功能，用于对调度队列中的暂挂Pod进行排序。一次可能只启用一个队列排序插件。
PreFilter：这些插件用于在过滤之前预处理或检查有关Pod或群集的信息。他们可以将广告连播标记为不可调度。
Filter：这些插件与调度策略中的 Predicates等效，用于过滤掉无法运行Pod的节点。过滤器按配置顺序调用。如果没有节点通过所有筛选器，则pod被标记为不可调度。
PreScore：这是一个信息扩展点，可用于进行预评分工作。
Score：这些插件为已通过过滤阶段的每个节点提供分数。然后，调度程序将选择加权分数总和最高的节点。
Reserve：这是一个信息扩展点，当为给定Pod保留资源时通知插件。插件还实现了Unreserve调用，该调用在Reserve期间或之后失败的情况下被调用。
Permit：这些插件可以阻止或延迟Pod的绑定。
PreBind：这些插件执行绑定Pod之前所需的任何工作。
Bind：插件将Pod绑定到节点。绑定插件按顺序调用，一旦完成绑定，其余的插件将被跳过。至少需要一个绑定插件。
PostBind：这是一个信息扩展点，在绑定Pod之后会调用它。

Scheduling plugins
默认情况下启用以下插件，实现这些扩展点中的一个或多个：
SelectorSpread：优先于属于Services的Pod跨节点传播一种将在Pod集合上运行的应用程序公开为网络服务的方式。ReplicaSets和StatefulSets扩展点：PreScore，Score。
ImageLocality：支持已经具有Pod运行的容器映像的节点。延伸点：得分。
TaintToleration：实现污点和容忍。实现扩展点：过滤器，Prescore，分数。
NodeName：检查Pod规范节点名称是否与当前节点匹配。扩展点：过滤器。
NodePorts：检查节点是否具有用于请求的Pod端口的空闲端口。扩展点：PreFilter，Filter。
NodePreferAvoidPods：根据节点注释scheduler.alpha.kubernetes.io/preferAvoidPods对节点评分。延伸点：得分。
NodeAffinity：实现节点选择器和节点相似性。扩展点：过滤器，得分。
PodTopologySpread：实现Pod拓扑传播。扩展点：PreFilter，Filter，PreScore，Score。
NodeUnschedulable：筛选出将.spec.unschedulable设置为true的节点。扩展点：过滤器。
NodeResourcesFit：检查节点是否具有Pod正在请求的所有资源。扩展点：PreFilter，Filter。
NodeResourcesBalancedAllocation：如果在其中安排了Pod，则偏爱那些会获得更平衡资源使用的节点。延伸点：得分。
NodeResourcesLeastAllocated：支持资源分配低的节点。延伸点：得分。
VolumeBinding：检查节点是否具有或是否可以绑定请求的卷。扩展点：PreFilter，Filter，Reserve，PreBind。
VolumeRestrictions：检查节点中装入的卷是否满足特定于卷提供程序的限制。扩展点：过滤器。
VolumeZone：检查请求的卷是否满足它们可能具有的任何区域要求。扩展点：过滤器。
NodeVolumeLimits：检查节点是否可以满足CSI容量限制。扩展点：过滤器。
EBSLimits：检查节点是否可以满足AWS EBS容量限制。扩展点：过滤器。
GCEPDLimits：检查节点是否可以满足GCP-PD音量限制。扩展点：过滤器。
AzureDiskLimits：检查节点是否可以满足Azure磁盘卷限制。扩展点：过滤器。
InterPodAffinity：实现Pod间的亲和力和反亲和力。扩展点：PreFilter，Filter，PreScore，Score。
PrioritySort：提供基于默认优先级的排序。扩展点：QueueSort。
DefaultBinder：提供默认的绑定机制。扩展点：绑定。
DefaultPreemption：提供默认的抢占机制。扩展点：PostFilter。
您还可以通过组件配置API启用以下默认情况下未启用的插件：

NodeResourcesMostAllocated：支持资源分配高的节点。延伸点：得分。
RequestedToCapacityRatio：根据分配的资源的配置功能偏爱节点。延伸点：得分。
NodeResourceLimits：支持满足Pod资源限制的节点。扩展点：PreScore，得分。
CinderVolume：检查节点是否可以满足OpenStack Cinder的容量限制。扩展点：过滤器。
NodeLabel：根据配置的标签过滤和/或评分节点。扩展点：过滤器，得分。
ServiceAffinity：检查属于服务的Pod是否适合由配置的标签定义的一组节点。该插件还有利于在节点之间分布属于服务的Pod。扩展点：PreFilter，Filter，Score。
