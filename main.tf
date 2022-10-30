terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

#VPC creation
resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"
    
    tags = {
        Name = "Main VPC"
    }
}


#First Public Subnet
resource "aws_subnet" "public-1" {
#VPC ID
    vpc_id = aws_vpc.main_vpc.id
#CIDR_block for subnet
    cidr_block = "10.0.1.0/24"
#AZ for subnet
    availability_zone = "us-east-1a"
#Assign a public IP when it launched
    map_public_ip_on_launch = true

    tags = {
        Name = "Public-Subnet-1"
    }
}

#Second Public Subnet
resource "aws_subnet" "public-2" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.2.0/24"
#AZ for subnet
    availability_zone = "us-east-1b"
#Assign a public IP when it launched
    map_public_ip_on_launch = true

    tags = {
        Name = "Public-Subnet-2"
    }
}

#First Private Subnet
resource "aws_subnet" "private-1" {
  vpc_id     = aws_vpc.main_vpc.id
#CIDR_block for subnet
  cidr_block = "10.0.3.0/24"
#AZ for subnet
  availability_zone = "us-east-1a"

  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet-1"
  }
}
 
#Second Private Subnet
 resource "aws_subnet" "private-2" {
  vpc_id     = aws_vpc.main_vpc.id
#CIDR_block for subnet
  cidr_block = "10.0.4.0/24"
#AZ for subnet
  availability_zone = "us-east-1b"

  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet-2"
  }
}
 
#Create Internet Gateway to direct traffic
 resource "aws_internet_gateway" "gtw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "gtw"
  }
}


#Create Route Table
resource "aws_route_table" "main_route" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gtw.id
  }
  tags = {
    "Name" = "Main_route_table"
  }
  
}

#Connect route table with public subnets
resource "aws_route_table_association" "route_association_1" {
  subnet_id = aws_subnet.public-1.id
  route_table_id = aws_route_table.main_route.id
}

resource "aws_route_table_association" "route_association_2" {
  subnet_id = aws_subnet.public-2.id
  route_table_id = aws_route_table.main_route.id
}


#create public security group
resource "aws_security_group" "public_security" {
  name = "public_security"
  description = "Allow traffic"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    cidr_blocks = [ "0.0.0.0/0" ]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
}

#Private security group
resource "aws_security_group" "private_security" {
  name = "private_security"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    cidr_blocks      = ["10.0.0.0/16"]
    security_groups = [ aws_security_group.public_security.id ]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_groups = [ aws_security_group.public_security.id ]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

#Load balancer creation for public subnet
resource "aws_lb" "my_lb" {
  name = "my-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.public_security.id]
  subnets = [ aws_subnet.public-1.id,aws_subnet.public-2.id]
  
}

#Target group
resource "aws_lb_target_group" "my_target" {
  name = "my-target"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main_vpc.id

  depends_on = [
    aws_vpc.main_vpc
  ]
}


resource "aws_lb_target_group_attachment" "attachment-1" {
  target_group_arn = aws_lb_target_group.my_target.arn
  target_id        = aws_instance.ec2-1.id
  port             = 80

  depends_on = [
    aws_instance.ec2-1
  ]
}

resource "aws_lb_target_group_attachment" "attachment-2" {
  target_group_arn = aws_lb_target_group.my_target.arn
  target_id        = aws_instance.ec2-2.id
  port             = 80

  depends_on = [
    aws_instance.ec2-2
  ]
}

#Create listener
resource "aws_lb_listener" "listener_balance" {
  load_balancer_arn = aws_lb.my_lb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.my_target.arn
  }
}

#First EC2
resource "aws_instance" "ec2-1" {
  ami           = "ami-090fa75af13c156b4"
  instance_type = "t2.micro"
  key_name      = "two-tier"
  availability_zone = "us-east-1a"
  vpc_security_group_ids      = [aws_security_group.public_security.id]
  subnet_id                   = aws_subnet.public-1.id
  associate_public_ip_address = true
  user_data                   = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><body><h1>What's up everyone</h1></body></html>" > /var/www/html/index.html
        EOF

  tags = {
    Name = "first_instance"
  }
}

#Second EC2
resource "aws_instance" "ec2-2" {
  ami           = "ami-090fa75af13c156b4"
  instance_type = "t2.micro"
  key_name      = "two-tier"
  availability_zone = "us-east-1b"
  vpc_security_group_ids      = [aws_security_group.public_security.id]
  subnet_id                   = aws_subnet.public-2.id
  associate_public_ip_address = true
  user_data                   = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><body><h1>What's up everyone</h1></body></html>" > /var/www/html/index.html
        EOF

  tags = {
    Name = "second_instance"
  }
}


#Database Creation Consist of Subnet Group and a DBS instance

#Subnet group

resource "aws_db_subnet_group" "group_subnet" {
  name       = "group_subnet"
  subnet_ids = [aws_subnet.private-1.id,aws_subnet.private-2.id]
}

resource "aws_db_instance" "database" {
  allocated_storage    = 5
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  identifier           = "db-instance"
  db_name              = "database_1"
  username             = "admin"
  password             = "password"
  db_subnet_group_name = aws_db_subnet_group.group_subnet.id
  vpc_security_group_ids = [aws_security_group.private_security.id]  
  publicly_accessible = false
  skip_final_snapshot  = true
}

#Output to see if our IP and Load balancer are right
output "public_ip-1" {
  value = aws_instance.ec2-1.public_ip
}

output "public_ip-2" {
  value = aws_instance.ec2-2.public_ip
}
