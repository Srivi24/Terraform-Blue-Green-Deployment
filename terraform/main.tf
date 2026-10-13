# Find the default VPC
data "aws_vpc" "default" {
  default = true
}

# Find subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "selected" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

# Select one subnet in each of two Availability Zones
locals {
  subnets_by_az = {
    for id, subnet in data.aws_subnet.selected :
    subnet.availability_zone => id...
  }

  public_subnets = [
    for az in slice(sort(keys(local.subnets_by_az)), 0, 2) :
    local.subnets_by_az[az][0]
  ]
}

# Find the latest Amazon Linux 2023 image
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security group for the public load balancer
resource "aws_security_group" "alb" {
  name_prefix = "blue-green-alb-"
  description = "Allow HTTP traffic to the load balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for both EC2 instances
resource "aws_security_group" "app" {
  name_prefix = "blue-green-app-"
  description = "Allow HTTP only from the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "srivi24-blue-green"
  internal           = false
  load_balancer_type = "application"

  subnets         = local.public_subnets
  security_groups = [aws_security_group.alb.id]
}

# Independent target groups for Blue and Green
resource "aws_lb_target_group" "env" {
  for_each = toset(["blue", "green"])

  name     = "srivi24-${each.key}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Create the Blue and Green EC2 instances
resource "aws_instance" "env" {
  for_each = toset(["blue", "green"])

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = local.public_subnets[0]
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf install -y nginx

    cat > /usr/share/nginx/html/index.html <<'HTML'
    <!doctype html>
    <html>
      <head><title>Blue-Green Deployment</title></head>
      <body>
        <h1>Environment: ${each.key}</h1>
        <p>Status: Running</p>
      </body>
    </html>
    HTML

    systemctl enable --now nginx
  EOF

  user_data_replace_on_change = true

  tags = {
    Name        = "srivi24-${each.key}"
    Environment = each.key
  }
}

# Register both instances with their corresponding target groups
resource "aws_lb_target_group_attachment" "env" {
  for_each = toset(["blue", "green"])

  target_group_arn = aws_lb_target_group.env[each.key].arn
  target_id        = aws_instance.env[each.key].id
  port             = 80
}

# Route production traffic to the selected environment
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.env[var.live_environment].arn
  }
}