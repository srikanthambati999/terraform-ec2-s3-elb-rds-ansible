provider "aws" {
    region = "ap-south-1"
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    
}


resource "aws_vpc" "firstvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "pracinstance"
  }
}
resource "aws_subnet" "public_subnet"{
    vpc_id = "${aws_vpc.firstvpc.id}"
    cidr_block = " 10.0.1.0/24"
    tags={
        Name= "public subnet"
    }
}
resource "aws_subnet" "private_subnet"{
    vpc_id = "${aws_vpc.firstvpc.id}"
    cidr_block = " 10.0.2.0/24"
    tags={
        Name= "private subnet"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = "${aws_vpc.firstvpc.id}"
    tags={
        Name = "internetgateway"
    }
}

resource "aws_route_table" "aws_route"{
   vpc_id = "${aws_vpc.firstvpc.id}"
   route{
       cidr_block = "0.0.0.0/0"
       gateway_id = "${aws_internet_gateway.igw.id}"
   }
   tags={
       Name = "public subnet"
   }
   
}

resource "aws_route_table_association" "public_subnet_association"{
    subnet_id = "${aws_subnet.public_subnet.id}"
    route_table_id = "${aws_route_table.aws_route.id}"
}

resource "aws_eip" "eip"{
    vpc=true
}
resource "aws_nat_gateway" "nategateway" {
  subnet_id = "${aws_subnet.public_subnet.id}"
  allocation_id="${aws_eip.eip.id}"
  tags={
      Name="nat gateway"
  }

}

resource "aws_route_table" "natgwroute"{
    vpc_id ="${aws_vpc.firstvpc.id}"
    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_nat_gateway.nategateway.id}"
    }
    tags = {
        Name = "nat gateway route table"
    }
}
resource "aws_route_table_association" "natassociation" {
    subnet_id = "${aws_subnet.private_subnet.id}"
    route_table_id="${aws_route_table.natgwroute.id}"
}


#################rds###########


resource "aws_db_instance" "main_rds_instance" {
  identifier        = "${var.rds_instance_identifier}"
  allocated_storage = "${var.rds_allocated_storage}"
  engine            = "${var.rds_engine_type}"
  engine_version    = "${var.rds_engine_version}"
  instance_class    = "${var.rds_instance_class}"
  name              = "${var.database_name}"
  username          = "${var.database_user}"
  password          = "${var.database_password}"

  port = "${var.database_port}"

  # Because we're assuming a VPC, we use this option, but only one SG id
  vpc_security_group_ids = ["${aws_security_group.main_db_access.id}"]

  # We're creating a subnet group in the module and passing in the name
  db_subnet_group_name = "${aws_db_subnet_group.main_db_subnet_group.id}"
  parameter_group_name = "${var.use_external_parameter_group ? var.parameter_group_name : aws_db_parameter_group.main_rds_instance.id}"

  # We want the multi-az setting to be toggleable, but off by default
  multi_az            = "${var.rds_is_multi_az}"
  storage_type        = "${var.rds_storage_type}"
  iops                = "${var.rds_iops}"
  publicly_accessible = "${var.publicly_accessible}"

  # Upgrades
  allow_major_version_upgrade = "${var.allow_major_version_upgrade}"
  auto_minor_version_upgrade  = "${var.auto_minor_version_upgrade}"
  apply_immediately           = "${var.apply_immediately}"
  maintenance_window          = "${var.maintenance_window}"

  # Snapshots and backups
  skip_final_snapshot   = "${var.skip_final_snapshot}"
  copy_tags_to_snapshot = "${var.copy_tags_to_snapshot}"

  backup_retention_period = "${var.backup_retention_period}"
  backup_window           = "${var.backup_window}"

  # enhanced monitoring
  monitoring_interval = "${var.monitoring_interval}"

  tags = "${merge(var.tags, map("Name", format("%s", var.rds_instance_identifier)))}"
}

resource "aws_db_parameter_group" "main_rds_instance" {
  count = "${var.use_external_parameter_group ? 0 : 1}"

  name   = "${var.rds_instance_identifier}-${replace(var.db_parameter_group, ".", "")}-custom-params"
  family = "${var.db_parameter_group}"

  # Example for MySQL
  # parameter {
  #   name = "character_set_server"
  #   value = "utf8"
  # }


  # parameter {
  #   name = "character_set_client"
  #   value = "utf8"
  # }

  tags = "${merge(var.tags, map("Name", format("%s", var.rds_instance_identifier)))}"
}

resource "aws_db_subnet_group" "main_db_subnet_group" {
  name        = "${var.rds_instance_identifier}-subnetgrp"
  description = "RDS subnet group"
  subnet_ids  = ["${var.subnets}"]

  tags = "${merge(var.tags, map("Name", format("%s", var.rds_instance_identifier)))}"
}

# Security groups
resource "aws_security_group" "main_db_access" {
  name        = "${var.rds_instance_identifier}-access"
  description = "Allow access to the database"
  vpc_id      = "${var.rds_vpc_id}"

  tags = "${merge(var.tags, map("Name", format("%s", var.rds_instance_identifier)))}"
}

resource "aws_security_group_rule" "allow_db_access" {
  type = "ingress"

  from_port   = "${var.database_port}"
  to_port     = "${var.database_port}"
  protocol    = "tcp"
  cidr_blocks = ["${var.private_cidr}"]

  security_group_id = "${aws_security_group.main_db_access.id}"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.main_db_access.id}"
}



########alb######


resource "aws_elb" "elb" {
  name = "${var.elb_name}"
  subnets = ["${var.subnet_az1}","${var.subnet_az2}"]
  internal = "${var.elb_is_internal}"
  security_groups = ["${var.elb_security_group}"]

  listener {
    instance_port = "${var.backend_port}"
    instance_protocol = "${var.backend_protocol}"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "${var.health_check_target}"
    interval = 30
  }

  cross_zone_load_balancing = true
}

