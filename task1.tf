/* -------- Global Variable for the Key Pair -------- */ 

variable "mykey" {
	type	= string
	default	= "Task1Key"
}



/* -------- Set the provider for the instance -------- */

provider "aws" {
	region		= "ap-south-1"
	profile		= "abhishek"
}


/* -------- 1) Create the Security Group -------- */

resource "aws_security_group" "Task_1_SG" {
  name        = "Task_1_SG"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
	cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "Task_1_SG"
  }
}



/* -------- 2) & 3) Create an instance resource with key pair and security groups -------- */

resource "aws_instance" "web_instance" {
	ami				= "ami-0447a12f28fddb066"
	instance_type	= "t2.micro"
	key_name		= var.mykey
	security_groups	= [ "Task_1_SG" ]

	connection {
		type		= "ssh"
		user		= "ec2-user"
		private_key	= file("F:/Abhishek/Hybrid Cloud LW/task 1/Task1Key.pem")
		host		= aws_instance.web_instance.public_ip
	}
	
	provisioner "remote-exec" {
		inline = [
			"sudo yum install httpd git php -y ",
			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd",
		]
	}


	tags = {
		Name = "AbhiTera"
	}
}


/* -------- 4) Create an EBS volume -------- */

resource "aws_ebs_volume" "web_ebs" {
	availability_zone	= aws_instance.web_instance.availability_zone
	size				= 1

	tags = {
		Name	= "AbhiTeraEBS"
	}
}

/* -------- Attach the volume to a folder -------- */

resource "aws_volume_attachment" "web_ebs_att" {
	device_name		= "/dev/sdh"
	volume_id		= aws_ebs_volume.web_ebs.id
	instance_id		= aws_instance.web_instance.id
	force_detach	= true
}

/* -------- 5) & 6) Format, Mount & copy the code to the volume -------- */

resource "null_resource" "connection" {
	depends_on		= [
		aws_volume_attachment.web_ebs_att,
	]
	
	connection {
		type		= "ssh"
		user		= "ec2-user"
		private_key	= file("F:/Abhishek/Hybrid Cloud LW/task 1/Task1Key.pem")
		host		= aws_instance.web_instance.public_ip
	}
	
	provisioner "remote-exec" {
		inline = [
			"sudo mkfs.ext4 /dev/xvdh",
			"sudo mount /dev/xvdh /var/www/html/",
			"sudo rm -rf /var/www/html/*",
			"sudo git clone https://github.com/abhis2898/Cloud-Data.git /var/www/html/",
		]
	}
}

/* -------- 7) Create a S3 bucket & copy Github content to a local folder -------- */

resource "aws_s3_bucket" "terabucket5487" {
	bucket	= "terraform5487"
	acl		= "public-read"
	versioning {
		enabled		= true
	}
	force_destroy	= true

	tags = {
		Environment	= "Prod"
	}
	
	provisioner "local-exec" {
		command		= "git clone https://github.com/abhis2898/Cloud-Data.git dataFolder"
	}
	
	provisioner "local-exec" {
        when        = destroy
        command     = "echo Y | rmdir /s dataFolder"
    }
}

resource "aws_s3_bucket_object" "upload_image" {
	bucket	= aws_s3_bucket.terabucket5487.bucket
	key		= "image.jpg"
	source	= "dataFolder/image.jpg"
	acl		= "public-read"
}




/* -------- 8) Cloudfront using S3 and use the  Cloudfront URL -------- */

locals {
	s3_origin_id	= "aws_s3_bucket.terabucket5487.id"
}

resource "aws_cloudfront_distribution" "s3_cloudfront" {
	origin {
		domain_name		= aws_s3_bucket.terabucket5487.bucket_regional_domain_name
		origin_id		= local.s3_origin_id
	}
	
	enabled				= true
	is_ipv6_enabled		= true
	comment				= "Some comment"
	default_root_object	= "image.jpg"
	logging_config {
		include_cookies	= false
		bucket			=  aws_s3_bucket.terabucket5487.bucket_domain_name
	}

	default_cache_behavior {
		allowed_methods		= ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
		cached_methods		= ["GET", "HEAD"]
		target_origin_id	= local.s3_origin_id
		forwarded_values {
			query_string	= false
			cookies {
				forward = "none"
			}
		}
		
		viewer_protocol_policy	= "allow-all"
		min_ttl					= 0
		default_ttl				= 3600
		max_ttl					= 86400
	}
  
  	ordered_cache_behavior {
		path_pattern		= "/content/*"
		allowed_methods		= ["GET", "HEAD", "OPTIONS"]
		cached_methods		= ["GET", "HEAD"]
		target_origin_id	= local.s3_origin_id
		forwarded_values {
			query_string	= false
			cookies {
				forward = "none"
			}
		}
    
		min_ttl					= 0
		default_ttl				= 3600
		max_ttl					= 86400
		compress				= true
		viewer_protocol_policy	= "redirect-to-https"
	}
	
	price_class	= "PriceClass_200"
	restrictions {
		geo_restriction {
		restriction_type	= "whitelist"
		locations			= ["US", "CA", "GB", "DE","IN"]
		}
	}
	
	tags = {
		Environment	= "prod"
	}
	
	viewer_certificate {
		cloudfront_default_certificate	= true
	}
}

resource "null_resource" "nulldisplay"  {
	depends_on = [
		aws_cloudfront_distribution.s3_cloudfront,
	]
	connection {
		type		= "ssh"
		user		= "ec2-user"
		private_key	= file("F:/Abhishek/Hybrid Cloud LW/task 1/Task1Key.pem")
		host		= aws_instance.web_instance.public_ip
	}
	
	provisioner "remote-exec" {
		inline = [
			"sudo su << EOF",
			"echo \"<img src='https://${aws_cloudfront_distribution.s3_cloudfront.domain_name}/image.jpg' alt='image'>\" >> /var/www/html/index.php",
			"EOF",
		]
	}
}



/* -------- Display the Public Ip of the instance and Launch application on browser -------- */
 
output "public_IP" {
	value	= aws_instance.web_instance.public_ip
}

resource "null_resource" "nullfirefox"  {
	depends_on = [
		null_resource.nulldisplay,
	]
	provisioner "local-exec" {
		command = " start firefox  ${aws_instance.web_instance.public_ip}/index.php"
	}
}