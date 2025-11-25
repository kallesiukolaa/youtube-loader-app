# main.py

from googleapiclient.discovery import build
import os
import re
import functions_framework
import base64
import json
from google.cloud import run_v2, storage
from datetime import date, datetime, timezone
from urllib.parse import urlparse, parse_qs


def get_current_date_yyyymmdd():
    """
    Returns the current date as a string in the format YYYYMMDD.
    """
    # Get the current date object
    today = date.today()
    
    # Format the date object into the 'yyyymmdd' string format
    # %Y = full year (e.g., 2025)
    # %m = month as a zero-padded number (e.g., 11)
    # %d = day of the month as a zero-padded number (e.g., 21)
    formatted_date = today.strftime("%Y%m%d")
    
    return formatted_date

# Your function's entry point (e.g., triggered by an HTTP request or Pub/Sub)
def launch_job_to_load_video(video_url, channel_handle, video_title):
    """
    Launches the target Cloud Run Job with specific environment variables.
    """
    
    # --- Configuration ---
    PROJECT_ID = os.environ.get('GCP_PROJECT_ID') # Get this from the environment
    REGION = os.environ.get('REGION')             # Get this from the environment
    JOB_NAME = os.environ.get('JOB_NAME')           # The name of the job defined in Terraform
    CONTAINER_NAME = "main-container"
    LOCK_BUCKET_NAME = os.environ.get('VIDEO_BUCKET')

    query = urlparse(video_url).query
    video_id = parse_qs(query).get('v', [None])[0]

    LOCK_FILE_NAME = f"lock/{video_id}.lock"

    storage_client = storage.Client()
    lock_bucket = storage_client.bucket(LOCK_BUCKET_NAME)
    
    try:

        # 1. CHECK LOCK: Attempt to get the lock file metadata
        if lock_bucket.blob(LOCK_FILE_NAME).exists():
            print(f"Lock file found for video ID {video_id}. Job submission aborted.")
            return f"Video {video_id} is already being processed or is complete.", 200

        lock_bucket.blob(LOCK_FILE_NAME).upload_from_string(
            data="", 
            content_type="text/plain"
        )
        print(f"Lock file created: {LOCK_FILE_NAME}")

        # --- Environment Variables to Pass ---
        CUSTOM_ENV_VARS = {
            "EFS_PATH": os.environ.get('MOUNT_PATH'),
            "YOUTUBE_URL": video_url,
            "GCS_URI": f"gs://{os.environ.get('VIDEO_BUCKET')}/{channel_handle}/{get_current_date_yyyymmdd()}",
            "VIDEO_NAME": video_title,
            "BUCKET_NAME": os.environ.get('VIDEO_BUCKET')
        }
        # --------------------------------------

        
        # Initialize the Cloud Run client
        client = run_v2.JobsClient()
        
        # Build the full resource name for the job
        job_name = f"projects/{PROJECT_ID}/locations/{REGION}/jobs/{JOB_NAME}"

        # Build the overrides needed for the execution call
        overrides = run_v2.RunJobRequest.Overrides(
            container_overrides=[
                run_v2.RunJobRequest.Overrides.ContainerOverride(
                    # Only one container in your job, so index 0
                    name=CONTAINER_NAME,
                    env=[
                        # Convert your dictionary to the required list of EnvVar objects
                        run_v2.EnvVar(name=name, value=value)
                        for name, value in CUSTOM_ENV_VARS.items()
                    ]
                )
            ]
        )
        
        # Prepare the request to execute the job
        request = run_v2.RunJobRequest(
            name=job_name,
            overrides=overrides,
        )

        print(f"Executing job {JOB_NAME} with overrides: {CUSTOM_ENV_VARS}")

        # Send the API call to execute the job
        operation = client.run_job(request=request)
        
        # Note: client.run_job returns an Operation object,
        # indicating the execution has started, but not necessarily finished.

        return f"Cloud Run Job '{JOB_NAME}' execution started. Operation: {operation.operation.name}", 200

    except Exception as e:
        print(f"Error launching job: {e}")
        return f"Error launching job: {str(e)}", 500

def get_channel_id_from_handle(handle):
    # Initializes using the Cloud Function's Service Account (no API key needed)
    youtube = build("youtube", "v3")

    # The handle should be passed without the '@' symbol
    handle_without_at = handle.lstrip('@')
    
    response = youtube.channels().list(
        part="id",
        # Use the 'forHandle' parameter instead of 'id'
        forHandle=handle_without_at
    ).execute()
    
    # Extract the Channel ID from the response
    if response['items']:
        return response['items'][0]['id']
    else:
        return None

def is_channel_streaming_cheap(channel_id, intervall_seconds):
    """
    Chacks if there has been any upload activity during the past 5 minutes. 
    Only for avoiding to use search for no live streams
    
    Args:
        channel_id: The ID of the YouTube channel to check.
        
    Returns:
        True if the channel is uploaded something during the last 5 minutes
    """
    try:
        # 1. Build the YouTube API client
        youtube = build('youtube', 'v3')
        
        # 2. Call the activities.list method
        # We limit the results to the most recent activity (maxResults=5)
        # and only request the 'snippet' part.
        request = youtube.activities().list(
            part='snippet',
            channelId=channel_id,
            maxResults=20
        )
        
        # 3. Execute the request
        response = request.execute()
        
        # 4. Check the results
        if not response.get('items'):
            return False # No recent activity found

        items = response.get('items')

        # 5. Get only items that are at most intervall_seconds old
        items = filter(lambda x: (datetime.now(timezone.utc) - datetime.fromisoformat(x['snippet']['publishedAt'])).total_seconds() < intervall_seconds and x['snippet']['type'] == 'upload', items)
        items = list(items)

        # 6. Return True if there is more than 0 events during the pest 5 minutes
        return len(items) > 0

    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        return False

# The entry point for the Google Cloud Function
@functions_framework.cloud_event
def check_live_stream(cloud_event):
    """
    Checks if a given YouTube channel is currently live streaming using
    the function's Service Account credentials (no API Key needed).
    
    Args:
        request (flask.Request): The request object.
    Returns:
        A JSON response indicating the live status.
    """
    
    # 1. Get the channel ID from the request (No API key retrieval needed)
    pubsub_message = cloud_event.data.get("message")
    if not ( pubsub_message and "data" in pubsub_message):
        return {"error": f"Incorrect cloud event provided {cloud_event}"}
    
    # Extract the Base64 encoded payload
    encoded_data = pubsub_message["data"]
        
    # Decode the payload to get your original string (or JSON string)
    request_json = base64.b64decode(encoded_data).decode('utf-8')

    print(f"Received scheduled payload: {request_json}")

    # Try to parse the request to json
    try:
        request_json = json.loads(request_json)
    except json.JSONDecodeError:
        print(f"Error: Could not parse payload as JSON: {request_json}")
        return "Payload Error"
    
    # Validate the json; it should contain channel_handle-attribute
    if request_json and 'channel_handle' in request_json:
        channel_handle = request_json['channel_handle']
    else:
        return {"error": "Please provide a 'channel_handle' in the request body or query parameters."}, 400

    try:
        # 2. Initialize the YouTube service - NO developerKey is passed
        # The service account credentials are automatically picked up.
        youtube = build("youtube", "v3")

        channel_id = get_channel_id_from_handle(channel_handle)

        intervall_seconds = 300

        # Try to avoid using youtube.search() as it costs 100 credits.
        if not is_channel_streaming_cheap(channel_id, intervall_seconds):
            print(f'Channel {channel_handle} is not streaming currently.')
            return {
                "channel_id": channel_id,
                "is_live": False
            }, 200

        # 3. Call the search.list method
        search_response = youtube.search().list(
            part='snippet',
            channelId=channel_id,
            type='video',
            eventType='live',
            maxResults=1
        ).execute()

        # 4. Process the response (as before)
        if search_response.get('items'):
            item = search_response['items'][0]
            video_id = item['id']['videoId']
            title = item['snippet']['title']

            url = f"https://www.youtube.com/watch?v={video_id}"

            launch_job_to_load_video(url, channel_handle, title)
            
            return {
                "channel_id": channel_id,
                "is_live": True,
                "video_id": video_id,
                "title": title,
                "url": url
            }, 200
        else:
            return {
                "channel_id": channel_id,
                "is_live": False
            }, 200

    except Exception as e:
        print(f"An error occurred: {e}")
        return {"error": f"An API error occurred: {str(e)}"}, 500