# Reusable IRSA trust policy: scopes an AWS IAM role to exactly one
# Kubernetes ServiceAccount (namespace + name), not the whole OIDC provider.
locals {
  irsa_roles = {
    external-dns = {
      namespace       = "external-dns"
      service_account = "external-dns"
      policy_json     = data.aws_iam_policy_document.external_dns.json
    }
    aws-load-balancer-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy_json     = data.aws_iam_policy_document.alb_controller.json
    }
    karpenter = {
      namespace       = "kube-system"
      service_account = "karpenter"
      policy_json     = data.aws_iam_policy_document.karpenter.json
    }
  }
}

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each           = local.irsa_roles
  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "irsa" {
  for_each = local.irsa_roles
  name     = "${each.key}-policy"
  role     = aws_iam_role.irsa[each.key].id
  policy   = each.value.policy_json
}

# ---------------------------------------------------------------------------
# EBS CSI driver: uses the AWS managed policy directly rather than the
# inline-policy irsa_roles map above.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# ESO: one role per namespace, each scoped to only that environment's
# Secrets Manager path (node-api/<env>/*), so a compromised dev SecretStore
# cannot read staging or production secrets.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "eso_trust" {
  for_each = var.eso_namespaces

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.key}:node-api-secrets-reader"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_secrets_access" {
  for_each = var.eso_namespaces

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:*:*:secret:${each.value}*"]
  }
}

resource "aws_iam_role" "eso" {
  for_each           = var.eso_namespaces
  name               = "${var.cluster_name}-eso-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.eso_trust[each.key].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "eso" {
  for_each = var.eso_namespaces
  name     = "secrets-read"
  role     = aws_iam_role.eso[each.key].id
  policy   = data.aws_iam_policy_document.eso_secrets_access[each.key].json
}
