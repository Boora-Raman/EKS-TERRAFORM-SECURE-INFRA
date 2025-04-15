resource "aws_eks_cluster" "eks" {
  count    = var.is_eks_cluster_enabled == true ? 1 : 0
  name     = var.cluster-name
  role_arn = aws_iam_role.eks_cluster_role[count.index].arn

  version = var.kubernetes_version

  vpc_config {
    subnet_ids              = [aws_subnet.eks_private_subnet[0].id, aws_subnet.eks_private_subnet[1].id, aws_subnet.eks_private_subnet[2].id]
    endpoint_private_access = var.cluster_private_access
    endpoint_public_access  = var.cluster_public_access
    security_group_ids      = [aws_security_group.eks_security_group.id]
  }

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster-name
    env  = var.env
  }
}

// OIDC provider

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks-certificate.certificates[0].sha1_fingerprint]

  url = data.tls_certificate.eks-certificate.url
}

// Addons for implemeting the networking solutions and installing other important component like kube proxy

resource "aws_eks_addon" "eks_addons" {
  for_each = { for idx, addons in var.addons : idx => addons }

  cluster_name  = aws_eks_cluster.eks[0].name
  addon_name    = each.value.name
  addon_version = each.value.version

  depends_on = [
    aws_eks_node_group.eks_spot_node,
    aws_eks_node_group.ondemand_ng
  ]

}

// Node group  (ONDEMAND)

resource "aws_eks_node_group" "ondemand_ng" {
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-ondemand-ng"

  node_role_arn = aws_iam_role.eks_nodegroup_role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_ondemand
    min_size     = var.min_capacity_ondemand
    max_size     = var.max_capacity_ondemand
  }

  subnet_ids = [aws_subnet.eks_private_subnet[0].id, aws_subnet.eks_private_subnet[1].id, aws_subnet.eks_private_subnet[2].id]

  instance_types = var.ondemand_instance_type

  capacity_type = "ON_DEMAND"

  labels = {
    type = "ondemand"
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${var.cluster-name}-ondemand-ng"
  }

  depends_on = [aws_eks_cluster.eks]


}

// Node Group ( on spot )

resource "aws_eks_node_group" "eks_spot_node" {

  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}--eks-spot-node"
  node_role_arn   = aws_iam_role.eks_nodegroup_role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_spot_node
    min_size     = var.min_capacity_spot_node
    max_size     = var.max_capacity_spot_node
  }


  subnet_ids = [aws_subnet.eks_private_subnet[0].id, aws_subnet.eks_private_subnet[1].id, aws_subnet.eks_private_subnet[2].id]

  instance_types = var.spot_instance_type

  capacity_type = "SPOT"

  update_config {
    max_unavailable = 1

  }

  tags = {
    "Name" = "${var.cluster-name}-spot-nodes"
  }

  labels = {
    type      = "spot"
    lifecycle = "spot"
  }

  disk_size = 50

  depends_on = [aws_eks_cluster.eks]
}

resource "helm_release" "argocd" {
  depends_on = [aws_eks_node_group.eks_spot_node]
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "4.5.2"

  namespace = "argocd"

  set {
    name  = "service.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}
