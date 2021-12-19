PROJECT_ID=devops-mourad
ZONE=us-central1-b

run-local:
	docker-compose up -d

create-tf-backend-bucket:
	gsutil mb -p $(PROJECT_ID) gs://$(PROJECT_ID)-terraform

check-env:
ifndef ENV
	$(error Please set ENV=[staging|prod])
endif

# This cannot be indented or else make will include spaces in front of secret
define get-secret
$(shell gcloud secrets versions access latest --secret=$(1) --project=$(PROJECT_ID))
endef

terraform-create-workspace: check-env
	cd terraform && \
		terraform workspace new $(ENV)

terraform-init: check-env
	cd terraform && \
		terraform workspace select $(ENV) && \
		terraform init

TF_ACTION?=plan
terraform-action: check-env
	@cd terraform && \
		terraform workspace select $(ENV) && \
		terraform $(TF_ACTION) \
		-var-file="./environments/common.tfvars" \
		-var-file="./environments/$(ENV)/config.tfvars" \
		-var="cloudflare_api_token=$(call get-secret,cloudflare_api_token)"

SSH_STRING=mourad_dhambri@storybooks-vm-$(ENV)
OAUTH_CLIENT_ID=98786669149-14p4b6r69e23ojpea637kfivmd3jg4e0.apps.googleusercontent.com

VERSION?=latest
LOCAL_TAG=storybooks-app:$(VERSION)
REMOTE_TAG=gcr.io/$(PROJECT_ID)/$(LOCAL_TAG)
CONTAINER_NAME=storybooks-api
DB_NAME=storybooks

ssh:
	gcloud compute ssh $(SSH_STRING) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE)

ssh-cmd:
	@gcloud compute ssh $(SSH_STRING) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE) \
		--command="$(CMD)"

build:
	docker build -t $(LOCAL_TAG) .

push:
	docker tag $(LOCAL_TAG) $(REMOTE_TAG)
	docker push $(REMOTE_TAG)

deploy: check-env
	@$(MAKE) ssh-cmd CMD='docker-credential-gcr configure-docker'
	@echo "Pulling new container image..."
	$(MAKE) ssh-cmd CMD='docker pull $(REMOTE_TAG)'
	$(MAKE) ssh-cmd CMD='docker pull mongo:3.6-xenial'
	@echo "Removing old container..."
	-$(MAKE) ssh-cmd CMD='docker container stop $(CONTAINER_NAME)'
	-$(MAKE) ssh-cmd CMD='docker container rm -f $(CONTAINER_NAME)'
	-$(MAKE) ssh-cmd CMD='docker container stop mongo'
	-$(MAKE) ssh-cmd CMD='docker container rm -f mongo'
	-$(MAKE) ssh-cmd CMD='docker container prune -f'
	-$(MAKE) ssh-cmd CMD='docker network create mongo-network || true'
	-$(MAKE) ssh-cmd CMD='docker volume create mongodbdata || true'
	@echo "Starting new container..."
	$(MAKE) ssh-cmd CMD='docker run -d -p 27017:27017 -v mongodbdata:/data/db --network mongo-network --name mongo --restart=unless-stopped mongo:3.6-xenial'
	@$(MAKE) ssh-cmd CMD='docker run -d --name=$(CONTAINER_NAME) \
			--restart=unless-stopped \
			-p 80:3000 \
			-e PORT=3000 \
			--network mongo-network \
			-e \"MONGO_URI=mongodb://mongo:27017/$(DB_NAME)?retryWrites=true&w=majority\" \
			-e GOOGLE_CLIENT_ID=$(OAUTH_CLIENT_ID) \
			-e GOOGLE_CLIENT_SECRET=$(call get-secret,google_oauth_client_secret) \
			$(REMOTE_TAG)'

