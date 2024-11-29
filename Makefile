.PHONY: all $(MAKECMDGOALS)

# Construcción de imágenes Docker
build:
	docker build -t calculator-app .
	docker build -t calc-web ./web

# Iniciar servidor de API
server:
	docker run --rm --name apiserver --network-alias apiserver --env PYTHONPATH=/opt/calc --env FLASK_APP=app/api.py -p 5000:5000 -v $(PWD):/opt/calc -w /opt/calc calculator-app:latest flask run --host=0.0.0.0

# Pruebas Unitarias
test-unit:
	@echo "Running Unit Tests..."
	docker stop unit-tests || true
	docker rm unit-tests || true
	docker run --name unit-tests --env PYTHONPATH=/opt/calc -w /opt/calc -v $(PWD):/opt/calc calculator-app:latest pytest --cov --cov-report=xml:results/coverage.xml --cov-report=html:results/coverage --junit-xml=results/unit_result.xml -m unit || true
	mkdir -p results/unit
	docker cp unit-tests:/opt/calc/results ./results/unit || true
	docker rm unit-tests || true

# Pruebas API
test-api:
	@echo "Running API Tests..."
	docker network create calc-test-api || true
	docker stop apiserver || true
	docker rm apiserver || true
	docker run -d --network calc-test-api --env PYTHONPATH=/opt/calc --name apiserver --env FLASK_APP=app/api.py -p 5000:5000 -v $(PWD):/opt/calc -w /opt/calc calculator-app:latest flask run --host=0.0.0.0
	docker run --network calc-test-api --name api-tests --env PYTHONPATH=/opt/calc --env BASE_URL=http://apiserver:5000/ -w /opt/calc -v $(PWD):/opt/calc calculator-app:latest pytest --junit-xml=results/api_result.xml -m api || true
	mkdir -p results/api
	docker cp api-tests:/opt/calc/results ./results/api || true
	docker stop apiserver || true
	docker rm apiserver || true
	docker stop api-tests || true
	docker rm api-tests || true
	docker network rm calc-test-api || true

# Pruebas E2E
test-e2e:
	@echo "Running E2E Tests..."
	docker network create calc-test-e2e || true
	docker stop apiserver calc-web e2e-tests || true
	docker rm apiserver calc-web e2e-tests || true
	docker run -d --network calc-test-e2e --env PYTHONPATH=/opt/calc --name apiserver --env FLASK_APP=app/api.py -p 5000:5000 -v $(PWD):/opt/calc -w /opt/calc calculator-app:latest flask run --host=0.0.0.0
	docker run -d --network calc-test-e2e --name calc-web -p 80:80 calc-web
	docker create --network calc-test-e2e --name e2e-tests cypress/included:4.9.0 --browser chrome || true
	docker cp ./test/e2e/cypress.json e2e-tests:/cypress.json
	docker cp ./test/e2e/cypress e2e-tests:/cypress
	mkdir -p results/e2e
	docker start -a e2e-tests || true
	docker cp e2e-tests:/results ./results/e2e || true
	docker stop apiserver calc-web e2e-tests || true
	docker rm apiserver calc-web e2e-tests || true
	docker network rm calc-test-e2e || true

# Ejecutar aplicación web
run-web:
	docker run --rm --volume $(PWD)/web:/usr/share/nginx/html --name calc-web -p 80:80 nginx

# Detener aplicación web
stop-web:
	docker stop calc-web || true

# Iniciar servidor SonarQube
start-sonar-server:
	docker network create calc-sonar || true
	docker run -d --rm --stop-timeout 60 --network calc-sonar --name sonarqube-server -p 9000:9000 --volume $(PWD)/sonar/data:/opt/sonarqube/data --volume $(PWD)/sonar/logs:/opt/sonarqube/logs sonarqube:8.3.1-community

# Detener servidor SonarQube
stop-sonar-server:
	docker stop sonarqube-server || true
	docker network rm calc-sonar || true

# Iniciar Sonar Scanner
start-sonar-scanner:
	docker run --rm --network calc-sonar -v $(PWD):/usr/src sonarsource/sonar-scanner-cli

# Ejecutar Pylint
pylint:
	@echo "Running Pylint..."
	mkdir -p results
	docker run --rm --volume $(PWD):/opt/calc --env PYTHONPATH=/opt/calc -w /opt/calc calculator-app:latest pylint app/ | tee results/pylint_result.txt

# Despliegue en ambiente de Stage
deploy-stage:
	docker stop apiserver calc-web || true
	docker run -d --rm --name apiserver --network-alias apiserver --env PYTHONPATH=/opt/calc --env FLASK_APP=app/api.py -p 5000:5000 -v $(PWD):/opt/calc -w /opt/calc calculator-app:latest flask run --host=0.0.0.0
	docker run -d --rm --name calc-web -p 80:80 calc-web
