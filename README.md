# MonitoringTools
Setting up Monitoring tools on an Existing EKS cluster

# Setting up Monitoring tools on an Existing EKS cluster

This Terraform script is used to set up a monitoring stack in an existing Amazon EKS cluster. The stack includes Prometheus for metrics collection and alerting, Grafana for data visualization, and Alertmanager for handling alerts.

# Before script
Note- Alertmanager requires an IAM role attached to instance which cannot create EBS volume. Resolution is to create IAM policy (see json below) to read and write EBS features and attach to the IAM role. Once completed, you can run the script and it should work.

Json to create the IAM policy
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachVolume",
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:DeleteSnapshot",
                "ec2:DeleteTags",
                "ec2:DeleteVolume",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstances",
                "ec2:DescribeSnapshots",
                "ec2:DescribeTags",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumesModifications",
                "ec2:DetachVolume",
                "ec2:ModifyVolume"
            ],
            "Resource": "*"
        }
    ]
}
```
Here's a block-by-block breakdown:

**Block 1:**
Declares a Terraform variable cluster_name with a default value of A0-EKS-cluster. This is the name of the EKS cluster you want to connect to.

**Block 2:**
Retrieves data about an existing EKS cluster named cluster_name.

**Block 3:**
Retrieves data about the auth credentials for the EKS cluster cluster_name.

**Block 4 & 5:**
These two blocks configure the Helm and Kubernetes providers using the EKS cluster endpoint, the decoded CA certificate for the cluster, and the auth token.

**Block 6:**
Creates a new Kubernetes namespace named monitoring.

**Block 7:**
Deploys the kube-prometheus-stack Helm chart from the Prometheus community Helm charts repository into the monitoring namespace. This Helm chart packages Prometheus, Alertmanager, Grafana, and some default dashboards and exporters. The chart is configured to expose Prometheus via a LoadBalancer service, and use an AWS EBS CSI storage class for persistent volumes.

**Block 8:**
Deploys the Grafana Helm chart from the Grafana Helm charts repository into the monitoring namespace. The chart is configured to expose Grafana via a LoadBalancer service and to enable ingress.

**Block 9:**
Deploys the Alertmanager Helm chart from the Prometheus community Helm charts repository into the monitoring namespace. The chart is configured to expose Alertmanager via a LoadBalancer service, to use an AWS EBS CSI storage class for persistent volumes, and to enable ingress.

**Block 10 & 11:**
Defines a storage class named aws-ebs-csi that uses AWS EBS as the storage provisioner. This storage class is used for the persistent volumes in the Prometheus and Alertmanager deployments.

**Block 12:**
Deploys the AWS EBS CSI driver into the kube-system namespace, enabling the Kubernetes cluster to manage AWS EBS volumes.

**Blocks 13, 16, & 19:**
These blocks run a local command to get the hostname of the LoadBalancer services for Prometheus, Grafana, and Alertmanager, respectively, and save it to a local file.

**Blocks 14, 17, & 20:**
Reads the contents of the local files containing the LoadBalancer hostnames for Prometheus, Grafana, and Alertmanager, respectively.

**Blocks 15, 18, & 21:**
Creates DNS CNAME records in AWS Route 53 for Prometheus, Grafana, and Alertmanager, respectively. The CNAME records point to the hostnames of the LoadBalancer services. These records allow you to access the Prometheus, Grafana, and Alertmanager web UIs using custom domain names.

In summary, this script configures AWS EKS cluster with a monitoring stack consisting of Prometheus, Grafana, and Alertmanager. Each service is made accessible via a LoadBalancer and a custom DNS name, and the persistent storage for Prometheus and Alertmanager is backed by AWS EBS volumes.

# Adding Email Notifications to Alertmanager Configuration

Alertmanager can send notifications to different receivers based on their labels. Here, we will add an SMTP (Simple Mail Transfer Protocol) configuration to send email notifications. This will require an accessible SMTP server.

To add an SMTP email notification, you need to modify the Alertmanager configuration in your Kubernetes ConfigMap. Please follow the steps below:

1. First, open your Alertmanager ConfigMap for editing. If your ConfigMap is named alertmanager-config and is in the monitoring namespace, you would use:

`kubectl -n monitoring edit configmap <alertmanager_configmapname>`

2. Alertmanager configurations are usually in YAML format. Below is a template for an SMTP configuration:

```
global:
  smtp_smarthost: 'smtp.example.com:587' # The address of the SMTP server
  smtp_from: 'alertmanager@example.com' # The address from which the email is sent
  smtp_auth_username: 'smtp-user' # The SMTP user
  smtp_auth_password: 'smtp-password' # The SMTP password
  smtp_require_tls: true # Whether to require TLS

route:
  group_by: ['...'] # Replace '...' with your group_by labels
  receiver: 'team-emails'
  routes:
  - match:
      severity: critical
    receiver: 'team-emails'

receivers:
- name: 'team-emails'
  email_configs:
  - to: 'team@example.com' # Replace with the email address to send notifications to
```

Be sure to replace the values like 'smtp.example.com:587', 'alertmanager@example.com', 'smtp-user', 'smtp-password', and 'team@example.com' with your actual SMTP settings and email addresses.

3. Once you're done modifying the ConfigMap, save and close the file. Kubernetes will update the ConfigMap on the cluster.

4. Alertmanager needs to be restarted to pick up the changes. If Alertmanager is running as a Deployment named alertmanager in the monitoring namespace, use:

`kubectl -n monitoring rollout restart deployment alertmanager`

or run the below
`Invoke-WebRequest -Method Post -Uri http://<alertmanager loadbalancer IP>:9093/-/reload`

Once the Alertmanager is up and running, it will start sending alerts to the email addresses specified in the SMTP configuration.

Please note that the actual names of your ConfigMaps, Deployments, and namespaces might be different, and you will need to replace monitoring and alertmanager-config with the correct ones for your environment.

Also, this configuration doesn't cover more advanced use-cases, such as sending different alerts to different email addresses. You can create multiple receivers and routing rules to handle more complex scenarios.

For more details, you can refer to the official Alertmanager documentation: https://prometheus.io/docs/alerting/latest/configuration/


# Adding Custom Alert Rules to Prometheus Configuration and connect prometheus to the right Alertmanager service
To connect Prometheus to your running Alertmanager service, confirm on the prometheus configuration what service it is set as a Target.
You can do this from the GUI, naviage to the Configuration. Find what service is listed under the "regex" parameter. If it isn;t the service we have setup for Alertmanager(usually the case by default), you would have to perform the steps below to change the service and recive alerts from prometheus on Alertmanager.

`kubectl -n monitoring get prometheus`
`kubectl -n monitoring edit prometheus <prometheus config name>` 
Edit and change regex value to the right Alertmanager service which should be "alertmanager" in this case. Save config file and reload both prometheus and Alertmanager.

Prometheus alerting rules allow you to define conditions that should cause alerts to be fired. These rules are written in the Prometheus query language - PromQL.

Below is a step by-step guide to help you add a custom rule to your Prometheus setup:

1. Find your PrometheusRule configuration file: PrometheusRule objects define a desired Prometheus alerting rule in a Kubernetes cluster. These are usually stored in YAML files. They are generally in the same location as your other Kubernetes configuration files, but the exact location may depend on your setup.

2. Create or Edit the PrometheusRule object: Open the file with your preferred text editor. If you already have a PrometheusRule object, you can add your custom rules to it. If you don't, you can create a new one.

A simple example of a PrometheusRule file:

```
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    prometheus: example-prometheus
    role: alert-rules
  name: example-prometheus-rules
  namespace: default
spec:
  groups:
  - name: example-group
    rules:
    - alert: ExampleAlert
      expr: metric_name > 0
      for: 10m
      labels:
        severity: page
      annotations:
        summary: High traffic detected
```

Here, we define a rule named ExampleAlert which triggers when metric_name > 0 for a duration of 10m. This rule is grouped under the group example-group.

Annotations provide additional information about the alert while labels allow for filtering and defining alert routes.

Replace metric_name > 0 with your custom rule.

3. Apply the configuration: Once you have edited the PrometheusRule object, apply the changes using kubectl.

`kubectl apply -f <prometheus-rule-file>.yaml`

4. Reload Prometheus configuration: In many environments, Prometheus automatically reloads the configuration when it changes. or manually reload using command below

`Invoke-WebRequest -Method Post -Uri http://<prometheus loadbalancer IP>:9090/-/reload`

**Note:** The actual names of your PrometheusRule objects and Kubernetes configurations might be different and you will need to replace example-prometheus, example-prometheus-rules, example-group, and ExampleAlert with the correct ones for your environment.

For more details, you can refer to the official Prometheus documentation: https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/

If you are using the Prometheus Operator from CoreOS, you can find more information in the Prometheus Operator documentation: https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/user-guides/alerting.md
