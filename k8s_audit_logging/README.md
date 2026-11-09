# Task 2: Kubernetes Audit Logging

## Goal

Collect Kubernetes API audit events and investigate a simulated unauthorized
request to an application Secret.

## Implementation

Cluster: week8-healthchecks.
Region: us-east-1.
Log group: /aws/eks/week8-healthchecks/cluster.
Analysis tool: Amazon CloudWatch Logs Insights.

EKS exports api, audit and authenticator logs to CloudWatch.
Logs Insights discovers JSON fields and supports filtering and aggregation.
The analysis requires no additional Kubernetes Pods.

Task 2 step 3 explicitly permits a cloud provider's analysis service.
This implementation uses that option. The separate ELK-specific SUBMIT file
list is not included; acceptance must be checked if those exact files are required.

## Setup

1. Verified audit export using aws eks describe-cluster.
2. Granted the analysis identity the permissions in iam/cloudwatch-read.json.
3. Requested healthchecks-secrets using the week8-healthchecks-viewer context.
4. Confirmed that Kubernetes returned Forbidden.
5. Found the event in the CloudWatch audit stream.
6. Successfully ran queries/denied-secrets.cwli using Logs Insights.

The existing Terraform configuration sets CloudWatch retention to seven days.

## Investigation

This was an intentional lab exercise, not an actual intrusion.

| Field | Observed result |
| --- | --- |
| Request time, UTC | 2026-11-09T01:14:01.356882Z |
| Role | week8-healthchecks-viewer |
| Kubernetes group | healthchecks-viewers |
| Action | get |
| Target | secrets/healthchecks-secrets |
| Namespace | healthchecks |
| Response | 403 Forbidden |
| Authorization decision | forbid |

The denied-secrets query completed and matched one event in the selected
four-hour window.

Query ID: 578fdb4c-9125-4b70-ab8e-3ebad2f14058.
Saved result: evidence/denied-secrets.json.

The recorded user, action, target and response match the test request.
RBAC blocked this request. The event does not demonstrate successful Secret
retrieval or prove that the account was compromised.

For a real investigation, review repeated attempts, other requested resources
and successful operations by the same identity.

## Files

- iam/cloudwatch-read.json: permissions for the analysis commands.
- queries/denied-secrets.cwli: individual denied Secret requests.
- queries/denied-by-user.cwli: additional aggregation by user and resource.
- evidence/denied-secrets.json: verified result of the first query.

Both queries select ResponseComplete to avoid counting multiple request stages.
Interpret results only after the query status is Complete.

## Benefits and limits

Audit logs show who requested an operation, its target, time and outcome.
They help investigate incidents and verify access restrictions.

EKS uses an AWS-managed audit policy with exclusions for some system requests.
Secret operations are logged at Metadata level. This setup does not claim to
record literally every API request or every request body.

CloudWatch queries incur usage charges based on scanned data.
The worker nodes remain t4g.small.

A proposed t4g.medium replacement was rejected by the Free Tier restriction.
The working group was restored in Terraform, and the plan reported No changes.
Deletion of the rejected group remains a separate AWS cleanup check.

## References

- https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
- https://docs.aws.amazon.com/eks/latest/best-practices/auditing-and-logging.html
- https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html
