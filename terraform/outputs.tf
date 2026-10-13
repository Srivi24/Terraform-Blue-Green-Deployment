output "application_url" {
  description = "Public application URL"
  value       = "http://${aws_lb.app.dns_name}"
}

output "blue_status" {
  description = "Blue status according to the configured live environment"
  value = (
    var.live_environment == "blue" ? "live" : "idle"
  )
}

output "green_status" {
  description = "Green status according to the configured live environment"
  value = (
    var.live_environment == "green" ? "live" : "idle"
  )
}

output "live_environment" {
  description = "Configured live environment"
  value       = var.live_environment
}

output "blue_instance_id" {
  value = aws_instance.env["blue"].id
}

output "green_instance_id" {
  value = aws_instance.env["green"].id
}

output "blue_target_group_arn" {
  value = aws_lb_target_group.env["blue"].arn
}

output "green_target_group_arn" {
  value = aws_lb_target_group.env["green"].arn
}