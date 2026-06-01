pipeline {
    agent any

    environment {
        IMAGE_NAME     = 'pulsecheck'
        IMAGE_TAG      = "build-${env.BUILD_NUMBER}"
        
        // AWS Settings (Configure to match your infrastructure requirements)
        AWS_REGION     = 'us-east-1'
        AWS_ACCOUNT_ID = '123456789012'
        ECR_REPOSITORY = 'pulsecheck'
        ECS_CLUSTER    = 'pulsecheck-cluster-dev'
        ECS_SERVICE    = 'pulsecheck-service-dev'
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code repository...'
                checkout scm
            }
        }

        stage('Python Diagnostics & Testing') {
            steps {
                echo 'Installing dependencies and running Pytest suite...'
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    python3 -m pytest app/tests/test_main.py -v
                '''
            }
        }

        stage('Docker Image Compilation') {
            steps {
                echo "Compiling Docker Container Image: ${IMAGE_NAME}:${IMAGE_TAG}..."
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Simulated Environment Deploy & Probe') {
            steps {
                echo 'Spinning up container inside virtualized network to run diagnostics probes...'
                sh """
                    # Clean up legacy container if present
                    docker rm -f pulsecheck_test_jenkins || true
                    
                    docker run -d -p 8085:8000 --name pulsecheck_test_jenkins ${IMAGE_NAME}:${IMAGE_TAG}
                    sleep 5
                    
                    # Extract the container IP address dynamically
                    CONTAINER_IP=\$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pulsecheck_test_jenkins)
                    echo "Probing container at IP: \${CONTAINER_IP}"
                    
                    # Call API probe using the container's network IP and port 8000
                    curl -f http://\${CONTAINER_IP}:8000/health
                """
            }
            post {
                always {
                    sh """
                        docker stop pulsecheck_test_jenkins || true
                        docker rm -f pulsecheck_test_jenkins || true
                    """
                }
            }
        }

        stage('ECR Push') {
            when {
                branch 'main'
            }
            steps {
                echo 'Logging in to ECR and pushing compiled image...'
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                        
                        # Tag as SHA/Build and latest
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                        
                        # Push to Registry
                        docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                        docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                    '''
                }
            }
        }

        stage('Deploy to ECS Fargate') {
            when {
                branch 'main'
            }
            steps {
                echo 'Updating Fargate service to pull and run new task container...'
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --force-new-deployment --region ${AWS_REGION}
                    '''
                }
            }
        }
    }

    post {
        always {
            echo 'Performing workspace cleaning tasks...'
            cleanWs()
        }
    }
}

