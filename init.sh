# Creadits https://medium.com/@nonickedgr/gke-with-terraform-dfeb72cacd9b

# Project name: A human-readable name for your project.
# Project ID: A globally unique identifier for your project.
# Project number: An automatically generated unique identifier for your project.

export PROJECT_ID=gke-$(date +%d%m%Y%H%M%S)-test
USER_NAME=gke-sa-test

SA_EMAIL=$USER_NAME@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects create $PROJECT_ID

# Create a service account for Terraform

# Creation
gcloud iam service-accounts create $USER_NAME \
    --project ${PROJECT_ID} \
    --display-name $USER_NAME 

# Confirmation
gcloud iam service-accounts list --project $PROJECT_ID

# Creation
gcloud iam service-accounts \
    keys create gkesa_acc.json \
    --iam-account $SA_EMAIL \
    --project ${PROJECT_ID}


# Check local file
cat gkesa_acc.json

# Confirmation
gcloud iam service-accounts \
    keys list \
    --iam-account $SA_EMAIL \
    --project ${PROJECT_ID}

gcloud projects \
    add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:$SA_EMAIL \
    --role roles/owner

# If you deploy Cloud Functions **Gen 2**, builds go through Cloud Build / Cloud Run / Eventarc:
GEN2_ROLES=(
  roles/cloudfunctions.admin       # broad; simplest path
  roles/run.admin                  # Cloud Run services under the hood
  roles/cloudbuild.builds.editor   # Cloud Build to build/deploy
  roles/artifactregistry.admin     # container artifacts (if used)
  roles/eventarc.admin             # triggers (if used)
  roles/storage.admin              # source or staging buckets
  roles/iam.serviceAccountUser
  roles/cloudfunctions.developer
)

# ------- CONFIG: pick one set above -------
ROLES=("${GEN2_ROLES[@]}")        # <--- switch to GEN1_ROLES if using Gen 1

# Grant project-level roles
echo "Granting roles..."
for role in "${ROLES[@]}"; do
  echo " - ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --quiet >/dev/null
done

read -p "Enable the billing to the project ${PROJECT_ID}. After that press enter."

gcloud services enable cloudfunctions.googleapis.com --project=${PROJECT_ID}

gcloud services enable artifactregistry.googleapis.com --project=${PROJECT_ID}

gcloud services enable cloudbuild.googleapis.com --project=${PROJECT_ID}

echo "${PROJECT_ID}" > project.txt