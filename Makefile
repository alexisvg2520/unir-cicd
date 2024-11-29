# Definir rutas dependiendo del sistema operativo
OS := $(shell uname -s)
ifeq ($(OS),Linux)
    PATH_STYLE := $(CURDIR)
else
    # Convertir la ruta de Windows a formato Unisx compatible con Docker
    PATH_STYLE := /c/ProgramData/Jenkins/.jenkins/workspace/PruebaPipe
endif

.PHONY: all build server test-unit test-api test-e2e run-web stop-web start-sonar-server stop-sonar-server start-sonar-scanner pylint deploy-stage

# Construcción de imágenes Docker
build:
	docker build -t calculator-app .
	docker build -t calc-web ./web

# Ejecutar el servidor principal
server:
	docker run --rm --name apiserver --network-alias apiserver --env PYTHONPATH=/workspace --env FLASK_APP=app/api.py -p 5000:5000 -v $(PATH_STYLE):/workspace -w /workspace calculator-app:latest flask run --host=0.0.0.0

# Pruebas unitarias
test-unit:
	@echo "Running Unit Tests..."
	docker stop unit-tests || true
	docker rm unit-tests || true
	docker run --name unit-tests --env PYTHONPATH=/workspace -w /workspace -v $(PATH_STYLE):/workspace calculator-app:latest pytest --cov --cov-report=xml:results/coverage.xml --cov-report=html:results/coverage --junit-xml=results/unit_result.xml -m unit || true
	docker cp unit-tests:/workspace/results ./results || true
	docker rm unit-tests || true

# Pruebas de API
test-api:
	@echo "Running API Tests..."
	docker network create calc-test-api || true
	docker stop apiserver || true
	docker rm apiserver || true
	docker run -d --network calc-test-api --env PYTHONPATH=/workspace --name apiserver --env FLASK_APP=app/api.py -p 5000:5000 -v $(PATH_STYLE):/workspace -w /workspace calculator-app:latest flask run --host=0.0.0.0
	docker run --network calc-test-api --name api-tests --env PYTHONPATH=/workspace --env BASE_URL=http://apiserver:5000/ -v $(PATH_STYLE):/workspace -w /workspace calculator-app:latest pytest --junit-xml=results/api_result.xml -m api || true
	docker cp api-tests:/workspace/results ./results || true
	docker stop apiserver || true
	docker rm apiserver || true
	docker stop api-tests || true
	docker rm api-tests || true
	docker network rm calc-test-api || true

# Pruebas End-to-End (E2E)
test-e2e:
	@echo "Running E2E Tests..."
	docker network create calc-test-e2e || true
	docker stop apiserver || true
	docker rm apiserver || true
	docker stop calc-web || true
	docker rm calc-web || true
	docker stop e2e-tests || true
	docker rm e2e-tests || true
	docker run -d --network calc-test-e2e --env PYTHONPATH=/workspace --name apiserver --env FLASK_APP=app/api.py -p 5000:5000 -v $(PATH_STYLE):/workspace -w /workspace calculator-app:latest flask run --host=0.0.0.0
	docker run -d --network calc-test-e2e --name calc-web -p 80:80 calc-web
	docker create --network calc-test-e2e --name e2e-tests cypress/included:4.9.0 --browser chrome || true
	docker cp ./test/e2e/cypress.json e2e-tests:/cypress.json
	docker cp ./test/e2e/cypress e2e-tests:/cypress
	docker start -a e2e-tests || true
	docker cp e2e-tests:/results ./results || true
	docker rm apiserver || true
	docker rm calc-web || true
	docker rm e2e-tests || true
	docker network rm calc-test-e2e || true

# Ejecutar la aplicación web
run-web:
	docker run --rm -v $(PATH_STYLE)/web:/usr/share/nginx/html --name calc-web -p 80:80 nginx

# Detener la aplicación web
stop-web:
	docker stop calc-web || true

# Iniciar el servidor de SonarQube
start-sonar-server:
	docker network create calc-sonar || true
	docker run -d --rm --stop-timeout 60 --network calc-sonar --name sonarqube-server -p 9000:9000 -v $(PATH_STYLE)/sonar/data:/opt/sonarqube/data -v $(PATH_STYLE)/sonar/logs:/opt/sonarqube/logs sonarqube:8.3.1-community

# Detener el servidor de SonarQube
stop-sonar-server:
	docker stop sonarqube-server || true
	docker network rm calc-sonar || true

# Ejecutar el escáner de SonarQube
start-sonar-scanner:
	docker run --rm --network calc-sonar -v $(PATH_STYLE):/usr/src sonarsource/sonar-scanner-cli

# Ejecutar Pylint
pylint:
	@echo "Running Pylint..."
	docker run --rm -v $(PATH_STYLE):/workspace --env PYTHONPATH=/workspace -w /workspace calculator-app:latest pylint app/ | tee results/pylint_result.txt

# Despliegue en entorno de pruebas (stage)
deploy-stage:
	docker stop apiserver || true
	docker stop calc-web || true
	docker run -d --rm --name apiserver --network-alias apiserver --env PYTHONPATH=/workspace --env FLASK_APP=app/api.py -p 5000:5000 -v $(PATH_STYLE):/workspace -w /workspace calculator-app:latest flask run --host=0.0.0.0
	docker run -d --rm --name calc-web -p 80:80 calc-web
