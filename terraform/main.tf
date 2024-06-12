module "frontend" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "${var.project_name}-${var.environment}-${var.common_tags.component}"

  instance_type          = "t2.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]
    # convert StringList to list and get first element
  subnet_id              = local.public_subnet_id
  ami                    = data.aws_ami.ami_info.id

  tags = merge(
    var.common_tags,
    {
        name = "${var.project_name}-${var.environment}-${var.common_tags.component} "
    }
  )
}
##############################################
      #### NULL RESOURCE ####
#############################################
resource "null_resource" "frontend" {
 
  triggers = {
    instance_id = module.frontend.id  # this will be triggered everytime instance is created
  }
  connection {
        type     = "ssh"
        user     = "ec2-user"
        password = "DevOps321"
        host     = module.frontend.private_ip
    }

    provisioner "file" {
    source      = "${var.common_tags.component}.sh"
    destination = "/tmp/${var.common_tags.component}.sh"
  }
    provisioner "remote-exec" {
      inline = [ 
        "chmod +x /tmp/${var.common_tags.component}.sh",
        "sudo sh /tmp/${var.common_tags.component}.sh ${var.common_tags.component} ${var.environment} ${var.app_version}"
       ]
    }
}
##############################################
      #### STOPPING AMI ####
#############################################
resource "aws_ec2_instance_state" "frontend" {
  instance_id =  module.frontend.id
  state       = "stopped"

  depends_on = [ null_resource.frontend ]
} 
##############################################
      #### TO TAKE AMI ####
#############################################
resource "aws_ami_from_instance" "frontend" {
  name               = "${var.project_name}-${var.environment}-${var.common_tags.component}"
  source_instance_id = module.frontend.id

  depends_on = [ aws_ec2_instance_state.frontend ]
}
############################################################
      #### TERMINATE INSTANCE USING AWS CLI-LOCAL_EXEC ####
############################################################
resource "null_resource" "frontend_delete" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }

    provisioner "local-exec" {
        command = "aws ec2 terminate-instances --instance-ids ${module.frontend.id}"
    } 

    depends_on = [ aws_ami_from_instance.frontend ]
}
##############################################
      #### CREATING A TARGET GROUP ####
#############################################
resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.component}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value

  health_check {
    path                = "/health"
    port                = 8080
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
##############################################
      #### CREATING A LAUNCH TEMPLATE ####
#############################################

resource "aws_launch_template" "frontend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.component}"
  image_id = aws_ami_from_instance.frontend.id
  instance_initiated_shutdown_behavior = "terminate"
  update_default_version = true # sets the latest version to default        

  instance_type = "t2.micro"

  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.component}"
      }
    )
  }
}
##############################################
      #### CREATING AUTOSCALING GROUP ####
#############################################
resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.component}"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1
  target_group_arns = [aws_lb_target_group.frontend.arn]
  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }

  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.component}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Project"
    value               = "${var.project_name}"
    propagate_at_launch = false
  }
}
##############################################
      #### AUTO SCALLING POLICY  ####
#############################################
 resource "aws_autoscaling_policy" "frontend" {
  name                   =  "${var.project_name}-${var.environment}-${var.common_tags.component}"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name

   target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 7.0
  }
}
##############################################
      #### aws_lb_listener_rule  ####
#############################################
resource "aws_lb_listener_rule" "frontend" {
  listener_arn = data.aws_ssm_parameter.web_alb_listener_arn_https.value
  priority     = 100 # less number will be first validated

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = ["web-${var.environment}.${var.zone_name}"]
    }
  }
}