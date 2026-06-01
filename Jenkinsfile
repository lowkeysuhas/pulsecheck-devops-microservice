pipeline {
    agent any

    environment {
        IMAGE_NAME = 'pulsecheck'
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
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
                    docker run -d -p 8085:8000 --name pulsecheck_test_jenkins ${IMAGE_NAME}:${IMAGE_TAG}
                    sleep 5
                    
                    # Call API probe
                    curl -f http://localhost:8085/health
                    
                    # Cleanup
                    docker stop pulsecheck_test_jenkins
                    docker rm pulsecheck_test_jenkins
                """
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
