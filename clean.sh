# Get PROJECT_ID
export PROJECT_ID=$(gcloud projects list | grep -E "^gke-[0-9]+-test" | awk '{print $1}')

# Get service account
export SA_GKE=$(gcloud iam service-accounts list --project $PROJECT_ID | grep gke-sa-test | awk '{print $2}')

# Delete service account
gcloud iam service-accounts delete $SA_GKE  --project $PROJECT_ID

# Delete project
gcloud  projects delete $PROJECT_ID

# Delete the project file 
rm project.txt