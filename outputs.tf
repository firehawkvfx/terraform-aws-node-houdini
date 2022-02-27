output "instance_name" {
  value = local.instance_name
}
output "private_ip" {
  value = coelesce( module.node_centos7_houdini.private_ip, "")
}
output "id" {
  value = coelesce( module.node_centos7_houdini.id, "")
}
output "consul_private_dns" {
  value = coelesce( module.node_centos7_houdini.consul_private_dns, "")
}