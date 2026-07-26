output "fortigate_public_ips" {
  description = "EIPs de las 2 WAN del FortiGate."
  value = {
    wan1 = aws_eip.wan1.public_ip
    wan2 = aws_eip.wan2.public_ip
  }
}

output "fortigate_instance_id" {
  description = "ID de la instancia FortiGate."
  value       = aws_instance.fortigate.id
}

output "windows_instance_id" {
  description = "ID de la instancia Windows."
  value       = aws_instance.windows.id
}

output "windows_private_ip" {
  description = "IP privada del Windows."
  value       = aws_instance.windows.private_ip
}
