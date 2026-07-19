# GitHub Actions authenticates via OIDC, never long-lived AWS access keys.
# Trust is scoped to this specific repo (and optionally branch/environment)
# so a workflow in an unrelated repo cannot assume this role.
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.enable_github_actions_oidc ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

data "aws_iam_policy_document" "github_actions_trust" {
  count = var.enable_github_actions_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

# Non-production: push to ECR and update GitOps state (via the GitHub App
# instead, see docs/gitops.md — this role covers AWS-side permissions only).
resource "aws_iam_role" "ci_nonprod" {
  count              = var.enable_github_actions_oidc ? 1 : 0
  name               = "${var.cluster_name}-ci-nonprod"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci_nonprod" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_nonprod" {
  count  = var.enable_github_actions_oidc ? 1 : 0
  name   = "ecr-push"
  role   = aws_iam_role.ci_nonprod[0].id
  policy = data.aws_iam_policy_document.ci_nonprod.json
}

# Production: read-only, only for the digest-copy promotion step. CI never
# gets cluster-admin credentials — Flux is the only deployer.
resource "aws_iam_role" "ci_production_promotion" {
  count              = var.enable_github_actions_oidc ? 1 : 0
  name               = "${var.cluster_name}-ci-prod-promotion"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci_prod_promotion" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_prod_promotion" {
  count  = var.enable_github_actions_oidc ? 1 : 0
  name   = "ecr-digest-copy"
  role   = aws_iam_role.ci_production_promotion[0].id
  policy = data.aws_iam_policy_document.ci_prod_promotion.json
}
