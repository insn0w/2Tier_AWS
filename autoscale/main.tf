# ---autoscale/main.tf ---

data "aws_availability_zones" "available" {}

resource "random_shuffle" "az_list" {
  input        = data.aws_availability_zones.available.names
  result_count = var.max_subnets
}

#CREATE AN AWS VPC
resource "aws_vpc" "cicd_myvpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    Name = "cicd_myvpc"
  }
}


#CREATE 3 public subnets in different AZ's
resource "aws_subnet" "sub_public" {
  count                   = var.public_sn_count
  vpc_id                  = aws_vpc.cicd_myvpc.id
  cidr_block              = var.public_cidrs[count.index]
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sub_public_${count.index + 1}"
  }
}

#CREATE 3 private subnets in different AZ's
resource "aws_subnet" "sub_private1" {
  vpc_id                  = aws_vpc.cicd_myvpc.id
  cidr_block              = "10.0.7.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "sub_private1"
  }
}
resource "aws_subnet" "sub_private2" {
  vpc_id                  = aws_vpc.cicd_myvpc.id
  cidr_block              ="10.0.8.0/24"
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = false

  tags = {
    Name = "sub_private2"
  }
}
resource "aws_subnet" "sub_private3" {
  vpc_id                  = aws_vpc.cicd_myvpc.id
  cidr_block              = "10.0.9.0/24"
  availability_zone       = "us-east-1d"
  map_public_ip_on_launch = false

  tags = {
    Name = "sub_private3"
  }
}

#CREATE Elastic IP to associate with Nat Gateway in the private subnets
resource "aws_eip" "cg-eip" {
  vpc      = true
} 
 
 #CREATE NAT GATEWAY FOR PRIVATE SUBNETS
 resource "aws_nat_gateway" "pri-natgw1" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.sub_private1.id
}
 resource "aws_nat_gateway" "pri-natgw2" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.sub_private2.id
}
 resource "aws_nat_gateway" "pri-natgw3" {
  connectivity_type = "private"
  subnet_id         = aws_subnet.sub_private3.id
}

#CREATE an Internet Gateway that connects to the web/public tier for the VPC
resource "aws_internet_gateway" "cg_igw" {
  vpc_id = aws_vpc.cicd_myvpc.id

  tags = {
    Name = "cg_igw"
  }
}



#CREATE route table for association with public/web tier
resource "aws_route_table" "cg_pub_rtable" {
  vpc_id = aws_vpc.cicd_myvpc.id

  route {
    cidr_block = "0.0.0.0/0" #open to all routes
    gateway_id = aws_internet_gateway.cg_igw.id
  }

  tags = {
    Name = "cg_pub_rtable"
  }
}


#CREATE route association for  public subnets and route table
resource "aws_route_table_association" "public_tableassc" {
  count          = var.public_sn_count
  subnet_id      = aws_subnet.sub_public.*.id[count.index]
  route_table_id = aws_route_table.cg_pub_rtable.id
}




resource "aws_route_table" "cg_pri_rtable" {
  vpc_id = aws_vpc.cicd_myvpc.id
route {
    cidr_block = "10.0.7.0/24"  
    nat_gateway_id = aws_nat_gateway.pri-natgw1.id
    
  }
  
 route {
    cidr_block = "10.0.8.0/24" 
    nat_gateway_id = aws_nat_gateway.pri-natgw2.id
  }
  route {
    cidr_block = "10.0.9.0/24" 
    nat_gateway_id = aws_nat_gateway.pri-natgw3.id
  }
  
  
  tags = {
    Name = "cg_pri_rtable"
  }
}

#autoscaling group for web server


resource "aws_launch_template" "cicdlt" {
  name_prefix   = "cicdlt"
  image_id      = "ami-090fa75af13c156b4"
  instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "cicd_asg" {
  availability_zones        = data.aws_availability_zones.available.names
  desired_capacity          = var.private_sn_count
  max_size                  = var.private_sn_count
  min_size                  = var.private_sn_count
  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.cicdlt.id
      }
    }
  }
}

resource "aws_launch_template" "cicdbastionlt" {
  name_prefix   = "cicdbastionlt"
  image_id      = "ami-090fa75af13c156b4"
  instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "cicd_bastion_asg" {
  availability_zones = data.aws_availability_zones.available.names
  desired_capacity   = var.public_sn_count
  max_size           = var.public_sn_count
  min_size           = var.public_sn_count
  health_check_type  = "EC2"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.cicdbastionlt.id
      }
    }
  }
}


# security groups
resource "aws_security_group" "cicd_bastion_sg" {
  vpc_id     = aws_vpc.cicd_myvpc.id
  depends_on = [aws_route_table.cg_pub_rtable]

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cicd-bastion-sg"
  }
}

resource "aws_security_group" "cicd_priv_sg" {
  vpc_id     = aws_vpc.cicd_myvpc.id
  depends_on = [aws_route_table.cg_pri_rtable]

  ingress {
    description = "WebServerSG"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cicd-priv-sg"
  }
}




#CREATE ALB targeting Web Server ASG
resource "aws_lb" "cicd_lb" {
  name               = "cicd-lb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.cicd_priv_sg.id]

  subnet_mapping {
    subnet_id = aws_subnet.sub_private1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.sub_private2.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.sub_private3.id

  }




  enable_deletion_protection = true

  tags = {
    Environment = "cicd_lb"
  }
}

resource "aws_lb_target_group" "cicd_priv_tg" {
  name     = "cicd-priv-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.cicd_myvpc.id
}
resource "aws_lb_listener" "cicd_lb_listener" {
  load_balancer_arn = aws_lb.cicd_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cicd_priv_tg.arn
  }
}
