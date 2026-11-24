terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Dedicated Project 16 VPC
resource "aws_vpc" "project16" {
  cidr_block           = "10.60.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "project-16-vpc"
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_internet_gateway" "project16" {
  vpc_id = aws_vpc.project16.id

  tags = {
    Name    = "project-16-igw"
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.project16.id
  cidr_block              = "10.60.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "project-16-public-a"
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.project16.id
  cidr_block              = "10.60.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name    = "project-16-public-b"
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.project16.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.project16.id
  }

  tags = {
    Name    = "project-16-public-rt"
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ALB security group
resource "aws_security_group" "alb" {
  name        = "project-16-alb-sg"
  description = "Allow public HTTP and HTTPS to the load balancer"
  vpc_id      = aws_vpc.project16.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "project-16-alb-sg"
    project = "project-16"
    owner   = "aryan"
  }
}

# EC2 accepts web traffic only from the ALB
resource "aws_security_group" "web" {
  name        = "project-16-web-sg"
  description = "Allow HTTP only from Project 16 ALB"
  vpc_id      = aws_vpc.project16.id

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

  tags = {
    Name    = "project-16-web-sg"
    project = "project-16"
    owner   = "aryan"
  }
}

# Web server
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd

    cat > /var/www/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head>
      <title>Project 16 - Secure HTTPS Website</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          background: #101827;
          color: white;
          text-align: center;
          padding: 100px 20px;
        }
        .card {
          background: #1c293b;
          padding: 40px;
          border-radius: 12px;
          display: inline-block;
        }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Secure Website Successfully Deployed!</h1>
        <h2>Project 16 - Enable HTTPS using ACM</h2>
        <p>Application Load Balancer is serving this website.</p>
        <p>HTTPS configuration with AWS Certificate Manager.</p>
        <p>Status: Operational</p>
        <p>Created by Aryan Singh</p>
      </div>
    </body>
    </html>
    HTML
  USERDATA

  tags = {
    Name    = "project-16-web-server"
    project = "project-16"
    owner   = "aryan"
  }
}

# Target group for the web server
resource "aws_lb_target_group" "web" {
  name     = "project-16-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.project16.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    project = "project-16"
    owner   = "aryan"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# Application Load Balancer
resource "aws_lb" "project16" {
  name               = "project-16-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name    = "project-16-alb"
    project = "project-16"
    owner   = "aryan"
  }
}

output "alb_dns_name" {
  description = "DNS name of the Project 16 Application Load Balancer"
  value       = aws_lb.project16.dns_name
}

output "alb_arn" {
  value = aws_lb.project16.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.web.arn
}

# HTTPS listener using the ACM certificate
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.project16.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-2:590507089733:certificate/de8c5d2b-7b8b-4780-b5bf-74c9b9085bd2"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Block HTTP requests
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.project16.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "HTTP access is blocked. Please use HTTPS."
      status_code  = "403"
    }
  }
}
