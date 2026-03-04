pipeline {
    agent {
        dockerfile true
    }

    triggers {
        pollSCM('H * * * *')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Run Tests') {
            steps {
                sh '''
                    mkdir -p tests/reports
                    pytest tests/ -v -rA --junitxml=tests/reports/pytest-results.xml
                '''
            }
        }
    }

    post {
        always {
            junit 'tests/reports/pytest-results.xml'
            archiveArtifacts artifacts: 'tests/reports/logs/*.log', allowEmptyArchive: true
        }
    }
}
