# -------------------
# VARIABLE DECLARATIONS
# -------------------

# Region in which to provision AWS resources
variable "aws_region" {}

# CIDR block for the VPC (e.g., "10.0.0.0/16")
variable "cidr_block" {}

# CIDR block for the subnet (e.g., "10.0.1.0/24")
variable "subnet_cidr_block" {}

# Name of the EC2 Key Pair used for SSH access
variable "key_pair_name" {}

# EC2 instance type (e.g., "t2.micro")
variable "instance_type" {}




# -------------------
# PROVIDER CONFIGURATION
# -------------------

# Configures the AWS provider with the specified region
provider "aws" {
  region = var.aws_region
}

# -------------------
# DATA SOURCES
# -------------------

# Fetches the most recent Amazon Linux 2 AMI (Amazon Machine Image)
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  # Filters to only include AMIs with this naming pattern
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  # Filters to only include HVM virtualization type (required for EC2)
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  # Only get AMIs published by Amazon (owner ID)
  owners = ["137112412989"] # Amazon
}

# -------------------
# VPC & NETWORKING RESOURCES
# -------------------

# Create a custom Virtual Private Cloud (VPC)
resource "aws_vpc" "my-vpc" {
  cidr_block       = var.cidr_block
  instance_tenancy = "default"

  tags = {
    Name = "VPC-With-EC2"
  }
}

# Create a public subnet within the VPC
resource "aws_subnet" "public-subnet" {
  vpc_id     = aws_vpc.my-vpc.id
  cidr_block = var.subnet_cidr_block

  tags = {
    Name = "Public-Subnet"
  }
}

# Create an Internet Gateway and attach it to the VPC to enable internet access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "Internet-Gateway"
  }
}

# Add a default route to the internet via the internet gateway
resource "aws_default_route_table" "igw-route" {
  # Use the default route table associated with the VPC
  default_route_table_id = aws_vpc.my-vpc.default_route_table_id

  # Add a route for all IPv4 addresses (internet access)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "IGW-Route-Table"
  }
}

# -------------------
# SECURITY CONFIGURATION
# -------------------

# Create a security group for the EC2 instance
resource "aws_security_group" "sg-for-ec2" {
  name        = "SG-for-EC2"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.my-vpc.id

  tags = {
    Name = "SG-for-EC2"
  }
}

# Allow inbound SSH (port 22) from anywhere (not recommended for production)
resource "aws_vpc_security_group_ingress_rule" "allow_inbound_ssh" {
  security_group_id = aws_security_group.sg-for-ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# Allow inbound ICMP traffic (e.g., ping) from anywhere
resource "aws_vpc_security_group_ingress_rule" "allow_inbound_ICMP" {
  security_group_id = aws_security_group.sg-for-ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1     # ICMP types
  ip_protocol       = "icmp" # Internet Control Message Protocol
  to_port           = -1
}

# -------------------
# EC2 INSTANCE
# -------------------

# Launch a single Amazon Linux 2 EC2 instance in the public subnet
resource "aws_instance" "public-ec2" {
  ami                         = data.aws_ami.amazon_linux_2.id     # Use latest Amazon Linux 2 AMI
  instance_type               = var.instance_type                  # Instance type from variable
  associate_public_ip_address = true                               # Assign a public IP (for SSH/Internet)
  vpc_security_group_ids      = [aws_security_group.sg-for-ec2.id] # Attach the security group
  subnet_id                   = aws_subnet.public-subnet.id        # Launch in the public subnet
  key_name                    = var.key_pair_name                  # Required for SSH access

  tags = {
    Name = "Public-EC2"
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name = "VPCFlowLogsEC2"
}

# Create an IAM Role for VPC Flow Logs to publish logs to CloudWatch
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_logs_role" {
  name               = "vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Attach the policy to the IAM Role
data "aws_iam_policy_document" "policy_doc" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs_role_policy" {
  name   = "vpc-flow-logs-policy"
  role   = aws_iam_role.vpc_flow_logs_role.name
  policy = data.aws_iam_policy_document.policy_doc.json
}

resource "aws_flow_log" "eni_flowlogs_with_cloudwatch" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.loggroup.arn
  traffic_type    = "ALL"
  eni_id          = aws_instance.public-ec2.primary_network_interface_id
  depends_on      = [aws_iam_role_policy.vpc_flow_logs_role_policy, aws_instance.public-ec2]
}

resource "aws_cloudwatch_log_metric_filter" "only_my_public_ip" {
  name           = "VPCFlowLogsOnlyMyIPAddress"
  pattern        = "REJECT"
  log_group_name = aws_cloudwatch_log_group.loggroup.name

  metric_transformation {
    namespace = "ns-unauthorizedipaddressEc2"
    name      = "RejectIPBlock"
    value     = 1
    # dimensions = {
    #   IPAddress = "$.sourceIP"
    # }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "LambdaExecutionPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sns:Publish"
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Action   = "logs:CreateLogGroup"
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Action   = "logs:CreateLogStream"
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Action   = "logs:PutLogEvents"
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Action   = "ec2:AuthorizeSecurityGroupIngress"
        Resource = aws_security_group.sg-for-ec2.arn
        Effect   = "Allow"
      },
      {
        Action   = "ec2:RevokeSecurityGroupIngress"
        Resource = aws_security_group.sg-for-ec2.arn
        Effect   = "Allow"
      },
      {
        Action   = "ec2:DescribeInstances"
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda.zip"

  source {
    content  = file("block_ip.py")
    filename = "block_ip.py"
  }
}

# Create the Lambda function that sends alerts
resource "aws_lambda_function" "block_ip_from_alarm_func" {
  function_name = "BlockIP"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "block_ip.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path

  environment {
    variables = {
      SECURITY_GROUP_ID = aws_security_group.sg-for-ec2.id
    }
  }
}

resource "aws_sns_topic" "alarm_topic" {
  name = "UnauthorizedAccessTopic"
}

resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.block_ip_from_alarm_func.arn # Lambda ARN
}

resource "aws_cloudwatch_metric_alarm" "denied_access_to_ec2_alarm" {
  alarm_name          = "Denied-Access-EC2"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.only_my_public_ip.metric_transformation.0.name
  namespace           = aws_cloudwatch_log_metric_filter.only_my_public_ip.metric_transformation.0.namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
}