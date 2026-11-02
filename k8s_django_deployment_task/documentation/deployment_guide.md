# Django on Amazon EKS: Persistent Static Storage

## Purpose and current status

This guide describes how I added persistent storage to the Django Healthchecks application deployed in the first task. The application runs in Amazon EKS, while PostgreSQL runs separately in Amazon RDS.

The storage task required me to understand Persistent Volumes, Persistent Volume Claims and StorageClasses, explain their relationship, and mount persistent storage into the application Pods for static files.

As of 2 November 2026, Task 2 is complete. The restored application has two available replicas, its storage PVC is Bound, both preparation Jobs are Complete, and the website Certificate is Ready. The final acceptance test passed: application Pods on different nodes read the original restored marker and identical CSS, replacement Pods retained those files, and all three external HTTPS checks returned 200. The CSS served over HTTPS also matched the file read from EFS.

## Why persistent storage was needed

Kubernetes can replace a Pod during an update, after a failure or when rescheduling work to another node. Files written only to a container's writable layer do not provide persistent application storage. An `emptyDir` can survive a container restart within the same Pod, but it is removed with that Pod.

In this project, Django's CSS, JavaScript and other static assets are prepared in the container image. For the storage exercise, I copied those assets into EFS and mounted the resulting directory into the web containers. This makes the shared static directory independent of the lifetime of any individual application Pod.

The database is a separate concern. PostgreSQL data stays in RDS; the Kubernetes volume in this task stores static files, not database files.

## Storage concepts

| Concept | Meaning | Resource used here |
| --- | --- | --- |
| PersistentVolume, or PV | A cluster-scoped Kubernetes resource describing available persistent storage. | `week8-healthchecks-static`, referencing EFS through its CSI driver. |
| PersistentVolumeClaim, or PVC | A namespaced request for storage that binds to a suitable PV. | `healthchecks-static` in the `healthchecks` namespace. |
| StorageClass | A cluster-scoped description of a storage class and its provisioner. It can support automatic provisioning when configured for that purpose. | `week8-healthchecks-efs`, with provisioner `efs.csi.aws.com`. |
| CSI driver | The integration that allows Kubernetes to use an external storage system. | The Amazon EFS CSI driver installed as an EKS add-on. |
| EFS access point | An application-specific entry point into EFS, with a selected directory and POSIX identity. | The application's static directory, accessed as UID/GID `10001`. |

A Pod references a PVC in its namespace. The PVC binds to a PV, and the CSI driver mounts the backing storage on the node for the Pod to use. In our chart, both the PV's claim reference and the PVC's volume name are specified explicitly.

### Static provisioning in this project

I used static provisioning. Terraform creates the EFS file system, access point and mount targets. The Helm chart creates a PV that points to that existing storage, and a PVC that explicitly selects the PV.

The StorageClass is still declared and referenced, but it does not create a new EFS file system for this claim. The distinction matters: defining a StorageClass alone does not mean this deployment uses dynamic provisioning.

## Why I chose EFS

The application starts with two replicas and can scale to four. Those replicas can run on different worker nodes, so they need access to the same static files.

EFS provides shared file storage and supports the `ReadWriteMany` access mode used by this deployment. A normal EBS `ReadWriteOnce` setup would constrain mounts to a single node, although multiple Pods on that node can use the volume. That would not fit the intended placement of these replicas across nodes.

The cluster originally exposed a `gp2` StorageClass with the provisioner `kubernetes.io/aws-ebs`. Its presence did not provide the shared EFS storage needed by this design.

EFS adds cost, network dependencies and more components to operate. I used it here to meet the shared persistent storage requirement and learn the PV/PVC lifecycle. This lab does not establish that EFS is necessary for every Django deployment; serving versioned static assets directly from an image or through object storage is a separate architectural choice.

## Implementation

### AWS resources managed by Terraform

Terraform provisions:

- An encrypted EFS file system.
- An EFS access point rooted at `/healthchecks-static`.
- An enforced POSIX user and group of `10001`, with initial directory permissions of `750`.
- A mount target in each of the two private subnet Availability Zones.
- A security group allowing NFS traffic on TCP port `2049` from the EKS worker node security group.
- An IAM role for the EFS CSI controller, with the AWS-managed `AmazonEFSCSIDriverPolicy` policy.
- The `aws-efs-csi-driver` EKS add-on with a Pod Identity association for `efs-csi-controller-sa`.

The access point controls the application directory and identity. Mount targets provide the network connection. These are different parts of the storage path.

Installing the add-on creates Kubernetes resources including the `efs-csi-controller` Deployment and `efs-csi-node` DaemonSet. They are installed by EKS; they do not require local chart files with the same names.

### Kubernetes resources managed by Helm

| File under `k8s_django_deployment_task` | Responsibility |
| --- | --- |
| `terraform/storage.tf` | EFS, networking, access point, CSI role and EKS add-on. |
| `helm_chart/templates/storage-class.yaml` | EFS StorageClass. |
| `helm_chart/templates/pv.yaml` | Static PV referencing the Terraform-created EFS access point. |
| `helm_chart/templates/pvc.yaml` | Application storage claim. |
| `helm_chart/templates/static-seed-job.yaml` | Copies static assets from the image to a versioned directory on EFS when needed. |
| `helm_chart/templates/deployment.yaml` | Mounts the PVC into the web containers. |
| `helm_chart/values.yaml` | Default chart settings. |
| `environments/lab/storage-values.yaml` | Lab-specific storage names and current EFS volume handle. |
| `helmfile.yaml.gotmpl` | Release definitions, values files and deployment dependencies. |

The repository uses a root-level `helmfile.yaml.gotmpl` rather than the illustrative `helmfile/helmfile.yaml` path in the assignment. It serves the same deployment orchestration purpose. The existing chart structure was retained.

The PV and PVC both use `ReadWriteMany`, filesystem volume mode and the same StorageClass. The PVC names the PV explicitly. The CSI volume handle identifies the Terraform-created EFS file system and its access point.

Both PV and PVC declare `5Gi`. For this static EFS configuration, that value is Kubernetes capacity and claim metadata; it does not impose a 5 GiB filesystem quota on EFS.

### Preparing and mounting the static files

The image contains the output of Django's static asset preparation under `/app/static-collected`. The storage Job mounts EFS at `/persistent`, which leaves that image directory visible as the copy source.

For image tag `week8-v1`, the Job prepares the `releases/week8-v1/` directory on EFS.

It uses a lock and a temporary directory before publishing the completed version. The directory contains `.seed-complete`, a `.persistence-proof` marker, CSS, JavaScript and other static assets. If the completed version already exists, the Job preserves it instead of overwriting restored files.

The web Deployment mounts the same claim at `/app/static-collected`, using `releases/week8-v1` as the subpath. The mount is read-only in the web containers. This separates the Job that prepares files from the application containers that serve them.

### Helmfile deployment order

The existing local chart supports three project-defined `workload` values:

| Helm release | Workload value | Main resources |
| --- | --- | --- |
| `healthchecks-storage` | `storage` | StorageClass, PV, PVC and static preparation Job. |
| `healthchecks-migrations` | `migration` | Database migration Job and its configuration. |
| `healthchecks` | `web` | Deployment, Service, Ingress, Certificate and HPA. |

Template conditions select the resources generated for each release. `workload` is a custom chart setting, not a built-in Helm feature.

The web release depends on the storage and migration releases, metrics-server, cert-manager and Traefik. Helmfile waits for the required resources and Jobs before installing the web release. Terraform prepares the AWS infrastructure; Helmfile installs the application workloads into the resulting cluster.

## Deployment and recovery steps

I selected the lab AWS profile and region, configured access to the EKS cluster, and provided the local age key needed to decrypt the environment's secret values. Decrypted secret files were handled outside the repository.

### 1. Confirm the cluster and storage prerequisites

I checked the Kubernetes API, worker nodes and system components.

The API returned `ok`. Three ARM64 worker nodes were Ready. Both EFS CSI controller Pods and all three EFS CSI node Pods were running.

I also checked the EFS mount targets through AWS. Both were `available` in the new private subnets.

### 2. Restore the application image

The local Docker daemon initially was not running. After starting Docker Desktop, I loaded the saved image archive and confirmed that the image was `linux/arm64`, matching the worker nodes.

I authenticated Docker to ECR, pushed the `week8-v1` image, and verified its repository metadata through AWS. Its digest matched the backed-up image, confirming that the restored image was the one uploaded to the registry.

### 3. Restore the database and update environment references

After the lab teardown, Terraform recreated the infrastructure. RDS was restored from the encrypted manual snapshot `week8-healthchecks-night-20261101013851`, using PostgreSQL `17.11` and 20 GiB of allocated storage.

Restoring from a snapshot required `rds:RestoreDBInstanceFromDBSnapshot`, which was separate from the permission used to create the original database. After adding the missing permission, I generated a fresh Terraform plan and applied it. The database restore completed successfully.

Recreating infrastructure changed the VPC, subnet and EFS identifiers. I updated the lab values from the new Terraform outputs and retained private copies of the previous values. I also refreshed kubeconfig because the new EKS cluster had a different API endpoint.

The application credentials remained in the existing SOPS-encrypted values file. Helm-secrets, SOPS and age are the secret management tools used by this project. The private age key is kept outside Git.

### 4. Restore the EFS files

The encrypted archive contained paths starting with `efs/releases/week8-v1/`. I first listed the archive to confirm its layout.

I created a temporary PV, PVC and Pod referencing the new EFS access point. The Pod used the application image and ran as UID/GID `10001`. Once it was Ready, I streamed the decrypted archive into it and restored the files under the mounted EFS directory.

The restore removed the archive's outer `efs/` prefix, checked the release marker and CSS files, and published the completed `releases` directory. It restored **423 files**.

I recorded the restored `.persistence-proof` marker's SHA-256 checksum and used it as the baseline for the final persistence test.

I then deleted the temporary Pod, PVC and PV. The temporary PV used `Retain`, so removing those Kubernetes objects did not delete the EFS files. The permanent application claim was subsequently created by Helm.

### 5. Install ingress and update the application hostname

I installed Traefik together with its AWS Load Balancer Controller dependency through Helmfile.

The controller provisioned an internet-facing Network Load Balancer. A first attempt to resolve its DNS name from the Mac failed with `socket.gaierror`. A later lookup succeeded using the Mac resolver. A diagnostic version of the lookup also supported public DNS fallbacks, but the successful log did not require those fallbacks. The initial failure alone does not establish its underlying DNS cause.

I updated the lab hostname, `ALLOWED_HOSTS` and `SITE_ROOT` together. The restored application was available at [healthchecks.100-60-103-174.sslip.io](https://healthchecks.100-60-103-174.sslip.io).

For this lab, the hostname maps to one NLB IPv4 address and cross-zone load balancing is enabled. A production domain would normally be managed separately rather than relying on this lab hostname.

### 6. Deploy the complete environment

I validated the charts with the selected environment values and then applied the release configuration through Helmfile. All seven releases completed successfully: AWS Load Balancer Controller, Traefik, cert-manager, metrics-server, storage, migrations and the web application.

The migration Job and storage seed Job completed before the application deployment. The application reached two available replicas, and cert-manager reported the website Certificate as Ready.

## Issues and their solutions

| Issue | Explanation and resolution |
| --- | --- |
| EFS creation or tagging was denied. | The Terraform identity lacked the required EFS actions. I corrected the permissions and their resource scopes. EFS creation and management actions do not all support identical resource restrictions. |
| Attaching the EFS CSI policy was denied. | The Terraform identity needed permission to attach the specific AWS-managed EFS CSI policy to the project's CSI role. This is separate from the permissions that the driver later uses. |
| Creating the add-on failed on `iam:PassRole`. | Terraform needed to pass the CSI role during add-on and Pod Identity configuration. I scoped the permission to that role and the relevant AWS services. |
| The small nodes had limited Pod capacity. | The original workers exposed 11 Pod slots each, and system DaemonSets also consumed slots. I increased the node group from two desired workers to three to provide room for the storage driver, Jobs, application replicas and rolling updates. |
| Docker commands could not connect to `docker.sock`. | Docker Desktop was stopped. Starting it restored access to the local Docker Engine; the saved image then loaded successfully. |
| RDS snapshot restoration returned AccessDenied. | `CreateDBInstance` did not grant `RestoreDBInstanceFromDBSnapshot`. I added the separate restore permission and continued with a fresh plan after the partial apply. |
| No application Pods appeared after Terraform finished. | Terraform installed infrastructure and EKS add-ons. The application, ingress and supporting Helm releases still needed to be deployed through Helmfile. |
| Newly created resources had different IDs. | I refreshed kubeconfig and updated lab values from current Terraform outputs before deploying workloads. |
| The initial NLB DNS lookup failed. | I checked resolution again with a diagnostic lookup. The later Mac DNS lookup succeeded, and I updated all hostname-related values consistently. |
| The EFS archive contained an outer `efs/` directory. | I removed that prefix during extraction so the application would see `releases/week8-v1`, matching its volume subpath. |

## Verification record

These results are taken from the supplied deployment logs, not assumed from the presence of configuration files.

| Check | Observed result |
| --- | --- |
| EKS worker readiness | Three Ready workers. |
| EFS CSI components | Two controller Pods and three node Pods running. |
| EFS mount targets | Both available. |
| ECR image | `week8-v1` present with the expected digest. |
| EFS archive restoration | 423 files restored; proof checksum recorded. |
| Helmfile lint | No chart lint failures. |
| Helmfile sync | All seven releases installed or upgraded successfully. |
| Application Deployment | `2/2` Ready and Available. |
| Database migration Job | Complete, `1/1`. |
| Static preparation Job | Complete, `1/1`. |
| Application PVC | Bound to `week8-healthchecks-static`, RWX, class `week8-healthchecks-efs`. |
| Service | ClusterIP, service port `80`; chart targets container port `8080`. |
| HPA | Minimum 2, maximum 4; CPU and memory targets 80%. Observed CPU 9%, memory 55%, replicas 2. |
| Website Certificate | Ready=True, Secret `healthchecks-tls`. |
| NLB | Active and internet-facing. |
| External HTTPS live, ready and CSS requests | All three returned HTTP 200 with certificate verification enabled. Served CSS matched the EFS file checksum. |
| Restored marker in all web Pods, before and after Pod replacement | Passed on two distinct nodes before and after the rolling restart. Replacement Pod UIDs differed; restored proof and CSS checksums were unchanged. |

The HPA observation confirms that metrics are available. It does not, by itself, demonstrate a scale-out event. Load testing was reported as completed earlier and was not repeated during this recovery.

### Final acceptance checks

The final acceptance test verified external HTTPS responses, shared files across replicas, and persistence after application Pod replacement. Both initial replicas read the recorded restore marker and identical CSS from a mounted directory. A rolling restart created new Pods on different nodes; the same checks passed again. The final HTTPS checks returned 200, and the CSS response checksum matched the mounted EFS file.

I recorded the original Pod UIDs and mounted file checksums, performed a rolling restart, and waited for the replacement Pods to become Ready. I then confirmed that the Pod UIDs had changed while the proof and CSS checksums remained the same. The proof also matched the baseline recorded during the EFS restore.

### Recorded acceptance result

| Stage | Pod | Worker node |
| --- | --- | --- |
| Before restart | `healthchecks-55d54dbf49-86fqp` | `ip-10-80-37-65.ec2.internal` |
| Before restart | `healthchecks-55d54dbf49-tfvcs` | `ip-10-80-41-224.ec2.internal` |
| After restart | `healthchecks-58dd77b4c-2gvf2` | `ip-10-80-17-109.ec2.internal` |
| After restart | `healthchecks-58dd77b4c-7hl6k` | `ip-10-80-37-65.ec2.internal` |

The acceptance test passed. The live and ready health endpoints and the static CSS request all returned HTTP 200 over HTTPS. The CSS response checksum matched the file read from EFS.

## Retention and backup boundaries

The application PV has reclaim policy `Retain`. The storage resources also carry Helm's `helm.sh/resource-policy: keep` annotation. These settings help preserve storage resources during relevant Kubernetes and Helm operations, but they are not a backup strategy.

Deleting the underlying EFS file system through Terraform or AWS can still remove the data. For the overnight teardown, I therefore kept an encrypted EFS archive and a separate RDS snapshot. The database snapshot and the EFS archive protect different datasets; neither replaces the other.

The web containers mount static files read-only. Storage preparation and recovery are performed separately. New image tags should have their own versioned static directory so an update does not modify the directory still used by an older release.

## Why Kubernetes and Helm helped

Kubernetes allowed the application replicas to use a storage claim instead of embedding a node-specific disk path into the application. The application Pods can be replaced while the persistent storage remains separate. The same deployment also provides health checks, Service discovery, rolling updates and replica scaling.

Helm kept the storage definitions, application mount and environment settings together in version-controlled templates. Lab-specific identifiers could be supplied through values rather than copied into every manifest. Helmfile made the dependency order explicit: prepare storage and complete migrations before starting the web workload.

These tools also introduced operational overhead. I had to understand driver permissions, node capacity, mount targets, access modes, release dependencies and backup boundaries. For a small application, that complexity needs a reason. In this task, it supported the goal of learning persistent Kubernetes storage with multiple application replicas.

## Assignment coverage

| Requirement | Implementation and evidence |
| --- | --- |
| Learn PV, PVC and StorageClass concepts. | Definitions and their roles are explained in this guide. |
| Explain how the resources work together. | The storage flow, binding and static provisioning approach are described above. |
| Create a PV and attach it to application Pods for static files. | The Helm-managed EFS PV and Bound PVC are deployed; the web Deployment mounts the claim for static files. Both application replicas are Ready. The before/after replacement test passed on distinct nodes, and the static CSS served over HTTPS matched the EFS file. |

## References

- [Kubernetes: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes: Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Amazon EKS: Use elastic file system storage with Amazon EFS](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [Amazon EFS: Working with access points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html)

