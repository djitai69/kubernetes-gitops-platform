# AWS-side prerequisites for Karpenter. The Karpenter controller itself
# (IRSA role) is created in the iam module; NodePool/EC2NodeClass are
# Kubernetes resources deployed by Flux, not Terraform.

# ---------------------------------------------------------------------------
# Node role: used by EC2 instances Karpenter launches. Separate from the
# stable platform node group's role since these nodes have a narrower,
# workload-only purpose.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name
}

# ---------------------------------------------------------------------------
# Spot interruption handling: Karpenter watches this queue for interruption,
# rebalance-recommendation, and instance-state-change events so it can
# gracefully drain nodes before AWS reclaims them.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

locals {
  interruption_rules = {
    spot-interruption        = { source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] }
    rebalance-recommendation = { source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] }
    instance-state-change    = { source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.interruption_rules
  name     = "${var.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value.detail-type
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.interruption_rules
  rule     = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn      = aws_sqs_queue.karpenter_interruption.arn
}
