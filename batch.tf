# IAM Role for batch processing
resource "aws_iam_role" "batch_role" {
  name               = "batch_role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement":
    [
      {
          "Action": "sts:AssumeRole",
          "Effect": "Allow",
          "Principal": {
            "Service": "batch.amazonaws.com"
          }
      }
    ]
}
EOF
tags = {
    created-by = "terraform"
  }
}
# Attach the Batch policy to the Batch role
resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.batch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}
# Security Group for batch processing
resource "aws_security_group" "batch_security_group" {
  name        = "batch_security_group"
  description = "AWS Batch Security Group for batch jobs"
  vpc_id      = "vpc-03e9cdfedccd10720"
egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    created-by = "terraform"
  }
}

# EC2 IAM Resources. 

# IAM Role for underlying EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"
assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
tags = {
    created-by = "terraform"
  }
}
# Assign the EC2 role to the EC2 profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}
# Attach the EC2 container service policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

#Batch Job IAM Resources. 

# IAM Role for jobs
resource "aws_iam_role" "job_role" {
  name               = "job_role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement":
    [
      {
          "Action": "sts:AssumeRole",
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          }
      }
    ]
}
EOF
tags = {
    created-by = "terraform"
  }
}
# S3 read/write policy
resource "aws_iam_policy" "s3_policy" {
  name   = "s3_policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "s3:Get*",
            "s3:List*",
            "s3:Put*"
        ],
        "Resource": [
          "*"
          
        ]
    }
  ]
}
EOF
}
# Attach the policy to the job role
resource "aws_iam_role_policy_attachment" "job_policy_attachment" {
  role       = aws_iam_role.job_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# EFS IAM Resources. 

resource "aws_security_group" "efs_security_group" {
  name        = "efs_security_group"
  description = "Allow NFS traffic."
  vpc_id      = "vpc-03e9cdfedccd10720"
lifecycle {
    create_before_destroy = true
  }
ingress {
    from_port       = "2049"
    to_port         = "2049"
    protocol        = "tcp"
    security_groups = [aws_security_group.batch_security_group.id]
  }
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "No Outbound Restrictions"
  }
}



# EFS Resources

# EFS for sharing protein databases
resource "aws_efs_file_system" "efs" {
  creation_token   = "efs"
  performance_mode = "generalPurpose"
  encrypted        = "true"
}
resource "aws_efs_mount_target" "efs_mount_target" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = "subnet-0445b23a7315ad939"
  security_groups = [
    aws_security_group.efs_security_group.id,
    aws_security_group.batch_security_group.id
  ]
}
resource "aws_launch_template" "launch_template" {
  name = "launch_template"
update_default_version = true
  user_data              = base64encode(data.template_file.efs_template_file.rendered)
}
data "template_file" "efs_template_file" {
  template = file("${path.module}/launch_template_user_data.tpl")
  vars = {
    efs_id        = aws_efs_file_system.efs.id
    efs_directory = "/mnt/efs"
  }
}


# Batch Resources. 

resource "aws_batch_compute_environment" "batch_environment" {
  compute_environment_name = "batch-environment"
  compute_resources {
    instance_role = aws_iam_instance_profile.ec2_profile.arn
    launch_template {
      launch_template_name = aws_launch_template.launch_template.name
      version              = "$Latest"
    }
    instance_type = [
      "optimal"
    ]
    max_vcpus = 2
    min_vcpus = 0
    security_group_ids = [
      aws_security_group.batch_security_group.id,
      aws_security_group.efs_security_group.id
    ]
    subnets = ["subnet-0445b23a7315ad939"]
    type    = "EC2"
  }
  service_role = aws_iam_role.batch_role.arn
  type         = "MANAGED"
tags = {
    created-by = "terraform"
  }
}
resource "aws_batch_job_queue" "job_queue" {
  name     = "job_queue"
  state    = "ENABLED"
  priority = 1
  compute_environments = [
    aws_batch_compute_environment.batch_environment.arn
  ]
  depends_on = [aws_batch_compute_environment.batch_environment]
tags = {
    created-by = "terraform"
  }
}
resource "aws_batch_job_definition" "job" {
  name = "job"
  type = "container"
  parameters = {}
  container_properties = <<CONTAINER_PROPERTIES
{
  "image": "busybox",
  "jobRoleArn": "${aws_iam_role.job_role.arn}",
  "vcpus": 2,
  "memory": 1024,
  "environment": [],
  "volumes": [
      {
          "host": {
              "sourcePath": "/mnt/efs"
          },
          "name": "efs"
      }
  ],
  "mountPoints": [
      {
          "containerPath": "/mnt/efs",
          "sourceVolume": "efs",
          "readOnly": false
      }
  ],
  "command": []
}
CONTAINER_PROPERTIES
tags = {
    created-by = "terraform"
  }
}