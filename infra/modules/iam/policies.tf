# Minimal, scoped policies. AWS Load Balancer Controller and Karpenter's
# full upstream policies are long-lived JSON documents maintained
# upstream; referencing them here as data sources keeps this module from
# silently drifting out of date with the controller's actual requirements.

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }
}

data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json"
}

data "aws_iam_policy_document" "alb_controller" {
  source_policy_documents = [data.http.alb_controller_policy.response_body]
}

data "http" "karpenter_controller_policy" {
  url = "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.0.6/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml"
}

# The upstream Karpenter policy ships as a CloudFormation template, not
# standalone JSON, so the controller policy here is the documented minimal
# subset (EC2 fleet/instance lifecycle + pricing + SSM parameter reads)
# rather than a source_policy_documents fetch. Verify against the current
# Karpenter release notes before applying.
data "aws_iam_policy_document" "karpenter" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateFleet", "ec2:CreateLaunchTemplate", "ec2:CreateTags",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes", "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups", "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets", "ec2:RunInstances", "ec2:TerminateInstances",
      "pricing:GetProducts", "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/${var.cluster_name}-karpenter-node"]
  }
}
