# Test limits and requests in AKS

## Motivation

I know it is a good practice to use limits and requests for `k8s` resources, but what can go wrong otherwise? I want to play around with this in a fully automated way using `Terraform` in `AKS`.

## Prerequisites

A Linux or MacOS machine for local development. If you are running Windows, you first need to set up the *Windows Subsystem for Linux (WSL)* environment.

You need `docker cli` on your machine for testing purposes, and/or on the machines that run your pipeline.
You can these by running the following command:
```sh
docker --version
```

For `Azure` access you need the following:
- ARM_CLIENT_ID
- ARM_CLIENT_SECRET
- ARM_TENANT_ID
- ARM_SUBSCRIPTION_ID

## Implementation

To create a `AKS` cluster see [this tutorial](https://github.com/Frunza/create-aks-cluster-with-a-testing-application-via-terraform). I assume you already have this set up.

Now I want to create an application that uses the same memory and created more deployments for it with different limit and requests settings to see what happens. Such an application can look like:
```sh
resource "kubernetes_manifest" "memoryHog" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-best-effort"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 4
      selector = {
        matchLabels = {
          app = "memory-hog-best-effort"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-best-effort"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
          }]
        }
      }
    }
  }
}
```
Note how we can play around with the number of replicas(`replicas = 4`) and the memory usage(`--vm-bytes 400M`).

Depending how limits and requests are used, a deployment can fit in on of these categories:
-guaranteed: the limits and requests are the same
-burstable: the requested resources are lower than the limits
-best effort: no limits and requests are configured

With the `guaranteed` category, you basically tell `k8s` that you are sure your pod will stay within the limits you configure. If a container exceeds its limit, it will be terminated.
With the `burstable` category, you tell `k8s` that the pod need at least the resources configured by requests, but they can potentially grow to the defined limits. If a container exceeds its limit, it will be terminated.
With the `best effort` category, you say that you have no idea about the usage of the pod.

These categories play a role during scheduling. When nodes experience resource pressure (especially memory pressure), the kubelet evicts pods in the following order: `best effort` deployments pods first, then pods that exceed their requests in `burstable` deployments, and finally pods from `guaranteed` deployments, only if absolutely necessary.

Now let's start playing around.

Let's create deployments of each category with 6 pods:
```sh
resource "kubernetes_manifest" "memoryHogGuaranteed" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-guaranteed"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 6
      selector = {
        matchLabels = {
          app = "memory-hog-guaranteed"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-guaranteed"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "1000Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBurstable" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-burstable"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 6
      selector = {
        matchLabels = {
          app = "memory-hog-burstable"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-burstable"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "500Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBestEffort" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-best-effort"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 6
      selector = {
        matchLabels = {
          app = "memory-hog-best-effort"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-best-effort"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
          }]
        }
      }
    }
  }
}
```
If we call
```sh
kubectl get pods -n playground
```
we get
```sh
Failed
Unschedulable - 0/2 nodes are available: 2 Insufficient memory. preemption: 0/2 nodes are available: 2 No preemption victims found for incoming pod.
```

Since the `k8s` cluster contains 2 `Standard_D2_v2` nodes, there is not enough memory to schedule all pods, no scheduling will happen. Let's drop the number of pods in each deploy to 5:
```sh
resource "kubernetes_manifest" "memoryHogGuaranteed" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-guaranteed"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 5
      selector = {
        matchLabels = {
          app = "memory-hog-guaranteed"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-guaranteed"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "1000Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBurstable" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-burstable"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 5
      selector = {
        matchLabels = {
          app = "memory-hog-burstable"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-burstable"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "500Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBestEffort" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-best-effort"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 5
      selector = {
        matchLabels = {
          app = "memory-hog-best-effort"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-best-effort"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
          }]
        }
      }
    }
  }
}
```
If we call
```sh
kubectl get pods -n playground
```
we get
```sh
NAME                                      READY   STATUS    RESTARTS   AGE
memory-hog-best-effort-66df4d589d-46lnc   1/1     Running   0          5m59s
memory-hog-best-effort-66df4d589d-87qlp   1/1     Running   0          5m59s
memory-hog-best-effort-66df4d589d-jlwm8   1/1     Running   0          2m51s
memory-hog-best-effort-66df4d589d-t9mwv   1/1     Running   0          35s
memory-hog-best-effort-66df4d589d-vl887   1/1     Running   0          5m59s
memory-hog-burstable-596f497478-4hldf     1/1     Running   0          6m
memory-hog-burstable-596f497478-6mlsr     1/1     Running   0          6m
memory-hog-burstable-596f497478-6ppvd     1/1     Running   0          6m
memory-hog-burstable-596f497478-glbp9     1/1     Running   0          2m51s
memory-hog-burstable-596f497478-xkhzd     1/1     Running   0          35s
memory-hog-guaranteed-7f8bf797ff-9cn7v    1/1     Running   0          35s
memory-hog-guaranteed-7f8bf797ff-dk2bq    1/1     Running   0          6m
memory-hog-guaranteed-7f8bf797ff-fbkw9    1/1     Running   0          6m
memory-hog-guaranteed-7f8bf797ff-j4wt8    1/1     Running   0          2m51s
memory-hog-guaranteed-7f8bf797ff-kkl7j    1/1     Running   0          6m
```
Now everything seems to be running. Since we can be pretty sure that nothing will schedule at all if we increase the number of pods in the `guaranteed` and `burstable` deployments, let's instead the number of pods in the `best effort` deployment:
```sh
resource "kubernetes_manifest" "memoryHogGuaranteed" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-guaranteed"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 6
      selector = {
        matchLabels = {
          app = "memory-hog-guaranteed"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-guaranteed"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "1000Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBurstable" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-burstable"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 5
      selector = {
        matchLabels = {
          app = "memory-hog-burstable"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-burstable"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "500Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBestEffort" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-best-effort"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 10
      selector = {
        matchLabels = {
          app = "memory-hog-best-effort"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-best-effort"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 400M --vm-keep --oomable"]
          }]
        }
      }
    }
  }
}
```
If we call
```sh
kubectl get pods -n playground
```
we get
```sh
NAME                                      READY   STATUS                   RESTARTS        AGE
memory-hog-best-effort-66df4d589d-2dmm4   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-2q926   0/1     Pending                  0               47s
memory-hog-best-effort-66df4d589d-46lnc   0/1     ContainerStatusUnknown   1               28m
memory-hog-best-effort-66df4d589d-4hkd9   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-4kbm7   0/1     ContainerStatusUnknown   1               11m
memory-hog-best-effort-66df4d589d-55kjx   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-562j5   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-565pd   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-5jdbz   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-5tf8z   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-5z4mn   1/1     Running                  0               12m
memory-hog-best-effort-66df4d589d-652pq   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-65jqj   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-69mbm   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-6nn86   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-6pndv   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-6wwrk   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-75n4v   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-7dvcn   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-87qlp   0/1     ContainerStatusUnknown   1               28m
memory-hog-best-effort-66df4d589d-8ktml   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-8kxbn   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-8pfqv   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-96z6x   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-9lfxj   0/1     Pending                  0               2m29s
memory-hog-best-effort-66df4d589d-9vckp   1/1     Running                  0               12m
memory-hog-best-effort-66df4d589d-b4459   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-b8v9s   0/1     ContainerStatusUnknown   1               12m
memory-hog-best-effort-66df4d589d-bclbp   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-bf9wx   0/1     ContainerStatusUnknown   1               14m
memory-hog-best-effort-66df4d589d-bqt4h   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-cb792   0/1     ContainerStatusUnknown   1               14m
memory-hog-best-effort-66df4d589d-ckjr7   0/1     ContainerStatusUnknown   1               12m
memory-hog-best-effort-66df4d589d-d4z4x   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-d7kv5   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-d9svn   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-dgtsd   1/1     Running                  0               12m
memory-hog-best-effort-66df4d589d-dtldw   0/1     ContainerStatusUnknown   1               21m
memory-hog-best-effort-66df4d589d-dwdfd   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-f44p9   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-fxjqh   0/1     ContainerStatusUnknown   1               12m
memory-hog-best-effort-66df4d589d-g8bq9   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-g9zjm   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-gzbg6   0/1     Error                    0               12m
memory-hog-best-effort-66df4d589d-hgsvn   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-hlv28   0/1     Pending                  0               63s
memory-hog-best-effort-66df4d589d-hpxbl   0/1     ContainerStatusUnknown   1               14m
memory-hog-best-effort-66df4d589d-hxzt8   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-j6ft6   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-jlwm8   0/1     Error                    0               25m
memory-hog-best-effort-66df4d589d-kfc8d   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-kw8rd   1/1     Running                  0               3m19s
memory-hog-best-effort-66df4d589d-lcmc2   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-ljmll   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-lmq2f   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-lv666   1/1     Running                  0               12m
memory-hog-best-effort-66df4d589d-mj659   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-mpg4t   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-msdpq   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-mwr5s   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-ncvhx   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-nr5tv   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-p95n8   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-pbdrw   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-ptb7q   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-pxg5b   1/1     Running                  0               12m
memory-hog-best-effort-66df4d589d-pzdb5   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-qnk4s   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-r7sbt   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-rftzc   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-rkwlj   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-s5x25   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-sfjrl   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-sktsg   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-t7dht   0/1     ContainerStatusUnknown   1               14m
memory-hog-best-effort-66df4d589d-t9mwv   0/1     Error                    0               23m
memory-hog-best-effort-66df4d589d-tnpmj   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-tvrtb   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-v5tbf   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-vbtg2   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-vl887   0/1     ContainerStatusUnknown   1               28m
memory-hog-best-effort-66df4d589d-wrwbm   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-wrzfk   0/1     ContainerStatusUnknown   1               12m
memory-hog-best-effort-66df4d589d-wxs2z   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-wxw2b   1/1     Running                  0               10m
memory-hog-best-effort-66df4d589d-xd79v   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-xxw7n   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-xz4qk   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-z7nqx   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-zk4dn   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-zmbmb   0/1     Evicted                  0               11m
memory-hog-best-effort-66df4d589d-zmr2b   0/1     Evicted                  0               11m
memory-hog-burstable-596f497478-6mlsr     1/1     Running                  0               28m
memory-hog-burstable-596f497478-6ppvd     1/1     Running                  1 (4m55s ago)   28m
memory-hog-burstable-596f497478-7xx6k     1/1     Running                  1 (5m11s ago)   5m22s
memory-hog-burstable-596f497478-glbp9     1/1     Running                  0               25m
memory-hog-burstable-596f497478-xkhzd     1/1     Running                  2 (4m30s ago)   23m
memory-hog-guaranteed-7f8bf797ff-9cn7v    1/1     Running                  0               23m
memory-hog-guaranteed-7f8bf797ff-dk2bq    1/1     Running                  3 (3m28s ago)   28m
memory-hog-guaranteed-7f8bf797ff-fbkw9    1/1     Running                  0               28m
memory-hog-guaranteed-7f8bf797ff-j4wt8    1/1     Running                  1 (4m51s ago)   25m
memory-hog-guaranteed-7f8bf797ff-j56xl    0/1     Pending                  0               5m22s
memory-hog-guaranteed-7f8bf797ff-kkl7j    1/1     Running                  0               28m
```
Let's notice that 1 pod in `guaranteed` category deployment is pending and evictions happen to the pods in the `best effort` category deployment. But there is another another thing we should pay attention to: none of the pods in the `burstable` and `guaranteed` category deployments are evicted. This happens because the memory usage of those pods is under the defined limits. Let's change the memory usage to 800MB and see what happens:
```sh
resource "kubernetes_manifest" "memoryHogGuaranteed" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-guaranteed"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 4
      selector = {
        matchLabels = {
          app = "memory-hog-guaranteed"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-guaranteed"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 800M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "1000Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBurstable" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-burstable"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 4
      selector = {
        matchLabels = {
          app = "memory-hog-burstable"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-burstable"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 800M --vm-keep --oomable"]
            resources = {
              requests = {
                memory = "500Mi"
                cpu    = "100m"
              }
              limits = {
                memory = "1000Mi"
                cpu    = "500m"
              }
            }
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "memoryHogBestEffort" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "memory-hog-best-effort"
      namespace = kubernetes_namespace.playgroundNamespace.metadata[0].name
    }
    spec = {
      replicas = 4
      selector = {
        matchLabels = {
          app = "memory-hog-best-effort"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "memory-hog-best-effort"
          }
        }
        spec = {
          containers = [{
            name    = "memhog"
            image   = "alpine:3.20"
            command = ["sh","-c"]
            args    = ["apk add --no-cache stress-ng && exec stress-ng --vm 1 --vm-bytes 800M --vm-keep --oomable"]
          }]
        }
      }
    }
  }
}
```
If we call
```sh
kubectl get pods -n playground
```
we get
```sh
NAME                                      READY   STATUS                   RESTARTS      AGE
memory-hog-best-effort-6cdcbc667c-25fls   1/1     Running                  0             62s
memory-hog-best-effort-6cdcbc667c-5vpr2   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-7bm22   0/1     Pending                  0             16s
memory-hog-best-effort-6cdcbc667c-7fj2x   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-84zfv   1/1     Running                  0             48s
memory-hog-best-effort-6cdcbc667c-8nj8f   0/1     Error                    0             7m24s
memory-hog-best-effort-6cdcbc667c-9djdh   0/1     Error                    0             7m9s
memory-hog-best-effort-6cdcbc667c-9kffp   0/1     ContainerStatusUnknown   1             13m
memory-hog-best-effort-6cdcbc667c-9vmd8   0/1     ContainerStatusUnknown   1             14m
memory-hog-best-effort-6cdcbc667c-b4dd4   0/1     Evicted                  0             6m37s
memory-hog-best-effort-6cdcbc667c-dmqjq   0/1     Evicted                  0             6m37s
memory-hog-best-effort-6cdcbc667c-drkk8   0/1     ContainerStatusUnknown   1             14m
memory-hog-best-effort-6cdcbc667c-hjmln   0/1     ContainerStatusUnknown   1             14m
memory-hog-best-effort-6cdcbc667c-jd92c   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-jg57l   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-jszg5   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-lb9sx   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-pqcvr   0/1     ContainerStatusUnknown   1             14m
memory-hog-best-effort-6cdcbc667c-prz74   0/1     Error                    0             13m
memory-hog-best-effort-6cdcbc667c-qzrff   0/1     Error                    0             6m23s
memory-hog-best-effort-6cdcbc667c-tb4f9   1/1     Running                  0             6m37s
memory-hog-best-effort-6cdcbc667c-tml4l   0/1     Evicted                  0             6m37s
memory-hog-best-effort-6cdcbc667c-vnqx5   0/1     Evicted                  0             6m38s
memory-hog-best-effort-6cdcbc667c-xcl9z   0/1     Evicted                  0             6m38s
memory-hog-burstable-59d75b9549-7h8kx     1/1     Running                  0             14m
memory-hog-burstable-59d75b9549-7rmxb     0/1     ContainerStatusUnknown   1             14m
memory-hog-burstable-59d75b9549-fsmv9     1/1     Running                  0             14m
memory-hog-burstable-59d75b9549-fzk4l     1/1     Running                  2 (13m ago)   13m
memory-hog-burstable-59d75b9549-gb845     1/1     Running                  0             14m
memory-hog-guaranteed-fd685898d-7x2cr     1/1     Running                  2 (13m ago)   14m
memory-hog-guaranteed-fd685898d-tgn2l     1/1     Running                  0             14m
memory-hog-guaranteed-fd685898d-z4c7t     1/1     Running                  2 (13m ago)   14m
memory-hog-guaranteed-fd685898d-zlf2m     1/1     Running                  0             14m
```
Here we notice that a pod in the `burstable` category deployment is in `ContainerStatusUnknown` status, which was probably caused by an eviction. `ContainerStatusUnknown` is not a good state, since it indicates that the cluster is not healthy, which can happen if it is full. Other than that there is not much difference between the `guaranteed` and `burstable` categories. The pods in the `best effort` category deployment are the ones that get evicted and are in a very bad state, even though all deployments have 4 pods of each category.

## Conclusion

You should always use limits and requests for your deployments. For pods with a relatively stable memory usage, you can use the `guaranteed` category. For pods that can have different memory usage depending on the work they do, you should use the `burstable` category, so that you do no allocate a lot of memory which might not be actually used most of the time.
