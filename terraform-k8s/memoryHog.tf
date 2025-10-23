resource "kubernetes_namespace" "playgroundNamespace" {
  metadata {
    name = "playground"
  }
}

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
