output "instance_name" {
  value = local.instance_name
}
output "private_ip" {
  value = length(module.node_centos7_houdini) > 0 ? coalesce( module.node_centos7_houdini.private_ip, "") : ""
}
output "id" {
  value = length(module.node_centos7_houdini) > 0 ? coalesce( module.node_centos7_houdini.id, "") : ""
}
output "consul_private_dns" {
  value = length(module.node_centos7_houdini) > 0 ? coalesce( module.node_centos7_houdini.consul_private_dns, "") : ""
}