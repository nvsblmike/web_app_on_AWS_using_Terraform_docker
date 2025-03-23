terraform {
    required_version = ">= 1.5.0"
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

# AWS provider config
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
        Environment = "Production"
        Terraform = "true"
        Project = "Simple Web App Deployment"
        CostCenter = "DevOps"
    }
  }
}

# VPC Configuration
module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "5.0.0"

    name = "mcgeorge-vpc"
    cidr = "20.0.0.0/16"

    azs = ["${var.aws_region}a", "${var.aws_region}b"]
    public_subnets = ["20.0.1.0/24", "20.0.2.0/24"]
    private_subnets = ["20.0.101.0/24", "20.0.102.0/24"]
    enable_nat_gateway = true
    single_nat_gateway = true

    public_subnet_tags = {
        "NetworkTier" = "Public"
    }

    private_subnet_tags = {
        "NetworkTier" = "Private"
    }
}

# SSH Key Management
resource "tls_private_key" "ssh_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name = "key_to_all_instances-${var.environment}"
  public_key = tls_private_key.ssh_key.public_key_openssh

  lifecycle {
    ignore_changes = [key_name] # Prevent Terraform from trying to recreate it
  }
}

resource "local_file" "private_key" {
  content = tls_private_key.ssh_key.private_key_pem
  filename = "${path.module}/.ssh/private_key_to_all.pem"
  file_permission = "0600"
}

# Security Groups
resource "aws_security_group" "ansible_mc_sg" {
    name = "ansible_controller-sg"
    description = "Ansible Controller security group"
    vpc_id = module.vpc.vpc_id

    ingress {
        description = "SSH from trusted IPs"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Role = "Ansible Controller"
    }
}

# Ansible Controller EC2 Instance
resource "aws_instance" "ansible_controller-mc" {
  ami                    = data.aws_ami.ubuntu.id 
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.ansible_mc_sg.id]
  key_name               = aws_key_pair.generated_key.key_name
  monitoring             = true
  associate_public_ip_address = true  # Explicitly enable public IP

  user_data = templatefile("${path.module}/ansible-controller-setup.sh.tpl", {
    private_key_content = tls_private_key.ssh_key.private_key_pem
    ansible_user        = "ubuntu"
    SSH_DIR             = "/home/ubuntu/.ssh"  # <-- Add this line
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "Ansible-Controller-mc"
  }
}

resource "aws_security_group" "mcgeorge_ec2_sg" {
    name = "mcgeorge-ec2-sg"
    description = "EC2 Instance security group"
    vpc_id = module.vpc.vpc_id

    ingress {
        description = "SSH from Ansible Controller"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        security_groups = [aws_security_group.ansible_mc_sg.id]
    }

    ingress {
        description = ""
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Role = "EC2-Instance"
    }
}

resource "aws_instance" "mcgeorge-ec2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.mcgeorge_ec2_sg.id]
  key_name = aws_key_pair.generated_key.key_name
  monitoring = true
  associate_public_ip_address = true

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "EC2-Instance"
  }
}

# Supporting Data Sources
# Replace Amazon Linux AMI data source with Ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

