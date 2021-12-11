PROJECT_ID=devops-mourad

run-local:
	docker-compose up -d

create-tf-backend-bucket:
	gsutil mb -p $(PROJECT_ID) gs://$(PROJECT_ID)-terraform
