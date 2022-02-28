output "instance_name" {
  value = local.instance_name
}
output "private_ip" {
  value = coalesce(module.node_centos7_houdini[0].private_ip, "")
}
output "id" {
  value = coalesce(module.node_centos7_houdini[0].id, "")
}
output "consul_private_dns" {
  value = coalesce(module.node_centos7_houdini[0].consul_private_dns, "")
}
