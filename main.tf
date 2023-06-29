variable "cluster_name" {
  description = "The name of the EKS cluster to connect to"
  default = "A2-EKS-cluster"
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks --region eu-north-1 update-kubeconfig --name A2-EKS-cluster"
  }

  depends_on = [helm_release.prometheus]
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"

  set {
    name  = "prometheus.service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "server.persistentVolume.storageClass"
    value = "aws-ebs-csi"
  }
  set {
   name  = "server.ingress.enabled"
   value = "true"
  }
 set {
  name  = "server.ingress.hosts[0].name"
  value = "prometheustest.example.com"
 }
 set {
  name  = "server.ingress.hosts[0].path"
  value = "/"
 }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"

  values = [
    <<-EOT
    service:
      type: LoadBalancer
    ingress:
      enabled: true
      hosts:
        - grafanatest.example.com
      paths:
        - /
    EOT
  ]
}

resource "helm_release" "alertmanager" {
  name       = "alertmanager"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "alertmanager"
  namespace  = "monitoring"
  timeout    = 300

  depends_on = [
    kubernetes_namespace.monitoring,
  ]

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "persistentVolume.storageClass"
    value = "aws-ebs-csi"
  }
  set {
  name  = "server.ingress.enabled"
  value = "true"
  }
 set {
  name  = "server.ingress.hosts[0].name"
  value = "alertmanager.example.com"
 }
 set {
  name  = "server.ingress.hosts[0].path"
  value = "/"
 }
}

# prometheus
resource "null_resource" "get_lb_hostname" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' > lb_hostname.txt"
  }

  depends_on = [
    helm_release.prometheus,
  ]
}

data "local_file" "lb_hostname" {
  depends_on = [
    null_resource.get_lb_hostname,
  ]

  filename = "${path.module}/lb_hostname.txt"
}

resource "aws_route53_record" "lb_cname" {
  zone_id = "......" #enter Route 53 Hosted Zone ID
  name    = "prometheus.example.com"
  type    = "CNAME"
  records = [replace(trimspace(data.local_file.lb_hostname.content), "'", "")]
  ttl     = "300"
}

# Grafana
resource "null_resource" "get_grafana_lb_hostname" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' > grafana_lb_hostname.txt"
  }

  depends_on = [
    helm_release.grafana,
  ]
}

data "local_file" "grafana_lb_hostname" {
  depends_on = [
    null_resource.get_grafana_lb_hostname,
  ]

  filename = "${path.module}/grafana_lb_hostname.txt"
}

resource "aws_route53_record" "grafana_lb_cname" {
  zone_id = "......"
  name    = "grafana.example.com"
  type    = "CNAME"
  records = [replace(trimspace(data.local_file.grafana_lb_hostname.content), "'", "")]
  ttl     = "300"
}

# Alertmanager
resource "null_resource" "get_alertmanager_lb_hostname" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "kubectl get svc alertmanager -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' > alertmanager_lb_hostname.txt"
  }

  depends_on = [
    helm_release.alertmanager,
  ]
}

data "local_file" "alertmanager_lb_hostname" {
  depends_on = [
    null_resource.get_alertmanager_lb_hostname,
  ]

  filename = "${path.module}/alertmanager_lb_hostname.txt"
}

resource "aws_route53_record" "alertmanager_lb_cname" {
  zone_id = "....."
  name    = "alertmanager.example.com"
  type    = "CNAME"
  records = [replace(trimspace(data.local_file.alertmanager_lb_hostname.content), "'", "")]
  ttl     = "300"
}
